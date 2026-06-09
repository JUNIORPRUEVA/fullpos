import 'package:flutter/foundation.dart';

class TopbarActionBus {
  TopbarActionBus._();

  static final ValueNotifier<int> salesMovementToggle = ValueNotifier<int>(0);

  static void toggleSalesMovementPanel() {
    salesMovementToggle.value++;
  }
}
