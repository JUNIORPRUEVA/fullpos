import 'package:flutter/foundation.dart';

/// Calcula un `maxCrossAxisExtent` estable para que el ancho real de cada tile
/// NO se dispare cuando el ancho disponible cambia.
///
/// Flutter calcula las columnas con `floor`, lo que puede hacer que los tiles
/// queden muy anchos (1-2 columnas) en resoluciones intermedias.
///
/// Esta función fuerza un número de columnas usando `ceil` para mantener el tile
/// siempre <= `desiredMaxExtent`.
double stableMaxCrossAxisExtent({
  required double availableWidth,
  required double desiredMaxExtent,
  required double spacing,
  double minExtent = 140,
}) {
  if (availableWidth <= 0) return desiredMaxExtent;

  final columns = ((availableWidth + spacing) / (desiredMaxExtent + spacing))
      .ceil()
      .clamp(1, 1000);

  final computed = (availableWidth + spacing) / columns - spacing;
  final safe = computed.clamp(minExtent, desiredMaxExtent);

  // Evitar casos borde donde el floor cambie por redondeo.
  final epsilon = kDebugMode ? 0.01 : 0.001;
  return safe - epsilon;
}
