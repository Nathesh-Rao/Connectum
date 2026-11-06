import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../core/debug/seed_commands.dart';
import '../../core/widgets/app_notices.dart';
import '../../data/commands/command_line.dart';
import '../../data/commands/command_menu.dart';
import '../../data/commands/command_reply.dart';
import '../../data/models/hash_command.dart';

/// `/debug/commands`: the "#" logic against the fixture of the doc. Nothing
/// here reaches a server.
class DebugCommandsController extends GetxController {
  final text = TextEditingController();
  final focus = FocusNode();
  final lines = <String>[].obs;

  late final catalog = [
    for (final j in SeedCommands.catalogFrame()['commands'] as List)
      HashCommand.fromJson((j as Map).cast<String, dynamic>()),
  ];
  late final categories = [
    for (final c in SeedCommands.catalogFrame()['categories'] as List)
      CommandCategory((c as Map)['id'] as String, c['label'] as String),
  ];

  late final _suggester =
      CommandSuggester(
          (input, page, reqId) => SeedCommands.suggest(
            input,
            page,
            reqId,
            latency: Duration(milliseconds: _latency),
          ),
        )
        ..onResult = (r, {required isMore}) => _log(
          'suggestions #${r.reqId} for "${r.input}": '
          '${r.items.map((i) => i.value).join(', ')}${r.hasMore ? ' (more)' : ''}',
        );

  int _latency = 300;

  void _log(String line) => lines.insert(0, line);

  void onChanged(String value) {
    final rows = CommandMenu.filter(
      catalog,
      value.trimLeft().startsWith('#') &&
              CommandLine.parse(value)?.hasSpace != true
          ? value.trimLeft().substring(1)
          : '',
      categories: categories,
      permissions: <String>{},
    );
    final parsed = CommandLine.parse(value);
    _log(
      CommandLine.opensMenu(value)
          ? 'menu: ${rows.take(6).map((c) => '#${c.name}').join(' ')}'
                '${parsed?.hasSpace == true ? ' · args of #${parsed!.name}' : ''}'
          : 'plain chat text',
    );
    if (parsed != null && parsed.hasSpace) _suggester.request(value);
  }

  /// A fast answer for a newer request overtakes a slow one: only the newest
  /// shows.
  void staleDemo() {
    _latency = 1200;
    _suggester.request('#dm a');
    Timer(const Duration(milliseconds: 300), () {
      _latency = 100;
      _suggester.request('#dm r');
    });
    _log('stale demo: slow "a" then fast "r"; only "r" should show');
  }

  void validate() {
    final value = text.text;
    final parsed = CommandLine.parse(value);
    final cmd = parsed == null ? null : CommandMenu.find(catalog, parsed.name);
    if (parsed == null || cmd == null) {
      _log('not a known command');
      return;
    }
    final args = parsed.bind(cmd, groupNames: const ['Team A', 'Team A Lead']);
    _log(CommandValidator.check(cmd, args) ?? 'valid: ${args.values}');
  }

  void unknown() => _show(SeedCommands.unknownFrame('dmm'));

  void usage() => _show(SeedCommands.usageFrame());

  void _show(Map<String, dynamic> frame) {
    final r = CommandReply.fromFrame(frame, name: 'dm');
    if (r == null) return;
    _log(
      '${r.code}: ${r.message} ${r.suggestions.map((s) => '#$s').join(' ')}',
    );
    AppNotices.warning(r.message);
  }

  @override
  void onClose() {
    _suggester.dispose();
    text.dispose();
    focus.dispose();
    super.onClose();
  }
}
