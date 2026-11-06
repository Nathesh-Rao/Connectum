import 'dart:io';

import 'package:flutter/services.dart';

import 'connect_code.dart';

/// What one read of the install referrer found. A read that is not
/// conclusive (Play unavailable, timed out) is tried again on a later start.
class ReferrerRead {
  const ReferrerRead.found(String this.referrer) : isConclusive = true;
  const ReferrerRead.none() : referrer = null, isConclusive = true;
  const ReferrerRead.inconclusive() : referrer = null, isConclusive = false;

  final String? referrer;
  final bool isConclusive;
}

/// Where the Play Install Referrer string comes from.
abstract interface class InstallReferrerSource {
  Future<ReferrerRead> read();
}

class NoInstallReferrerSource implements InstallReferrerSource {
  const NoInstallReferrerSource();

  @override
  Future<ReferrerRead> read() async => const ReferrerRead.none();
}

/// Android: the official Play Install Referrer library through the
/// `connectum/device` channel. An install that did not come from Play
/// (sideloaded, debug) answers no referrer.
class PlayInstallReferrerSource implements InstallReferrerSource {
  const PlayInstallReferrerSource();

  static const _channel = MethodChannel('connectum/device');
  static const _retryDelays = [
    Duration(milliseconds: 500),
    Duration(seconds: 1),
  ];

  @override
  Future<ReferrerRead> read() async {
    if (!Platform.isAndroid) return const ReferrerRead.none();
    for (var attempt = 0; ; attempt++) {
      final String status;
      String? referrer;
      try {
        final answer = await _channel.invokeMapMethod<String, Object?>(
          'installReferrer',
        );
        status = answer?['status'] as String? ?? 'error';
        referrer = answer?['referrer'] as String?;
      } on PlatformException {
        return const ReferrerRead.inconclusive();
      } on MissingPluginException {
        return const ReferrerRead.none();
      }
      switch (status) {
        case 'ok':
          return referrer == null || referrer.isEmpty
              ? const ReferrerRead.none()
              : ReferrerRead.found(referrer);
        case 'unsupported' || 'developer_error':
          return const ReferrerRead.none();
        case 'disconnected' when attempt < _retryDelays.length:
          await Future<void>.delayed(_retryDelays[attempt]);
        default:
          return const ReferrerRead.inconclusive();
      }
    }
  }
}

/// What a referrer string holds: the code form, or a one-time claim token.
class ReferrerInvite {
  const ReferrerInvite({this.target, this.claim});

  final ConnectCode? target;
  final String? claim;
}

/// Reads `connect_code=CODE[&connect_org=ORG][&connect_branch=NAME]` or
/// `connect_claim=TOKEN` (percent decoded, unknown parameters ignored). The
/// values are handed to [ConnectLinkParser], so it stays the only place that
/// accepts a code. The code form wins when both are present.
class InstallReferrerParser {
  InstallReferrerParser._();

  static const maxLength = 1000;
  static final _claim = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

  static ConnectCode? parse(String? raw) => read(raw).target;

  static ReferrerInvite read(String? raw) {
    final params = _params(raw);
    if (params == null) return const ReferrerInvite();
    final target = _target(params);
    if (target != null) return ReferrerInvite(target: target);
    final claim = params['connect_claim'];
    return ReferrerInvite(
      claim: claim != null && _claim.hasMatch(claim) ? claim : null,
    );
  }

  static Map<String, String>? _params(String? raw) {
    var text = raw?.trim() ?? '';
    if (text.isEmpty || text.length > maxLength) return null;
    try {
      if (!text.contains('=') && text.contains('%3D')) {
        text = Uri.decodeComponent(text);
      }
      return Uri.splitQueryString(text);
    } on FormatException {
      return null;
    }
  }

  static ConnectCode? _target(Map<String, String> params) {
    final code = params['connect_code'];
    if (code == null || code.isEmpty) return null;
    final org = params['connect_org'];
    final branch = params['connect_branch'];
    final link = ConnectLinkParser.link(code, org: org, branch: branch);
    return ConnectLinkParser.parse(link).value;
  }
}
