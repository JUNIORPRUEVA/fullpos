/// Tracks active import/export operations for update safety validation.
///
/// This is a minimal, centralized tracker that allows the update system
/// to detect when an import or export operation is in progress and block
/// installation until the operation is complete.
class ImportExportActivityTracker {
  ImportExportActivityTracker._();

  static final ImportExportActivityTracker instance =
      ImportExportActivityTracker._();

  int _activeOperations = 0;

  /// Whether there is at least one active import or export operation.
  bool get isActive => _activeOperations > 0;

  /// Call before starting an import or export operation.
  void markStarted() {
    _activeOperations++;
  }

  /// Call after an import or export operation completes (success or failure).
  void markCompleted() {
    if (_activeOperations > 0) {
      _activeOperations--;
    }
  }

  /// Waits until all import/export operations finish, up to [timeout].
  Future<bool> waitUntilIdle(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_activeOperations > 0) {
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return true;
  }
}
