import 'ai_models.dart';
import 'ai_repository.dart';

/// The setup state, kept for a minute so opening a chat or tapping the icon
/// does not ask the server each time. The sheet refreshes it when it opens,
/// and a change of agents drops it.
class AiSetupCache {
  AiSetupCache(this._repository, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now {
    _repository.agentsChanged.listen((_) => clear());
  }

  static const keepFor = Duration(seconds: 60);

  final AiRepository _repository;
  final DateTime Function() _now;
  AiSetup? _value;
  DateTime? _at;
  Future<AiSetup>? _inFlight;

  void clear() {
    _value = null;
    _at = null;
  }

  Future<AiSetup> get({bool isRefresh = false}) {
    final value = _value;
    final at = _at;
    if (!isRefresh &&
        value != null &&
        at != null &&
        _now().difference(at) < keepFor) {
      return Future.value(value);
    }
    return _inFlight ??= _repository
        .getSetupState()
        .then((fresh) {
          _value = fresh;
          _at = _now();
          return fresh;
        })
        .whenComplete(() => _inFlight = null);
  }
}
