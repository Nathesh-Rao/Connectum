import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_formatter.dart';
import 'log_settings_store.dart';

/// What the Settings tile shows.
class LogState {
  const LogState({this.isEnabled = false, this.fileName, this.sizeBytes = 0});

  final bool isEnabled;
  final String? fileName;
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is LogState &&
      other.isEnabled == isEnabled &&
      other.fileName == fileName &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(isEnabled, fileName, sizeBytes);
}

/// The opt-in log file. Nothing exists on disk until [startNew] runs once.
/// Every public method swallows its own failures (a debugPrint only, never
/// AppLog) so logging can never throw, block or recurse.
class LogFileSink {
  LogFileSink({
    required Future<Directory> Function() directory,
    DateTime Function()? clock,
    LogContext Function()? context,
    Future<LogEnvironment> Function()? environment,
    this.maxBytes = 10 * 1024 * 1024,
    this.flushInterval = const Duration(seconds: 2),
    this.flushLines = 50,
  }) : _directory = directory,
       _clock = clock ?? DateTime.now,
       _context = context ?? (() => LogContext.unknown),
       _environment = environment ?? (() async => const LogEnvironment());

  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final LogContext Function() _context;
  final Future<LogEnvironment> Function() _environment;
  final int maxBytes;
  final Duration flushInterval;
  final int flushLines;

  final state = ValueNotifier<LogState>(const LogState());

  final _buffer = StringBuffer();
  Future<void> _chain = Future.value();
  Timer? _timer;
  LogSettingsStore? _store;
  LogSettings _settings = const LogSettings();
  File? _file;
  int _size = 0;
  int _lines = 0;
  bool _isCapped = false;
  String? _lastContextKey;
  String? _lastDate;
  _Pending? _pending;
  int _repeats = 1;
  LogEnvironment _env = const LogEnvironment();

  bool get isEnabled => _file != null && state.value.isEnabled;

  /// Reads the saved switch. With it ON the current file is continued under a
  /// one-line session marker; a file deleted meanwhile is replaced.
  Future<void> init() async {
    try {
      final dir = await _dir();
      _store = LogSettingsStore(dir);
      _settings = await _store!.load();
      _env = await _environment();
      final name = _settings.fileName;
      final existing = name == null ? null : File('${dir.path}/$name');
      final hasFile = existing != null && await existing.exists();
      if (!_settings.isEnabled) {
        _size = hasFile ? await existing.length() : 0;
        _publish(isEnabled: false, name: hasFile ? name : null, file: existing);
        return;
      }
      if (!hasFile) {
        await _create(dir);
        return;
      }
      _file = existing;
      _size = await existing.length();
      _isCapped = _size >= maxBytes;
      _lastContextKey = _contextKey(_context());
      _startSession(_clock());
      final previous = _settings.version;
      if (previous != null && previous != _env.version) {
        _add('I', 'app', 'App version changed: $previous -> ${_env.version}');
      }
      await _saveSettings(
        isEnabled: true,
        name: name,
        created: _settings.created,
      );
      _publish(isEnabled: true, name: name, file: existing);
    } catch (e) {
      debugPrint('log init failed: ${e.runtimeType}');
    }
  }

  /// True when the saved file still exists on disk.
  Future<bool> hasOldFile() async {
    try {
      final name = _settings.fileName;
      if (name == null) return false;
      return await File('${(await _dir()).path}/$name').exists();
    } catch (e) {
      debugPrint('log check failed: ${e.runtimeType}');
      return false;
    }
  }

  /// Deletes an old file if there is one, creates a new one with a header and
  /// switches logging on.
  Future<void> startNew() async {
    try {
      await flush();
      final dir = await _dir();
      final old = _settings.fileName;
      if (old != null) {
        final f = File('${dir.path}/$old');
        if (await f.exists()) await f.delete();
      }
      _file = null;
      _env = await _environment();
      await _create(dir);
    } catch (e) {
      debugPrint('log start failed: ${e.runtimeType}');
    }
  }

  /// Keeps the old file, adds a new header block and switches logging on. With
  /// no file on disk this is [startNew].
  Future<void> startAppend() async {
    try {
      final name = _settings.fileName;
      final dir = await _dir();
      final f = name == null ? null : File('${dir.path}/$name');
      if (f == null || !await f.exists()) return startNew();
      _env = await _environment();
      _file = f;
      _size = await f.length();
      _isCapped = _size >= maxBytes;
      _pending = null;
      _repeats = 1;
      final context = _context();
      _lastContextKey = _contextKey(context);
      if (!_isCapped) {
        final now = _clock();
        _enqueue(
          LogFormatter.header(
            env: _env,
            fileCreated: _settings.created ?? LogFormatter.withOffset(now),
            started: now,
            context: context,
            isAppend: true,
          ),
        );
        _startSession(now);
      }
      await _saveSettings(
        isEnabled: true,
        name: name,
        created: _settings.created,
      );
      _publish(isEnabled: true, name: name, file: f);
      await flush();
    } catch (e) {
      debugPrint('log append failed: ${e.runtimeType}');
    }
  }

  /// Writes the closing line, flushes, keeps the file and stops writing.
  Future<void> disable() async {
    try {
      if (isEnabled) _add('I', 'logs', 'LOGGING DISABLED');
      await flush();
      final file = _file;
      _file = null;
      await _saveSettings(
        isEnabled: false,
        name: _settings.fileName,
        created: _settings.created,
      );
      _publish(isEnabled: false, name: _settings.fileName, file: file);
    } catch (e) {
      debugPrint('log disable failed: ${e.runtimeType}');
    }
  }

  /// One entry. The caller is worked out here, only while logging is on, and
  /// is written for warnings and errors only.
  void log(String level, String tag, String message, {StackTrace? stack}) {
    if (_file == null) return;
    try {
      final trace = stack ?? StackTrace.current;
      _add(
        level,
        tag,
        message,
        caller: level == 'I' ? null : LogFormatter.caller(trace),
        details: level == 'E' && stack != null
            ? LogFormatter.frames(stack)
            : const [],
      );
    } catch (e) {
      debugPrint('log write failed: ${e.runtimeType}');
    }
  }

  /// One entry with no stack work: the API lines, whose message already
  /// carries the caller and body as extra lines.
  void logRaw(String level, String tag, String message) {
    if (_file == null) return;
    try {
      _add(level, tag, message);
    } catch (e) {
      debugPrint('log write failed: ${e.runtimeType}');
    }
  }

  /// Call when the signed-in user or organisation may have changed: one
  /// `SESSION` line when it did.
  void updateContext() {
    if (_file == null) return;
    try {
      final c = _context();
      final key = _contextKey(c);
      if (key == _lastContextKey) return;
      _lastContextKey = key;
      _add('I', 'session', 'user=${c.userLabel}  org=${c.orgLabel}');
    } catch (e) {
      debugPrint('log context failed: ${e.runtimeType}');
    }
  }

  /// Waits until everything buffered so far is on disk.
  Future<void> flush() {
    try {
      _timer?.cancel();
      _timer = null;
      _flushPending();
      final file = _file;
      if (_buffer.isNotEmpty && file != null) {
        final text = _buffer.toString();
        _buffer.clear();
        _lines = 0;
        _chain = _chain
            .then(
              (_) =>
                  file.writeAsString(text, mode: FileMode.append, flush: true),
            )
            .then(
              (_) => _publish(
                isEnabled: state.value.isEnabled,
                name: state.value.fileName,
                file: file,
              ),
            )
            .catchError((Object e) {
              debugPrint('log flush failed: ${e.runtimeType}');
            });
      } else {
        _buffer.clear();
        _lines = 0;
      }
    } catch (e) {
      debugPrint('log flush failed: ${e.runtimeType}');
    }
    return _chain;
  }

  /// The current file after a flush, or null when there is none on disk.
  Future<File?> fileForExport() async {
    try {
      await flush();
      final name = state.value.fileName ?? _settings.fileName;
      if (name == null) return null;
      final f = File('${(await _dir()).path}/$name');
      return await f.exists() ? f : null;
    } catch (e) {
      debugPrint('log export failed: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> dispose() async {
    await flush();
    state.dispose();
  }

  Future<Directory> _dir() async {
    final d = await _directory();
    await d.create(recursive: true);
    return d;
  }

  Future<void> _create(Directory dir) async {
    final now = _clock();
    final name = LogFormatter.fileName(now);
    final file = File('${dir.path}/$name');
    final created = LogFormatter.withOffset(now);
    final header =
        LogFormatter.header(
          env: _env,
          fileCreated: created,
          started: now,
          context: _context(),
          isAppend: false,
        ) +
        LogFormatter.sessionBlock(now, _env.version);
    await file.writeAsString(header, flush: true);
    _file = file;
    _size = utf8.encode(header).length;
    _isCapped = false;
    _pending = null;
    _repeats = 1;
    _lastContextKey = _contextKey(_context());
    _lastDate = LogFormatter.date(now);
    await _saveSettings(isEnabled: true, name: name, created: created);
    _publish(isEnabled: true, name: name, file: file);
  }

  Future<void> _saveSettings({
    required bool isEnabled,
    required String? name,
    required String? created,
  }) async {
    _settings = LogSettings(
      isEnabled: isEnabled,
      fileName: name,
      created: created,
      version: _env.version,
    );
    await _store?.save(_settings);
  }

  static String _contextKey(LogContext c) => '${c.userLabel}|${c.orgLabel}';

  /// A session box and the date line under it.
  void _startSession(DateTime at) {
    _flushPending();
    _lastDate = LogFormatter.date(at);
    _enqueue(LogFormatter.sessionBlock(at, _env.version));
  }

  /// Holds the newest entry so identical ones that follow only raise its
  /// count; the line is written once, with `(xN)` when N is 2 or more.
  void _add(
    String level,
    String tag,
    String message, {
    String? caller,
    List<String> details = const [],
  }) {
    final next = _Pending(_clock(), level, tag, message, caller, details);
    final held = _pending;
    if (held != null && held.key == next.key) {
      _repeats++;
      return;
    }
    _flushPending();
    _pending = next;
  }

  void _flushPending() {
    final p = _pending;
    if (p == null) return;
    _pending = null;
    final day = LogFormatter.date(p.at);
    if (day != _lastDate) {
      _lastDate = day;
      _enqueue(LogFormatter.dateLine(p.at));
    }
    _enqueue(
      LogFormatter.entry(
        at: p.at,
        level: p.level,
        tag: p.tag,
        message: p.message,
        caller: p.caller,
        details: p.details,
        repeat: _repeats,
      ),
    );
    _repeats = 1;
  }

  void _enqueue(String text) {
    if (_isCapped) return;
    final bytes = utf8.encode(text).length;
    if (_size + bytes > maxBytes) {
      _isCapped = true;
      text = '${LogFormatter.capLine}\n';
      _size += utf8.encode(text).length;
    } else {
      _size += bytes;
    }
    _buffer.write(text);
    _lines += '\n'.allMatches(text).length;
    if (_lines >= flushLines) {
      flush();
    } else {
      _timer ??= Timer(flushInterval, flush);
    }
  }

  void _publish({required bool isEnabled, String? name, File? file}) {
    final next = LogState(
      isEnabled: isEnabled,
      fileName: name,
      sizeBytes: _size,
    );
    if (state.value != next) state.value = next;
  }
}

class _Pending {
  _Pending(
    this.at,
    this.level,
    this.tag,
    this.message,
    this.caller,
    this.details,
  );

  final DateTime at;
  final String level;
  final String tag;
  final String message;
  final String? caller;
  final List<String> details;

  String get key => '$level|${LogFormatter.category(tag)}|$message|$caller';
}
