import 'package:flutter/material.dart';

/// Utilidades para generar colores determinísticos a partir de strings.
class ColorUtils {
  ColorUtils._();

  /// Genera un color hex (#RRGGBB) determinístico para un producto.
  ///
  /// - Usa el nombre como semilla principal.
  /// - categoryId (opcional) agrega variación sin romper la estabilidad.
  /// - Evita colores demasiado claros para que el texto blanco tenga contraste.
  static String generateDeterministicColorHex(
    String? name, {
    int? categoryId,
  }) {
    final seed = (name?.trim().isEmpty ?? true) ? 'PRODUCT' : name!.trim();
    var hash = 0;
    for (final codeUnit in seed.toLowerCase().codeUnits) {
      hash = (hash * 31 + codeUnit) & 0xFFFFFFFF;
    }
    if (categoryId != null) {
      hash = (hash ^ (categoryId * 9973)) & 0xFFFFFFFF;
    }

    int channel(int shift) {
      final raw = (hash >> shift) & 0xFF;
      // Limitar a rango [40, 200] para evitar colores muy claros/oscuro extremo.
      return 40 + (raw % 160);
    }

    final r = channel(0);
    final g = channel(8);
    final b = channel(16);

    return '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
        '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  /// Convierte un hex (#RRGGBB) a [Color], devolviendo [fallback] si es inválido.
  static Color colorFromHex(
    String? hex, {
    Color fallback = const Color(0xFF607D8B),
  }) {
    final value = (hex ?? '').replaceAll('#', '').trim();
    if (value.length == 6) {
      try {
        return Color(int.parse('FF$value', radix: 16));
      } catch (_) {
        return fallback;
      }
    }
    return fallback;
  }

  /// Convierte un [Color] a hex #RRGGBB.
  static String colorToHex(Color color) {
    final rgb = color.value & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
