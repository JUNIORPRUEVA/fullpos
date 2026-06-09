import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/services/logout_flow_service.dart';
import '../../features/cash/data/operation_flow_service.dart';
import '../../features/cash/ui/cash_close_dialog.dart';
import '../../features/cash/ui/cash_panel_sheet.dart';
import '../../features/license/data/license_models.dart';
import '../../features/license/services/license_storage.dart';
import '../../features/settings/providers/business_settings_provider.dart';
import '../constants/app_sizes.dart';
import '../session/session_manager.dart';
import '../session/ui_preferences.dart';
import '../theme/app_status_theme.dart';
import '../theme/app_tokens.dart';
import '../theme/color_utils.dart';

/// Topbar principal de FullPOS.
///
/// Muestra el título de la pantalla, el estado de caja y un menú de usuario/
/// empresa limpio con accesos a perfil, licencia, seguridad, configuración,
/// cortes, soporte y cierre de sesión.
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

enum _UserMenuAction {
  profile,
  license,
  security,
  settings,
  finishShift,
  viewCurrentCut,
  cutHistory,
  support,
  logout,
}

class _TopbarState extends ConsumerState<Topbar>
    with SingleTickerProviderStateMixin {
  static const Color _topbarBackground = Colors.white;
  static const Color _softTextColor = Color(0xFF64748B);
  static const Color _strongTextColor = Color(0xFF0F172A);

  late final AnimationController _cashPulseController;
  Timer? _cashTimer;
  StreamSubscription<void>? _sessionSub;
  StreamSubscription<void>? _uiPrefsSub;

  final LicenseStorage _licenseStorage = LicenseStorage();

  String? _username;
  String? _displayName;
  String? _role;
  String? _terminalId;
  String? _profileImagePath;
  LicenseInfo? _licenseInfo;

  bool _canAccessCash = false;
  bool _canViewCashHistory = false;
  bool _canCloseShift = false;
  bool _canOpenCashbox = false;
  bool _loadingOpenCashSessionId = false;
  int? _openCashSessionId;

  @override
  void initState() {
    super.initState();

    _cashPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _refreshTopbarData();

    _sessionSub = SessionManager.changes.listen((_) {
      if (!mounted) return;
      _refreshTopbarData();
    });

    _uiPrefsSub = UiPreferences.changes.listen((_) {
      if (!mounted) return;
      unawaited(_loadProfileImage());
    });

    _cashTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_loadOpenCashSessionId());
    });
  }

  @override
  void dispose() {
    _cashTimer?.cancel();
    _sessionSub?.cancel();
    _uiPrefsSub?.cancel();
    _cashPulseController.dispose();
    super.dispose();
  }

  void _refreshTopbarData() {
    unawaited(_loadUserSummary());
    unawaited(_loadProfileImage());
    unawaited(_loadCashAccess());
    unawaited(_loadOpenCashSessionId());
    unawaited(_loadLicenseInfo());
  }

  Future<void> _loadUserSummary() async {
    final username = await SessionManager.username();
    final displayName = await SessionManager.displayName();
    final role = await SessionManager.role();
    final terminalId = await SessionManager.terminalId();

    if (!mounted) return;
    setState(() {
      _username = _cleanText(username) ?? 'Usuario';
      _displayName = _cleanText(displayName);
      _role = _cleanText(role);
      _terminalId = _cleanText(terminalId);
    });
  }

  Future<void> _loadProfileImage() async {
    final userId = await SessionManager.userId();
    final username = await SessionManager.username();
    final userKey = _buildUserKey(userId: userId, username: username);

    if (userKey == null) {
      if (!mounted) return;
      setState(() => _profileImagePath = null);
      return;
    }

    String? path = await UiPreferences.getProfileImagePath(userKey);
    if (path != null && !await File(path).exists()) {
      await UiPreferences.setProfileImagePath(userKey, null);
      path = null;
    }

    if (!mounted) return;
    setState(() => _profileImagePath = path);
  }

  Future<void> _loadCashAccess() async {
    try {
      final permissions = await AuthRepository.getCurrentPermissions();
      final isAdmin = await AuthRepository.isAdmin();

      if (!mounted) return;
      setState(() {
        _canAccessCash =
            isAdmin || permissions.canOpenCash || permissions.canCloseCash;
        _canViewCashHistory = isAdmin || permissions.canViewCashHistory;
        _canCloseShift =
            isAdmin || permissions.canCloseShift || permissions.canCloseCash;
        _canOpenCashbox =
            isAdmin || permissions.canOpenCashbox || permissions.canOpenCash;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canAccessCash = false;
        _canViewCashHistory = false;
        _canCloseShift = false;
        _canOpenCashbox = false;
      });
    }
  }

  Future<void> _loadLicenseInfo() async {
    try {
      final info = await _licenseStorage.getLastInfo();
      if (!mounted) return;
      setState(() => _licenseInfo = info);
    } catch (_) {
      if (!mounted) return;
      setState(() => _licenseInfo = null);
    }
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

  String? _buildUserKey({required int? userId, required String? username}) {
    if (userId != null) return 'id:$userId';
    final trimmedUsername = _cleanText(username);
    if (trimmedUsername == null) return null;
    return 'u:$trimmedUsername';
  }

  String _roleLabel() {
    final normalized = (_role ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'admin':
        return 'Administrador';
      case 'cashier':
      case 'cajero':
        return 'Cajero';
      case 'seller':
      case 'vendedor':
        return 'Vendedor';
      default:
        return normalized.isEmpty ? 'Usuario activo' : _role!.trim();
    }
  }

  String _cashChipLabel() {
    final terminal = (_terminalId ?? '').trim();
    if (terminal.isEmpty) return 'Caja principal';

    final compact = terminal.length > 10
        ? terminal.substring(terminal.length - 6).toUpperCase()
        : terminal.toUpperCase();
    return 'Caja $compact';
  }

  String _licenseBadgeTitle() {
    final info = _licenseInfo;
    if (info == null) return 'Licencia pendiente';
    if (info.isBlocked) return 'Licencia bloqueada';
    if (info.isExpired) return 'Licencia vencida';
    if (info.isActive) return 'Licencia activa';
    return 'Licencia pendiente';
  }

  String _licenseBadgeSubtitle() {
    final info = _licenseInfo;
    if (info == null) return 'Verifica tu licencia';
    if (info.isBlocked) return 'Contacta soporte';
    if (info.isExpired) return 'Renovación requerida';

    final end = info.fechaFin;
    if (end == null) {
      return info.isActive ? 'Sin vencimiento visible' : 'Pendiente de validar';
    }

    final now = DateTime.now();
    final days = end.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (days < 0) return 'Licencia vencida';
    if (days == 0) return 'Vence hoy';
    if (days == 1) return 'Vence en 1 día';
    return 'Vence en $days días';
  }

  Color _licenseBadgeColor(ColorScheme scheme, AppStatusTheme? status) {
    final info = _licenseInfo;
    if (info == null) return status?.warning ?? scheme.tertiary;
    if (info.isExpired || info.isBlocked) return status?.error ?? scheme.error;
    if (info.isActive) return status?.success ?? scheme.primary;
    return status?.warning ?? scheme.tertiary;
  }

  void _showSnack(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  Future<void> _handleUserMenuAction(_UserMenuAction action) async {
    switch (action) {
      case _UserMenuAction.profile:
        context.go('/account');
        return;
      case _UserMenuAction.license:
        context.go('/settings/license');
        return;
      case _UserMenuAction.security:
        _showSnack('Seguridad estará disponible pronto.');
        return;
      case _UserMenuAction.settings:
        context.go('/settings');
        return;
      case _UserMenuAction.finishShift:
        final sessionId = _openCashSessionId;
        if (sessionId == null) {
          _showSnack('No hay turno abierto.');
          return;
        }

        await CashCloseDialog.show(
          context,
          sessionId: sessionId,
          logoutAfterClose: true,
          autoCloseImmediately: true,
        );
        if (!mounted) return;
        unawaited(_loadOpenCashSessionId());
        return;
      case _UserMenuAction.viewCurrentCut:
        final sessionId = _openCashSessionId;
        if (sessionId == null) {
          context.go('/cash');
          return;
        }

        await CashPanelSheet.show(context, sessionId: sessionId);
        if (!mounted) return;
        unawaited(_loadOpenCashSessionId());
        return;
      case _UserMenuAction.cutHistory:
        context.go('/cash/history');
        return;
      case _UserMenuAction.support:
        _showSnack('Soporte estará disponible pronto.');
        return;
      case _UserMenuAction.logout:
        if (_openCashSessionId != null) {
          _showSnack('Finaliza el turno antes de cerrar sesión.');
          return;
        }

        try {
          await LogoutFlowService.defaultPerformLogout(context);
        } catch (e) {
          if (!mounted) return;
          _showSnack(
            'No se pudo cerrar sesión: $e',
            backgroundColor: Theme.of(context).colorScheme.error,
          );
        }
        return;
    }
  }

  PopupMenuItem<_UserMenuAction> _buildMenuItem(
    BuildContext context, {
    required _UserMenuAction value,
    required IconData icon,
    required String label,
    required double width,
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final itemColor = color ?? const Color(0xFF334155);

    return PopupMenuItem<_UserMenuAction>(
      value: value,
      height: 46,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        itemColor.withOpacity(0.10),
                        Colors.white,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: itemColor.withOpacity(0.12),
                      ),
                    ),
                    child: Icon(icon, size: 17, color: itemColor),
                  ),
                  const SizedBox(width: 12),
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
                        fontSize: 13.5,
                        fontWeight: fontWeight,
                        height: 1.1,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: itemColor.withOpacity(0.45),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final tokens = theme.extension<AppTokens>() ?? AppTokens.defaultTokens;
    final businessName = ref.watch(businessSettingsProvider).businessName.trim();

    final appBarFg = ColorUtils.ensureReadableColor(
      tokens.topbarText,
      _topbarBackground,
      minRatio: 4.5,
    );
    final chromeBorderColor = Color.alphaBlend(
      tokens.outline.withOpacity(
        theme.brightness == Brightness.dark ? 0.34 : 0.52,
      ),
      _topbarBackground,
    );
    final chromeShadowColor = Color.alphaBlend(
      theme.shadowColor.withOpacity(
        theme.brightness == Brightness.dark ? 0.28 : 0.12,
      ),
      _topbarBackground,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        final s = widget.scale.clamp(0.85, 1.12);
        final topbarHeight = ((AppSizes.topbarHeight + 8) * s).clamp(
          56.0,
          70.0,
        );
        final topInset = (widget.topPadding * s).clamp(0.0, 12.0);
        final padM = AppSizes.paddingM * s;
        final padL = AppSizes.paddingL * s;
        final spaceS = AppSizes.spaceS * s;
        final spaceM = AppSizes.spaceM * s;
        final horizontalPad = ((isCompact ? padM : padL) * 0.75).clamp(
          10.0,
          20.0,
        );

        final isOpen = _openCashSessionId != null;
        final brandAccent = ColorUtils.ensureReadableColor(
          tokens.buttonPrimary,
          _topbarBackground,
          minRatio: 3.0,
        );
        final statusColor = isOpen
            ? (status?.success ?? const Color(0xFF16A34A))
            : (status?.error ?? scheme.error);
        final profileName = (_displayName ?? _username ?? 'Usuario').trim();
        final username = (_username ?? 'usuario').trim();
        final companyLabel = businessName.isEmpty ? 'FULLPOS' : businessName;
        final showCashLabel = constraints.maxWidth >= 720;
        final showUserDetails = constraints.maxWidth >= 820;
        final showUserSubtitle = constraints.maxWidth >= 1024;
        final canCash = _canAccessCash;
        final canHistory = _canViewCashHistory || canCash;
        final canFinishShift = _canCloseShift;
        final canViewCurrentCut = canCash || _canCloseShift || _canOpenCashbox;
        final hasShift = _openCashSessionId != null;
        final menuWidth = constraints.maxWidth < 430 ? 286.0 : 324.0;

        final menuItems = <PopupMenuEntry<_UserMenuAction>>[
          PopupMenuItem<_UserMenuAction>(
            enabled: false,
            height: 0,
            padding: EdgeInsets.zero,
            child: SizedBox(
              width: menuWidth,
              child: _TopbarMenuHeader(
                companyName: companyLabel,
                displayName: profileName,
                roleLabel: _roleLabel(),
                licenseTitle: _licenseBadgeTitle(),
                licenseSubtitle: _licenseBadgeSubtitle(),
                accentColor: brandAccent,
                badgeColor: _licenseBadgeColor(scheme, status),
                imagePath: _profileImagePath,
              ),
            ),
          ),
          const PopupMenuDivider(height: 1),
          _buildMenuItem(
            context,
            value: _UserMenuAction.profile,
            icon: Icons.person_outline_rounded,
            label: 'Mi perfil',
            width: menuWidth,
          ),
          _buildMenuItem(
            context,
            value: _UserMenuAction.license,
            icon: Icons.workspace_premium_outlined,
            label: 'Licencia',
            width: menuWidth,
          ),
          _buildMenuItem(
            context,
            value: _UserMenuAction.security,
            icon: Icons.shield_outlined,
            label: 'Seguridad',
            width: menuWidth,
          ),
          _buildMenuItem(
            context,
            value: _UserMenuAction.settings,
            icon: Icons.settings_outlined,
            label: 'Configuración',
            width: menuWidth,
          ),
          if (canViewCurrentCut || canHistory || (canFinishShift && hasShift))
            const PopupMenuDivider(height: 1),
          if (canViewCurrentCut)
            _buildMenuItem(
              context,
              value: _UserMenuAction.viewCurrentCut,
              icon: Icons.receipt_long_outlined,
              label: 'Ver corte actual',
              width: menuWidth,
            ),
          if (canHistory)
            _buildMenuItem(
              context,
              value: _UserMenuAction.cutHistory,
              icon: Icons.history_rounded,
              label: 'Historial de cortes',
              width: menuWidth,
            ),
          if (canFinishShift && hasShift)
            _buildMenuItem(
              context,
              value: _UserMenuAction.finishShift,
              icon: Icons.flag_outlined,
              label: 'Finalizar turno',
              width: menuWidth,
              color: status?.warning ?? scheme.tertiary,
              fontWeight: FontWeight.w800,
            ),
          const PopupMenuDivider(height: 1),
          _buildMenuItem(
            context,
            value: _UserMenuAction.support,
            icon: Icons.support_agent_outlined,
            label: 'Soporte',
            width: menuWidth,
          ),
          _buildMenuItem(
            context,
            value: _UserMenuAction.logout,
            icon: Icons.logout_rounded,
            label: 'Cerrar sesión',
            width: menuWidth,
            color: scheme.error,
            fontWeight: FontWeight.w800,
          ),
        ];

        return Container(
          height: topbarHeight + topInset,
          padding: EdgeInsets.fromLTRB(
            horizontalPad,
            topInset,
            horizontalPad,
            0,
          ),
          decoration: BoxDecoration(
            color: _topbarBackground,
            border: widget.showBottomBorder
                ? Border(
                    bottom: BorderSide(color: chromeBorderColor, width: 1),
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: chromeShadowColor,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
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
              Expanded(
                child: Text(
                  'Facturar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: appBarFg,
                    fontSize: ((isCompact ? 16 : 18) * s).clamp(15.0, 20.0),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.08,
                    height: 1.2,
                    fontFamilyFallback: const [
                      'Poppins',
                      'Segoe UI',
                      'Roboto',
                      'Arial',
                    ],
                  ),
                ),
              ),
              SizedBox(width: spaceS * 0.6),
              AnimatedBuilder(
                animation: _cashPulseController,
                builder: (context, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CashRegisterStatusChip(
                        scale: s,
                        visibleLabel: showCashLabel,
                        isOpen: isOpen,
                        accentColor: brandAccent,
                        statusColor: statusColor,
                        label: _cashChipLabel(),
                        openSessionId: _openCashSessionId,
                        pulseValue: isOpen ? _cashPulseController.value : 0,
                      ),
                      SizedBox(width: (10 * s).clamp(8.0, 12.0)),
                      PopupMenuButton<_UserMenuAction>(
                        tooltip: 'Cuenta y empresa',
                        position: PopupMenuPosition.under,
                        offset: const Offset(0, 10),
                        constraints: BoxConstraints(
                          minWidth: menuWidth,
                          maxWidth: menuWidth,
                        ),
                        elevation: 14,
                        color: _topbarBackground,
                        surfaceTintColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                          side: BorderSide(
                            color: brandAccent.withOpacity(0.14),
                          ),
                        ),
                        onSelected: _handleUserMenuAction,
                        itemBuilder: (_) => menuItems,
                        child: Tooltip(
                          message: '$profileName · @$username',
                          waitDuration: const Duration(milliseconds: 350),
                          child: _TopbarUserMenuButton(
                            scale: s,
                            accentColor: brandAccent,
                            borderColor: chromeBorderColor,
                            backgroundColor: Color.alphaBlend(
                              brandAccent.withOpacity(0.05),
                              Colors.white,
                            ),
                            displayName: profileName,
                            subtitle: isOpen ? 'Cajero activo' : 'Caja pendiente',
                            showDetails: showUserDetails,
                            showSubtitle: showUserSubtitle,
                            imagePath: _profileImagePath,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(width: spaceM),
            ],
          ),
        );
      },
    );
  }
}

class _CashRegisterStatusChip extends StatelessWidget {
  const _CashRegisterStatusChip({
    required this.scale,
    required this.visibleLabel,
    required this.isOpen,
    required this.accentColor,
    required this.statusColor,
    required this.label,
    required this.openSessionId,
    required this.pulseValue,
  });

  final double scale;
  final bool visibleLabel;
  final bool isOpen;
  final Color accentColor;
  final Color statusColor;
  final String label;
  final int? openSessionId;
  final double pulseValue;

  @override
  Widget build(BuildContext context) {
    final background = Color.alphaBlend(
      statusColor.withOpacity(isOpen ? 0.10 : 0.08),
      Colors.white,
    );
    final borderColor = statusColor.withOpacity(isOpen ? 0.30 : 0.22);
    final shadowOpacity = isOpen ? 0.12 + (pulseValue * 0.10) : 0.06;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      height: (42 * scale).clamp(38.0, 46.0),
      padding: EdgeInsets.symmetric(
        horizontal: visibleLabel ? (13 * scale).clamp(11.0, 15.0) : 10,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(shadowOpacity),
            blurRadius: isOpen ? 18 : 10,
            spreadRadius: -9,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: (25 * scale).clamp(22.0, 28.0),
            height: (25 * scale).clamp(22.0, 28.0),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isOpen
                  ? Icons.point_of_sale_rounded
                  : Icons.lock_outline_rounded,
              size: (15 * scale).clamp(13.0, 17.0),
              color: statusColor,
            ),
          ),
          if (visibleLabel) ...[
            SizedBox(width: (8 * scale).clamp(6.0, 10.0)),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOpen ? 'Caja abierta' : 'Caja cerrada',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: (10.5 * scale).clamp(9.5, 11.5),
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  openSessionId == null ? label : '$label #$openSessionId',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _TopbarState._strongTextColor,
                    fontSize: (12.5 * scale).clamp(11.0, 13.5),
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TopbarUserMenuButton extends StatelessWidget {
  const _TopbarUserMenuButton({
    required this.scale,
    required this.accentColor,
    required this.borderColor,
    required this.backgroundColor,
    required this.displayName,
    required this.subtitle,
    required this.showDetails,
    required this.showSubtitle,
    required this.imagePath,
  });

  final double scale;
  final Color accentColor;
  final Color borderColor;
  final Color backgroundColor;
  final String displayName;
  final String subtitle;
  final bool showDetails;
  final bool showSubtitle;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: (44 * scale).clamp(40.0, 48.0),
      padding: EdgeInsets.only(
        left: (8 * scale).clamp(7.0, 10.0),
        right: showDetails ? (10 * scale).clamp(8.0, 12.0) : 8,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 12,
            spreadRadius: -8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UserAvatar(
            size: (30 * scale).clamp(28.0, 34.0),
            accentColor: accentColor,
            name: displayName,
            imagePath: imagePath,
          ),
          if (showDetails) ...[
            SizedBox(width: (9 * scale).clamp(7.0, 11.0)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _TopbarState._strongTextColor,
                      fontSize: (13.2 * scale).clamp(12.0, 14.2),
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  if (showSubtitle) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _TopbarState._softTextColor,
                        fontSize: (10.5 * scale).clamp(9.5, 11.5),
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          SizedBox(width: (6 * scale).clamp(5.0, 8.0)),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: (20 * scale).clamp(18.0, 22.0),
            color: _TopbarState._softTextColor,
          ),
        ],
      ),
    );
  }
}

class _TopbarMenuHeader extends StatelessWidget {
  const _TopbarMenuHeader({
    required this.companyName,
    required this.displayName,
    required this.roleLabel,
    required this.licenseTitle,
    required this.licenseSubtitle,
    required this.accentColor,
    required this.badgeColor,
    required this.imagePath,
  });

  final String companyName;
  final String displayName;
  final String roleLabel;
  final String licenseTitle;
  final String licenseSubtitle;
  final Color accentColor;
  final Color badgeColor;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accentColor.withOpacity(0.12), Colors.white),
            Colors.white,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _UserAvatar(
                size: 46,
                accentColor: accentColor,
                name: displayName,
                imagePath: imagePath,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _TopbarState._strongTextColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      roleLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _TopbarState._softTextColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.78),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withOpacity(0.12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    size: 18,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        companyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _TopbarState._strongTextColor,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        licenseSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _TopbarState._softTextColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: badgeColor.withOpacity(0.22)),
                  ),
                  child: Text(
                    licenseTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.size,
    required this.accentColor,
    required this.name,
    this.imagePath,
  });

  final double size;
  final Color accentColor;
  final String name;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final initials = _initials(name);
    final path = imagePath;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor,
            Color.alphaBlend(Colors.black.withOpacity(0.18), accentColor),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.20),
            blurRadius: 12,
            spreadRadius: -5,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: path != null
          ? Image.file(
              File(path),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _InitialsText(initials: initials),
            )
          : _InitialsText(initials: initials),
    );
  }

  static String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

class _InitialsText extends StatelessWidget {
  const _InitialsText({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}
