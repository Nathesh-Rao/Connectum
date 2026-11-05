import '../../../core/theme/app_colors.dart';
import '../../../core/utils/attachment_tag.dart';
import 'file_download.dart';

/// The family a document belongs to; picks the tile label and tint.
enum DocumentKind {
  pdf('PDF', AppColors.docPdf, 'application/pdf'),
  word('DOC', AppColors.docWord, 'word'),
  excel('XLS', AppColors.docExcel, 'excel'),
  slides('PPT', AppColors.docSlides, 'powerpoint'),
  text('TXT', AppColors.docText, 'text/plain'),
  archive('ZIP', AppColors.docArchive, 'zip'),
  other('FILE', AppColors.docOther, '');

  const DocumentKind(this.label, this.palette, this._mimeHint);

  final String label;
  final AppTilePalette palette;
  final String _mimeHint;

  static const _extensions = {
    'pdf': pdf,
    'doc': word,
    'docx': word,
    'odt': word,
    'rtf': word,
    'xls': excel,
    'xlsx': excel,
    'csv': excel,
    'ods': excel,
    'ppt': slides,
    'pptx': slides,
    'odp': slides,
    'txt': text,
    'md': text,
    'log': text,
    'zip': archive,
    'rar': archive,
    '7z': archive,
    'gz': archive,
    'tar': archive,
  };

  /// By the file name's extension first, then by the MIME type.
  static DocumentKind of(String name, String mime) {
    final byName = _extensions[extensionOf(name)];
    if (byName != null) return byName;
    final type = mime.toLowerCase();
    if (type.isEmpty) return other;
    for (final kind in values) {
      if (kind._mimeHint.isNotEmpty && type.contains(kind._mimeHint)) {
        return kind;
      }
    }
    return type.contains('spreadsheet')
        ? excel
        : type.contains('presentation')
        ? slides
        : type.contains('wordprocessing')
        ? word
        : other;
  }

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }
}

/// What a document card shows for an attachment: kind, name and info line.
class DocumentInfo {
  DocumentInfo._(this.kind, this.name, this.tileLabel, this.details);

  factory DocumentInfo.of(AttachmentTag tag) {
    final kind = DocumentKind.of(tag.name, tag.type);
    final ext = DocumentKind.extensionOf(tag.name).toUpperCase();
    final label =
        kind == DocumentKind.other && ext.isNotEmpty && ext.length <= 4
        ? ext
        : kind.label;
    return DocumentInfo._(
      kind,
      tag.name.isEmpty ? 'File' : tag.name,
      label,
      tag.size.isEmpty ? label : '$label · ${tag.size}',
    );
  }

  /// Longest name drawn before the middle is cut out (about two lines).
  static const maxNameChars = 32;

  final DocumentKind kind;
  final String name;
  final String tileLabel;

  /// "PDF · 2.4 MB"
  final String details;

  /// [name] with the middle replaced by an ellipsis; the end, with the
  /// extension, stays.
  String get shortName => middleEllipsis(name, maxNameChars);

  static String middleEllipsis(String name, int maxChars) {
    if (name.length <= maxChars) return name;
    final ext = DocumentKind.extensionOf(name);
    final tail = (ext.isEmpty ? 6 : ext.length + 1 + 5).clamp(1, maxChars ~/ 2);
    final head = maxChars - tail - 1;
    return '${name.substring(0, head)}…${name.substring(name.length - tail)}';
  }
}

/// The action button on a document card.
enum DocumentButtonState {
  idle,
  downloading,
  done,
  failed;

  /// A running [download] wins, then a failed one; with none, the file is
  /// either on the phone ([isSaved]) or still to fetch. A cancelled download
  /// is removed by the controller and so reads as idle again.
  static DocumentButtonState of({
    required bool isSaved,
    required FileDownload? download,
  }) {
    if (download != null) {
      return download.isFailed.value ? failed : downloading;
    }
    return isSaved ? done : idle;
  }
}
