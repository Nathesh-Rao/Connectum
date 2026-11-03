import 'dart:convert';

import '../config/app_config.dart';

/// The `[ATTACHMENT:{...}]` text the web chat uses to carry a file. The server
/// never reads it: it is an ordinary message of at most 2000 characters. This
/// is the only place a tag is built or parsed.
class AttachmentTag {
  const AttachmentTag({
    required this.kind,
    required this.name,
    required this.size,
    required this.url,
    required this.type,
    this.e2eKey,
    this.e2eIv,
    this.caption = '',
  });

  static const maxLength = 2000;
  static const kinds = {'image', 'video', 'audio', 'file'};
  static final _pattern = RegExp(r'\[ATTACHMENT:(\{.*?\})\]');

  final String kind;
  final String name;

  /// Human readable, "1.2 MB", or empty when unknown.
  final String size;

  /// Relative `/uploads/<name>` as the upload answered it.
  final String url;
  final String type;

  /// Base64url key and iv of an encrypted blob (`e2e` in the tag); both or
  /// neither. They are only ever put in a tag that travels inside an envelope.
  final String? e2eKey;
  final String? e2eIv;

  /// Text outside the tag (the web composer never writes any).
  final String caption;

  bool get isImage => kind == 'image';

  /// The url points at an encrypted blob that [e2eKey] and [e2eIv] open.
  bool get isEncrypted => e2eKey != null && e2eIv != null;

  /// A blob url without a usable key: it can never be opened.
  bool get isUnreadable => !isEncrypted && url.endsWith('.e2e');

  /// The file's absolute address, only when it is a chat upload on this
  /// server. Any other host is refused rather than fetched.
  String? get resolvedUrl {
    final origin = AppConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (origin.isEmpty) return null;
    if (_isUploadPath(url)) return '$origin$url';
    if (url.startsWith('$origin/') &&
        _isUploadPath(url.substring(origin.length))) {
      return url;
    }
    return null;
  }

  static bool _isUploadPath(String path) =>
      path.startsWith('/uploads/') &&
      path.length > '/uploads/'.length &&
      !path.contains('..') &&
      !path.contains('\\');

  /// The tag as the web builds it: key order `kind, name, size, url, type`,
  /// then `e2e` for an encrypted blob.
  /// Throws a [FormatException] when [url] is empty (a tag without a file is
  /// never sent) or the tag cannot fit in [maxLength], even with a shortened
  /// name.
  String build() {
    if (url.isEmpty) throw const FormatException('Attachment has no url');
    var shown = name.replaceAll('}]', '_');
    while (true) {
      final text =
          '[ATTACHMENT:${jsonEncode({
            'kind': kind,
            'name': shown,
            'size': size,
            'url': url,
            'type': type,
            if (isEncrypted) 'e2e': {'key': e2eKey, 'iv': e2eIv},
          })}]';
      if (text.length <= maxLength) return text;
      if (shown.length <= 1) {
        throw const FormatException('Attachment tag too long');
      }
      shown = shown.substring(0, shown.length ~/ 2);
    }
  }

  /// "1.2 MB", "340 KB", "12 B".
  static String sizeText(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// The tag inside [text], or null for anything that is not a well-formed
  /// one (no tag, bad JSON, unknown kind, empty url): the caller then shows
  /// the text as it is.
  static AttachmentTag? parse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    try {
      final json = jsonDecode(match.group(1)!);
      if (json is! Map) return null;
      final kind = json['kind'];
      final url = json['url'];
      if (kind is! String || !kinds.contains(kind)) return null;
      if (url is! String || url.isEmpty) return null;
      final name = json['name'];
      final size = json['size'];
      final type = json['type'];
      final e2e = json['e2e'];
      final key = e2e is Map ? e2e['key'] : null;
      final iv = e2e is Map ? e2e['iv'] : null;
      final hasKey = key is String && key.isNotEmpty;
      final hasIv = iv is String && iv.isNotEmpty;
      return AttachmentTag(
        kind: kind,
        name: name is String ? name : '',
        size: size is String
            ? size
            : size is num
            ? sizeText(size.toInt())
            : '',
        url: url,
        type: type is String ? type : '',
        e2eKey: hasKey && hasIv ? key : null,
        e2eIv: hasKey && hasIv ? iv : null,
        caption: text.replaceRange(match.start, match.end, '').trim(),
      );
    } on FormatException {
      return null;
    }
  }

  /// What a chat row, a reply quote or a search hit shows instead of the raw
  /// tag. Null when [text] is not an attachment.
  static String? preview(String text) {
    final tag = parse(text);
    if (tag == null) return null;
    return switch (tag.kind) {
      'image' => 'Photo',
      'video' => 'Video',
      'audio' => 'Voice note',
      _ => tag.name.isEmpty ? 'File' : tag.name,
    };
  }
}
