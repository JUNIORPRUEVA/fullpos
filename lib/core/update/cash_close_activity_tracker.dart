/// Tracks active cash shift closing operations for update safety validation.
///
/// This is a minimal, centralized tracker that allows the update system
/// to detect when a cash shift closing process is in progress and block
/// installation until the operation is complete.
class CashCloseActivityTracker {
  CashCloseActivityTracker._();

  static final CashCloseActivityTracker instance =
      CashCloseActivityTracker._();

  int _activeClosings = 0;

  /// Whether there is at least one active cash shift closing operation.
  bool get isClosing => _activeClosings > 0;

  /// Call before starting a cash shift closing operation.
  void markClosingStarted() {
    _activeClosings++;
  }

  /// Call after a cash shift closing operation completes (success or failure).
  void markClosingCompleted() {
    if (_activeClosings > 0) {
      _activeClosings--;
    }
  }

  /// Waits until all cash closing operations finish, up to [timeout].
  Future<bool> waitUntilIdle(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_activeClosings > 0) {
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return true;
  }
}
