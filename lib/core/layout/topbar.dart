import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cash/data/operation_flow_service.dart';
import '../../features/cash/ui/cash_close_dialog.dart';
import '../../features/cash/ui/cash_panel_sheet.dart';
import '../../features/auth/services/logout_flow_service.dart';
import '../../features/settings/providers/business_settings_provider.dart';
import '../constants/app_sizes.dart';
import '../session/session_manager.dart';
import '../theme/app_tokens.dart';
import '../theme/color_utils.dart';
import 'topbar_utility_panels.dart';

/// Topbar principal de FullPOS.
/// Orden: Menú | Vender                                      Apps | Turno | Usuario | Mi negocio
///
/// Nota importante:
/// El OverflowBox fuerza el ancho visual al ancho completo de la ventana.
/// Esto corrige el caso donde el Topbar está montado dentro de la columna izquierda.
class Topbar extends ConsumerStatefulWidget {
  const Topbar({
    super.key,
    this.showMenuButton = false,
    this.onMenuPressed,
    this.isMenuOpen = false,
    this.scale = 1.0,
    this.showBottomBorder = true,
    this.topPadding = 0.0,
  });

  final bool showMenuButton;
  final VoidCallback? onMenuPressed;
  final bool isMenuOpen;
  final double scale;
  final bool showBottomBorder;
  final double topPadding;

  @override
  ConsumerState<Topbar> createState() => _TopbarState();
}

enum _TopbarMenuAction {
  profile,
  support,
  license,
  cloud,
  settings,
  logout,
  makeShiftCut,
  currentShift,
  shiftHistory,
}

class _TopbarState extends ConsumerState<Topbar> {
  static const Color _softTextColor = Color(0xFF64748B);
  static const Color _strongTextColor = Color(0xFF0F172A);

  Timer? _cashTimer;
  StreamSubscription<void>? _sessionSub;

  String? _username;
  String? _displayName;

  bool _loadingOpenCashSessionId = false;
  int? _openCashSessionId;

  @override
  void initState() {
    super.initState();

    _refreshTopbarData();

    _sessionSub = SessionManager.changes.listen((_) {
      if (!mounted) return;
      _refreshTopbarData();
    });

    _cashTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_loadOpenCashSessionId());
    });
  }

  @override
  void dispose() {
    _cashTimer?.cancel();
    _sessionSub?.cancel();
    super.dispose();
  }

  void _refreshTopbarData() {
    unawaited(_loadUserSummary());
    unawaited(_loadOpenCashSessionId());
  }

  Future<void> _loadUserSummary() async {
    final username = await SessionManager.username();
    final displayName = await SessionManager.displayName();

    if (!mounted) return;
    setState(() {
      _username = _cleanText(username) ?? 'Usuario';
      _displayName = _cleanText(displayName);
    });
  }

  Future<void> _loadOpenCashSessionId() async {
    if (_loadingOpenCashSessionId) return;
    _loadingOpenCashSessionId = true;

    try {
      final sessionId =
          (await OperationFlowService.loadActiveSession())?.shiftId;

      if (!mounted) return;

      if (sessionId != _openCashSessionId) {
        setState(() => _openCashSessionId = sessionId);
      }
    } catch (_) {
      // No bloquear la UI si falla la consulta del estado de caja.
    } finally {
      _loadingOpenCashSessionId = false;
    }
  }

  static String? _cleanText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String _activeUserName() {
    final name = (_displayName ?? _username ?? '').trim();
    return name.isEmpty ? 'Usuario' : name;
  }

  Future<void> _showCompanyProductsDialog() async {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ?? AppTokens.defaultTokens;

    final accent = ColorUtils.ensureReadableColor(
      tokens.buttonPrimary,
      Colors.white,
      minRatio: 3.0,
    );

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _CompanyProductsDialog(
          accentColor: accent,
          onClose: () => Navigator.of(dialogContext).pop(),
        );
      },
    );
  }

  Future<void> _handleMenuAction(_TopbarMenuAction action) async {
    switch (action) {
      case _TopbarMenuAction.profile:
        await TopbarUtilityPanels.showProfile(context);
        return;
      case _TopbarMenuAction.support:
        await TopbarUtilityPanels.showSupport(context);
        return;
      case _TopbarMenuAction.license:
        await TopbarUtilityPanels.showLicense(context);
        return;
      case _TopbarMenuAction.cloud:
        await TopbarUtilityPanels.showCloud(context);
        return;
      case _TopbarMenuAction.settings:
        context.go('/settings');
        return;
      case _TopbarMenuAction.logout:
        await LogoutFlowService.requestLogout(
          context,
          performLogout: () => LogoutFlowService.defaultPerformLogout(context),
        );
        return;
      case _TopbarMenuAction.makeShiftCut:
        final sessionId = _openCashSessionId;
        if (sessionId == null) {
          context.go('/cash');
          return;
        }

        await CashCloseDialog.show(
          context,
          sessionId: sessionId,
          logoutAfterClose: false,
        );

        if (!mounted) return;
        unawaited(_loadOpenCashSessionId());
        return;
      case _TopbarMenuAction.currentShift:
        final sessionId = _openCashSessionId;

        if (sessionId == null) {
          context.go('/cash');
          return;
        }

        await CashPanelSheet.show(context, sessionId: sessionId);

        if (!mounted) return;
        unawaited(_loadOpenCashSessionId());
        return;
      case _TopbarMenuAction.shiftHistory:
        context.go('/cash/history');
        return;
    }
  }

  PopupMenuItem<_TopbarMenuAction> _buildMenuItem(
    BuildContext context, {
    required _TopbarMenuAction value,
    required IconData icon,
    required String label,
    required double width,
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final itemColor = color ?? const Color(0xFF334155);

    return PopupMenuItem<_TopbarMenuAction>(
      value: value,
      height: 44,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        itemColor.withOpacity(0.08),
                        Colors.white,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: itemColor.withOpacity(0.10)),
                    ),
                    child: Icon(icon, size: 16, color: itemColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ColorUtils.ensureReadableColor(
                          itemColor,
                          scheme.surface,
                          minRatio: 4.0,
                        ),
                        fontSize: 13,
                        fontWeight: fontWeight,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: itemColor.withOpacity(0.42),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<_TopbarMenuAction>> _businessMenuItems(
    BuildContext context,
    double menuWidth,
  ) {
    return [
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.profile,
        icon: Icons.person_outline_rounded,
        label: 'Mi perfil',
        width: menuWidth,
      ),
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.support,
        icon: Icons.support_agent_rounded,
        label: 'Soporte',
        width: menuWidth,
      ),
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.license,
        icon: Icons.workspace_premium_outlined,
        label: 'Licencias',
        width: menuWidth,
      ),
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.cloud,
        icon: Icons.cloud_outlined,
        label: 'Nube',
        width: menuWidth,
      ),
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.settings,
        icon: Icons.settings_outlined,
        label: 'Configuración',
        width: menuWidth,
      ),
      const PopupMenuDivider(height: 8),
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.logout,
        icon: Icons.logout_rounded,
        label: 'Cerrar sesión',
        width: menuWidth,
        color: const Color(0xFFDC2626),
        fontWeight: FontWeight.w800,
      ),
    ];
  }

  List<PopupMenuEntry<_TopbarMenuAction>> _turnMenuItems(
    BuildContext context,
    double menuWidth,
  ) {
    return [
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.makeShiftCut,
        icon: Icons.point_of_sale_rounded,
        label: 'Hacer corte de turno',
        width: menuWidth,
      ),
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.currentShift,
        icon: Icons.receipt_long_rounded,
        label: 'Turno actual',
        width: menuWidth,
      ),
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.shiftHistory,
        icon: Icons.history_rounded,
        label: 'Historial de turnos',
        width: menuWidth,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ?? AppTokens.defaultTokens;
    final businessSettings = ref.watch(businessSettingsProvider);
    final businessName =
        _cleanText(businessSettings.businessName) ?? 'Mi negocio';
    final businessLogoPath = _cleanText(businessSettings.logoPath);

    const topbarBg = Colors.white;

    final appBarFg = ColorUtils.ensureReadableColor(
      tokens.topbarText,
      topbarBg,
      minRatio: 4.5,
    );

    final chromeBorderColor = Color.alphaBlend(
      tokens.outline.withOpacity(
        theme.brightness == Brightness.dark ? 0.34 : 0.52,
      ),
      topbarBg,
    );

    final screenWidth = MediaQuery.sizeOf(context).width;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = screenWidth < 900;
        final s = widget.scale.clamp(0.85, 1.12);

        final topbarHeight = (AppSizes.topbarHeight * s).clamp(48.0, 56.0);
        final topInset = (widget.topPadding * s).clamp(0.0, 12.0);

        final padM = AppSizes.paddingM * s;
        final padL = AppSizes.paddingL * s;
        final spaceS = AppSizes.spaceS * s;

        final horizontalPad = ((isCompact ? padM : padL) * 0.55).clamp(
          8.0,
          14.0,
        );

        final brandAccent = ColorUtils.ensureReadableColor(
          tokens.buttonPrimary,
          topbarBg,
          minRatio: 3.0,
        );

        final activeUser = _activeUserName();

        final businessMenuWidth = screenWidth < 430 ? 238.0 : 270.0;
        final turnMenuWidth = screenWidth < 430 ? 230.0 : 258.0;

        final showBusinessText = screenWidth >= 520;
        final showProductsButton = screenWidth >= 500;
        final showTurnLabel = screenWidth >= 690;

        final topbarContent = Container(
          width: screenWidth,
          height: topbarHeight + topInset,
          padding: EdgeInsets.fromLTRB(
            horizontalPad,
            topInset,
            horizontalPad,
            0,
          ),
          decoration: BoxDecoration(
            color: topbarBg,
            border: widget.showBottomBorder
                ? Border(
                    left: BorderSide(color: chromeBorderColor, width: 1),
                    right: BorderSide(color: chromeBorderColor, width: 1),
                    bottom: BorderSide(color: chromeBorderColor, width: 1),
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.035),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.showMenuButton) ...[
                IconButton(
                  onPressed: widget.onMenuPressed,
                  tooltip: 'Menú',
                  splashRadius: 20,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: Icon(
                      widget.isMenuOpen ? Icons.close_rounded : Icons.menu,
                      key: ValueKey<bool>(widget.isMenuOpen),
                      size: 22,
                      color: appBarFg,
                    ),
                  ),
                ),
                SizedBox(width: spaceS * 0.3),
              ],
              Text(
                'Vender',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: appBarFg,
                  fontSize: ((isCompact ? 16 : 18) * s).clamp(15.5, 20.0),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.05,
                  height: 1.25,
                  fontFamilyFallback: const [
                    'Poppins',
                    'Segoe UI',
                    'Roboto',
                    'Arial',
                  ],
                ),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showProductsButton) ...[
                    _TopbarIconAction(
                      scale: s,
                      icon: Icons.apps_rounded,
                      tooltip: 'Productos de la empresa',
                      color: _softTextColor,
                      borderColor: chromeBorderColor,
                      onTap: () => unawaited(_showCompanyProductsDialog()),
                    ),
                    SizedBox(width: (7 * s).clamp(5.0, 8.0)),
                  ],
                  PopupMenuButton<_TopbarMenuAction>(
                    tooltip: 'Turnos',
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 8),
                    constraints: BoxConstraints(
                      minWidth: turnMenuWidth,
                      maxWidth: turnMenuWidth,
                    ),
                    elevation: 10,
                    color: topbarBg,
                    surfaceTintColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: brandAccent.withOpacity(0.12)),
                    ),
                    onSelected: _handleMenuAction,
                    itemBuilder: (_) => _turnMenuItems(context, turnMenuWidth),
                    child: _TurnMenuButton(
                      scale: s,
                      visibleLabel: showTurnLabel,
                      accentColor: brandAccent,
                      borderColor: chromeBorderColor,
                      isOpen: _openCashSessionId != null,
                    ),
                  ),
                  SizedBox(width: (7 * s).clamp(5.0, 8.0)),
                  _ActiveCashierChip(
                    scale: s,
                    name: activeUser,
                    borderColor: chromeBorderColor,
                  ),
                  SizedBox(width: (7 * s).clamp(5.0, 8.0)),
                  PopupMenuButton<_TopbarMenuAction>(
                    tooltip: 'Negocio y cuenta',
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 8),
                    constraints: BoxConstraints(
                      minWidth: businessMenuWidth,
                      maxWidth: businessMenuWidth,
                    ),
                    elevation: 10,
                    color: topbarBg,
                    surfaceTintColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: brandAccent.withOpacity(0.12)),
                    ),
                    onSelected: _handleMenuAction,
                    itemBuilder: (_) =>
                        _businessMenuItems(context, businessMenuWidth),
                    child: Tooltip(
                      message: businessName,
                      waitDuration: const Duration(milliseconds: 350),
                      child: _BusinessMenuButton(
                        scale: s,
                        businessName: businessName,
                        logoPath: businessLogoPath,
                        showText: showBusinessText,
                        accentColor: brandAccent,
                        borderColor: chromeBorderColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );

        return SizedBox(
          width: constraints.maxWidth,
          height: topbarHeight + topInset,
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: screenWidth,
            maxWidth: screenWidth,
            minHeight: topbarHeight + topInset,
            maxHeight: topbarHeight + topInset,
            child: topbarContent,
          ),
        );
      },
    );
  }
}

class _BusinessMenuButton extends StatelessWidget {
  const _BusinessMenuButton({
    required this.scale,
    required this.businessName,
    required this.logoPath,
    required this.showText,
    required this.accentColor,
    required this.borderColor,
  });

  final double scale;
  final String businessName;
  final String? logoPath;
  final bool showText;
  final Color accentColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final height = (36 * scale).clamp(34.0, 40.0);
    final cleanName = businessName.trim().isEmpty
        ? 'Mi negocio'
        : businessName.trim();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: height,
      padding: EdgeInsets.only(
        left: (6 * scale).clamp(5.0, 7.0),
        right: showText ? (12 * scale).clamp(10.0, 14.0) : 6,
      ),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accentColor.withOpacity(0.035), Colors.white),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: borderColor.withOpacity(0.85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BusinessLogoMark(
            size: (26 * scale).clamp(24.0, 29.0),
            accentColor: accentColor,
            name: cleanName,
            logoPath: logoPath,
          ),
          if (showText) ...[
            SizedBox(width: (8 * scale).clamp(6.0, 9.0)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                cleanName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _TopbarState._strongTextColor,
                  fontSize: (13.2 * scale).clamp(12.4, 14.2),
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: 0.05,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BusinessLogoMark extends StatelessWidget {
  const _BusinessLogoMark({
    required this.size,
    required this.accentColor,
    required this.name,
    required this.logoPath,
  });

  final double size;
  final Color accentColor;
  final String name;
  final String? logoPath;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final normalizedPath = (logoPath ?? '').trim();
    final hasLogo =
        normalizedPath.isNotEmpty && File(normalizedPath).existsSync();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor,
            Color.alphaBlend(Colors.black.withOpacity(0.16), accentColor),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.18),
            blurRadius: 10,
            spreadRadius: -7,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? Image.file(File(normalizedPath), fit: BoxFit.cover)
          : Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: (10.8 * (size / 26)).clamp(9.5, 12.0),
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
    );
  }

  static String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'N';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }

    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

class _TurnMenuButton extends StatelessWidget {
  const _TurnMenuButton({
    required this.scale,
    required this.visibleLabel,
    required this.accentColor,
    required this.borderColor,
    required this.isOpen,
  });

  final double scale;
  final bool visibleLabel;
  final Color accentColor;
  final Color borderColor;
  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final height = (34 * scale).clamp(32.0, 38.0);

    final bg = Color.alphaBlend(accentColor.withOpacity(0.08), Colors.white);

    return Tooltip(
      message: isOpen ? 'Turno abierto' : 'Gestionar turno',
      waitDuration: const Duration(milliseconds: 350),
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: visibleLabel ? (10 * scale).clamp(9.0, 12.0) : 7,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: accentColor.withOpacity(0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: (22 * scale).clamp(20.0, 24.0),
              height: (22 * scale).clamp(20.0, 24.0),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.13),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                Icons.point_of_sale_rounded,
                size: (14.5 * scale).clamp(13.0, 16.0),
                color: accentColor,
              ),
            ),
            if (visibleLabel) ...[
              SizedBox(width: (7 * scale).clamp(5.0, 8.0)),
              Text(
                'Turno',
                style: TextStyle(
                  color: accentColor,
                  fontSize: (12 * scale).clamp(11.2, 12.8),
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              SizedBox(width: (3 * scale).clamp(2.0, 4.0)),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: (17 * scale).clamp(15.0, 18.0),
                color: accentColor.withOpacity(0.72),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActiveCashierChip extends StatelessWidget {
  const _ActiveCashierChip({
    required this.scale,
    required this.name,
    required this.borderColor,
  });

  final double scale;
  final String name;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final cleanName = name.trim().isEmpty ? 'Usuario' : name.trim();
    final height = (34 * scale).clamp(32.0, 38.0);

    return Tooltip(
      message: cleanName,
      waitDuration: const Duration(milliseconds: 350),
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: (10 * scale).clamp(8.0, 12.0),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: borderColor.withOpacity(0.75)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: (17 * scale).clamp(15.0, 18.0),
              color: _TopbarState._softTextColor,
            ),
            SizedBox(width: (6 * scale).clamp(5.0, 7.0)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 136),
              child: Text(
                cleanName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _TopbarState._strongTextColor,
                  fontSize: (12.5 * scale).clamp(11.6, 13.2),
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopbarIconAction extends StatelessWidget {
  const _TopbarIconAction({
    required this.scale,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.borderColor,
    required this.onTap,
  });

  final double scale;
  final IconData icon;
  final String tooltip;
  final Color color;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = (34 * scale).clamp(32.0, 38.0);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Ink(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: borderColor.withOpacity(0.70)),
            ),
            child: Icon(
              icon,
              size: (18 * scale).clamp(16.0, 19.0),
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyProductsDialog extends StatelessWidget {
  const _CompanyProductsDialog({
    required this.accentColor,
    required this.onClose,
  });

  final Color accentColor;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accentColor.withOpacity(0.13)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 34,
                spreadRadius: -14,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accentColor.withOpacity(0.14),
                        ),
                      ),
                      child: Icon(
                        Icons.apps_rounded,
                        color: accentColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Productos de la empresa',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _TopbarState._strongTextColor,
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Soluciones disponibles para tu negocio',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _TopbarState._softTextColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                      color: _TopbarState._softTextColor,
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                child: Column(
                  children: [
                    _CompanyProductCard(
                      accentColor: accentColor,
                      icon: Icons.point_of_sale_rounded,
                      title: 'FullPOS',
                      subtitle: 'Facturación, ventas, caja e inventario.',
                    ),
                    const SizedBox(height: 10),
                    _CompanyProductCard(
                      accentColor: accentColor,
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'FullCredit',
                      subtitle: 'Gestión de créditos, clientes y pagos.',
                    ),
                    const SizedBox(height: 10),
                    _CompanyProductCard(
                      accentColor: accentColor,
                      icon: Icons.payments_outlined,
                      title: 'FullPréstamos',
                      subtitle: 'Control profesional de préstamos y cobros.',
                    ),
                    const SizedBox(height: 10),
                    _CompanyProductCard(
                      accentColor: accentColor,
                      icon: Icons.smart_toy_outlined,
                      title: 'Bots / Automatizaciones',
                      subtitle: 'Automatización de ventas y seguimiento.',
                    ),
                    const SizedBox(height: 10),
                    _CompanyProductCard(
                      accentColor: accentColor,
                      icon: Icons.cloud_outlined,
                      title: 'Nube',
                      subtitle: 'Sincronización, respaldo y acceso remoto.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyProductCard extends StatelessWidget {
  const _CompanyProductCard({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accentColor.withOpacity(0.035), Colors.white),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accentColor.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _TopbarState._strongTextColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _TopbarState._softTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.chevron_right_rounded,
            color: accentColor.withOpacity(0.45),
            size: 20,
          ),
        ],
      ),
    );
  }
}
