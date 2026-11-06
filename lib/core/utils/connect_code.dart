import '../config/app_config.dart';

enum ConnectRejection {
  empty,
  tooLong,
  otherScheme,
  wrongHost,
  notConnectLink,
  badCode,
}

/// A validated Connectum code. Never print it: the text form is redacted.
class ConnectCode {
  const ConnectCode({required this.code, this.org, this.branch});

  final String code;

  /// The organisation named by a person's link; null on an organisation's own.
  final String? org;
  final String? branch;

  bool get isPersonLink => org != null;

  String get display => '${code.substring(0, 4)}-${code.substring(4)}';

  /// The whole link in the one form the server reads for sure; what the
  /// server calls and the stored pending target use. Parsing it again gives
  /// the same code, org and branch.
  String get linkText => ConnectLinkParser.link(code, org: org, branch: branch);

  /// The same code without the branch, once the server called it unavailable.
  ConnectCode withoutBranch() => ConnectCode(code: code, org: org);

  @override
  String toString() => 'ConnectCode(…)';
}

class ConnectParse {
  const ConnectParse.accepted(ConnectCode this.value) : rejection = null;
  const ConnectParse.rejected(ConnectRejection this.rejection) : value = null;

  final ConnectCode? value;
  final ConnectRejection? rejection;

  bool get isAccepted => value != null;
}

/// The one place raw text (a scan, a link, a typed code) becomes a code.
/// Accepts `https://<allowed host>/connect/CODE`, `connectum://connect/CODE`,
/// `connectum:CODE`, each with optional `?org=` and `?branch=`, or a bare code.
class ConnectLinkParser {
  ConnectLinkParser._();

  static const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const codeLength = 8;
  static const maxLength = 300;
  static const maxBranchLength = 60;
  static const scheme = 'connectum';
  static const publicHost = 'connectum.app';

  static final _bare = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 \-]*$');
  static final _control = RegExp(r'[\x00-\x1F\x7F]');

  static Set<String> get _hosts {
    final host = AppConfig.baseUrl.isEmpty
        ? ''
        : Uri.tryParse(AppConfig.baseUrl)?.host ?? '';
    return {publicHost, if (host.isNotEmpty) host.toLowerCase()};
  }

  /// The https link for a code. Spaces are written as `%20`, never `+`.
  static String link(String code, {String? org, String? branch}) => Uri(
    scheme: 'https',
    host: publicHost,
    pathSegments: ['connect', code],
    query: query({'org': org, 'branch': branch}),
  ).toString();

  /// A query string with every value percent-encoded (`%20` for a space).
  /// Null and empty values are left out.
  static String? query(Map<String, String?> values) {
    final parts = [
      for (final e in values.entries)
        if (e.value != null && e.value!.isNotEmpty)
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value!)}',
    ];
    return parts.isEmpty ? null : parts.join('&');
  }

  static ConnectParse parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const ConnectParse.rejected(ConnectRejection.empty);
    }
    if (text.length > maxLength) {
      return const ConnectParse.rejected(ConnectRejection.tooLong);
    }
    if (_control.hasMatch(text)) {
      return const ConnectParse.rejected(ConnectRejection.notConnectLink);
    }
    final mark = text.indexOf('?');
    if (mark > 0 && _bare.hasMatch(text.substring(0, mark))) {
      return _bareWithQuery(text.substring(0, mark), text.substring(mark + 1));
    }
    if (_bare.hasMatch(text)) {
      final code = _normalize(text, isForgiving: true);
      return code == null
          ? const ConnectParse.rejected(ConnectRejection.badCode)
          : ConnectParse.accepted(ConnectCode(code: code));
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) {
      return const ConnectParse.rejected(ConnectRejection.notConnectLink);
    }
    final String segment;
    switch (uri.scheme.toLowerCase()) {
      case 'https':
        final segments = [...uri.pathSegments];
        if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
        if (!_hosts.contains(uri.host.toLowerCase()) ||
            uri.userInfo.isNotEmpty ||
            (uri.hasPort && uri.port != 443)) {
          return const ConnectParse.rejected(ConnectRejection.wrongHost);
        }
        if (segments.length != 2 || segments.first != 'connect') {
          return const ConnectParse.rejected(ConnectRejection.notConnectLink);
        }
        segment = segments[1];
      case scheme:
        if (uri.host.isEmpty) {
          segment = uri.path;
        } else if (uri.host == 'connect' && uri.pathSegments.length == 1) {
          segment = uri.pathSegments.first;
        } else {
          return const ConnectParse.rejected(ConnectRejection.notConnectLink);
        }
      default:
        return const ConnectParse.rejected(ConnectRejection.otherScheme);
    }
    final code = _normalize(segment, isForgiving: false);
    if (code == null) {
      return const ConnectParse.rejected(ConnectRejection.badCode);
    }
    return _accepted(
      code,
      uri.queryParameters['org'],
      uri.queryParameters['branch'],
    );
  }

  /// `CODE?branch=X`, `CODE?org=Y&branch=X` or `CODE?org=Y` without a scheme.
  static ConnectParse _bareWithQuery(String head, String query) {
    final code = _normalize(head, isForgiving: true);
    if (code == null) {
      return const ConnectParse.rejected(ConnectRejection.badCode);
    }
    final Map<String, String> params;
    try {
      params = Uri.splitQueryString(query);
    } on FormatException {
      return const ConnectParse.rejected(ConnectRejection.notConnectLink);
    }
    return _accepted(code, params['org'], params['branch']);
  }

  static ConnectParse _accepted(String code, String? orgText, String? branch) {
    final org = _normalize(orgText ?? '', isForgiving: false);
    return ConnectParse.accepted(
      ConnectCode(
        code: code,
        org: org == code ? null : org,
        branch: _branch(branch),
      ),
    );
  }

  /// Typed text: case, spaces and dashes ignored, O is 0, I and L are 1, U is V.
  static String? _normalize(String text, {required bool isForgiving}) {
    var chars = text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (isForgiving) {
      chars = chars
          .replaceAll('O', '0')
          .replaceAll('I', '1')
          .replaceAll('L', '1')
          .replaceAll('U', 'V');
    }
    if (chars.length != codeLength) return null;
    for (final c in chars.split('')) {
      if (!alphabet.contains(c)) return null;
    }
    return chars;
  }

  /// A label only: trimmed, limited, dropped when it holds odd characters.
  static String? _branch(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || text.length > maxBranchLength) return null;
    return _control.hasMatch(text) ? null : text;
  }
}
