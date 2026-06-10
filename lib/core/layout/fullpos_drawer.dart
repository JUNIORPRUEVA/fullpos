import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'topbar_action_bus.dart';

// ─────────────────────────────────────────────────────────────
// Constantes de diseño FullPOS
// ─────────────────────────────────────────────────────────────
const Color _kPrimaryBlue = Color(0xFF1A56DB);
const Color _kBorderColor = Color(0xFFE2E8F0);
const Color _kTextDark = Color(0xFF0F172A);
const Color _kTextMuted = Color(0xFF64748B);
const Color _kActiveBg = Color(0xFFEAF2FF);
const Color _kHoverBg = Color(0xFFF1F5F9);
const Color _kWhite = Colors.white;
const double _kDrawerWidth = 320.0;
const Duration _kAnimationDuration = Duration(milliseconds: 260);

/// Drawer lateral premium tipo SaaS/POS para FullPOS.
/// Diseño moderno, elegante y profesional con animación slide + fade.
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

  // Submenús expandidos
  bool _inventoryExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _kAnimationDuration,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(-1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
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
    final current = _currentPath();
    return current == route || current.startsWith('$route/');
  }

  void _navigate(String route) {
    try {
      context.go(route);
    } catch (_) {}
    _closeDrawer();
  }

  void _closeDrawer() {
    _controller.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _handleMovementToggle() {
    TopbarActionBus.toggleSalesMovementPanel();
    _closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _closeDrawer,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          color: Colors.black.withOpacity(0.35),
          child: GestureDetector(
            onTap: () {}, // Evita que el tap cierre al tocar el drawer
            child: SlideTransition(
              position: _slideAnimation,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: _kDrawerWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: _kWhite,
                    border: Border(
                      right: BorderSide(color: _kBorderColor, width: 1),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 30,
                        spreadRadius: -8,
                        offset: const Offset(8, 0),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        const _DrawerHeader(),
                        _DrawerCurrentShift(
                          onTap: () => _navigate('/cash'),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListView(
                            padding: EdgeInsets.zero,
                            physics: const ClampingScrollPhysics(),
                            children: [
                              const _DrawerSectionTitle(title: 'PRINCIPAL'),
                              _DrawerNavItem(
                                icon: PhosphorIcons.receipt(
                                  PhosphorIconsStyle.regular,
                                ),
                                activeIcon: PhosphorIcons.receipt(
                                  PhosphorIconsStyle.fill,
                                ),
                                title: 'Ventas',
                                isActive: _isActive('/sales'),
                                onTap: () => _navigate('/sales'),
                              ),
                              _DrawerNavItem(
                                icon: PhosphorIcons.package(
                                  PhosphorIconsStyle.regular,
                                ),
                                activeIcon: PhosphorIcons.package(
                                  PhosphorIconsStyle.fill,
                                ),
                                title: 'Inventario',
                                isActive: _isActive('/products'),
                                hasSubmenu: true,
                                isExpanded: _inventoryExpanded,
                                onTap: () {
                                  setState(() {
                                    _inventoryExpanded = !_inventoryExpanded;
                                  });
                                },
                              ),
                              if (_inventoryExpanded) ...[
                                _DrawerSubItem(
                                  title: 'Productos',
                                  isActive: _isActive('/products'),
                                  onTap: () => _navigate('/products'),
                                ),
                                _DrawerSubItem(
                                  title: 'Historial de stock',
                                  isActive: _isActive('/products/history'),
                                  onTap: () => _navigate('/products/history'),
                                ),
                              ],
                              _DrawerNavItem(
                                icon: PhosphorIcons.wallet(
                                  PhosphorIconsStyle.regular,
                                ),
                                activeIcon: PhosphorIcons.wallet(
                                  PhosphorIconsStyle.fill,
                                ),
                                title: 'Movimiento efectivo',
                                isActive: false,
                                onTap: _handleMovementToggle,
                              ),
                              _DrawerNavItem(
                                icon: PhosphorIcons.chartBar(
                                  PhosphorIconsStyle.regular,
                                ),
                                activeIcon: PhosphorIcons.chartBar(
                                  PhosphorIconsStyle.fill,
                                ),
                                title: 'Reportes',
                                isActive:
                                    _isActive('/reports') ||
                                    _isActive('/factura'),
                                onTap: () => _navigate('/reports'),
                              ),
                              const SizedBox(height: 8),
                              const _DrawerSectionTitle(title: 'GESTIÓN'),
                              _DrawerNavItem(
                                icon: PhosphorIcons.clockCounterClockwise(
                                  PhosphorIconsStyle.regular,
                                ),
                                activeIcon: PhosphorIcons.clockCounterClockwise(
                                  PhosphorIconsStyle.fill,
                                ),
                                title: 'Historial de ventas',
                                isActive: _isActive('/factura'),
                                onTap: () => _navigate('/factura'),
                              ),
                              _DrawerNavItem(
                                icon: PhosphorIcons.shoppingBag(
                                  PhosphorIconsStyle.regular,
                                ),
                                activeIcon: PhosphorIcons.shoppingBag(
                                  PhosphorIconsStyle.fill,
                                ),
                                title: 'Compras',
                                isActive: _isActive('/purchases'),
                                onTap: () => _navigate('/purchases'),
                              ),
                              _DrawerNavItem(
                                icon: PhosphorIcons.usersThree(
                                  PhosphorIconsStyle.regular,
                                ),
                                activeIcon: PhosphorIcons.usersThree(
                                  PhosphorIconsStyle.fill,
                                ),
                                title: 'Clientes / Contactos',
                                isActive: _isActive('/clients'),
                                onTap: () => _navigate('/clients'),
                              ),
                              const SizedBox(height: 8),
                              const _DrawerSectionTitle(title: 'SISTEMA'),
                              _DrawerNavItem(
                                icon: PhosphorIcons.gear(
                                  PhosphorIconsStyle.regular,
                                ),
                                activeIcon: PhosphorIcons.gear(
                                  PhosphorIconsStyle.fill,
                                ),
                                title: 'Configuración',
                                isActive: _isActive('/settings'),
                                onTap: () => _navigate('/settings'),
                              ),
                              const SizedBox(height: 16),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header del drawer
// ─────────────────────────────────────────────────────────────
class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Logo / Icono
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1A56DB),
                  Color(0xFF1E40AF),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1A56DB).withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.receipt_long_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Título y subtítulo
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FullPOS',
                  style: TextStyle(
                    color: _kTextDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sistema de facturación',
                  style: TextStyle(
                    color: _kTextMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          // Botón cerrar
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              onPressed: () {
                // Buscar el estado del drawer padre para cerrar
                final state = context.findAncestorStateOfType<_FullPosDrawerState>();
                state?._closeDrawer();
              },
              padding: EdgeInsets.zero,
              iconSize: 20,
              icon: Icon(
                Icons.close_rounded,
                color: _kTextMuted,
              ),
              style: IconButton.styleFrom(
                backgroundColor: _kHoverBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Fila de turno actual
// ─────────────────────────────────────────────────────────────
class _DrawerCurrentShift extends StatelessWidget {
  final VoidCallback onTap;

  const _DrawerCurrentShift({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: _kHoverBg,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _kBorderColor.withOpacity(0.6),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.point_of_sale_rounded,
                  size: 20,
                  color: _kPrimaryBlue,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Turno actual',
                    style: TextStyle(
                      color: _kTextDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: _kTextMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Título de sección
// ─────────────────────────────────────────────────────────────
class _DrawerSectionTitle extends StatelessWidget {
  final String title;

  const _DrawerSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          color: _kTextMuted.withOpacity(0.8),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Ítem de navegación principal
// ─────────────────────────────────────────────────────────────
class _DrawerNavItem extends StatefulWidget {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  final bool isActive;
  final VoidCallback onTap;
  final bool hasSubmenu;
  final bool isExpanded;

  const _DrawerNavItem({
    required this.icon,
    required this.activeIcon,
    required this.title,
    required this.isActive,
    required this.onTap,
    this.hasSubmenu = false,
    this.isExpanded = false,
  });

  @override
  State<_DrawerNavItem> createState() => _DrawerNavItemState();
}

class _DrawerNavItemState extends State<_DrawerNavItem> {
  bool _isHover = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 1.5),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHover = true),
        onExit: (_) => setState(() => _isHover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 44,
          decoration: BoxDecoration(
            color: widget.isActive
                ? _kActiveBg
                : _isHover
                    ? _kHoverBg
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(10),
              splashColor: _kPrimaryBlue.withOpacity(0.06),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    // Barra activa izquierda
                    if (widget.isActive)
                      Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _kPrimaryBlue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    else
                      const SizedBox(width: 3),
                    const SizedBox(width: 8),
                    // Icono
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      transform: _isHover
                          ? (Matrix4.identity()..translate(2.0, 0.0))
                          : Matrix4.identity(),
                      child: Icon(
                        widget.isActive ? widget.activeIcon : widget.icon,
                        size: 20,
                        color: widget.isActive
                            ? _kPrimaryBlue
                            : _kTextDark.withOpacity(0.75),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Título
                    Expanded(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          color: widget.isActive
                              ? _kPrimaryBlue
                              : _kTextDark,
                          fontSize: 13.5,
                          fontWeight:
                              widget.isActive
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    // Chevron para submenú
                    if (widget.hasSubmenu)
                      AnimatedRotation(
                        turns: widget.isExpanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: _kTextMuted,
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
// Ítem de submenú
// ─────────────────────────────────────────────────────────────
class _DrawerSubItem extends StatefulWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _DrawerSubItem({
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_DrawerSubItem> createState() => _DrawerSubItemState();
}

class _DrawerSubItemState extends State<_DrawerSubItem> {
  bool _isHover = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52, right: 16, top: 1, bottom: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHover = true),
        onExit: (_) => setState(() => _isHover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: 36,
          decoration: BoxDecoration(
            color: widget.isActive
                ? _kActiveBg
                : _isHover
                    ? _kHoverBg
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              splashColor: _kPrimaryBlue.withOpacity(0.06),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: widget.isActive
                            ? _kPrimaryBlue
                            : _kTextMuted.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.isActive
                            ? _kPrimaryBlue
                            : _kTextDark.withOpacity(0.8),
                        fontSize: 13,
                        fontWeight:
                            widget.isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
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
// Footer del drawer
// ─────────────────────────────────────────────────────────────
class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter();

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
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: _kBorderColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.sync_rounded,
                size: 14,
                color: _kTextMuted.withOpacity(0.7),
              ),
              const SizedBox(width: 6),
              Text(
                'Última sincronización',
                style: TextStyle(
                  color: _kTextMuted.withOpacity(0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 28,
                height: 28,
                child: IconButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sincronizando...'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  icon: Icon(
                    Icons.refresh_rounded,
                    color: _kPrimaryBlue,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: _kPrimaryBlue.withOpacity(0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const SizedBox(width: 20),
              Text(
                formattedTime,
                style: TextStyle(
                  color: _kTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const Spacer(),
              Text(
                'FullPOS Cloud',
                style: TextStyle(
                  color: _kPrimaryBlue.withOpacity(0.7),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
