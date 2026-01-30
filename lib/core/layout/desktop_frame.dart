import 'package:flutter/widgets.dart';

/// Contenedor base para desktop: centra el contenido y aplica un maxWidth
/// global para evitar que el layout se estire excesivamente en monitores grandes.
class DesktopFrame extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  const DesktopFrame({
    super.key,
    required this.child,
    this.maxWidth = 1500,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
