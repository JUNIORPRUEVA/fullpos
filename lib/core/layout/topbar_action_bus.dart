import 'package:flutter/foundation.dart';

class TopbarActionBus {
  static final ValueNotifier<int> salesMovementToggle = ValueNotifier<int>(0);
  static String? _pendingMovementType;
  static bool _pendingCurrentCutView = false;

  static void toggleSalesMovementPanel() {
    salesMovementToggle.value++;
  }

  static void queueSalesCashMovementDialog(String type) {
    _pendingMovementType = type;
  }

  static void queueSalesCurrentCutView() {
    _pendingCurrentCutView = true;
  }

  static void dispatchPendingSalesOverlay() {
    salesMovementToggle.value++;
  }

  static ({String? movementType, bool openCurrentCut})
  consumePendingSalesOverlay() {
    final movementType = _pendingMovementType;
    final openCurrentCut = _pendingCurrentCutView;
    _pendingMovementType = null;
    _pendingCurrentCutView = false;
    return (
      movementType: movementType,
      openCurrentCut: openCurrentCut,
    );
  }
}
