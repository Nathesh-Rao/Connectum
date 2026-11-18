import '../../data/smart_view/sv_saved_view.dart';
import '../../data/socket/socket_service.dart' show SocketCallError;

/// DEMO_MODE and `/debug/smartviews`: the saved views of the Leave request
/// demo kept in memory, answering `smartview.views` / `.views.save` in place
/// of the server (whole-list replace, like the real one). The first save
/// after [armConflict] finds another device's change to "Pending only".
class SeedSavedViews {
  SeedSavedViews({this.isForbidden = false, this.failReads = false});

  /// Every save answers `forbidden`.
  bool isForbidden;

  /// Every read fails (the retry pill).
  bool failReads;
  int reads = 0;
  int writes = 0;
  bool _conflictArmed = false;

  final _lists = <String, List<Map<String, Object?>>>{};

  static List<Map<String, Object?>> _initial() => [
    {
      'id': 'demo-pending',
      'name': 'Pending only',
      'search': '',
      'filters': [
        {
          'col': 'stage',
          'op': 'in',
          'value': ['Open', 'In progress'],
        },
      ],
      'sort': {'col': 'from', 'dir': 'asc'},
      'groupBy': <String>[],
      'hidden': <String>[],
      'order': <String>[],
      'widths': <String, Object?>{},
      'kpis': true,
      'charts': true,
      'webOnly': {'keep': 'me'},
    },
    {
      'id': 'demo-status',
      'name': 'By status',
      'search': '',
      'filters': <Object?>[],
      'sort': null,
      'groupBy': ['stage', 'kind'],
      'hidden': <String>[],
      'order': <String>[],
      'widths': <String, Object?>{},
      'kpis': true,
      'charts': true,
    },
    {
      'id': 'demo-compact',
      'name': 'Compact',
      'search': '',
      'filters': <Object?>[],
      'sort': null,
      'groupBy': <String>[],
      'hidden': ['notes', 'manager', 'to', 'start_time', 'balance', 'On'],
      'order': ['title', 'stage', 'from', 'days'],
      'widths': <String, Object?>{},
      'kpis': true,
      'charts': true,
    },
  ];

  /// The next save finds "Pending only" renamed on another device.
  void armConflict() => _conflictArmed = true;

  Future<Map<String, dynamic>> call(
    String cmd,
    Map<String, dynamic> args,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final name = '${args['name']}';
    final list = _lists.putIfAbsent(
      name,
      () => name == 'leave' ? _initial() : <Map<String, Object?>>[],
    );
    switch (cmd) {
      case 'smartview.views':
        reads++;
        if (failReads) throw const SocketCallError('error', 'Failed');
        return {
          'mine': [for (final v in list) Map<String, Object?>.of(v)],
          'shared': <Object?>[],
          'canPublish': false,
        };
      case 'smartview.views.save':
        writes++;
        if (isForbidden) throw const SocketCallError('forbidden');
        final incoming = [
          for (final v in (args['views'] as List))
            Map<String, Object?>.from(v as Map),
        ];
        _lists[name] = incoming;
        return {'views': incoming};
    }
    throw SocketCallError('unknown_command', cmd);
  }

  /// Another device renames "Pending only" (shown as a conflict on a save).
  void remoteRename(String source, String id, String name) {
    final list = _lists[source];
    if (list == null) return;
    for (final v in list) {
      if (v['id'] == id) v['name'] = name;
    }
  }

  /// Runs the armed conflict at the first read after the opening one (the
  /// re-read a save makes).
  Future<Map<String, dynamic>> callWithConflict(
    String cmd,
    Map<String, dynamic> args,
  ) async {
    if (_conflictArmed && cmd == 'smartview.views' && reads >= 1) {
      _conflictArmed = false;
      remoteRename('${args['name']}', 'demo-pending', 'Pending (renamed)');
    }
    return call(cmd, args);
  }

  SvViewsSnapshot get snapshot => SvViewsSnapshot(_lists);
}

class SvViewsSnapshot {
  SvViewsSnapshot(this._lists);

  final Map<String, List<Map<String, Object?>>> _lists;

  List<SvSavedView> of(String source) => [
    for (final v in _lists[source] ?? const <Map<String, Object?>>[])
      ?SvSavedView.tryParse(v),
  ];
}
