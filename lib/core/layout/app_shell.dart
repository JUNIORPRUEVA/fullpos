import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';
import 'sidebar.dart';
import 'topbar.dart';
import 'footer.dart';

/// Layout principal de la aplicación (Sidebar + Topbar + Content + Footer)
class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  static const double _drawerBreakpointWidth = 1200;
  static const double _shortHeightBreakpoint = 560;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _breakpointHysteresis = 40;
  bool _didInitResponsive = false;
  bool _isNarrow = false;
  bool _isShort = false;

  double _sidebarWidthFor(double maxWidth) {
    // Sidebar más estrecho para una estética corporativa limpia.
    // Mantiene ancho consistente en resoluciones comunes.
    if (maxWidth < 1360) {
      return 182.0;
    }
    final proportional = maxWidth * 0.128;
    return proportional.clamp(182.0, 198.0);
  }

  void _updateResponsive(BoxConstraints constraints) {
    if (!_didInitResponsive) {
      _didInitResponsive = true;
      _isNarrow = constraints.maxWidth < AppShell._drawerBreakpointWidth;
      _isShort = constraints.maxHeight < AppShell._shortHeightBreakpoint;
      return;
    }

    final narrowLower = AppShell._drawerBreakpointWidth - _breakpointHysteresis;
    final narrowUpper = AppShell._drawerBreakpointWidth + _breakpointHysteresis;
    if (constraints.maxWidth < narrowLower) _isNarrow = true;
    if (constraints.maxWidth > narrowUpper) _isNarrow = false;

    final shortLower = AppShell._shortHeightBreakpoint - _breakpointHysteresis;
    final shortUpper = AppShell._shortHeightBreakpoint + _breakpointHysteresis;
    if (constraints.maxHeight < shortLower) _isShort = true;
    if (constraints.maxHeight > shortUpper) _isShort = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _updateResponsive(constraints);

        final isShort = _isShort;
        final showFooter = !isShort;
        final sidebarWidth = _sidebarWidthFor(constraints.maxWidth);
        final sidebarScale = 1.0;
        final topbarHeight = AppSizes.topbarHeight;
        final topbarScale = 1.0;
        final footerHeight = showFooter ? AppSizes.footerHeight : 0.0;
        final footerScale = 1.0;

        final isDesktop =
            Platform.isWindows || Platform.isLinux || Platform.isMacOS;
        final double topbarInnerTopPadding = isDesktop
            ? AppSizes.paddingXS
            : 0.0;

        final topbarWidget = Builder(
          builder: (context) => Topbar(
            scale: topbarScale,
            topPadding: topbarInnerTopPadding,
            showMenuButton: true,
            onMenuPressed: () => Scaffold.of(context).openDrawer(),
          ),
        );

        final contentColumn = Column(
          children: [
            SizedBox(
              height: topbarHeight + topbarInnerTopPadding,
              child: topbarWidget,
            ),
            Expanded(child: widget.child),
            if (showFooter)
              SizedBox(
                height: footerHeight,
                child: Footer(scale: footerScale),
              ),
          ],
        );

        return Scaffold(
          backgroundColor: Colors.transparent,
          drawer: Drawer(
            width: sidebarWidth,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            child: SafeArea(
              child: Sidebar(
                forcedCollapsed: false,
                customWidth: sidebarWidth,
                scale: sidebarScale,
              ),
            ),
          ),
          body: SafeArea(child: contentColumn),
        );
      },
    );
  }
}
