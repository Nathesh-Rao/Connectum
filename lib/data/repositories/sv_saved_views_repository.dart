import 'dart:async';

import '../smart_view/sv_saved_view.dart';
import '../socket/socket_service.dart' show SocketCallError;

/// What the server returned for one source: the person's own views, the
/// shared ones (read only) and whether they may publish.
class SvViewsLoad {
  const SvViewsLoad({
    this.mine = const [],
    this.shared = const [],
    this.canPublish = false,
  });

  final List<SvSavedView> mine;
  final List<SvSavedView> shared;
  final bool canPublish;

  /// The stored Default View entry, if any (never shown as a tab).
  SvSavedView? get stored {
    for (final v in mine) {
      if (v.isDefault) return v;
    }
    return null;
  }

  /// The tabs: own views except the Default entry.
  List<SvSavedView> get tabs => [
    for (final v in mine)
      if (!v.isDefault) v,
  ];
}

enum SvChangeKind { add, update, remove }

/// One change to one view id: the only thing a save applies.
class SvViewChange {
  const SvViewChange.add(SvSavedView this.view)
    : kind = SvChangeKind.add,
      id = '';
  const SvViewChange.update(SvSavedView this.view)
    : kind = SvChangeKind.update,
      id = '';
  const SvViewChange.remove(this.id) : kind = SvChangeKind.remove, view = null;

  final SvChangeKind kind;
  final SvSavedView? view;
  final String id;

  String get targetId => view?.id ?? id;
}

enum SvSaveStatus {
  saved,

  /// The target view changed on another device since it was loaded.
  conflict,

  /// The fresh list could not be read, so nothing was written.
  readFailed,
  writeFailed,
  offline,
  forbidden,
  invalid,
}

class SvSaveOutcome {
  const SvSaveOutcome(this.status, {this.views = const [], this.message = ''});

  final SvSaveStatus status;

  /// The own views after the save (or the fresh list on a conflict).
  final List<SvSavedView> views;
  final String message;

  bool get isSaved => status == SvSaveStatus.saved;
}

/// A person's saved views of one source: `smartview.views` and
/// `smartview.views.save`, which REPLACES the whole list and has no
/// revision. So before every write the list is read again, the one change is
/// merged into it by view id (other devices' views stay), and a change to a
/// view that moved remotely asks first. [call] is the Smart View command gate
/// (one at a time, paced); tests and the demo pass a fake.
class SvSavedViewsRepository {
  SvSavedViewsRepository({required this.call});

  static const cmdViews = 'smartview.views';
  static const cmdSave = 'smartview.views.save';
  static const kind = 'structure';
  static const forbiddenCodes = {
    'forbidden',
    'not_allowed',
    'permission_denied',
    'no_permission',
  };

  final Future<Map<String, dynamic>> Function(
    String cmd,
    Map<String, dynamic> args,
  )
  call;

  Future<SvViewsLoad> load(String source) async {
    final data = await call(cmdViews, {'kind': kind, 'name': source});
    return SvViewsLoad(
      mine: _list(data['mine']),
      shared: _list(data['shared']),
      canPublish: data['canPublish'] == true,
    );
  }

  static List<SvSavedView> _list(Object? raw) => [
    if (raw is List)
      for (final v in raw) ?SvSavedView.tryParse(v),
  ];

  /// Applies [change] to the fresh list. [seen] is the target as this
  /// device loaded it (null for an add); [isOverwrite] answers a conflict.
  Future<SvSaveOutcome> apply(
    String source,
    SvViewChange change, {
    SvSavedView? seen,
    bool isOverwrite = false,
  }) async {
    final problem = _check(change);
    if (problem != null) {
      return SvSaveOutcome(SvSaveStatus.invalid, message: problem);
    }
    final SvViewsLoad fresh;
    try {
      fresh = await load(source);
    } on SocketCallError catch (e) {
      return _fail(e, SvSaveStatus.readFailed);
    }
    final list = [...fresh.mine];
    final id = change.targetId;
    final at = list.indexWhere((v) => v.id == id);
    final remote = at < 0 ? null : list[at];

    if (change.kind != SvChangeKind.add && !isOverwrite) {
      final moved = change.kind == SvChangeKind.remove && remote == null
          ? false
          : remote == null || !remote.sameAs(seen);
      if (moved) {
        return SvSaveOutcome(SvSaveStatus.conflict, views: list);
      }
    }

    switch (change.kind) {
      case SvChangeKind.add:
        final v = change.view!;
        list.removeWhere((x) => x.id == v.id);
        final named = list.where((x) => !x.isDefault).length;
        if (!v.isDefault && named >= SvViewLimits.maxNamed) {
          return const SvSaveOutcome(
            SvSaveStatus.invalid,
            message: 'At most 20 views.',
          );
        }
        if (_nameTaken(list, v)) {
          return const SvSaveOutcome(
            SvSaveStatus.invalid,
            message: 'A view with that name exists.',
          );
        }
        list.insert(0, v);
      case SvChangeKind.update:
        final v = change.view!;
        if (_nameTaken([...list]..removeWhere((x) => x.id == v.id), v)) {
          return const SvSaveOutcome(
            SvSaveStatus.invalid,
            message: 'A view with that name exists.',
          );
        }
        if (at < 0) {
          list.insert(0, v);
        } else {
          list[at] = v;
        }
      case SvChangeKind.remove:
        if (at >= 0) list.removeAt(at);
    }

    try {
      final data = await call(cmdSave, {
        'kind': kind,
        'name': source,
        'views': [for (final v in list) v.toJson()],
      });
      final saved = _list(data['views']);
      return SvSaveOutcome(
        SvSaveStatus.saved,
        views: data['views'] is List ? saved : list,
      );
    } on SocketCallError catch (e) {
      return _fail(e, SvSaveStatus.writeFailed);
    }
  }

  static bool _nameTaken(List<SvSavedView> others, SvSavedView v) {
    if (v.isDefault) return false;
    final n = v.name.toLowerCase();
    return n == SvViewLimits.defaultName.toLowerCase() ||
        others.any((x) => !x.isDefault && x.name.toLowerCase() == n);
  }

  static String? _check(SvViewChange c) {
    final v = c.view;
    if (v == null) return null;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(v.id)) {
      return 'A view needs an id.';
    }
    if (!v.isDefault &&
        (v.name.isEmpty ||
            v.name.length > SvViewLimits.maxName ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(v.name))) {
      return 'A view needs a name of 1 to 40 characters.';
    }
    if (v.filters.length > SvViewLimits.maxFilters) {
      return 'A view can hold at most 30 filters.';
    }
    if (v.groupBy.length > SvViewLimits.maxGroups) {
      return 'A view can group by at most 5 fields.';
    }
    return null;
  }

  static SvSaveOutcome _fail(SocketCallError e, SvSaveStatus failed) {
    if (e.isConnectionGap) return const SvSaveOutcome(SvSaveStatus.offline);
    if (forbiddenCodes.contains(e.code)) {
      return const SvSaveOutcome(SvSaveStatus.forbidden);
    }
    return SvSaveOutcome(failed, message: e.code);
  }
}
