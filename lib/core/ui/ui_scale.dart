import 'package:flutter/widgets.dart';

/// Factor de escala suave para desktop.
///
/// - Base: 1366px (HD).
/// - Clamp para evitar que la UI se infle o se encoja demasiado.
double uiScale(
  BuildContext context, {
  double baseWidth = 1366,
  double min = 0.9,
  double max = 1.15,
}) {
  final mq = MediaQuery.of(context);
  final logicalWidth = mq.size.width;
  if (logicalWidth <= 0) return 1.0;

  // En Windows, el escalado DPI reduce los "logical pixels" disponibles.
  // Usar ancho físico estabiliza el layout entre 100%, 125%, 150%, etc.
  final physicalWidth = logicalWidth * mq.devicePixelRatio;
  return (physicalWidth / baseWidth).clamp(min, max);
}
