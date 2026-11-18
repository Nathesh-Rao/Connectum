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
    SvFileKind? kind,
  }) : _kind = kind;

  static final _id = RegExp(r'^[a-f0-9]{24}$');
  static const maxPerCell = 20;

  final String id;
  final String name;
  final String mime;
  final int size;
  final SvFileKind? _kind;

  SvFileKind get kind => _kind ?? kindOf(name, mime);

  /// The name with path parts removed and control characters dropped; safe to
  /// use as a file name on the device. Never empty.
  /// The viewer for this file. Spreadsheets other than csv / tsv and the
  /// legacy Office formats have none (file card).
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
        if (ext == 'docx') return SvViewer.docx;
        if (ext == 'pptx') return SvViewer.pptx;
        return SvViewer.none;
      case SvFileKind.archive:
        return ext == 'zip' ? SvViewer.zip : SvViewer.none;
      case SvFileKind.other:
        return SvViewer.none;
    }
  }

  /// "PDF", "XLSX": the extension in capitals, else the kind label.
  String get typeLabel {
    final ext = extensionOf(name).toUpperCase();
    return ext.isEmpty || ext.length > 5 ? kind.label : ext;
  }

  String get safeName => sanitizeName(name);

  String get sizeText => formatSize(size);

  /// `<id>_<size>`: a cache key that changes when the file does.
  String get cacheKey => '${id}_$size';

  String get semanticLabel =>
      sizeText.isEmpty ? 'File $name' : 'File $name, $sizeText';

  static bool isFileId(String id) => _id.hasMatch(id);

  static SvFile? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = idText(raw['id']);
    if (!isFileId(id)) return null;
    final name = idText(raw['name']);
    return SvFile(
      id: id,
      name: name.isEmpty ? 'File' : name,
      mime: idText(raw['mime']),
      size: intOf(raw['size']),
    );
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

  /// `1.2 MB`, `340 KB`, `12 B`; empty when the size is not known.
  static String formatSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
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
