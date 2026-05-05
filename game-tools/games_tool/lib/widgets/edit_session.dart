import 'dart:async';

typedef EditSessionValidator<T> = String? Function(T value);
typedef EditSessionPersist<T> = Future<void> Function(T value);
typedef EditSessionAreEqual<T> = bool Function(T a, T b);

class EditSession<T> {
  EditSession({
    required T initialValue,
    required EditSessionPersist<T> onPersist,
    EditSessionValidator<T>? validate,
    EditSessionAreEqual<T>? areEqual,
    Duration debounce = const Duration(milliseconds: 320),
  })  : _current = initialValue,
        _lastPersisted = initialValue,
        _onPersist = onPersist,
        _validate = validate,
        _areEqual = areEqual,
        _debounce = debounce;

  T _current;
  T _lastPersisted;
  final EditSessionPersist<T> _onPersist;
  final EditSessionValidator<T>? _validate;
  final EditSessionAreEqual<T>? _areEqual;
  final Duration _debounce;

  Timer? _debounceTimer;
  bool _persistInFlight = false;
  bool _dirtyDuringPersist = false;

  String? get validationError => _validate?.call(_current);

  void update(T value) {
    _current = value;
    _schedule();
  }

  /// Resets both current and last-persisted to [value], cancelling any pending
  /// debounce. Use when external data changes and the session should treat the
  /// new value as the already-persisted baseline.
  void resetToValue(T value) {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _current = value;
    _lastPersisted = value;
  }

  Future<void> flush() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _persistIfNeeded();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void _schedule() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(_persistIfNeeded());
    });
  }

  bool _isEqual(T a, T b) {
    final areEqual = _areEqual;
    if (areEqual != null) {
      return areEqual(a, b);
    }
    return a == b;
  }

  Future<void> _persistIfNeeded() async {
    if (_validate?.call(_current) != null) {
      return;
    }
    if (_isEqual(_current, _lastPersisted)) {
      return;
    }

    if (_persistInFlight) {
      _dirtyDuringPersist = true;
      return;
    }

    _persistInFlight = true;
    final T snapshot = _current;
    try {
      await _onPersist(snapshot);
      _lastPersisted = snapshot;
    } finally {
      _persistInFlight = false;
      if (_dirtyDuringPersist) {
        _dirtyDuringPersist = false;
        _schedule();
      }
    }
  }
}
