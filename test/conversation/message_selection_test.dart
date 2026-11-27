import 'package:connectum/core/selection/message_selection.dart';
import 'package:connectum/core/selection/selection_rules.dart';
import 'package:connectum/data/models/reaction.dart';
import 'package:connectum/features/conversation/models/emoji_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

SelectionTarget _t(
  String id, {
  bool reply = true,
  bool star = false,
  bool del = true,
  bool fwd = true,
  bool copy = true,
  bool pin = false,
  bool edit = false,
  bool retry = false,
  bool react = true,
  bool form = false,
}) => SelectionTarget(
  id: id,
  canReply: reply,
  canStar: star,
  canDelete: del,
  canForward: fwd,
  canCopy: copy,
  canPin: pin,
  canEdit: edit,
  canRetry: retry,
  canReact: react,
  hasFormMenu: form,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('which actions apply', () {
    test('one chat message: reply, delete, forward, copy in that order', () {
      expect(SelectionRules.available([_t('1')]), [
        SelectionAction.reply,
        SelectionAction.delete,
        SelectionAction.forward,
        SelectionAction.copy,
      ]);
    });

    test('one note: icons reply, star, delete; overflow copy, pin, edit', () {
      final list = SelectionRules.available([
        _t('1', star: true, pin: true, edit: true, fwd: false),
      ]);
      expect(list, [
        SelectionAction.reply,
        SelectionAction.star,
        SelectionAction.delete,
        SelectionAction.copy,
        SelectionAction.pin,
        SelectionAction.edit,
      ]);
    });

    test('a chat message: Edit is an icon right after Reply', () {
      final list = SelectionRules.available([
        _t('1', edit: true),
      ], isEditIcon: true);
      expect(list.take(2), [SelectionAction.reply, SelectionAction.edit]);
    });

    test('two messages: reply, edit, pin and retry go; the rest stay', () {
      final list = SelectionRules.available([
        _t('1', star: true, pin: true, edit: true, retry: true),
        _t('2', star: true, pin: true, edit: true, retry: true),
      ]);
      expect(list, [
        SelectionAction.star,
        SelectionAction.delete,
        SelectionAction.forward,
        SelectionAction.copy,
      ]);
    });

    test('an action needs every selected message to allow it', () {
      final list = SelectionRules.available([
        _t('1'),
        _t('2', del: false, fwd: false),
      ]);
      expect(list, [SelectionAction.copy]);
    });

    test('a failed message only keeps retry and remove', () {
      final failed = _t(
        '1',
        reply: false,
        fwd: false,
        copy: false,
        react: false,
        retry: true,
      );
      expect(SelectionRules.available([failed]), [
        SelectionAction.retry,
        SelectionAction.delete,
      ]);
    });

    test('a form message offers its menu in the overflow', () {
      final list = SelectionRules.available([
        _t('1', reply: false, fwd: false, copy: false, del: false, form: true),
      ]);
      expect(list, [SelectionAction.formMenu]);
    });

    test('nothing selected, nothing offered', () {
      expect(SelectionRules.available(const []), isEmpty);
    });
  });

  group('reaction bar rule', () {
    test('one message that takes reactions', () {
      expect(
        SelectionRules.showsReactions([_t('1')], isSupported: true),
        isTrue,
      );
    });
    test('never for two messages', () {
      expect(
        SelectionRules.showsReactions([_t('1'), _t('2')], isSupported: true),
        isFalse,
      );
    });
    test('never where the thread has none (notes, teams)', () {
      expect(
        SelectionRules.showsReactions([_t('1')], isSupported: false),
        isFalse,
      );
    });
    test('never for a message that cannot take one', () {
      expect(
        SelectionRules.showsReactions([
          _t('1', react: false),
        ], isSupported: true),
        isFalse,
      );
    });
  });

  group('icons versus overflow', () {
    final all = SelectionRules.available([
      _t('1', star: true, pin: true, edit: true),
    ]);

    test('320 px: at most four icons, the rest in the menu', () {
      final s = SelectionRules.split(all, 320);
      expect(s.icons, [
        SelectionAction.reply,
        SelectionAction.star,
        SelectionAction.delete,
        SelectionAction.forward,
      ]);
      expect(s.overflow, [
        SelectionAction.copy,
        SelectionAction.pin,
        SelectionAction.edit,
      ]);
    });

    test('320 px, a chat message: Reply, Edit, Delete, Forward are icons', () {
      final chat = SelectionRules.available([
        _t('1', edit: true),
      ], isEditIcon: true);
      final s = SelectionRules.split(chat, 320, isEditIcon: true);
      expect(s.icons, [
        SelectionAction.reply,
        SelectionAction.edit,
        SelectionAction.delete,
        SelectionAction.forward,
      ]);
    });

    test('a wider screen shows five icons', () {
      final s = SelectionRules.split([
        SelectionAction.retry,
        SelectionAction.reply,
        SelectionAction.star,
        SelectionAction.delete,
        SelectionAction.forward,
      ], 411);
      expect(s.icons, hasLength(5));
      expect(s.overflow, isEmpty);
    });

    test('an icon that does not fit moves to the front of the menu', () {
      final s = SelectionRules.split([
        SelectionAction.retry,
        SelectionAction.reply,
        SelectionAction.star,
        SelectionAction.delete,
        SelectionAction.forward,
        SelectionAction.copy,
      ], 320);
      expect(s.icons, hasLength(4));
      expect(s.overflow, [SelectionAction.forward, SelectionAction.copy]);
    });
  });

  group('selection state', () {
    late MessageSelection s;
    setUp(() => s = MessageSelection());

    test('long press selects one message', () {
      s.onLongPress('a');
      expect(s.ids, ['a']);
      expect(s.isSingle, isTrue);
      expect(s.only, 'a');
    });

    test('taps add others and the selected one is deselected', () {
      s.onLongPress('a');
      s.onTap('b');
      expect(s.ids, ['a', 'b']);
      expect(s.only, isNull);
      s.onTap('a');
      expect(s.ids, ['b']);
      s.onTap('b');
      expect(s.isActive, isFalse);
    });

    test('long press on a selected message keeps it selected', () {
      s.onLongPress('a');
      s.onLongPress('a');
      expect(s.ids, ['a']);
    });

    test('back (clear) leaves selection', () {
      s.onLongPress('a');
      s.onTap('b');
      s.clear();
      expect(s.isActive, isFalse);
    });

    test(
      'a message arriving keeps the selection; a vanished id is dropped',
      () {
        s.onLongPress('a');
        s.onTap('b');
        s.prune({'a', 'b', 'c'});
        expect(s.ids, ['a', 'b']);
        s.prune({'a', 'c'});
        expect(s.ids, ['a']);
      },
    );

    test('a scroll hides the bar and keeps the selection; a tap shows it', () {
      s.onLongPress('a');
      s.hideBar();
      expect(s.isBarHidden.value, isTrue);
      expect(s.isActive, isTrue);
      s.onTap('b');
      expect(s.isBarHidden.value, isFalse);
    });

    test('hiding with nothing selected does nothing', () {
      s.hideBar();
      expect(s.isBarHidden.value, isFalse);
    });
  });

  group('emoji the picker offers', () {
    test('the quick seven come first', () {
      expect(Reaction.quick, ['👍', '❤️', '😂', '😮', '😢', '🙏', '👏']);
      expect(EmojiCatalog.all.take(7).map((e) => e.emoji), Reaction.quick);
    });

    test('every emoji is one token the server takes, once', () {
      final list = EmojiCatalog.all.map((e) => e.emoji).toList();
      expect(list.toSet(), hasLength(list.length));
      expect(list.every(EmojiCatalog.isSendable), isTrue);
    });

    test('an emoji with a space is not sendable', () {
      expect(EmojiCatalog.isSendable('👍 👍'), isFalse);
      expect(EmojiCatalog.isSendable(''), isFalse);
    });

    test('search finds by word, and gives all for an empty query', () {
      expect(EmojiCatalog.search('').length, EmojiCatalog.all.length);
      expect(EmojiCatalog.search('rocket').map((e) => e.emoji), ['🚀']);
      expect(EmojiCatalog.search('zzzz'), isEmpty);
    });
  });
}
