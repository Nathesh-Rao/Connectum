import '../models/hash_command.dart';

/// Which commands the menu offers and in what order, with the web's rules
/// (hashCommandsCatalog.js).
class CommandMenu {
  CommandMenu._();

  /// Run when typed in full, never offered.
  static const hidden = {
    'forms',
    'form',
    'historyhost',
    'transfer',
    'scan',
    'lookups',
  };

  static const _permissionOf = {
    'broadcast': 'broadcast',
    'announce': 'broadcast',
    'studio': 'studio.use',
    'code': 'studio.use',
    'ide': 'studio.use',
    'addemployee': 'invite.employees',
    'inviteemployee': 'invite.employees',
  };

  /// The permission a command needs on top of the server's `requires`.
  static String? permissionOf(HashCommand c) => _permissionOf[c.name];

  /// Offered to this person: not hidden, permission held, `admin` only for
  /// admins. Unknown permissions (null) keep those commands out.
  static bool isOffered(
    HashCommand c, {
    Set<String>? permissions,
    bool isAdmin = false,
  }) {
    if (hidden.contains(c.name)) return false;
    if (c.requires == 'admin' && !isAdmin) return false;
    final need = permissionOf(c);
    if (need != null && !(permissions?.contains(need) ?? false)) return false;
    return true;
  }

  /// Higher is better; 0 does not match.
  static int score(HashCommand c, String query) {
    final q = query.toLowerCase();
    if (c.name == q) return 100;
    if (c.aliases.contains(q)) return 90;
    if (c.name.startsWith(q)) return 80;
    if (c.aliases.any((a) => a.startsWith(q))) return 70;
    if (c.name.contains(q)) return 50;
    if (c.aliases.any((a) => a.contains(q))) return 40;
    if (c.summary.toLowerCase().contains(q)) return 30;
    if (c.category.toLowerCase().contains(q)) return 20;
    return 0;
  }

  /// The rows for [query] (the text after `#`). With nothing typed they are
  /// grouped by [categories]' order (unknown and custom categories last, in
  /// the catalogue's order); otherwise by score, ties in catalogue order.
  static List<HashCommand> filter(
    List<HashCommand> catalog,
    String query, {
    List<CommandCategory> categories = const [],
    Set<String>? permissions,
    bool isAdmin = false,
  }) {
    final offered = [
      for (final c in catalog)
        if (isOffered(c, permissions: permissions, isAdmin: isAdmin)) c,
    ];
    if (query.isEmpty) {
      int rank(HashCommand c) {
        final i = categories.indexWhere((x) => x.id == c.category);
        return i < 0 ? categories.length : i;
      }

      final indexed = offered.asMap().entries.toList()
        ..sort((a, b) {
          final r = rank(a.value).compareTo(rank(b.value));
          return r != 0 ? r : a.key.compareTo(b.key);
        });
      return [for (final e in indexed) e.value];
    }
    final scored = <(int, int, HashCommand)>[];
    for (var i = 0; i < offered.length; i++) {
      final s = score(offered[i], query);
      if (s > 0) scored.add((s, i, offered[i]));
    }
    scored.sort(
      (a, b) => b.$1 != a.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2),
    );
    return [for (final s in scored) s.$3];
  }

  /// The command a typed word runs: exact name or alias, server commands
  /// before local ones.
  static HashCommand? find(List<HashCommand> catalog, String word) {
    final w = word.toLowerCase();
    for (final c in catalog) {
      if (!c.isLocal && c.answersTo(w)) return c;
    }
    for (final c in catalog) {
      if (c.isLocal && c.answersTo(w)) return c;
    }
    return null;
  }

  /// Screens the app has that the server does not know as commands.
  static List<HashCommand> localEntries(List<HashCommand> server) {
    bool taken(String word) => server.any((c) => c.answersTo(word));
    List<String> free(List<String> words) => [
      for (final w in words)
        if (!taken(w)) w,
    ];
    return [
      if (!taken('tasks'))
        HashCommand(
          name: 'tasks',
          aliases: free(const ['task', 'todo']),
          category: 'people',
          summary: 'Open your tasks and to-dos',
          usage: '#tasks',
          isLocal: true,
        ),
      if (!taken('connections'))
        HashCommand(
          name: 'connections',
          aliases: free(const ['contacts', 'associates-screen']),
          category: 'people',
          summary: 'People you are connected with',
          usage: '#connections',
          isLocal: true,
        ),
    ];
  }
}
