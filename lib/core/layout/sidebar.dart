import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_sizes.dart';
import '../bootstrap/app_bootstrap_controller.dart';
import '../errors/error_handler.dart';
import '../session/ui_preferences.dart';
import '../session/session_manager.dart';
import '../theme/color_utils.dart';
import '../../features/settings/providers/business_settings_provider.dart';
import '../../features/settings/providers/theme_provider.dart';
import '../../features/products/utils/catalog_pdf_launcher.dart';

/// Sidebar del layout principal con navegacion (colapsable).
///
/// Importante: El usuario pidio restaurar el diseno del sidebar. Este sidebar
/// mantiene un estilo "premium" (pill/hover/selected) y expone la mayoria de
/// rutas principales (segun `lib/app/router.dart`), sin agregar botones nuevos
/// de "logout" dentro del sidebar.
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

class _SidebarState extends ConsumerState<Sidebar> {
  bool _isCollapsed = false;

  @override
  void initState() {
    super.initState();
    _isCollapsed = widget.forcedCollapsed ?? _isCollapsed;
    _loadState();
  }

  Future<void> _loadState() async {
    final collapsed =
        widget.forcedCollapsed ?? await UiPreferences.isSidebarCollapsed();
    if (mounted) setState(() => _isCollapsed = collapsed);
  }

  Future<void> _toggleSidebar() async {
    if (widget.forcedCollapsed != null) {
      if (mounted) setState(() => _isCollapsed = !_isCollapsed);
      return;
    }

    final newState = await UiPreferences.toggleSidebar();
    if (mounted) setState(() => _isCollapsed = newState);
  }

  void _go(BuildContext context, String route) {
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    final themeSettings = ref.watch(themeProvider);
    final businessSettings = ref.watch(businessSettingsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final sidebarBg = themeSettings.sidebarColor;
    final sidebarTextColor = ColorUtils.ensureReadableColor(
      themeSettings.sidebarTextColor,
      sidebarBg,
    );
    final activeColor = themeSettings.sidebarActiveColor;
    final hoverColor = themeSettings.hoverColor;

    final borderColor = scheme.outlineVariant.withOpacity(0.35);
    final shadowColor = theme.shadowColor;

    final s = widget.scale.clamp(0.65, 1.12);
    final targetWidth = widget.customWidth ?? AppSizes.sidebarWidth;
    final collapsedWidth = (72.0 * s).clamp(60.0, 78.0);
    final topbarHeight = (AppSizes.topbarHeight * s).clamp(52.0, 72.0);
    final padM = AppSizes.paddingM * s;
    final padS = AppSizes.paddingS * s;

    final logoFile = businessSettings.logoPath != null
        ? File(businessSettings.logoPath!)
        : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: _isCollapsed ? collapsedWidth : targetWidth,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(right: BorderSide(color: borderColor, width: 2)),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(6, 8),
          ),
          BoxShadow(
            color: scheme.onSurface.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(-2, -2),
            spreadRadius: -3,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Durante la animacion de ancho, el layout puede estar en un estado
          // intermedio. Evitamos overflows tratando el sidebar como colapsado
          // hasta que haya suficiente ancho real.
          final effectiveCollapsed = _isCollapsed || constraints.maxWidth < 160;

          Widget logoImage({required double size}) {
            if (logoFile != null && logoFile.existsSync()) {
              return Image.file(
                logoFile,
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              );
            }

            return Image.asset(
              'assets/imagen/lonchericon.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            );
          }

          final title =
              (businessSettings.businessName.trim().isNotEmpty
                      ? businessSettings.businessName.trim()
                      : 'FULLPOS')
                  .toUpperCase();

          final header = LayoutBuilder(
            builder: (context, headerConstraints) {
              final availableWidth = headerConstraints.maxWidth;
              final horizontalPad = effectiveCollapsed
                  ? (padS * 0.6).clamp(4.0, 10.0)
                  : padM;
              final contentWidth = math.max(
                0.0,
                availableWidth - (horizontalPad * 2),
              );

              final desiredLogoSize = effectiveCollapsed
                  ? (48 * s).clamp(36.0, 52.0)
                  : (40 * s).clamp(32.0, 44.0);

              // In collapsed mode: show ONLY the logo (no chevron button).
              // Tap the logo to expand the menu.
              final desiredBtnSize = (40 * s).clamp(32.0, 44.0);
              final btnSize = effectiveCollapsed
                  ? 0.0
                  : math.min(desiredBtnSize, contentWidth);
              final gap = (!effectiveCollapsed && contentWidth > 0) ? padS : 0.0;

              final maxLogoSize = contentWidth - btnSize - gap;
              final showLogo = maxLogoSize >= 24.0;
              final logoSize = showLogo ? math.min(desiredLogoSize, maxLogoSize) : 0.0;

              return SizedBox(
                height: topbarHeight,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPad),
                  child: Row(
                    mainAxisAlignment:
                        effectiveCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      if (showLogo)
                        Tooltip(
                          message: effectiveCollapsed ? 'Expandir menú' : 'Menú',
                          waitDuration: const Duration(milliseconds: 350),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: effectiveCollapsed ? _toggleSidebar : null,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: SizedBox(
                                  width: logoSize,
                                  height: logoSize,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: logoImage(size: logoSize),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (!effectiveCollapsed) ...[
                        SizedBox(width: padS),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: sidebarTextColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: (14.5 * s).clamp(12.0, 15.5),
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Sistema POS',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: sidebarTextColor.withOpacity(0.78),
                                  fontWeight: FontWeight.w700,
                                  fontSize: (11.0 * s).clamp(9.5, 12.5),
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (!effectiveCollapsed) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Colapsar menú',
                          onPressed: _toggleSidebar,
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints.tightFor(
                            width: btnSize,
                            height: btnSize,
                          ),
                          iconSize: (22 * s).clamp(18.0, 24.0),
                          icon: Icon(
                            Icons.chevron_left,
                            color: sidebarTextColor.withOpacity(0.95),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );

          Widget sectionLabel(String text) {
            if (effectiveCollapsed) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.fromLTRB(padM, 10, padM, 6),
              child: Text(
                text.toUpperCase(),
                style: TextStyle(
                  color: sidebarTextColor.withOpacity(0.65),
                  fontSize: (11.0 * s).clamp(10.0, 12.0),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
            );
          }

          return Column(
            children: [
              header,
              Divider(color: sidebarTextColor.withOpacity(0.12), height: 1),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(vertical: padS),
                  children: [
                    sectionLabel('Ventas'),
                    PremiumNavItem(
                      icon: Icons.point_of_sale,
                      title: 'Ventas',
                      route: '/sales',
                      onTap: () => _go(context, '/sales'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.receipt_long_outlined,
                      title: 'Lista de ventas',
                      route: '/sales-list',
                      onTap: () => _go(context, '/sales-list'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.request_quote_outlined,
                      title: 'Cotizaciones',
                      route: '/quotes-list',
                      onTap: () => _go(context, '/quotes-list'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.assignment_return_outlined,
                      title: 'Devoluciones',
                      route: '/returns-list',
                      onTap: () => _go(context, '/returns-list'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.account_balance,
                      title: 'Creditos',
                      route: '/credits-list',
                      onTap: () => _go(context, '/credits-list'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    sectionLabel('Caja'),
                    PremiumNavItem(
                      icon: Icons.receipt_long_outlined,
                      title: 'Corte',
                      route: '/cash/history',
                      onTap: () => _go(context, '/cash/history'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.payments_outlined,
                      title: 'Gastos',
                      route: '/cash/expenses',
                      onTap: () => _go(context, '/cash/expenses'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    sectionLabel('Inventario'),
                    PremiumNavItem(
                      icon: Icons.inventory_2_outlined,
                      title: 'Productos',
                      route: '/products',
                      onTap: () => _go(context, '/products'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.picture_as_pdf,
                      title: 'Producto PDF',
                      route: null,
                      onTap: () => CatalogPdfLauncher.openFromSidebar(context),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.timeline,
                      title: 'Historial de stock',
                      route: '/products/history',
                      onTap: () => _go(context, '/products/history'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.people_alt_outlined,
                      title: 'Clientes',
                      route: '/clients',
                      onTap: () => _go(context, '/clients'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    sectionLabel('Compras'),
                    PremiumNavItem(
                      icon: Icons.shopping_cart_outlined,
                      title: 'Ordenes de compra',
                      route: '/purchases',
                      onTap: () => _go(context, '/purchases'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.add_shopping_cart,
                      title: 'Nueva orden',
                      route: '/purchases/new',
                      onTap: () => _go(context, '/purchases/new'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.auto_awesome,
                      title: 'Orden automatica',
                      route: '/purchases/auto',
                      onTap: () => _go(context, '/purchases/auto'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    sectionLabel('Reportes y herramientas'),
                    PremiumNavItem(
                      icon: Icons.bar_chart,
                      title: 'Reportes',
                      route: '/reports',
                      onTap: () => _go(context, '/reports'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.build_outlined,
                      title: 'Herramientas',
                      route: '/tools',
                      onTap: () => _go(context, '/tools'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    PremiumNavItem(
                      icon: Icons.confirmation_number_outlined,
                      title: 'NCF',
                      route: '/ncf',
                      onTap: () => _go(context, '/ncf'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),
                    sectionLabel('Configuracion'),
                    PremiumNavItem(
                      icon: Icons.settings_outlined,
                      title: 'Configuracion',
                      route: '/settings',
                      onTap: () => _go(context, '/settings'),
                      isCollapsed: effectiveCollapsed,
                      textColor: sidebarTextColor,
                      activeColor: activeColor,
                      hoverColor: hoverColor,
                      scale: s,
                    ),

                    SizedBox(height: (AppSizes.spaceXL * 2) * s),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Fixed logout button at end of sidebar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: padM, vertical: (12 * s).clamp(10.0, 16.0)),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular((12 * s).clamp(8.0, 14.0)),
                    color: Color.alphaBlend(scheme.error.withOpacity(0.06), sidebarBg.withOpacity(0.02)),
                  ),
                  child: PremiumNavItem(
                    icon: Icons.logout,
                    title: 'Cerrar sesión',
                    route: null,
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Cerrar sesión'),
                          content: const Text('¿Deseas cerrar sesión del sistema?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.pop(context, true),
                              icon: const Icon(Icons.logout),
                              label: const Text('Cerrar sesión'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: scheme.error,
                                foregroundColor: scheme.onError,
                              ),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          ref.read(appBootstrapProvider).forceLoggedOut();
                          await SessionManager.logout();
                          await ref.read(appBootstrapProvider).refreshAuth();
                          // Navegar usando el contexto root para evitar quedarse
                          // atrapado dentro del ShellRoute.
                          if (!context.mounted) return;
                          final rootCtx =
                              ErrorHandler.navigatorKey.currentContext ?? context;
                          GoRouter.of(rootCtx).refresh();
                          GoRouter.of(rootCtx).go('/login');
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('No se pudo cerrar sesión: $e'),
                                backgroundColor: scheme.error,
                              ),
                            );
                          }
                        }
                      }
                    },
                    isCollapsed: effectiveCollapsed,
                    textColor: sidebarTextColor,
                    activeColor: scheme.error,
                    hoverColor: hoverColor,
                    scale: s,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Item de navegacion del sidebar (premium + hover/selected)
class PremiumNavItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? route;
  final VoidCallback? onTap;
  final bool isCollapsed;
  final Color textColor;
  final Color activeColor;
  final Color hoverColor;
  final double scale;

  const PremiumNavItem({
    super.key,
    required this.icon,
    required this.title,
    required this.route,
    this.onTap,
    required this.isCollapsed,
    required this.textColor,
    required this.activeColor,
    required this.hoverColor,
    this.scale = 1.0,
  });

  @override
  State<PremiumNavItem> createState() => _PremiumNavItemState();
}

class _PremiumNavItemState extends State<PremiumNavItem> {
  bool _isHover = false;

  String _safeCurrentPath(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      // ignore
    }

    try {
      final router = GoRouter.of(context);
      final routeInfo = router.routeInformationProvider.value;
      return routeInfo.uri.path;
    } catch (_) {
      // ignore
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shadowColor = theme.shadowColor;
    final transparent = Colors.transparent;

    final currentRoute = _safeCurrentPath(context);
    final isActive = widget.route != null && currentRoute == widget.route;
    final isEnabled = widget.onTap != null || widget.route != null;

    final s = widget.scale.clamp(0.65, 1.12);
    const duration = Duration(milliseconds: 180);
    final pillRadius = BorderRadius.circular((16 * s).clamp(12.0, 16.0));

    final idleBg = widget.textColor.withOpacity(0.04);
    final hoverBgA = widget.hoverColor.withOpacity(0.14);
    final hoverBgB = widget.hoverColor.withOpacity(0.06);
    final activeBgA = widget.activeColor.withOpacity(0.22);
    final activeBgB = widget.activeColor.withOpacity(0.10);

    final fgColor = isActive ? widget.textColor.withOpacity(0.98) : widget.textColor;
    final iconColor = isActive ? widget.activeColor.withOpacity(0.95) : widget.textColor;

    final item = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: (widget.isCollapsed ? 6 : 12) * s,
        vertical: (4 * s).clamp(3.0, 4.0),
      ),
      child: Material(
        color: transparent,
        shape: RoundedRectangleBorder(borderRadius: pillRadius),
        clipBehavior: Clip.antiAlias,
        child: MouseRegion(
          cursor: isEnabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _isHover = true),
          onExit: (_) => setState(() => _isHover = false),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: pillRadius,
            hoverColor: widget.hoverColor.withOpacity(0.10),
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(
                horizontal: widget.isCollapsed ? 0 : (14 * s).clamp(10.0, 14.0),
                vertical: widget.isCollapsed
                    ? (10 * s).clamp(7.0, 10.0)
                    : (12 * s).clamp(8.0, 12.0),
              ),
              decoration: BoxDecoration(
                gradient: isActive
                    ? LinearGradient(
                        colors: [
                          activeBgA,
                          activeBgB,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : (_isHover
                          ? LinearGradient(
                              colors: [
                                hoverBgA,
                                hoverBgB,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null),
                color: isActive || _isHover
                    ? null
                    : idleBg,
                borderRadius: pillRadius,
                border: Border.all(
                  color: isActive
                      ? widget.activeColor.withOpacity(0.35)
                      : widget.textColor.withOpacity(0.08),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withOpacity(isActive ? 0.22 : 0.16),
                    blurRadius: isActive ? 12 : 9,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: widget.isCollapsed
                  ? SizedBox(
                      height: (44 * s).clamp(36.0, 44.0),
                      child: Center(
                        child: Icon(
                          widget.icon,
                          color: iconColor,
                          size: (22 * s).clamp(18.0, 22.0),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        Icon(
                          widget.icon,
                          color: iconColor,
                          size: (21 * s).clamp(18.0, 22.0),
                        ),
                        SizedBox(width: (12 * s).clamp(8.0, 12.0)),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: TextStyle(
                              color: fgColor,
                              fontSize: (14.5 * s).clamp(12.0, 14.5),
                              fontWeight: isActive
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: (16 * s).clamp(14.0, 16.0),
                          color: fgColor.withOpacity(0.55),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    if (!widget.isCollapsed) return item;

    return Tooltip(
      message: widget.title,
      waitDuration: const Duration(milliseconds: 450),
      child: item,
    );
  }
}
