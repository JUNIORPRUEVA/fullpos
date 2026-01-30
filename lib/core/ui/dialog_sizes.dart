import 'package:flutter/material.dart';

/// Helper para normalizar tamaños de diálogos en toda la aplicación
///
/// REGLA: Todos los diálogos deben ser pequeños y elegantes, no fullscreen.
/// - width = min(screenWidth * 0.30, 520)
/// - height = min(screenHeight * 0.70, 720)
class DialogSizes {
  DialogSizes._();

  /// Retorna BoxConstraints para diálogos pequeños
  ///
  /// Uso:
  /// ```dart
  /// showDialog(
  ///   context: context,
  ///   builder: (context) => Dialog(
  ///     child: ConstrainedBox(
  ///       constraints: DialogSizes.small(context),
  ///       child: YourDialogContent(),
  ///     ),
  ///   ),
  /// );
  /// ```
  static BoxConstraints small(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final maxWidth = (size.width * 0.30).clamp(320.0, 520.0);
    final maxHeight = (size.height * 0.70).clamp(400.0, 720.0);

    return BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      minWidth: 320.0,
    );
  }

  /// Variante para diálogos medianos (ej: formularios complejos)
  static BoxConstraints medium(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final maxWidth = (size.width * 0.40).clamp(420.0, 680.0);
    final maxHeight = (size.height * 0.75).clamp(500.0, 800.0);

    return BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      minWidth: 420.0,
    );
  }

  /// Variante para diálogos grandes (ej: visualización de datos)
  static BoxConstraints large(BuildContext context) {
    final size = MediaQuery.of(context).size;

    final maxWidth = (size.width * 0.50).clamp(520.0, 900.0);
    final maxHeight = (size.height * 0.80).clamp(600.0, 1000.0);

    return BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      minWidth: 520.0,
    );
  }

  /// Padding estándar dentro de diálogos
  static const EdgeInsets dialogPadding = EdgeInsets.all(24.0);

  /// Padding para contenido con scroll
  static const EdgeInsets scrollPadding = EdgeInsets.symmetric(
    horizontal: 24.0,
    vertical: 16.0,
  );

  /// Spacing entre elementos de formulario
  static const double formSpacing = 16.0;

  /// Altura de botones en diálogos
  static const double buttonHeight = 48.0;

  /// Border radius para diálogos
  static const double dialogRadius = 12.0;
}
