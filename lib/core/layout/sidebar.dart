import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/services/logout_flow_service.dart';
import '../bootstrap/app_bootstrap_controller.dart';
import '../constants/app_sizes.dart';
import '../errors/error_handler.dart';
import '../session/session_manager.dart';
import '../session/ui_preferences.dart';
import '../theme/app_tokens.dart';

class Sidebar extends ConsumerStatefulWidget {
  final bool? forcedCollapsed;
  final double? customWidth;
  final double scale;

  const Sidebar({
    super.key,
    this.forcedCollapsed,
    this.customWidth,
    this.scale = 1.0,
  });

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar>
    with SingleTickerProviderStateMixin {
  bool _isCollapsed = false;
  bool _isAdministrationExpanded = true;
  AnimationController? _collapseController;

  AnimationController _ensureCollapseController() {
    return _collapseController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: _isCollapsed ? 1.0 : 0.0,
    );
  }

  double get _collapseValue {
    final rawValue = _collapseController?.value ?? (_isCollapsed ? 1.0 : 0.0);
    return Curves.easeInOutCubic.transform(rawValue.clamp(0.0, 1.0));
  }

  @override
  void initState() {
    super.initState();
    _isCollapsed = widget.forcedCollapsed ?? false;
    _ensureCollapseController();
    _loadState();
  }

  @override
  void dispose() {
    _collapseController?.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    final collapsed =
        widget.forcedCollapsed ?? await UiPreferences.isSidebarCollapsed();
    if (mounted) {
      _setCollapsed(collapsed, animate: false);
    }
  }

  void _setCollapsed(bool collapsed, {bool animate = true}) {
    if (!mounted) return;
    final controller = _ensureCollapseController();
    setState(() => _isCollapsed = collapsed);
    if (!animate) {
      controller.value = collapsed ? 1.0 : 0.0;
      return;
    }
    if (collapsed) {
      controller.forward();
    } else {
      controller.reverse();
    }
  }

  Future<void> _toggleSidebar() async {
    if (widget.forcedCollapsed != null) {
      _setCollapsed(!_isCollapsed);
      return;
    }

    final newState = await UiPreferences.toggleSidebar();
    if (mounted) {
      _setCollapsed(newState);
    }
  }

  void _go(BuildContext context, String route) {
    context.go(route);
  }

  String _safeCurrentPath(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {}

    try {
      return GoRouter.of(context).routeInformationProvider.value.uri.path;
    } catch (_) {}

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.extension<AppTokens>() ?? AppTokens.defaultTokens;
    final screenSize = MediaQuery.of(context).size;

    final sidebarBg = tokens.sidebarBackground;
    final sidebarTextColor = tokens.sidebarText;
    final isSidebarVeryLight = sidebarBg.computeLuminance() > 0.78;
    final isTextVeryDark = sidebarTextColor.computeLuminance() < 0.12;
    final effectiveSidebarTextColor = (isSidebarVeryLight && isTextVeryDark)
        ? sidebarTextColor.withOpacity(0.76)
        : sidebarTextColor;

    final activeColor = tokens.sidebarActive;
    final hoverColor = tokens.tileHover;
    final borderColor = tokens.sidebarBorder;
    final currentRoute = _safeCurrentPath(context);

    final baseScale = widget.scale.clamp(0.65, 1.12);
    final adaptiveExpandedWidth = (screenSize.width * 0.152).clamp(
      204.0,
      236.0,
    );
    final targetWidth = widget.customWidth ?? adaptiveExpandedWidth;
    final collapsedWidth = (screenSize.width * 0.05 * baseScale).clamp(
      60.0,
      76.0,
    );
    final topbarHeight = (AppSizes.topbarHeight * baseScale).clamp(52.0, 72.0);
    final padM = AppSizes.paddingM * baseScale;
    final padS = AppSizes.paddingS * baseScale;

    return AnimatedBuilder(
      animation: _ensureCollapseController(),
      builder: (context, _) {
        final collapse = _collapseValue;
        final expanded = Curves.easeOutCubic.transform(1.0 - collapse);
        final visualCollapsed = collapse > 0.88;
        final currentWidth =
            targetWidth + ((collapsedWidth - targetWidth) * collapse);

        return Container(
          width: currentWidth,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: sidebarBg,
            border: Border(right: BorderSide(color: borderColor, width: 1)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactHeight = constraints.maxHeight < 780;
              final ultraCompactHeight = constraints.maxHeight < 690;
              final navScale = (baseScale * (constraints.maxHeight / 860))
                  .clamp(0.72, 1.0);
              final railPaddingH = visualCollapsed
                  ? (6 * navScale).clamp(4.0, 8.0)
                  : (13 * navScale).clamp(11.0, 16.0);
              final railPaddingV = (8 * navScale).clamp(6.0, 10.0);
              final expandedContentMaxWidth = visualCollapsed
                  ? 74.0
                  : (186 * navScale).clamp(176.0, 194.0);
              final showHeaderSubtitle = !compactHeight;
              final showSectionLabels = !ultraCompactHeight;
              final headerHeight = compactHeight
                  ? (topbarHeight - (4 * baseScale)).clamp(48.0, topbarHeight)
                  : topbarHeight;

              final reportRoutes = <String>{'/reports', '/sales-list'};
              final administrationRoutes = <String>{
                '/purchases',
                '/cash/expenses',
                '/quotes-list',
              };
              final shouldShowAdministrationChildren =
                  _isAdministrationExpanded ||
                  administrationRoutes.contains(currentRoute);

              final primaryEntries =
                  <
                    ({
                      IconData icon,
                      String title,
                      String? route,
                      VoidCallback onTap,
                    })
                  >[
                    (
                      icon: Icons.point_of_sale_outlined,
                      title: 'Ventas',
                      route: '/sales',
                      onTap: () => _go(context, '/sales'),
                    ),
                    (
                      icon: Icons.inventory_2_outlined,
                      title: 'Productos',
                      route: '/products',
                      onTap: () => _go(context, '/products'),
                    ),
                    (
                      icon: Icons.people_alt_outlined,
                      title: 'Clientes',
                      route: '/clients',
                      onTap: () => _go(context, '/clients'),
                    ),
                    (
                      icon: Icons.bar_chart_outlined,
                      title: 'Reportes',
                      route: '/reports',
                      onTap: () => _go(context, '/reports'),
                    ),
                  ];

              final administrationEntries =
                  <({IconData icon, String title, String route})>[
                    (
                      icon: Icons.shopping_cart_outlined,
                      title: 'Compras',
                      route: '/purchases',
                    ),
                    (
                      icon: Icons.payments_outlined,
                      title: 'Gastos',
                      route: '/cash/expenses',
                    ),
                    (
                      icon: Icons.request_quote_outlined,
                      title: 'Cotizaciones',
                      route: '/quotes-list',
                    ),
                  ];

              final systemEntries =
                  <({IconData icon, String title, String route})>[
                    (
                      icon: Icons.settings_outlined,
                      title: 'Configuración',
                      route: '/settings',
                    ),
                  ];

              Widget buildNavEntry({
                required IconData icon,
                required String title,
                required String? route,
                required VoidCallback onTap,
                Color? itemTextColor,
                Color? itemActiveColor,
                Set<String>? activeRoutes,
                bool showTrailingChevron = true,
              }) {
                return PremiumNavItem(
                  icon: icon,
                  title: title,
                  route: route,
                  onTap: onTap,
                  collapseProgress: collapse,
                  textColor: itemTextColor ?? effectiveSidebarTextColor,
                  activeColor: itemActiveColor ?? activeColor,
                  activeRoutes: activeRoutes,
                  hoverColor: hoverColor,
                  scale: navScale,
                  showTrailingChevron:
                      showTrailingChevron && !visualCollapsed && !compactHeight,
                );
              }

              final header = LayoutBuilder(
                builder: (context, headerConstraints) {
                  final availableWidth = headerConstraints.maxWidth;
                  final horizontalPad = visualCollapsed
                      ? (padS * 0.6).clamp(4.0, 10.0)
                      : (padM * 1.08).clamp(16.0, 20.0);
                  final contentWidth = math.max(
                    0.0,
                    availableWidth - (horizontalPad * 2),
                  );
                  final desiredBrandSize = visualCollapsed
                      ? (44 * baseScale).clamp(36.0, 48.0)
                      : (40 * baseScale).clamp(34.0, 44.0);
                  final brandSize = math.min(desiredBrandSize, contentWidth);
                  final desiredBtnSize = (40 * baseScale).clamp(32.0, 44.0);
                  final btnSize = math.min(desiredBtnSize, contentWidth);

                  Widget brandIconShell() {
                    return SizedBox(
                      width: brandSize,
                      height: brandSize,
                      child: Center(
                        child: SizedBox(
                          width: (24 * baseScale).clamp(20.0, 26.0),
                          height: (24 * baseScale).clamp(20.0, 26.0),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: (21.5 * baseScale).clamp(18.0, 23.0),
                                color: effectiveSidebarTextColor.withOpacity(
                                  0.96,
                                ),
                              ),
                              Positioned(
                                right: -1,
                                top: 2,
                                child: Icon(
                                  Icons.memory_outlined,
                                  size: (9.8 * baseScale).clamp(8.5, 11.0),
                                  color: effectiveSidebarTextColor.withOpacity(
                                    0.88,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  if (visualCollapsed) {
                    return SizedBox(
                      height: headerHeight,
                      child: Center(
                        child: Tooltip(
                          message: 'Expandir menú',
                          waitDuration: const Duration(milliseconds: 350),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _toggleSidebar,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: brandIconShell(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return SizedBox(
                    height: headerHeight,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                      child: Row(
                        children: [
                          Tooltip(
                            message: visualCollapsed ? 'Expandir menú' : 'Menú',
                            waitDuration: const Duration(milliseconds: 350),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: visualCollapsed ? _toggleSidebar : null,
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: brandIconShell(),
                                ),
                              ),
                            ),
                          ),
                          if (expanded > 0.001)
                            Expanded(
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: expanded,
                                  child: Opacity(
                                    opacity: expanded,
                                    child: Padding(
                                      padding: EdgeInsets.only(left: padS),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'FULLPOS',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color:
                                                        effectiveSidebarTextColor,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: (14.8 * baseScale)
                                                        .clamp(12.5, 15.8),
                                                    letterSpacing: 0.35,
                                                  ),
                                                ),
                                                if (showHeaderSubtitle) ...[
                                                  const SizedBox(height: 3),
                                                  Text(
                                                    'Point of sale',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color:
                                                          effectiveSidebarTextColor
                                                              .withOpacity(
                                                                0.62,
                                                              ),
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize:
                                                          (11.0 * baseScale)
                                                              .clamp(9.5, 12.0),
                                                      letterSpacing: 0.16,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          IconButton(
                                            tooltip: 'Colapsar menú',
                                            onPressed: _toggleSidebar,
                                            padding: EdgeInsets.zero,
                                            constraints:
                                                BoxConstraints.tightFor(
                                                  width: btnSize,
                                                  height: btnSize,
                                                ),
                                            iconSize: (22 * baseScale).clamp(
                                              18.0,
                                              24.0,
                                            ),
                                            icon: Icon(
                                              Icons.chevron_left,
                                              color: effectiveSidebarTextColor
                                                  .withOpacity(0.95),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );

              Widget sectionLabel(String text) {
                if (!showSectionLabels || expanded <= 0.001) {
                  return const SizedBox.shrink();
                }
                return ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    heightFactor: expanded,
                    child: Opacity(
                      opacity: expanded,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          railPaddingH,
                          (8 * navScale).clamp(6.0, 8.0),
                          railPaddingH,
                          (4 * navScale).clamp(3.0, 6.0),
                        ),
                        child: Row(
                          children: [
                            Text(
                              text.toUpperCase(),
                              style: TextStyle(
                                color: effectiveSidebarTextColor.withOpacity(
                                  0.65,
                                ),
                                fontSize: (9.1 * navScale).clamp(8.2, 10.2),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.9,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Divider(
                                height: 1,
                                thickness: 1,
                                color: effectiveSidebarTextColor.withOpacity(
                                  0.16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  SizedBox(height: (3 * navScale).clamp(2.0, 6.0)),
                  header,
                  Divider(
                    color: effectiveSidebarTextColor.withOpacity(0.12),
                    height: 1,
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        railPaddingH,
                        railPaddingV,
                        railPaddingH,
                        railPaddingV,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: expandedContentMaxWidth,
                          ),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              visualCollapsed ? 2 : 0,
                              (6 * navScale).clamp(4.0, 8.0),
                              visualCollapsed ? 2 : 0,
                              (6 * navScale).clamp(4.0, 8.0),
                            ),
                            child: Column(
                              children: [
                                sectionLabel('Principal'),
                                for (final entry in primaryEntries)
                                  buildNavEntry(
                                    icon: entry.icon,
                                    title: entry.title,
                                    route: entry.route,
                                    onTap: entry.onTap,
                                    activeRoutes: entry.title == 'Reportes'
                                        ? reportRoutes
                                        : null,
                                  ),
                                SizedBox(
                                  height: (4 * navScale).clamp(2.0, 6.0),
                                ),
                                buildNavEntry(
                                  icon: Icons.folder_open_outlined,
                                  title: 'Administración',
                                  route: null,
                                  onTap: () {
                                    if (visualCollapsed) {
                                      _setCollapsed(false);
                                      setState(
                                        () => _isAdministrationExpanded = true,
                                      );
                                      return;
                                    }
                                    setState(
                                      () => _isAdministrationExpanded =
                                          !_isAdministrationExpanded,
                                    );
                                  },
                                  activeRoutes: administrationRoutes,
                                ),
                                if (shouldShowAdministrationChildren &&
                                    !visualCollapsed)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: Column(
                                      children: [
                                        for (final entry
                                            in administrationEntries)
                                          buildNavEntry(
                                            icon: entry.icon,
                                            title: entry.title,
                                            route: entry.route,
                                            onTap: () =>
                                                _go(context, entry.route),
                                            showTrailingChevron: false,
                                          ),
                                      ],
                                    ),
                                  ),
                                const Spacer(),
                                Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    visualCollapsed ? 10 : 8,
                                    (6 * navScale).clamp(3.0, 7.0),
                                    visualCollapsed ? 10 : 8,
                                    (6 * navScale).clamp(3.0, 7.0),
                                  ),
                                  child: Divider(
                                    color: scheme.outlineVariant.withOpacity(
                                      0.22,
                                    ),
                                    height: 1,
                                  ),
                                ),
                                sectionLabel('Sistema'),
                                for (final entry in systemEntries)
                                  buildNavEntry(
                                    icon: entry.icon,
                                    title: entry.title,
                                    route: entry.route,
                                    onTap: () => _go(context, entry.route),
                                  ),
                                SizedBox(
                                  height: (5 * navScale).clamp(3.0, 7.0),
                                ),
                                buildNavEntry(
                                  icon: Icons.logout_outlined,
                                  title: 'Cerrar sesión',
                                  route: null,
                                  onTap: () async {
                                    try {
                                      await LogoutFlowService.requestLogout(
                                        context,
                                        performLogout: () async {
                                          ref
                                              .read(appBootstrapProvider)
                                              .forceLoggedOut();
                                          await SessionManager.logout();
                                          await ref
                                              .read(appBootstrapProvider)
                                              .refreshAuth();
                                          if (!context.mounted) {
                                            return;
                                          }
                                          final rootCtx =
                                              ErrorHandler
                                                  .navigatorKey
                                                  .currentContext ??
                                              context;
                                          GoRouter.of(rootCtx).refresh();
                                          GoRouter.of(rootCtx).go('/login');
                                        },
                                      );
                                    } catch (e) {
                                      if (!context.mounted) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'No se pudo cerrar sesión: $e',
                                          ),
                                          backgroundColor: scheme.error,
                                        ),
                                      );
                                    }
                                  },
                                  itemTextColor: effectiveSidebarTextColor,
                                  itemActiveColor: scheme.error,
                                  showTrailingChevron: false,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class PremiumNavItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? route;
  final Set<String>? activeRoutes;
  final VoidCallback? onTap;
  final double collapseProgress;
  final Color textColor;
  final Color activeColor;
  final Color hoverColor;
  final double scale;
  final bool showTrailingChevron;

  const PremiumNavItem({
    super.key,
    required this.icon,
    required this.title,
    required this.route,
    this.activeRoutes,
    this.onTap,
    required this.collapseProgress,
    required this.textColor,
    required this.activeColor,
    required this.hoverColor,
    this.scale = 1.0,
    this.showTrailingChevron = true,
  });

  @override
  State<PremiumNavItem> createState() => _PremiumNavItemState();
}

class _PremiumNavItemState extends State<PremiumNavItem> {
  bool _isHover = false;

  String _safeCurrentPath(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {}

    try {
      final router = GoRouter.of(context);
      return router.routeInformationProvider.value.uri.path;
    } catch (_) {}

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final currentRoute = _safeCurrentPath(context);
    final isActive =
        (widget.route != null && currentRoute == widget.route) ||
        (widget.activeRoutes?.contains(currentRoute) ?? false);
    final isEnabled = widget.onTap != null || widget.route != null;

    final s = widget.scale.clamp(0.65, 1.12);
    final collapse = widget.collapseProgress.clamp(0.0, 1.0);
    final expanded = Curves.easeOutCubic.transform(1.0 - collapse);
    final visuallyCollapsed = collapse > 0.9;
    const duration = Duration(milliseconds: 180);
    final itemRadius = BorderRadius.circular((10 * s).clamp(8.0, 10.0));
    final hoverBg = Color.alphaBlend(
      Colors.white.withOpacity(0.035),
      widget.hoverColor.withOpacity(0.12),
    );
    final activeBg = Color.alphaBlend(
      Colors.white.withOpacity(visuallyCollapsed ? 0.07 : 0.05),
      widget.activeColor.withOpacity(0.18),
    );

    final baseFg = widget.textColor;
    final fgColor = isActive
        ? Colors.white
        : baseFg.withOpacity(_isHover ? 0.98 : 0.90);
    final iconColor = isActive
        ? Colors.white
        : baseFg.withOpacity(_isHover ? 0.98 : 0.88);
    final itemBg = visuallyCollapsed
        ? Colors.transparent
        : (isActive ? activeBg : (_isHover ? hoverBg : Colors.transparent));

    Widget collapsedIconPresentation() {
      return SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isActive)
              Positioned(
                left: 0,
                child: Container(
                  width: (2.0 * s).clamp(2.0, 2.4),
                  height: (18 * s).clamp(16.0, 20.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.94),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            Icon(
              widget.icon,
              color: iconColor,
              size: (20.4 * s).clamp(18.0, 20.8),
            ),
          ],
        ),
      );
    }

    final item = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: visuallyCollapsed
            ? 0
            : ((8 - (4 * collapse)) * s).clamp(2.0, 8.0),
        vertical: visuallyCollapsed
            ? (2.8 * s).clamp(2.0, 3.6)
            : (2.2 * s).clamp(1.0, 3.0),
      ),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: itemRadius),
        clipBehavior: Clip.antiAlias,
        child: MouseRegion(
          cursor: isEnabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _isHover = true),
          onExit: (_) => setState(() => _isHover = false),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: itemRadius,
            hoverColor: Colors.transparent,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(
                horizontal: visuallyCollapsed
                    ? 0
                    : ((7.0 * expanded) * s).clamp(0.0, 8.0),
                vertical: visuallyCollapsed
                    ? 0
                    : ((6.0 + (0.8 * expanded)) * s).clamp(4.5, 6.8),
              ),
              decoration: BoxDecoration(
                color: itemBg,
                borderRadius: itemRadius,
              ),
              child: SizedBox(
                height: visuallyCollapsed
                    ? (32 * s).clamp(28.0, 34.0)
                    : ((31 + (2.5 * expanded)) * s).clamp(26.0, 34.0),
                child: visuallyCollapsed
                    ? collapsedIconPresentation()
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: duration,
                            width: isActive ? 2.0 * expanded : 0,
                            height: (17 * s).clamp(15.0, 18.0),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.white.withOpacity(0.92)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          if (isActive && expanded > 0.08)
                            SizedBox(
                              width: ((6 * expanded) * s).clamp(0.0, 6.0),
                            ),
                          Icon(
                            widget.icon,
                            color: iconColor,
                            size: (18.5 * s).clamp(15.0, 18.5),
                          ),
                          if (expanded > 0.001)
                            Expanded(
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: expanded,
                                  child: Opacity(
                                    opacity: expanded,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        left: ((7 * expanded) * s).clamp(
                                          0.0,
                                          7.0,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              widget.title,
                                              style: TextStyle(
                                                color: fgColor,
                                                fontSize: (12.35 * s).clamp(
                                                  10.4,
                                                  12.6,
                                                ),
                                                fontWeight: isActive
                                                    ? FontWeight.w600
                                                    : FontWeight.w600,
                                                letterSpacing: 0.08,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              softWrap: false,
                                            ),
                                          ),
                                          if (widget.showTrailingChevron)
                                            Icon(
                                              Icons.chevron_right,
                                              size: (14 * s).clamp(12.0, 14.0),
                                              color: fgColor.withOpacity(0.56),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!visuallyCollapsed) {
      return item;
    }

    return Tooltip(
      message: widget.title,
      waitDuration: const Duration(milliseconds: 450),
      child: item,
    );
  }
}
