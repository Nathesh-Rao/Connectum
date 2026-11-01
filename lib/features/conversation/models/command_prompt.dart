import 'package:get/get.dart';

import '../../../data/models/hash_command.dart';
import '../../../data/repositories/command_repository.dart';

/// The "#" commands list of one composer. It is open while the text starts
/// with `#` and no space has been typed yet (the command name is still being
/// written), and lists the catalog filtered by that prefix.
class CommandPrompt {
  CommandPrompt(this._commands);

  final CommandRepository _commands;

  /// The text after the `#`, or null while the list is closed.
  final query = RxnString();

  void onTextChanged(String value) {
    final t = value.trimLeft();
    final isOpen = t.startsWith('#') && !t.contains(RegExp(r'\s'));
    final next = isOpen ? t.substring(1) : null;
    if (next == query.value) return;
    query.value = next;
    if (isOpen) _commands.ensureLoaded();
  }

  void close() => query.value = null;

  List<HashCommand> get matches => _commands.matching(query.value ?? '');

  bool get isLoading => _commands.isLoading.value;

  /// Read inside an Obx so the list follows the catalog as it arrives.
  bool get hasCatalog => _commands.catalog.isNotEmpty;
}
