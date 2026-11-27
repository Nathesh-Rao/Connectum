import '../../../data/models/reaction.dart';

/// One emoji the "+" picker offers, with the words the search matches.
class EmojiEntry {
  const EmojiEntry(this.emoji, this.words);

  final String emoji;
  final String words;
}

/// The emoji of the "+" picker. The server takes any one-token emoji for
/// `/react` (it only drops a line whose emoji has a space), so this is a
/// curated list, not a restriction. The quick row and the web's extra ten come
/// first.
class EmojiCatalog {
  EmojiCatalog._();

  static const _extra = [
    EmojiEntry('😀', 'smile happy grin'),
    EmojiEntry('😁', 'beam grin teeth'),
    EmojiEntry('🤣', 'rofl laugh floor'),
    EmojiEntry('😊', 'blush smile warm'),
    EmojiEntry('😍', 'love heart eyes'),
    EmojiEntry('😘', 'kiss love'),
    EmojiEntry('😎', 'cool sunglasses'),
    EmojiEntry('🤔', 'think hmm question'),
    EmojiEntry('😅', 'sweat nervous relief'),
    EmojiEntry('😉', 'wink'),
    EmojiEntry('🙂', 'slight smile'),
    EmojiEntry('🙃', 'upside down silly'),
    EmojiEntry('😴', 'sleep tired zzz'),
    EmojiEntry('😭', 'cry sob sad tears'),
    EmojiEntry('😡', 'angry mad rage'),
    EmojiEntry('😱', 'scream shock fear'),
    EmojiEntry('😬', 'grimace awkward'),
    EmojiEntry('🤯', 'mind blown'),
    EmojiEntry('🥳', 'party celebrate'),
    EmojiEntry('🤗', 'hug'),
    EmojiEntry('🫡', 'salute respect'),
    EmojiEntry('🤝', 'handshake deal agree'),
    EmojiEntry('👎', 'thumbs down no dislike'),
    EmojiEntry('👌', 'ok perfect'),
    EmojiEntry('✌️', 'peace victory'),
    EmojiEntry('🤞', 'fingers crossed luck'),
    EmojiEntry('💪', 'strong muscle power'),
    EmojiEntry('🙌', 'raised hands praise'),
    EmojiEntry('👋', 'wave hello bye'),
    EmojiEntry('✅', 'check done yes'),
    EmojiEntry('❌', 'cross no wrong'),
    EmojiEntry('⚠️', 'warning caution'),
    EmojiEntry('❓', 'question'),
    EmojiEntry('❗', 'exclamation important'),
    EmojiEntry('💡', 'idea light bulb'),
    EmojiEntry('📌', 'pin pushpin'),
    EmojiEntry('⭐', 'star favorite'),
    EmojiEntry('🌟', 'glowing star'),
    EmojiEntry('💥', 'boom collision'),
    EmojiEntry('🎯', 'target goal bullseye'),
    EmojiEntry('🏆', 'trophy win'),
    EmojiEntry('☕', 'coffee tea break'),
    EmojiEntry('🍕', 'pizza food'),
    EmojiEntry('🎂', 'cake birthday'),
    EmojiEntry('🌈', 'rainbow'),
    EmojiEntry('☀️', 'sun sunny'),
    EmojiEntry('🌧️', 'rain'),
    EmojiEntry('💙', 'blue heart'),
    EmojiEntry('💚', 'green heart'),
    EmojiEntry('💛', 'yellow heart'),
    EmojiEntry('🧡', 'orange heart'),
    EmojiEntry('💜', 'purple heart'),
    EmojiEntry('🖤', 'black heart'),
    EmojiEntry('💔', 'broken heart'),
    EmojiEntry('😇', 'angel innocent'),
    EmojiEntry('🤦', 'facepalm'),
    EmojiEntry('🤷', 'shrug unsure'),
    EmojiEntry('🙈', 'see no evil monkey'),
    EmojiEntry('🫶', 'heart hands love'),
    EmojiEntry('😂', 'joy tears laugh'),
  ];

  static const _names = {
    '👍': 'thumbs up like yes',
    '❤️': 'heart love red',
    '😂': 'joy tears laugh',
    '😮': 'wow surprised open mouth',
    '😢': 'cry sad tear',
    '🙏': 'pray thanks please folded hands',
    '👏': 'clap applause',
    '🔥': 'fire hot lit',
    '🎉': 'party tada celebrate',
    '💯': 'hundred perfect',
    '🚀': 'rocket launch fast',
    '✨': 'sparkles shiny',
    '🥰': 'smiling hearts love',
    '🤩': 'star struck wow',
    '👀': 'eyes look',
  };

  /// Every offered emoji once: the quick row, the web's extra ten, then the
  /// rest.
  static final List<EmojiEntry> all = () {
    final seen = <String>{};
    final out = <EmojiEntry>[];
    for (final e in [...Reaction.quick, ...Reaction.more]) {
      if (seen.add(e)) out.add(EmojiEntry(e, _names[e] ?? ''));
    }
    for (final e in _extra) {
      if (seen.add(e.emoji)) out.add(e);
    }
    return out;
  }();

  /// The emoji whose words contain every word of [query]; all when it is
  /// empty.
  static List<EmojiEntry> search(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return all;
    return [
      for (final e in all)
        if (words.every(e.words.contains) || words.every(e.emoji.contains)) e,
    ];
  }

  /// What the server takes: one token, no space.
  static bool isSendable(String emoji) =>
      emoji.isNotEmpty && !RegExp(r'\s').hasMatch(emoji);
}
