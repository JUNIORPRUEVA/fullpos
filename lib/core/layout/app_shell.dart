import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';
import 'topbar.dart';
import 'footer.dart';
import 'fullpos_drawer.dart';

/// Layout principal de la aplicación (Topbar + Content + Footer)
/// El drawer lateral se abre mediante showGeneralDialog para tener
/// control total de la animación y el overlay.
class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  static const double _shortHeightBreakpoint = 560;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _breakpointHysteresis = 40;
  bool _didInitResponsive = false;
  bool _isShort = false;

  void _updateResponsive(BoxConstraints constraints) {
    if (!_didInitResponsive) {
      _didInitResponsive = true;
      _isShort = constraints.maxHeight < AppShell._shortHeightBreakpoint;
      return;
    }

    final shortLower = AppShell._shortHeightBreakpoint - _breakpointHysteresis;
    final shortUpper = AppShell._shortHeightBreakpoint + _breakpointHysteresis;
    if (constraints.maxHeight < shortLower) _isShort = true;
    if (constraints.maxHeight > shortUpper) _isShort = false;
  }

  void _openDrawer(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar menú',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return const FullPosDrawer();
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return child;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _updateResponsive(constraints);

        final isShort = _isShort;
        final showFooter = !isShort;
        final topbarHeight = AppSizes.topbarHeight;
        final footerHeight = showFooter ? AppSizes.footerHeight : 0.0;

        final topbarWidget = Builder(
          builder: (context) => Column(
            children: [
              Expanded(
                child: Topbar(
                  scale: 1.0,
                  topPadding: 0,
                  showMenuButton: true,
                  showBottomBorder: false,
                  onMenuPressed: () => _openDrawer(context),
                ),
              ),
            ],
          ),
        );

        final contentColumn = Column(
          children: [
            SizedBox(height: topbarHeight, child: topbarWidget),
            Expanded(child: widget.child),
            if (showFooter)
              SizedBox(
                height: footerHeight,
                child: Footer(scale: 1.0),
              ),
          ],
        );

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(child: contentColumn),
        );
      },
    );
  }
}
