import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../constants/app_sizes.dart';
import '../session/ui_preferences.dart';
import '../theme/app_tokens.dart';
import '../theme/color_utils.dart';

class _SidebarIconPair {
  final IconData outline;
  final IconData filled;

  const _SidebarIconPair({required this.outline, required this.filled});
}

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
  bool _isCollapsed = true;
  bool _isClientsExpanded = false;
  bool _isAdministrationExpanded = false;
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
    _isCollapsed = widget.forcedCollapsed ?? true;
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
    final tokens = theme.extension<AppTokens>() ?? AppTokens.defaultTokens;
    final screenSize = MediaQuery.of(context).size;

    final sidebarBaseColor = theme.brightness == Brightness.dark
        ? const Color(0xFF1E293B)
        : const Color(0xFFF2F6F9);
    final sidebarTextColor = theme.brightness == Brightness.dark
        ? const Color(0xFFE2E8F0)
        : const Color(0xFF1E293B);
    Color sidebarHighlight(double opacity) => Color.alphaBlend(
      sidebarTextColor.withOpacity(opacity),
      sidebarBaseColor,
    );

    Color sidebarShadow(double opacity) => Color.alphaBlend(
      theme.shadowColor.withOpacity(opacity),
      sidebarBaseColor,
    );
    final effectiveSidebarTextColor = sidebarTextColor;
    final sidebarMutedTextColor = Color.alphaBlend(
      sidebarTextColor.withOpacity(0.55),
      sidebarBaseColor,
    );
    final sidebarHoverColor = Color.alphaBlend(
      const Color(0xFF2563EB).withOpacity(0.08),
      sidebarBaseColor,
    );
    final sidebarActiveColor = theme.brightness == Brightness.dark
        ? const Color(0xFF60A5FA)
        : const Color(0xFF2563EB);
    final sidebarActiveTopColor = Color.alphaBlend(
      sidebarHighlight(0.10),
      sidebarActiveColor,
    );
    final sidebarActiveBottomColor = Color.alphaBlend(
      sidebarShadow(0.18),
      sidebarActiveColor,
    );
    final sidebarTooltipColor = theme.brightness == Brightness.dark
        ? const Color(0xFF334155)
        : const Color(0xFF475569);
    final sidebarTooltipTextColor = ColorUtils.ensureReadableColor(
      sidebarTextColor,
      sidebarTooltipColor,
      minRatio: 4.5,
    );
    final sidebarBorderColor = Color.alphaBlend(
      const Color(
        0xFFCBD5E1,
      ).withOpacity(theme.brightness == Brightness.dark ? 0.14 : 0.18),
      sidebarBaseColor,
    );
    final currentRoute = _safeCurrentPath(context);

    final baseScale = widget.scale.clamp(0.65, 1.12);
    final adaptiveExpandedWidth = (screenSize.width * 0.124).clamp(
      176.0,
      194.0,
    );
    final targetWidth = widget.customWidth ?? adaptiveExpandedWidth;
    final collapsedWidth = (screenSize.width * 0.05 * baseScale).clamp(
      58.0,
      68.0,
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
          height: double.infinity,
          width: currentWidth,
          clipBehavior: Clip.none,
          decoration: BoxDecoration(
            color: sidebarBaseColor,
            border: Border(
              right: BorderSide(color: sidebarBorderColor, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 22,
                spreadRadius: -14,
                offset: const Offset(8, 0),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          sidebarHighlight(0.04),
                          Colors.transparent,
                          const Color(0xFFE2E8F0),
                        ],
                        stops: const [0.0, 0.38, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final compactHeight = constraints.maxHeight < 780;
                  final ultraCompactHeight = constraints.maxHeight < 690;
                  final navScale = (baseScale * (constraints.maxHeight / 860))
                      .clamp(0.72, 1.0);
                  final railPaddingH = visualCollapsed
                      ? (8 * navScale).clamp(7.0, 10.0)
                      : (12 * navScale).clamp(10.0, 14.0);
                  final railPaddingV = visualCollapsed
                      ? (12 * navScale).clamp(10.0, 14.0)
                      : (8 * navScale).clamp(6.0, 10.0);
                  final expandedContentMaxWidth = visualCollapsed
                      ? 64.0
                      : (168 * navScale).clamp(158.0, 176.0);
                  final showHeaderSubtitle = !compactHeight && !visualCollapsed;
                  final showSectionLabels = !ultraCompactHeight;
                  final headerHeight = compactHeight
                      ? (topbarHeight - (8 * baseScale)).clamp(
                          44.0,
                          topbarHeight,
                        )
                      : topbarHeight;

                  final reportRoutes = <String>{'/reports', '/factura'};
                  final clientsRoutes = <String>{
                    '/clients',
                    '/quotes-list',
                    '/credits-list',
                  };
                  final administrationRoutes = <String>{
                    '/purchases',
                    '/cash/expenses',
                  };
                  final shouldShowClientsChildren =
                      _isClientsExpanded ||
                      clientsRoutes.any(
                        (route) =>
                            currentRoute == route ||
                            currentRoute.startsWith('$route/'),
                      );
                  final shouldShowAdministrationChildren =
                      _isAdministrationExpanded ||
                      administrationRoutes.any(
                        (route) =>
                            currentRoute == route ||
                            currentRoute.startsWith('$route/'),
                      );

                  final primaryEntries =
                      <
                        ({
                          _SidebarIconPair icon,
                          String title,
                          String route,
                          VoidCallback onTap,
                        })
                      >[
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.storefront(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.storefront(
                              PhosphorIconsStyle.fill,
                            ),
                          ),
                          title: 'Ventas',
                          route: '/sales',
                          onTap: () => _go(context, '/sales'),
                        ),
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.package(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.package(
                              PhosphorIconsStyle.fill,
                            ),
                          ),
                          title: 'Productos',
                          route: '/products',
                          onTap: () => _go(context, '/products'),
                        ),
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.usersThree(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.usersThree(
                              PhosphorIconsStyle.fill,
                            ),
                          ),
                          title: 'Clientes',
                          route: '/clients',
                          onTap: () => _go(context, '/clients'),
                        ),
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.chartBar(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.chartBar(
                              PhosphorIconsStyle.fill,
                            ),
                          ),
                          title: 'Reportes',
                          route: '/reports',
                          onTap: () => _go(context, '/reports'),
                        ),
                      ];

                  final clientChildEntries =
                      <({_SidebarIconPair icon, String title, String route})>[
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.userList(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.userList(
                              PhosphorIconsStyle.fill,
                            ),
                          ),
                          title: 'Clientes',
                          route: '/clients',
                        ),
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.notePencil(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.notePencil(
                              PhosphorIconsStyle.fill,
                            ),
                          ),
                          title: 'Cotizaciones',
                          route: '/quotes-list',
                        ),
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.creditCard(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.creditCard(
                              PhosphorIconsStyle.fill,
                            ),
                          ),
                          title: 'Créditos',
                          route: '/credits-list',
                        ),
                      ];

                  final administrationEntries =
                      <({_SidebarIconPair icon, String title, String route})>[
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.shoppingCart(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.shoppingCart(
                              PhosphorIconsStyle.fill,
                            ),
                          ),
                          title: 'Compras',
                          route: '/purchases',
                        ),
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.currencyDollar(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.currencyDollar(
                              PhosphorIconsStyle.fill,
                            ),
                          ),
                          title: 'Gastos',
                          route: '/cash/expenses',
                        ),
                      ];

                  final systemEntries =
                      <({_SidebarIconPair icon, String title, String route})>[
                        (
                          icon: _SidebarIconPair(
                            outline: PhosphorIcons.gear(
                              PhosphorIconsStyle.regular,
                            ),
                            filled: PhosphorIcons.gear(PhosphorIconsStyle.fill),
                          ),
                          title: 'Configuración',
                          route: '/settings',
                        ),
                      ];

                  Widget buildNavEntry({
                    required _SidebarIconPair icon,
                    required String title,
                    required String? route,
                    required VoidCallback onTap,
                    Color? itemTextColor,
                    Color? itemActiveColor,
                    Set<String>? activeRoutes,
                    bool lowEmphasis = false,
                    bool showTrailingChevron = true,
                    Widget? trailing,
                    bool showSubmenuBadge = false,
                  }) {
                    return PremiumNavItem(
                      outlineIcon: icon.outline,
                      activeIcon: icon.filled,
                      title: title,
                      route: route,
                      onTap: onTap,
                      collapseProgress: collapse,
                      textColor: itemTextColor ?? effectiveSidebarTextColor,
                      activeColor: itemActiveColor ?? tokens.sidebarActive,
                      activeRoutes: activeRoutes,
                      currentRoute: currentRoute,
                      hoverColor: sidebarHoverColor,
                      surfaceColor: sidebarBaseColor,
                      tooltipBackgroundColor: sidebarTooltipColor,
                      tooltipTextColor: sidebarTooltipTextColor,
                      activeGradientStart: sidebarActiveTopColor,
                      activeGradientEnd: sidebarActiveBottomColor,
                      scale: navScale,
                      lowEmphasis: lowEmphasis,
                      showTrailingChevron:
                          showTrailingChevron &&
                          !visualCollapsed &&
                          !compactHeight,
                      trailing: trailing,
                      showSubmenuBadge: showSubmenuBadge,
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
                          ? (40 * baseScale).clamp(34.0, 44.0)
                          : (34 * baseScale).clamp(30.0, 38.0);
                      final brandSize = math.min(
                        desiredBrandSize,
                        contentWidth,
                      );
                      final desiredBtnSize = (34 * baseScale).clamp(30.0, 38.0);
                      final btnSize = math.min(desiredBtnSize, contentWidth);

                      Widget brandIconShell() {
                        final showCollapsedToggleBadge = visualCollapsed;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeInOut,
                          width: brandSize,
                          height: brandSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color.alphaBlend(
                                  Colors.white.withOpacity(0.08),
                                  sidebarBaseColor,
                                ),
                                Color.alphaBlend(
                                  Colors.white.withOpacity(0.02),
                                  sidebarBaseColor,
                                ),
                              ],
                            ),
                            border: Border.all(color: sidebarBorderColor),
                            boxShadow: [
                              BoxShadow(
                                color: sidebarShadow(0.16),
                                blurRadius: 14,
                                spreadRadius: -10,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Center(
                            child: SizedBox(
                              width: (24 * baseScale).clamp(22.0, 28.0),
                              height: (24 * baseScale).clamp(22.0, 28.0),
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  PhosphorIcon(
                                    PhosphorIcons.receipt(
                                      PhosphorIconsStyle.regular,
                                    ),
                                    size: (19 * baseScale).clamp(17.0, 21.0),
                                    color: sidebarTextColor,
                                  ),
                                  Positioned(
                                    right: -1.5,
                                    bottom: 1,
                                    child: PhosphorIcon(
                                      PhosphorIcons.creditCard(
                                        PhosphorIconsStyle.fill,
                                      ),
                                      size: (9.6 * baseScale).clamp(8.0, 11.0),
                                      color: sidebarActiveColor,
                                    ),
                                  ),
                                  if (showCollapsedToggleBadge)
                                    Positioned(
                                      right: -5,
                                      bottom: -5,
                                      child: Container(
                                        width: (15.5 * baseScale).clamp(
                                          14.0,
                                          18.0,
                                        ),
                                        height: (15.5 * baseScale).clamp(
                                          14.0,
                                          18.0,
                                        ),
                                        decoration: BoxDecoration(
                                          color: sidebarActiveColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: sidebarBaseColor,
                                            width: 1.4,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: sidebarShadow(0.22),
                                              blurRadius: 10,
                                              spreadRadius: -4,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: PhosphorIcon(
                                            PhosphorIcons.caretRight(
                                              PhosphorIconsStyle.bold,
                                            ),
                                            size: (9 * baseScale).clamp(
                                              8.0,
                                              10.0,
                                            ),
                                            color:
                                                ColorUtils.ensureReadableColor(
                                                  sidebarTextColor,
                                                  sidebarActiveColor,
                                                  minRatio: 4.5,
                                                ),
                                          ),
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
                              message: 'Mostrar menu',
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _toggleSidebar,
                                  borderRadius: BorderRadius.circular(16),
                                  hoverColor: Colors.transparent,
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

                      final showAnimatedHeader = expanded > 0.42;

                      return SizedBox(
                        height: headerHeight,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: horizontalPad,
                          ),
                          child: Row(
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: visualCollapsed
                                      ? _toggleSidebar
                                      : null,
                                  borderRadius: BorderRadius.circular(16),
                                  hoverColor: Colors.transparent,
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: brandIconShell(),
                                  ),
                                ),
                              ),
                              if (showAnimatedHeader)
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
                                                        color: sidebarTextColor,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize:
                                                            (13.6 * baseScale)
                                                                .clamp(
                                                                  11.8,
                                                                  14.2,
                                                                ),
                                                        letterSpacing: 0.44,
                                                      ),
                                                    ),
                                                    if (showHeaderSubtitle) ...[
                                                      const SizedBox(height: 3),
                                                      Text(
                                                        'Sistema comercial',
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color:
                                                              sidebarMutedTextColor,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          fontSize:
                                                              (10.0 * baseScale)
                                                                  .clamp(
                                                                    8.8,
                                                                    10.8,
                                                                  ),
                                                          letterSpacing: 0.22,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              IconButton(
                                                onPressed: _toggleSidebar,
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    BoxConstraints.tightFor(
                                                      width: btnSize,
                                                      height: btnSize,
                                                    ),
                                                iconSize: (22 * baseScale)
                                                    .clamp(18.0, 24.0),
                                                style: IconButton.styleFrom(
                                                  backgroundColor:
                                                      Color.alphaBlend(
                                                        sidebarHighlight(0.04),
                                                        sidebarBaseColor,
                                                      ),
                                                  foregroundColor:
                                                      sidebarTextColor,
                                                ),
                                                icon: PhosphorIcon(
                                                  PhosphorIcons.caretLeft(
                                                    PhosphorIconsStyle.bold,
                                                  ),
                                                  color: sidebarTextColor,
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
                              (8 * navScale).clamp(6.0, 10.0),
                              railPaddingH,
                              (5 * navScale).clamp(4.0, 7.0),
                            ),
                            child: Text(
                              text.toUpperCase(),
                              style: TextStyle(
                                color: sidebarMutedTextColor.withOpacity(0.92),
                                fontSize: (8.4 * navScale).clamp(7.8, 9.4),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: [
                      SizedBox(height: (6 * navScale).clamp(4.0, 8.0)),
                      header,
                      SizedBox(height: (6 * navScale).clamp(4.0, 8.0)),
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
                                  (2 * navScale).clamp(1.0, 4.0),
                                  visualCollapsed ? 2 : 0,
                                  (4 * navScale).clamp(3.0, 6.0),
                                ),
                                child: Column(
                                  children: [
                                    sectionLabel('Principal'),
                                    for (final entry in primaryEntries)
                                      if (entry.title != 'Clientes' &&
                                          entry.title != 'Reportes')
                                        buildNavEntry(
                                          icon: entry.icon,
                                          title: entry.title,
                                          route: entry.route,
                                          onTap: entry.onTap,
                                          activeRoutes:
                                              entry.title == 'Reportes'
                                              ? reportRoutes
                                              : null,
                                        ),
                                    buildNavEntry(
                                      icon: _SidebarIconPair(
                                        outline: PhosphorIcons.usersThree(
                                          PhosphorIconsStyle.regular,
                                        ),
                                        filled: PhosphorIcons.usersThree(
                                          PhosphorIconsStyle.fill,
                                        ),
                                      ),
                                      title: 'Clientes',
                                      route: null,
                                      onTap: () {
                                        if (visualCollapsed) {
                                          _setCollapsed(false);
                                          setState(
                                            () => _isClientsExpanded = true,
                                          );
                                          return;
                                        }
                                        setState(
                                          () => _isClientsExpanded =
                                              !_isClientsExpanded,
                                        );
                                      },
                                      activeRoutes: clientsRoutes,
                                      trailing: AnimatedRotation(
                                        turns: _isClientsExpanded ? 0.25 : 0.0,
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        child: PhosphorIcon(
                                          PhosphorIcons.caretRight(
                                            PhosphorIconsStyle.bold,
                                          ),
                                          size: (13.5 * navScale).clamp(
                                            12.0,
                                            14.0,
                                          ),
                                          color: effectiveSidebarTextColor
                                              .withOpacity(0.58),
                                        ),
                                      ),
                                      showSubmenuBadge: true,
                                    ),
                                    AnimatedSize(
                                      duration: const Duration(
                                        milliseconds: 240,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      alignment: Alignment.topCenter,
                                      child:
                                          shouldShowClientsChildren &&
                                              !visualCollapsed
                                          ? Padding(
                                              padding: EdgeInsets.only(
                                                left: (16 * navScale).clamp(
                                                  12.0,
                                                  18.0,
                                                ),
                                                top: (4 * navScale).clamp(
                                                  2.0,
                                                  6.0,
                                                ),
                                              ),
                                              child: AnimatedOpacity(
                                                duration: const Duration(
                                                  milliseconds: 180,
                                                ),
                                                curve: Curves.easeOut,
                                                opacity:
                                                    shouldShowClientsChildren
                                                    ? 1
                                                    : 0,
                                                child: Column(
                                                  children: [
                                                    for (final entry
                                                        in clientChildEntries)
                                                      buildNavEntry(
                                                        icon: entry.icon,
                                                        title: entry.title,
                                                        route: entry.route,
                                                        onTap: () => _go(
                                                          context,
                                                          entry.route,
                                                        ),
                                                        lowEmphasis: true,
                                                        showTrailingChevron:
                                                            false,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                    for (final entry in primaryEntries)
                                      if (entry.title == 'Reportes')
                                        buildNavEntry(
                                          icon: entry.icon,
                                          title: entry.title,
                                          route: entry.route,
                                          onTap: entry.onTap,
                                          activeRoutes:
                                              entry.title == 'Reportes'
                                              ? reportRoutes
                                              : null,
                                        ),
                                    SizedBox(
                                      height: (5 * navScale).clamp(4.0, 7.0),
                                    ),
                                    buildNavEntry(
                                      icon: _SidebarIconPair(
                                        outline: PhosphorIcons.squaresFour(
                                          PhosphorIconsStyle.regular,
                                        ),
                                        filled: PhosphorIcons.squaresFour(
                                          PhosphorIconsStyle.fill,
                                        ),
                                      ),
                                      title: 'Administración',
                                      route: null,
                                      onTap: () {
                                        if (visualCollapsed) {
                                          _setCollapsed(false);
                                          setState(
                                            () => _isAdministrationExpanded =
                                                true,
                                          );
                                          return;
                                        }
                                        setState(
                                          () => _isAdministrationExpanded =
                                              !_isAdministrationExpanded,
                                        );
                                      },
                                      activeRoutes: administrationRoutes,
                                      trailing: AnimatedRotation(
                                        turns: _isAdministrationExpanded
                                            ? 0.25
                                            : 0.0,
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        child: PhosphorIcon(
                                          PhosphorIcons.caretRight(
                                            PhosphorIconsStyle.bold,
                                          ),
                                          size: (13.5 * navScale).clamp(
                                            12.0,
                                            14.0,
                                          ),
                                          color: effectiveSidebarTextColor
                                              .withOpacity(0.58),
                                        ),
                                      ),
                                      showSubmenuBadge: true,
                                    ),
                                    AnimatedSize(
                                      duration: const Duration(
                                        milliseconds: 240,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      alignment: Alignment.topCenter,
                                      child:
                                          shouldShowAdministrationChildren &&
                                              !visualCollapsed
                                          ? Padding(
                                              padding: EdgeInsets.only(
                                                left: (16 * navScale).clamp(
                                                  12.0,
                                                  18.0,
                                                ),
                                                top: (4 * navScale).clamp(
                                                  2.0,
                                                  6.0,
                                                ),
                                              ),
                                              child: AnimatedOpacity(
                                                duration: const Duration(
                                                  milliseconds: 180,
                                                ),
                                                curve: Curves.easeOut,
                                                opacity:
                                                    shouldShowAdministrationChildren
                                                    ? 1
                                                    : 0,
                                                child: Column(
                                                  children: [
                                                    for (final entry
                                                        in administrationEntries)
                                                      buildNavEntry(
                                                        icon: entry.icon,
                                                        title: entry.title,
                                                        route: entry.route,
                                                        onTap: () => _go(
                                                          context,
                                                          entry.route,
                                                        ),
                                                        showTrailingChevron:
                                                            false,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                    const Spacer(),
                                    Container(
                                      margin: EdgeInsets.fromLTRB(
                                        visualCollapsed ? 10 : 8,
                                        (10 * navScale).clamp(8.0, 12.0),
                                        visualCollapsed ? 10 : 8,
                                        (8 * navScale).clamp(6.0, 10.0),
                                      ),
                                      height: 1,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Colors.transparent,
                                            sidebarBorderColor,
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                    sectionLabel('Sistema'),
                                    for (final entry in systemEntries)
                                      buildNavEntry(
                                        icon: entry.icon,
                                        title: entry.title,
                                        route: entry.route,
                                        onTap: () => _go(context, entry.route),
                                        lowEmphasis: true,
                                      ),
                                    SizedBox(
                                      height: (6 * navScale).clamp(4.0, 8.0),
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
            ],
          ),
        );
      },
    );
  }
}

class PremiumNavItem extends StatefulWidget {
  final IconData outlineIcon;
  final IconData activeIcon;
  final String title;
  final String? route;
  final String currentRoute;
  final Set<String>? activeRoutes;
  final VoidCallback? onTap;
  final double collapseProgress;
  final Color textColor;
  final Color activeColor;
  final Color hoverColor;
  final Color surfaceColor;
  final Color tooltipBackgroundColor;
  final Color tooltipTextColor;
  final Color activeGradientStart;
  final Color activeGradientEnd;
  final double scale;
  final bool lowEmphasis;
  final bool showTrailingChevron;
  final Widget? trailing;
  final bool showSubmenuBadge;

  const PremiumNavItem({
    super.key,
    required this.outlineIcon,
    required this.activeIcon,
    required this.title,
    required this.route,
    required this.currentRoute,
    this.activeRoutes,
    this.onTap,
    required this.collapseProgress,
    required this.textColor,
    required this.activeColor,
    required this.hoverColor,
    required this.surfaceColor,
    required this.tooltipBackgroundColor,
    required this.tooltipTextColor,
    required this.activeGradientStart,
    required this.activeGradientEnd,
    this.scale = 1.0,
    this.lowEmphasis = false,
    this.showTrailingChevron = true,
    this.trailing,
    this.showSubmenuBadge = false,
  });

  @override
  State<PremiumNavItem> createState() => _PremiumNavItemState();
}

class _PremiumNavItemState extends State<PremiumNavItem> {
  static const _hoverDuration = Duration(milliseconds: 150);
  static const _tooltipDuration = Duration(milliseconds: 160);

  bool _isHover = false;
  final OverlayPortalController _tooltipController = OverlayPortalController();
  final LayerLink _tooltipLayerLink = LayerLink();

  void _scheduleTooltipShow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isHover) return;
      if (Overlay.maybeOf(context) == null) return;
      try {
        _tooltipController.show();
      } catch (_) {
        // OverlayPortal can assert in debug if shown before it receives z-order.
      }
    });
  }

  void _scheduleTooltipHide() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isHover) return;
      try {
        _tooltipController.hide();
      } catch (_) {
        // OverlayPortal can assert in debug if hidden after detaching.
      }
    });
  }

  void _setHover(bool value) {
    if (!mounted || _isHover == value) return;

    if (value) {
      setState(() => _isHover = true);
      _scheduleTooltipShow();
      return;
    }

    setState(() => _isHover = false);
    Future<void>.delayed(_tooltipDuration, () {
      if (mounted && !_isHover) {
        _scheduleTooltipHide();
      }
    });
  }

  @override
  void dispose() {
    try {
      _tooltipController.hide();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchesRoute =
        widget.route != null &&
        (widget.currentRoute == widget.route ||
            widget.currentRoute.startsWith('${widget.route}/'));
    final matchesActiveRoute =
        widget.activeRoutes?.any(
          (route) =>
              widget.currentRoute == route ||
              widget.currentRoute.startsWith('$route/'),
        ) ??
        false;
    final isActive = matchesRoute || matchesActiveRoute;
    final isEnabled = widget.onTap != null || widget.route != null;

    final s = widget.scale.clamp(0.65, 1.12);
    Color navHighlight(double opacity) => Color.alphaBlend(
      widget.textColor.withOpacity(opacity),
      widget.surfaceColor,
    );

    Color navShadow(double opacity) => Color.alphaBlend(
      Theme.of(context).shadowColor.withOpacity(opacity),
      widget.surfaceColor,
    );
    final collapse = widget.collapseProgress.clamp(0.0, 1.0);
    final expanded = Curves.easeOutCubic.transform(1.0 - collapse);
    final visuallyCollapsed = collapse > 0.9;
    final itemRadius = BorderRadius.circular((9 * s).clamp(7.0, 9.0));
    final contentOpacity =
        (!visuallyCollapsed && widget.lowEmphasis && !_isHover && !isActive)
        ? 0.6
        : 1.0;
    final itemBorderColor = isActive
        ? Color.alphaBlend(
            widget.textColor.withOpacity(0.18),
            widget.surfaceColor,
          )
        : (_isHover
              ? Color.alphaBlend(
                  widget.textColor.withOpacity(0.10),
                  widget.surfaceColor,
                )
              : Colors.transparent);
    final glowColor =
        Color.lerp(widget.activeGradientEnd, widget.activeColor, 0.18) ??
        widget.activeGradientEnd;

    final fgColor = isActive
        ? ColorUtils.ensureReadableColor(
            widget.tooltipTextColor,
            widget.activeGradientEnd,
            minRatio: 4.5,
          )
        : widget.textColor.withOpacity(_isHover ? 0.98 : 0.88);
    final iconColor = isActive
        ? fgColor
        : widget.textColor.withOpacity(_isHover ? 0.98 : 0.86);
    final collapsedIconShellSize = (32 * s).clamp(30.0, 36.0);
    final collapsedShellBase = isActive
        ? widget.activeGradientEnd
        : Color.alphaBlend(
            navShadow(_isHover ? 0.08 : 0.14),
            widget.surfaceColor,
          );
    final collapsedShellTop = Color.alphaBlend(
      navHighlight(isActive ? 0.26 : (_isHover ? 0.20 : 0.16)),
      collapsedShellBase,
    );
    final collapsedShellBottom = Color.alphaBlend(
      navShadow(isActive ? 0.04 : (_isHover ? 0.08 : 0.12)),
      collapsedShellBase,
    );
    final tooltipGap = (14 * s).clamp(12.0, 16.0);
    final rowHeight = visuallyCollapsed
        ? (42 * s).clamp(40.0, 46.0)
        : (38 * s).clamp(35.0, 42.0);

    Widget buildSubmenuBadge() {
      return Container(
        key: Key('submenu-badge-${widget.title}'),
        width: visuallyCollapsed ? 15 : 14,
        height: visuallyCollapsed ? 15 : 14,
        decoration: BoxDecoration(
          color: isActive
              ? fgColor.withOpacity(0.16)
              : widget.textColor.withOpacity(_isHover ? 0.16 : 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive
                ? fgColor.withOpacity(0.34)
                : widget.textColor.withOpacity(0.18),
            width: 0.8,
          ),
        ),
        child: Center(
          child: PhosphorIcon(
            PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
            size: visuallyCollapsed ? 8.5 : 8,
            color: isActive ? fgColor : widget.textColor.withOpacity(0.72),
          ),
        ),
      );
    }

    return OverlayPortal(
      controller: _tooltipController,
      overlayChildBuilder: (context) {
        return IgnorePointer(
          child: CompositedTransformFollower(
            link: _tooltipLayerLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.centerRight,
            followerAnchor: Alignment.centerLeft,
            offset: Offset(tooltipGap, 0),
            child: UnconstrainedBox(
              alignment: Alignment.centerLeft,
              child: AnimatedSlide(
                duration: _tooltipDuration,
                curve: Curves.easeInOut,
                offset: _isHover ? Offset.zero : const Offset(-0.08, 0),
                child: AnimatedOpacity(
                  duration: _tooltipDuration,
                  curve: Curves.easeInOut,
                  opacity: _isHover ? 1 : 0,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 190),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.tooltipBackgroundColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Color.alphaBlend(
                            widget.tooltipTextColor.withOpacity(0.08),
                            widget.tooltipBackgroundColor,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: navShadow(0.28),
                            blurRadius: 20,
                            spreadRadius: -10,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.tooltipTextColor,
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.08,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _tooltipLayerLink,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: visuallyCollapsed
                ? (8 * s).clamp(6.0, 10.0)
                : (5 * s).clamp(3.0, 6.0),
          ),
          child: MouseRegion(
            cursor: isEnabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) => _setHover(true),
            onExit: (_) => _setHover(false),
            child: AnimatedScale(
              duration: _hoverDuration,
              curve: Curves.easeInOut,
              scale: _isHover ? 1.05 : 1.0,
              alignment: visuallyCollapsed
                  ? Alignment.center
                  : Alignment.centerLeft,
              child: Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: itemRadius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: itemRadius,
                  hoverColor: Colors.transparent,
                  splashColor: widget.textColor.withOpacity(0.05),
                  highlightColor: widget.textColor.withOpacity(0.03),
                  child: AnimatedContainer(
                    duration: _hoverDuration,
                    curve: Curves.easeInOut,
                    padding: EdgeInsets.symmetric(
                      horizontal: visuallyCollapsed
                          ? 0
                          : (11 * s).clamp(9.0, 13.0),
                      vertical: visuallyCollapsed
                          ? 0
                          : (4.5 * s).clamp(3.0, 6.0),
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? null
                          : (_isHover ? widget.hoverColor : Colors.transparent),
                      gradient: isActive
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                widget.activeGradientStart,
                                widget.activeGradientEnd,
                              ],
                            )
                          : null,
                      borderRadius: itemRadius,
                      border: Border.all(color: itemBorderColor),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: glowColor.withOpacity(0.42),
                                blurRadius: 20,
                                spreadRadius: -8,
                                offset: const Offset(0, 10),
                              ),
                            ]
                          : _isHover
                          ? [
                              BoxShadow(
                                color: navShadow(0.16),
                                blurRadius: 14,
                                spreadRadius: -8,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : [const BoxShadow(color: Colors.transparent)],
                    ),
                    child: Opacity(
                      opacity: contentOpacity,
                      child: SizedBox(
                        height: rowHeight,
                        child: visuallyCollapsed
                            ? Center(
                                child: AnimatedContainer(
                                  duration: _hoverDuration,
                                  curve: Curves.easeInOut,
                                  width: collapsedIconShellSize,
                                  height: collapsedIconShellSize,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        collapsedShellTop,
                                        collapsedShellBottom,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Color.alphaBlend(
                                        widget.textColor.withOpacity(
                                          isActive
                                              ? 0.18
                                              : (_isHover ? 0.11 : 0.08),
                                        ),
                                        collapsedShellBase,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isActive
                                            ? glowColor.withOpacity(0.44)
                                            : navShadow(_isHover ? 0.18 : 0.10),
                                        blurRadius: isActive ? 18 : 12,
                                        spreadRadius: -8,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    navHighlight(
                                                      isActive
                                                          ? 0.16
                                                          : (_isHover
                                                                ? 0.12
                                                                : 0.10),
                                                    ),
                                                    Colors.transparent,
                                                    navShadow(
                                                      isActive ? 0.06 : 0.10,
                                                    ),
                                                  ],
                                                  stops: const [0.0, 0.55, 1.0],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 8,
                                          right: 8,
                                          top: 7,
                                          child: IgnorePointer(
                                            child: Container(
                                              height: 1.2,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                gradient: LinearGradient(
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                  colors: [
                                                    Colors.transparent,
                                                    Color.alphaBlend(
                                                      widget.textColor
                                                          .withOpacity(
                                                            isActive
                                                                ? 0.32
                                                                : (_isHover
                                                                      ? 0.26
                                                                      : 0.22),
                                                          ),
                                                      collapsedShellBase,
                                                    ),
                                                    Colors.transparent,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Center(
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              PhosphorIcon(
                                                isActive
                                                    ? widget.activeIcon
                                                    : widget.outlineIcon,
                                                color: isActive
                                                    ? fgColor
                                                    : widget.textColor
                                                          .withOpacity(
                                                            _isHover
                                                                ? 1.0
                                                                : 0.98,
                                                          ),
                                                size: (19.5 * s).clamp(
                                                  18.0,
                                                  21.0,
                                                ),
                                              ),
                                              if (widget.showSubmenuBadge)
                                                Positioned(
                                                  right: -5,
                                                  bottom: -4,
                                                  child: buildSubmenuBadge(),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      PhosphorIcon(
                                        isActive
                                            ? widget.activeIcon
                                            : widget.outlineIcon,
                                        color: iconColor,
                                        size: (19.5 * s).clamp(18.0, 21.0),
                                      ),
                                      if (widget.showSubmenuBadge)
                                        Positioned(
                                          right: -6,
                                          bottom: -5,
                                          child: buildSubmenuBadge(),
                                        ),
                                    ],
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
                                                left: (12 * s).clamp(8.0, 11.0),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      widget.title,
                                                      style: TextStyle(
                                                        color: fgColor,
                                                        fontSize: (12.1 * s)
                                                            .clamp(11.0, 12.8),
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        letterSpacing: 0.12,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      softWrap: false,
                                                    ),
                                                  ),
                                                  if (widget.trailing != null)
                                                    widget.trailing!
                                                  else if (widget
                                                      .showTrailingChevron)
                                                    PhosphorIcon(
                                                      PhosphorIcons.caretRight(
                                                        PhosphorIconsStyle.bold,
                                                      ),
                                                      size: (13.5 * s).clamp(
                                                        12.0,
                                                        14.0,
                                                      ),
                                                      color: fgColor
                                                          .withOpacity(0.58),
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
            ),
          ),
        ),
      ),
    );
  }
}
