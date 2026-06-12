import 'package:flutter/foundation.dart';

class TopbarActionBus {
  static final ValueNotifier<int> salesMovementToggle = ValueNotifier<int>(0);
  static String? _pendingMovementType;
  static bool _pendingCurrentShiftPanel = false;

  static void toggleSalesMovementPanel() {
    salesMovementToggle.value++;
  }

  static void queueSalesCashMovementDialog(String type) {
    _pendingMovementType = type;
  }

  static void queueSalesCurrentShiftPanel() {
    _pendingCurrentShiftPanel = true;
  }

  static void dispatchPendingSalesOverlay() {
    salesMovementToggle.value++;
  }

  static ({String? movementType, bool openCurrentShiftPanel})
  consumePendingSalesOverlay() {
    final movementType = _pendingMovementType;
    final openCurrentShiftPanel = _pendingCurrentShiftPanel;
    _pendingMovementType = null;
    _pendingCurrentShiftPanel = false;
    return (
      movementType: movementType,
      openCurrentShiftPanel: openCurrentShiftPanel,
    );
  }
}
