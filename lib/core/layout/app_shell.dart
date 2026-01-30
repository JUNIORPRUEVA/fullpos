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

  static const double _drawerBreakpointWidth = 900;
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
    // Se adapta proporcionalmente al ancho disponible.
    // Mantiene un rango para que no se vea ni gigante ni aplastado.
    final w = maxWidth * 0.17;
    return w.clamp(170.0, AppSizes.sidebarWidth);
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
            final sidebarScale =
                (sidebarWidth / AppSizes.sidebarWidth).clamp(0.75, 1.0);
            final topbarHeight =
                (constraints.maxHeight * 0.08).clamp(54.0, 78.0);
            final topbarScale =
                (topbarHeight / AppSizes.topbarHeight).clamp(0.85, 1.12);
            final footerHeight =
                showFooter ? (constraints.maxHeight * 0.07).clamp(44.0, 64.0) : 0.0;
            final footerScale =
                (footerHeight / AppSizes.footerHeight).clamp(0.8, 1.12);

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
