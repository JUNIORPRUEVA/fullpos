import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'topbar_action_bus.dart';

// ─────────────────────────────────────────────────────────────
// FullPOS Drawer Compact Premium
// Orden:
// 1) Ventas, Inventario, Reportes fuera y primero.
// 2) Submenú Clientes.
// 3) Submenú Movimiento efectivo.
// 4) Submenú Gestión.
// 5) Facturación electrónica abajo separada.
// ─────────────────────────────────────────────────────────────
const Color _kPrimaryBlue = Color(0xFF1A56DB);
const Color _kBorderColor = Color(0xFFE2E8F0);
const Color _kTextDark = Color(0xFF0F172A);
const Color _kTextMuted = Color(0xFF64748B);
const Color _kActiveBg = Color(0xFFEAF2FF);
const Color _kHoverBg = Color(0xFFF1F5F9);
const Color _kPanelBg = Colors.white;
const Color _kFooterBg = Color(0xFFF8FAFC);

const double _kDrawerWidth = 318.0;
const Duration _kAnimationDuration = Duration(milliseconds: 250);

// ─── Rutas reales del proyecto ───────────────────────────────
const String _kSalesRoute = '/sales';
const String _kInventoryRoute = '/products';
const String _kInventoryStockAdjustmentRoute = '/products/stock-adjustment';
const String _kInventoryMovementsRoute = '/products/movements';
const String _kInventoryCountRoute = '/products/count';
const String _kReportsRoute = '/reports';

const String _kClientsRoute = '/clients';
const String _kClientCreditsRoute = '/credits';
const String _kClientLayawaysRoute = '/layaways';

const String _kMoneyIncomeRoute = '/sales';
const String _kMoneyOutcomeRoute = '/sales';
const String _kMoneyHistoryRoute = '/cash/history';

const String _kPurchaseCreateRoute = '/purchases/new';
const String _kPurchaseHistoryRoute = '/purchases';
const String _kSupplierCreateRoute = '/suppliers/new';
const String _kSuppliersHistoryRoute = '/suppliers';

const String _kElectronicBillingRoute = '/electronic-documents';

class FullPosDrawer extends ConsumerStatefulWidget {
  const FullPosDrawer({super.key});

  @override
  ConsumerState<FullPosDrawer> createState() => _FullPosDrawerState();
}

class _FullPosDrawerState extends ConsumerState<FullPosDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  bool _clientsExpanded = false;
  bool _inventoryExpanded = false;
  bool _moneyExpanded = false;
  bool _managementExpanded = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _kAnimationDuration,
      reverseDuration: const Duration(milliseconds: 205),
    );

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(curved);

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);

    _scaleAnimation = Tween<double>(begin: 0.986, end: 1.0).animate(curved);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _currentPath() {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      return '';
    }
  }

  bool _isActive(String route) {
    if (route.isEmpty) return false;
    final current = _currentPath();
    return current == route || current.startsWith('$route/');
  }

  bool _isAnyActive(List<String> routes) {
    return routes.any(_isActive);
  }

  void _navigate(String route) {
    try {
      context.go(route);
    } catch (_) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir $route'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    _closeDrawer();
  }

  void _closeDrawer() {
    _controller.reverse().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _closeDrawerThen(VoidCallback action) {
    final router = GoRouter.of(context);
    _controller.reverse().then((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      action();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        router.go(_kSalesRoute);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          TopbarActionBus.dispatchPendingSalesOverlay();
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventoryRoutes = [
      _kInventoryRoute,
      _kInventoryStockAdjustmentRoute,
      _kInventoryMovementsRoute,
      _kInventoryCountRoute,
    ];
    final inventoryActive = _isAnyActive(inventoryRoutes);
    return GestureDetector(
      onTap: _closeDrawer,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          color: Colors.black.withOpacity(0.34),
          child: GestureDetector(
            onTap: () {},
            child: SlideTransition(
              position: _slideAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                alignment: Alignment.centerLeft,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: _kDrawerWidth,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: _kPanelBg,
                      border: const Border(
                        right: BorderSide(color: _kBorderColor, width: 1),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.14),
                          blurRadius: 34,
                          spreadRadius: -12,
                          offset: const Offset(10, 0),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Column(
                        children: [
                          _DrawerHeader(onClose: _closeDrawer),
                          _DrawerCurrentShift(
                            onTap: () {
                              TopbarActionBus.queueSalesCurrentCutView();
                              _closeDrawerThen(() {});
                            },
                          ),
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                              physics: const ClampingScrollPhysics(),
                              children: [
                                _DrawerNavItem(
                                  icon: PhosphorIcons.receipt(
                                    PhosphorIconsStyle.regular,
                                  ),
                                  activeIcon: PhosphorIcons.receipt(
                                    PhosphorIconsStyle.fill,
                                  ),
                                  title: 'Ventas',
                                  isActive: _isActive(_kSalesRoute),
                                  isPrimary: true,
                                  onTap: () => _navigate(_kSalesRoute),
                                ),
                                _DrawerExpandableItem(
                                  icon: PhosphorIcons.package(
                                    PhosphorIconsStyle.regular,
                                  ),
                                  activeIcon: PhosphorIcons.package(
                                    PhosphorIconsStyle.fill,
                                  ),
                                  title: 'Inventario',
                                  isExpanded:
                                      _inventoryExpanded || inventoryActive,
                                  isActive: inventoryActive,
                                  onTap: () {
                                    setState(() {
                                      _inventoryExpanded = !_inventoryExpanded;
                                    });
                                  },
                                ),
                                _DrawerSubmenu(
                                  visible:
                                      _inventoryExpanded || inventoryActive,
                                  children: [
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.cube(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Productos y servicios',
                                      isActive: _isActive(_kInventoryRoute),
                                      onTap: () => _navigate(_kInventoryRoute),
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.slidersHorizontal(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Ajuste de stock',
                                      isActive: _isActive(
                                        _kInventoryStockAdjustmentRoute,
                                      ),
                                      onTap: () => _navigate(
                                        _kInventoryStockAdjustmentRoute,
                                      ),
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.arrowsClockwise(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Movimientos de inventario',
                                      isActive: _isActive(
                                        _kInventoryMovementsRoute,
                                      ),
                                      onTap: () =>
                                          _navigate(_kInventoryMovementsRoute),
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.clipboardText(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Recuento de inventario',
                                      isActive: _isActive(
                                        _kInventoryCountRoute,
                                      ),
                                      onTap: () =>
                                          _navigate(_kInventoryCountRoute),
                                    ),
                                  ],
                                ),
                                _DrawerNavItem(
                                  icon: PhosphorIcons.chartBar(
                                    PhosphorIconsStyle.regular,
                                  ),
                                  activeIcon: PhosphorIcons.chartBar(
                                    PhosphorIconsStyle.fill,
                                  ),
                                  title: 'Reportes',
                                  isActive: _isActive(_kReportsRoute),
                                  isPrimary: true,
                                  onTap: () => _navigate(_kReportsRoute),
                                ),

                                const SizedBox(height: 12),

                                _DrawerExpandableItem(
                                  icon: PhosphorIcons.userList(
                                    PhosphorIconsStyle.regular,
                                  ),
                                  activeIcon: PhosphorIcons.userList(
                                    PhosphorIconsStyle.fill,
                                  ),
                                  title: 'Clientes',
                                  isExpanded: _clientsExpanded,
                                  isActive: _isAnyActive([
                                    _kClientsRoute,
                                    _kClientCreditsRoute,
                                    _kClientLayawaysRoute,
                                  ]),
                                  onTap: () {
                                    setState(() {
                                      _clientsExpanded = !_clientsExpanded;
                                    });
                                  },
                                ),
                                _DrawerSubmenu(
                                  visible: _clientsExpanded,
                                  children: [
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.users(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Clientes',
                                      isActive: _isActive(_kClientsRoute),
                                      onTap: () => _navigate(_kClientsRoute),
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.creditCard(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Créditos',
                                      isActive: _isActive(_kClientCreditsRoute),
                                      onTap: () =>
                                          _navigate(_kClientCreditsRoute),
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.package(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Apartados',
                                      isActive: _isActive(_kClientLayawaysRoute),
                                      onTap: () =>
                                          _navigate(_kClientLayawaysRoute),
                                    ),
                                  ],
                                ),

                                _DrawerExpandableItem(
                                  icon: PhosphorIcons.wallet(
                                    PhosphorIconsStyle.regular,
                                  ),
                                  activeIcon: PhosphorIcons.wallet(
                                    PhosphorIconsStyle.fill,
                                  ),
                                  title: 'Movimiento efectivo',
                                  isExpanded: _moneyExpanded,
                                  isActive: _isAnyActive([
                                    _kMoneyIncomeRoute,
                                    _kMoneyOutcomeRoute,
                                    _kMoneyHistoryRoute,
                                  ]),
                                  onTap: () {
                                    setState(() {
                                      _moneyExpanded = !_moneyExpanded;
                                    });
                                  },
                                ),
                                _DrawerSubmenu(
                                  visible: _moneyExpanded,
                                  children: [
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.arrowCircleDown(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Registrar ingreso',
                                      isActive: false,
                                      onTap: () {
                                        TopbarActionBus.queueSalesCashMovementDialog(
                                          'income',
                                        );
                                        _closeDrawerThen(() {});
                                      },
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.arrowCircleUp(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Registrar salida',
                                      isActive: false,
                                      onTap: () {
                                        TopbarActionBus.queueSalesCashMovementDialog(
                                          'outcome',
                                        );
                                        _closeDrawerThen(() {});
                                      },
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.clockCounterClockwise(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Movimiento de efectivo',
                                      isActive: _isActive(_kMoneyHistoryRoute),
                                      onTap: () =>
                                          _navigate(_kMoneyHistoryRoute),
                                    ),
                                  ],
                                ),

                                _DrawerExpandableItem(
                                  icon: PhosphorIcons.briefcase(
                                    PhosphorIconsStyle.regular,
                                  ),
                                  activeIcon: PhosphorIcons.briefcase(
                                    PhosphorIconsStyle.fill,
                                  ),
                                  title: 'Gestión',
                                  isExpanded: _managementExpanded,
                                  isActive: _isAnyActive([
                                    _kPurchaseCreateRoute,
                                    _kPurchaseHistoryRoute,
                                    _kSupplierCreateRoute,
                                    _kSuppliersHistoryRoute,
                                  ]),
                                  onTap: () {
                                    setState(() {
                                      _managementExpanded =
                                          !_managementExpanded;
                                    });
                                  },
                                ),
                                _DrawerSubmenu(
                                  visible: _managementExpanded,
                                  children: [
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.shoppingCart(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Realizar compra',
                                      isActive: _isActive(
                                        _kPurchaseCreateRoute,
                                      ),
                                      onTap: () =>
                                          _navigate(_kPurchaseCreateRoute),
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.listChecks(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Historial de compras',
                                      isActive: _isActive(
                                        _kPurchaseHistoryRoute,
                                      ),
                                      onTap: () =>
                                          _navigate(_kPurchaseHistoryRoute),
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.userPlus(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Registrar suplidor',
                                      isActive: _isActive(
                                        _kSupplierCreateRoute,
                                      ),
                                      onTap: () =>
                                          _navigate(_kSupplierCreateRoute),
                                    ),
                                    _DrawerSubItem(
                                      icon: PhosphorIcons.truck(
                                        PhosphorIconsStyle.regular,
                                      ),
                                      title: 'Ver suplidores',
                                      isActive: _isActive(
                                        _kSuppliersHistoryRoute,
                                      ),
                                      onTap: () =>
                                          _navigate(_kSuppliersHistoryRoute),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),
                                const _DrawerSoftDivider(),
                                const SizedBox(height: 10),

                                _DrawerNavItem(
                                  icon: PhosphorIcons.fileText(
                                    PhosphorIconsStyle.regular,
                                  ),
                                  activeIcon: PhosphorIcons.fileText(
                                    PhosphorIconsStyle.fill,
                                  ),
                                  title: 'Facturación electrónica',
                                  isActive: _isActive(_kElectronicBillingRoute),
                                  isPrimary: false,
                                  onTap: () =>
                                      _navigate(_kElectronicBillingRoute),
                                ),
                              ],
                            ),
                          ),
                          const _DrawerFooter(),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _kBorderColor, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_kPrimaryBlue, Color(0xFF1D4ED8), Color(0xFF1E40AF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: _kPrimaryBlue.withOpacity(0.23),
                  blurRadius: 16,
                  spreadRadius: -8,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 22,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FullPOS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _kTextDark,
                    fontSize: 17.5,
                    fontWeight: FontWeight.w800,
                    height: 1.08,
                    letterSpacing: -0.15,
                    decoration: TextDecoration.none,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Sistema de facturación',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _kTextMuted,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w500,
                    height: 1.12,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _DrawerCloseButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _DrawerCloseButton extends StatefulWidget {
  const _DrawerCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DrawerCloseButton> createState() => _DrawerCloseButtonState();
}

class _DrawerCloseButtonState extends State<_DrawerCloseButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _hovered ? _kActiveBg : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _hovered ? const Color(0xFFBFD1F7) : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(10),
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: _hovered ? _kPrimaryBlue : _kTextMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Current shift
// ─────────────────────────────────────────────────────────────
class _DrawerCurrentShift extends StatefulWidget {
  const _DrawerCurrentShift({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DrawerCurrentShift> createState() => _DrawerCurrentShiftState();
}

class _DrawerCurrentShiftState extends State<_DrawerCurrentShift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 7),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 42,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFFF8FBFF) : Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: _hovered ? const Color(0xFFBFD1F7) : _kBorderColor,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(11),
              splashColor: _kPrimaryBlue.withOpacity(0.06),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.point_of_sale_rounded,
                      size: 18,
                      color: _hovered ? _kPrimaryBlue : _kTextMuted,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Cerrar turno',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _kTextDark,
                          fontSize: 13.8,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                          letterSpacing: 0.02,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    AnimatedSlide(
                      duration: const Duration(milliseconds: 150),
                      offset: _hovered ? const Offset(0.10, 0) : Offset.zero,
                      child: Icon(
                        Icons.logout_rounded,
                        size: 18,
                        color: _hovered ? _kPrimaryBlue : _kTextMuted,
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
  }
}

class _DrawerSoftDivider extends StatelessWidget {
  const _DrawerSoftDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 1,
        decoration: BoxDecoration(
          color: _kBorderColor.withOpacity(0.85),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Main item
// ─────────────────────────────────────────────────────────────
class _DrawerNavItem extends StatelessWidget {
  const _DrawerNavItem({
    required this.icon,
    required this.activeIcon,
    required this.title,
    required this.isActive,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String title;
  final bool isActive;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    return _DrawerBaseItem(
      icon: isActive ? activeIcon : icon,
      title: title,
      isActive: isActive,
      onTap: onTap,
      isPrimary: isPrimary,
    );
  }
}

class _DrawerExpandableItem extends StatelessWidget {
  const _DrawerExpandableItem({
    required this.icon,
    required this.activeIcon,
    required this.title,
    required this.isExpanded,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String title;
  final bool isExpanded;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _DrawerBaseItem(
      icon: isActive ? activeIcon : icon,
      title: title,
      isActive: isActive,
      onTap: onTap,
      trailing: AnimatedRotation(
        turns: isExpanded ? 0.25 : 0.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: isActive ? _kPrimaryBlue : _kTextMuted,
        ),
      ),
    );
  }
}

class _DrawerBaseItem extends StatefulWidget {
  const _DrawerBaseItem({
    required this.icon,
    required this.title,
    required this.isActive,
    required this.onTap,
    this.trailing,
    this.isPrimary = false,
  });

  final IconData icon;
  final String title;
  final bool isActive;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool isPrimary;

  @override
  State<_DrawerBaseItem> createState() => _DrawerBaseItemState();
}

class _DrawerBaseItemState extends State<_DrawerBaseItem> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
   final highlighted = widget.isActive;

final bgColor = widget.isActive
    ? _kActiveBg
    : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 100),
          scale: _pressed ? 0.985 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            height: widget.isPrimary ? 42 : 40,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: widget.isActive
                    ? const Color(0xFFBFD1F7)
                    : Colors.transparent,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                onTapDown: (_) => setState(() => _pressed = true),
                onTapCancel: () => setState(() => _pressed = false),
                onTapUp: (_) => setState(() => _pressed = false),
                borderRadius: BorderRadius.circular(9),
                splashColor: _kPrimaryBlue.withOpacity(0.06),
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 3,
                        height: widget.isActive ? 20 : 0,
                        decoration: BoxDecoration(
                          color: _kPrimaryBlue,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      SizedBox(width: widget.isActive ? 9 : 12),
                      AnimatedSlide(
                        duration: const Duration(milliseconds: 150),
                        offset: _hovered ? const Offset(0.08, 0) : Offset.zero,
                        child: Icon(
                          widget.icon,
                          size: widget.isPrimary ? 19 : 18,
                          color: widget.isActive
                              ? _kPrimaryBlue
                              : highlighted
                              ? _kTextDark
                              : _kTextMuted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.isActive ? _kPrimaryBlue : _kTextDark,
                            fontSize: widget.isPrimary ? 14.4 : 14.0,
                            fontWeight: widget.isPrimary
                                ? FontWeight.w600
                                : widget.isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                            height: 1.28,
                            letterSpacing: 0.01,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      if (widget.trailing != null) widget.trailing!,
                    ],
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

// ─────────────────────────────────────────────────────────────
// Submenu
// ─────────────────────────────────────────────────────────────
class _DrawerSubmenu extends StatelessWidget {
  const _DrawerSubmenu({required this.visible, required this.children});

  final bool visible;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 170),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return SizeTransition(
          sizeFactor: animation,
          axisAlignment: -1,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: visible
          ? Padding(
              key: const ValueKey('submenu-visible'),
              padding: const EdgeInsets.only(left: 26, right: 8, bottom: 4),
              child: Column(children: children),
            )
          : const SizedBox(key: ValueKey('submenu-hidden')),
    );
  }
}

class _DrawerSubItem extends StatefulWidget {
  const _DrawerSubItem({
    required this.icon,
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_DrawerSubItem> createState() => _DrawerSubItemState();
}

class _DrawerSubItemState extends State<_DrawerSubItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isActive
        ? _kActiveBg
        : _hovered
        ? _kHoverBg
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 34,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              splashColor: _kPrimaryBlue.withOpacity(0.05),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: widget.isActive
                            ? _kPrimaryBlue
                            : _kTextMuted.withOpacity(0.48),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(
                      widget.icon,
                      size: 15,
                      color: widget.isActive
                          ? _kPrimaryBlue
                          : _kTextMuted.withOpacity(0.86),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.isActive
                              ? _kPrimaryBlue
                              : _kTextDark.withOpacity(0.82),
                          fontSize: 13.25,
                          fontWeight: widget.isActive
                              ? FontWeight.w600
                              : FontWeight.w500,
                          height: 1.22,
                          letterSpacing: 0.01,
                          decoration: TextDecoration.none,
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
  }
}

// ─────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────
class _DrawerFooter extends StatefulWidget {
  const _DrawerFooter();

  @override
  State<_DrawerFooter> createState() => _DrawerFooterState();
}

class _DrawerFooterState extends State<_DrawerFooter> {
  bool _syncHover = false;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final formattedTime =
        '${now.day.toString().padLeft(2, '0')}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
      decoration: const BoxDecoration(
        color: _kFooterBg,
        border: Border(top: BorderSide(color: _kBorderColor, width: 1)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _kActiveBg,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFBFD1F7)),
            ),
            child: const Icon(
              Icons.cloud_done_rounded,
              size: 18,
              color: _kPrimaryBlue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Última sincronización',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _kTextDark,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  formattedTime,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _kTextMuted.withOpacity(0.86),
                    fontSize: 11.2,
                    fontWeight: FontWeight.w500,
                    height: 1.12,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'FullPOS Cloud',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _kPrimaryBlue.withOpacity(0.78),
                    fontSize: 11.0,
                    fontWeight: FontWeight.w600,
                    height: 1.12,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _syncHover = true),
            onExit: (_) => setState(() => _syncHover = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _syncHover ? _kPrimaryBlue : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _syncHover ? _kPrimaryBlue : _kBorderColor,
                ),
                boxShadow: [
                  if (_syncHover)
                    BoxShadow(
                      color: _kPrimaryBlue.withOpacity(0.18),
                      blurRadius: 16,
                      spreadRadius: -8,
                      offset: const Offset(0, 8),
                    ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(
                        content: Text('Sincronizando...'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 22,
                    color: _syncHover ? Colors.white : _kPrimaryBlue,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
