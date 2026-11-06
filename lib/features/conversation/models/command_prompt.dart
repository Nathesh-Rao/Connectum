import 'package:get/get.dart';

import '../../../data/commands/command_line.dart';
import '../../../data/commands/command_reply.dart';
import '../../../data/models/hash_command.dart';
import '../../../data/repositories/command_repository.dart';

/// The "#" menu of one composer. Two stages: while the command name is being
/// written it lists the catalogue; once a space follows a known name it asks
/// the server for the choices of the current argument. The owner calls
/// [dispose].
class CommandPrompt {
  CommandPrompt(this._commands) {
    _suggester = _commands.createSuggester()..onResult = _onResult;
  }

  final CommandRepository _commands;
  late final CommandSuggester _suggester;

  /// The text after the `#` while the name is being written, else null.
  final query = RxnString();

  /// The command whose arguments are being written, else null.
  final command = Rxn<HashCommand>();

  /// Choices for the current argument.
  final items = <CommandSuggestion>[].obs;
  final hasMore = false.obs;
  final isLoadingItems = false.obs;

  /// The argument being written: its name and a one-line hint (usage, or the
  /// characters left for a text argument).
  final argName = ''.obs;
  final hint = ''.obs;

  /// Names the server suggested for an unknown command.
  final unknownNames = <String>[].obs;

  String _input = '';
  String _token = '';
  int _page = 1;

  bool get isOpen =>
      query.value != null || command.value != null || unknownNames.isNotEmpty;

  void onTextChanged(String value, {int? caret}) {
    unknownNames.clear();
    if (!CommandLine.opensMenu(value)) {
      close();
      return;
    }
    final end = caret == null ? value.length : caret.clamp(0, value.length);
    final upTo = value.substring(0, end).trimLeft();
    final parsed = CommandLine.parse(upTo);
    if (parsed == null || !parsed.hasSpace) {
      _toNames(upTo.length <= 1 ? '' : upTo.substring(1));
      return;
    }
    final cmd = _commands.find(parsed.name);
    if (cmd == null) {
      close();
      return;
    }
    query.value = null;
    command.value = cmd;
    _input = upTo;
    _readArgument(cmd, parsed.rest);
  }

  void _toNames(String next) {
    final wasOpen = query.value != null;
    command.value = null;
    items.clear();
    hasMore.value = false;
    _suggester.cancel();
    if (next == query.value && wasOpen) return;
    query.value = next;
    _commands.ensureLoaded();
  }

  void _readArgument(HashCommand cmd, String rest) {
    final args = cmd.args;
    if (args.isEmpty) {
      argName.value = '';
      hint.value = cmd.usage;
      items.clear();
      return;
    }
    final at = rest.isEmpty ? 0 : rest.split(' ').length - 1;
    final arg = args[at < args.length ? at : args.length - 1];
    argName.value = arg.name;
    final isText = arg.isRest || arg.type == 'text' && at >= args.length - 1;
    if (isText) {
      _suggester.cancel();
      items.clear();
      hasMore.value = false;
      final used = at < args.length ? rest.split(' ').skip(at).join(' ') : '';
      final max = arg.max;
      hint.value = max == null
          ? cmd.usage
          : '${cmd.usage}  ·  ${max - used.runes.length} left';
      return;
    }
    hint.value = cmd.usage;
    isLoadingItems.value = true;
    _page = 1;
    _suggester.request(_input);
  }

  void _onResult(CommandSuggestions r, {required bool isMore}) {
    isLoadingItems.value = false;
    _page = r.page;
    _token = r.token;
    if (r.kind != 'arg') {
      items.clear();
      hasMore.value = false;
      return;
    }
    if (r.argName.isNotEmpty) argName.value = r.argName;
    isMore ? items.addAll(r.items) : items.assignAll(r.items);
    hasMore.value = r.hasMore;
  }

  /// Asks for the next page of choices.
  void loadMore() {
    if (!hasMore.value || isLoadingItems.value) return;
    isLoadingItems.value = true;
    _suggester.request(_input, page: _page + 1);
  }

  /// The text with [item] in place of the word being written, and one space.
  String insert(CommandSuggestion item) {
    var base = _input;
    if (_token.isNotEmpty && base.endsWith(_token)) {
      base = base.substring(0, base.length - _token.length);
    } else {
      final cut = base.lastIndexOf(' ');
      base = base.substring(0, cut + 1);
    }
    return '$base${item.value} ';
  }

  /// [text] with the command name replaced by [name] (a suggested one).
  static String rename(String text, String name) {
    final t = text.trimLeft();
    final parsed = CommandLine.parse(t);
    if (parsed == null) return '#$name ';
    final tail = t.substring(1 + parsed.name.length);
    return '#$name$tail';
  }

  void close() {
    query.value = null;
    command.value = null;
    items.clear();
    hasMore.value = false;
    isLoadingItems.value = false;
    unknownNames.clear();
    _suggester.cancel();
  }

  void dispose() => _suggester.dispose();

  List<HashCommand> get matches => _commands.menu(query.value ?? '');

  bool get isLoading => _commands.isLoading.value;

  /// Read inside an Obx so the list follows the catalogue as it arrives.
  bool get hasCatalog => _commands.catalog.isNotEmpty;
}
