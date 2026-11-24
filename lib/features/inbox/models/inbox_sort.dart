import 'inbox_filter.dart';
import 'inbox_row.dart';

final _digits = RegExp(r'(\d+)');

const _from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
const _to = 'aaaaaaceeeeiiiinooooouuuuyy';

/// Lower case with the common Latin accents folded, as the web's
/// `plainText`.
String _plain(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final r in lower.runes) {
    final c = String.fromCharCode(r);
    final i = _from.indexOf(c);
    out.write(i < 0 ? c : _to[i]);
  }
  return out.toString();
}

/// Compares two texts as the web's `localeCompare(..., {numeric:true,
/// sensitivity:"base"})`: runs of digits compare as numbers.
int naturalCompare(String a, String b) {
  final x = _plain(a);
  final y = _plain(b);
  final pa = _parts(x);
  final pb = _parts(y);
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final u = pa[i];
    final v = pb[i];
    final nu = BigInt.tryParse(u);
    final nv = BigInt.tryParse(v);
    final c = nu != null && nv != null ? nu.compareTo(nv) : u.compareTo(v);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}

List<String> _parts(String s) => _split(s);

List<String> _split(String s) {
  final out = <String>[];
  var at = 0;
  for (final m in _digits.allMatches(s)) {
    if (m.start > at) out.add(s.substring(at, m.start));
    out.add(m.group(0)!);
    at = m.end;
  }
  if (at < s.length) out.add(s.substring(at));
  return out;
}

/// The loaded rows in the order Sort says (`sortRows`): the server always
/// answers newest first; Oldest, A to Z and Z to A are the client's. A row
/// with no time goes last in Oldest. Equal rows keep the order they came in.
List<InboxRow> sortInboxRows(List<InboxRow> rows, String sort) {
  int time(InboxRow r) => r.ts > 0 ? r.ts : 0;
  int newest(InboxRow a, InboxRow b) => time(b) - time(a);
  int Function(InboxRow, InboxRow) by = newest;
  if (sort == InboxSort.oldest) {
    by = (a, b) => time(a) > 0 && time(b) > 0
        ? time(a) - time(b)
        : time(b) > 0
        ? 1
        : time(a) > 0
        ? -1
        : 0;
  } else if (sort == InboxSort.asc || sort == InboxSort.desc) {
    final dir = sort == InboxSort.asc ? 1 : -1;
    by = (a, b) {
      final c = dir * naturalCompare(a.subject, b.subject);
      return c != 0 ? c : newest(a, b);
    };
  }
  final indexed = [for (var i = 0; i < rows.length; i++) (i, rows[i])];
  indexed.sort((a, b) {
    final c = by(a.$2, b.$2);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
