/// Tracks active print jobs for update safety validation.
///
/// This is a minimal, centralized tracker that allows the update system
/// to detect when a print job is in progress and block installation
/// until printing is complete.
class PrintActivityTracker {
  PrintActivityTracker._();

  static final PrintActivityTracker instance = PrintActivityTracker._();

  int _activePrintJobs = 0;

  /// Whether there is at least one active print job.
  bool get isPrinting => _activePrintJobs > 0;

  /// Whether there are pending print jobs (same as isPrinting for now).
  bool get hasPendingPrintJobs => _activePrintJobs > 0;

  /// Call before starting a print job.
  void markPrintStarted() {
    _activePrintJobs++;
  }

  /// Call after a print job completes (success or failure).
  void markPrintCompleted() {
    if (_activePrintJobs > 0) {
      _activePrintJobs--;
    }
  }

  /// Waits until all print jobs finish, up to [timeout].
  Future<bool> waitUntilIdle(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_activePrintJobs > 0) {
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return true;
  }
}
