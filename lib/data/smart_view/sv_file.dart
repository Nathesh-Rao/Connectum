import '../../core/theme/app_colors.dart';
import '../models/ids.dart';

/// What a file is, from its mime type and name (never from the server's
/// `application/octet-stream`). Picks the icon, the tint and the viewer.
enum SvFileKind {
  image('IMG', AppColors.docWord),
  pdf('PDF', AppColors.docPdf),
  video('VID', AppColors.docSlides),
  audio('AUD', AppColors.docSlides),
  text('TXT', AppColors.docText),
  office('DOC', AppColors.docExcel),
  archive('ZIP', AppColors.docArchive),
  other('FILE', AppColors.docOther);

  const SvFileKind(this.label, this.palette);

  final String label;
  final AppTilePalette palette;

  /// Shown in the viewer as text (first 200 KB).
  bool get isTextual => this == text;
}

/// Which in-app viewer draws a file. `none` is the file card.
enum SvViewer { image, pdf, video, audio, sheet, docx, pptx, zip, text, none }

/// One file of a record: a Connectum file id with the name, type and size the
/// row's `files` map gives. Only the id is ever fetched.
class SvFile {
  const SvFile({
    required this.id,
    required this.name,
    this.mime = '',
    this.size = 0,
    this.ext,
    this.uploadedAt,
    this.etag,
    SvFileKind? kind,
  }) : _kind = kind;

  static final _id = RegExp(r'^[a-f0-9]{24}$');
  static final _etag = RegExp(r'^[a-f0-9]{64}$');
  static const maxPerCell = 20;
  static const maxNameChars = 120;
  static const maxTypeChars = 10;

  final String id;
  final String name;
  final String mime;
  final int size;

  /// `fileMeta:2` only. `''` means the name has no extension; null means the
  /// server did not say (an older server), so the name decides.
  final String? ext;

  /// Epoch ms of the upload, or null.
  final int? uploadedAt;

  /// Bare 64-hex SHA-256 of the content, or null.
  final String? etag;
  final SvFileKind? _kind;

  SvFileKind get kind => _kind ?? kindOf(name, mime);

  /// The name with path parts removed and control characters dropped; safe to
  /// use as a file name on the device. Never empty.
  /// The viewer for this file. Spreadsheets other than csv / tsv / xlsx and
  /// the legacy Office formats have none (file card).
  SvViewer get viewer {
    final ext = extensionOf(name);
    switch (kind) {
      case SvFileKind.image:
        return ext == 'bmp' || ext == 'heic' ? SvViewer.none : SvViewer.image;
      case SvFileKind.pdf:
        return SvViewer.pdf;
      case SvFileKind.video:
        return SvViewer.video;
      case SvFileKind.audio:
        return SvViewer.audio;
      case SvFileKind.text:
        return ext == 'csv' || ext == 'tsv' ? SvViewer.sheet : SvViewer.text;
      case SvFileKind.office:
        if (ext == 'xlsx') return SvViewer.sheet;
        if (ext == 'docx') return SvViewer.docx;
        if (ext == 'pptx') return SvViewer.pptx;
        return SvViewer.none;
      case SvFileKind.archive:
        return ext == 'zip' ? SvViewer.zip : SvViewer.none;
      case SvFileKind.other:
        return SvViewer.none;
    }
  }

  /// "PDF", "XLSX": the extension in capitals (letters and digits only), else
  /// IMAGE, DOC or TEXT from the mime type, else FILE.
  String get typeLabel {
    final plain = (ext ?? extensionOf(name)).replaceAll(
      RegExp(r'[^A-Za-z0-9]'),
      '',
    );
    if (plain.isNotEmpty && plain.length <= maxTypeChars) {
      return plain.toUpperCase();
    }
    final type = mime.toLowerCase().trim();
    if (type.startsWith('image/')) return 'IMAGE';
    if (type.startsWith('text/')) return 'TEXT';
    if (type == 'application/pdf' ||
        type.contains('msword') ||
        type.contains('ms-excel') ||
        type.contains('ms-powerpoint') ||
        type.contains('openxmlformats') ||
        type.contains('opendocument')) {
      return 'DOC';
    }
    return 'FILE';
  }

  /// "PDF · 51 KB": the type, and the size when it is known.
  String get metaText =>
      sizeText.isEmpty ? typeLabel : '$typeLabel · $sizeText';

  /// The viewer header: "PDF · 51 KB · Uploaded Nov 24, 2026 · 1 of 5". Parts
  /// that are not known are left out; the position shows with 2 files or more.
  String headerText({int position = 1, int total = 1}) {
    final up = uploadedAt;
    return [
      typeLabel,
      if (sizeText.isNotEmpty) sizeText,
      if (up != null) 'Uploaded ${_date(up)}',
      if (total > 1) '$position of $total',
    ].join(' · ');
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${_months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String get safeName => sanitizeName(name);

  String get sizeText => formatSize(size);

  String get semanticLabel => 'File $name, ${metaText.replaceAll(' · ', ', ')}';

  static bool isFileId(String id) => _id.hasMatch(id);

  static SvFile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = idText(raw['id']);
    if (!isFileId(id)) return null;
    final name = _cutName(idText(raw['name']));
    final ext = raw['ext'];
    final up = raw['uploadedAt'];
    final tag = raw['etag'];
    final size = intOf(raw['size']);
    return SvFile(
      id: id,
      name: name.isEmpty ? 'File' : name,
      mime: idText(raw['mime']),
      size: size > 0 ? size : 0,
      ext: ext is String ? ext : null,
      uploadedAt: up is num && up > 0 ? up.toInt() : null,
      etag: tag is String && _etag.hasMatch(tag.toLowerCase())
          ? tag.toLowerCase()
          : null,
    );
  }

  static String _cutName(String name) {
    if (name.length <= maxNameChars) return name;
    final units = name.codeUnits;
    var end = maxNameChars;
    if (units[end - 1] >= 0xD800 && units[end - 1] <= 0xDBFF) end--;
    return name.substring(0, end);
  }

  /// The files of one field: the ids in [value] in order, with the details
  /// from [info] (the row's `files[field]`); an id without details is `File`.
  static List<SvFile> listOf(Object? value, Object? info) {
    final byId = <String, SvFile>{};
    if (info is List) {
      for (final f in info) {
        final parsed = tryParse(f);
        if (parsed != null) byId[parsed.id] = parsed;
      }
    }
    final seen = <String>{};
    final out = <SvFile>[];
    if (value is List) {
      for (final x in value) {
        final id = idText(x);
        if (!isFileId(id) || !seen.add(id)) continue;
        out.add(byId[id] ?? SvFile(id: id, name: 'File'));
        if (out.length == maxPerCell) break;
      }
    }
    return out;
  }

  static const _images = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic'};
  static const _text = {
    'txt',
    'md',
    'log',
    'csv',
    'tsv',
    'json',
    'xml',
    'yaml',
    'yml',
    'ini',
    'sql',
    'dart',
    'js',
    'ts',
    'html',
    'css',
    'java',
    'py',
    'sh',
  };
  static const _office = {
    'doc',
    'docx',
    'odt',
    'rtf',
    'xls',
    'xlsx',
    'ods',
    'ppt',
    'pptx',
    'odp',
  };
  static const _archive = {'zip', 'rar', '7z', 'gz', 'tar', 'tgz', 'bz2'};
  static const _video = {'mp4', 'mov', 'webm', 'mkv', 'avi', 'm4v'};
  static const _audio = {'mp3', 'm4a', 'wav', 'ogg', 'aac', 'flac'};

  /// Mime type first (an image mime that is SVG stays `other`: SVG may carry
  /// script and is never drawn), then the extension.
  static SvFileKind kindOf(String name, String mime) {
    final type = mime.toLowerCase().trim();
    final ext = extensionOf(name);
    if (type == 'image/svg+xml' || ext == 'svg') return SvFileKind.other;
    if (type.startsWith('image/')) return SvFileKind.image;
    if (type == 'application/pdf') return SvFileKind.pdf;
    if (type.startsWith('video/')) return SvFileKind.video;
    if (type.startsWith('audio/')) return SvFileKind.audio;
    if (type.startsWith('text/') ||
        type == 'application/json' ||
        type == 'application/xml' ||
        type == 'application/x-yaml') {
      return SvFileKind.text;
    }
    if (type.contains('zip') ||
        type.contains('rar') ||
        type.contains('x-7z') ||
        type.contains('gzip') ||
        type.contains('x-tar')) {
      return type.contains('openxml') ? SvFileKind.office : SvFileKind.archive;
    }
    if (type.contains('msword') ||
        type.contains('ms-excel') ||
        type.contains('ms-powerpoint') ||
        type.contains('openxmlformats') ||
        type.contains('opendocument')) {
      return SvFileKind.office;
    }
    if (ext == 'pdf') return SvFileKind.pdf;
    if (_images.contains(ext)) return SvFileKind.image;
    if (_text.contains(ext)) return SvFileKind.text;
    if (_office.contains(ext)) return SvFileKind.office;
    if (_archive.contains(ext)) return SvFileKind.archive;
    if (_video.contains(ext)) return SvFileKind.video;
    if (_audio.contains(ext)) return SvFileKind.audio;
    return SvFileKind.other;
  }

  static String extensionOf(String name) {
    final last = name.split(RegExp(r'[/\\]')).last;
    final dot = last.lastIndexOf('.');
    if (dot <= 0 || dot == last.length - 1) return '';
    return last.substring(dot + 1).toLowerCase();
  }

  /// A server name is untrusted text: path separators, control characters and
  /// leading dots go; the length is capped, the extension kept.
  static String sanitizeName(String raw) {
    var name = raw.split(RegExp(r'[/\\]')).last;
    name = name
        .replaceAll(RegExp(r'[\x00-\x1F\x7F:*?"<>|]'), '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .trim();
    if (name.length > 100) {
      final ext = extensionOf(name);
      final keep = ext.isEmpty || ext.length > 10 ? 0 : ext.length + 1;
      name = '${name.substring(0, 100 - keep)}${keep == 0 ? '' : '.$ext'}';
    }
    return name.isEmpty ? 'file' : name;
  }

  /// `980 B`, `1.5 KB`, `51 KB`, `5.0 MB`; empty when the size is not known
  /// (0 or less).
  static String formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 10) return '${kb.toStringAsFixed(1)} KB';
    if (kb.round() < 1024) return '${kb.round()} KB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  /// [name] with the middle cut out and the extension kept.
  static String middleEllipsis(String name, int maxChars) {
    if (name.length <= maxChars) return name;
    final ext = extensionOf(name);
    final tail = (ext.isEmpty ? 6 : ext.length + 1 + 4).clamp(1, maxChars ~/ 2);
    final head = maxChars - tail - 1;
    return '${name.substring(0, head)}…${name.substring(name.length - tail)}';
  }
}
