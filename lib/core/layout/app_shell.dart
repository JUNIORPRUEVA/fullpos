import 'package:flutter/material.dart';
import '../constants/app_sizes.dart';
import '../theme/app_gradient_theme.dart';
import '../window/window_service.dart';
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
      return 220.0;
    }
    final proportional = maxWidth * 0.16;
    return proportional.clamp(220.0, 250.0);
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
    return ValueListenableBuilder<bool>(
      valueListenable: WindowService.fullScreenListenable,
      builder: (context, isFullScreen, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            _updateResponsive(constraints);

            final isNarrow = _isNarrow;
            final isShort = _isShort;
            final showFooter = !isShort;
            final sidebarWidth = _sidebarWidthFor(constraints.maxWidth);
            final sidebarScale = 1.0;
            final topbarHeight = AppSizes.topbarHeight;
            final topbarScale = 1.0;
            final footerHeight = showFooter ? AppSizes.footerHeight : 0.0;
            final footerScale = 1.0;

            Widget topbarWidget = Topbar(
              scale: topbarScale,
              showBottomBorder: !isFullScreen,
            );
            if (isNarrow) {
              topbarWidget = Builder(
                builder: (context) => Topbar(
                  scale: topbarScale,
                  showBottomBorder: !isFullScreen,
                  showMenuButton: true,
                  onMenuPressed: () => Scaffold.of(context).openDrawer(),
                ),
              );
            }

            final contentColumn = Column(
              children: [
                SizedBox(height: topbarHeight, child: topbarWidget),
                Expanded(child: widget.child),
                if (showFooter)
                  SizedBox(height: footerHeight, child: Footer(scale: footerScale)),
              ],
            );

            final theme = Theme.of(context);
            final scheme = theme.colorScheme;
            final gradientTheme = theme.extension<AppGradientTheme>();
            final fallbackGradient = LinearGradient(
              colors: [scheme.surface, scheme.primaryContainer],
              stops: const [0.0, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            );
            final baseBody = Container(
              decoration: BoxDecoration(
                gradient: gradientTheme?.backgroundGradient ?? fallbackGradient,
              ),
              child: isNarrow
                  ? SafeArea(child: contentColumn)
                    : Row(
                        children: [
                          Sidebar(
                            customWidth: sidebarWidth,
                            scale: sidebarScale,
                          ),
                          Expanded(child: contentColumn),
                        ],
                      ),
            );

            return Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              drawer: isNarrow
                  ? Drawer(
                      child: SafeArea(
                        child: Sidebar(
                          forcedCollapsed: false,
                          customWidth: sidebarWidth,
                          scale: sidebarScale,
                        ),
                      ),
                    )
                  : null,
              body: baseBody,
            );
          },
        );
      },
    );
  }
}
