import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cash/data/operation_flow_service.dart';
import '../../features/cash/ui/cash_panel_sheet.dart';
import '../../features/license/data/license_models.dart';
import '../../features/license/services/license_storage.dart';
import '../constants/app_sizes.dart';
import '../session/session_manager.dart';
import '../session/ui_preferences.dart';
import '../theme/app_tokens.dart';
import '../theme/color_utils.dart';

/// Topbar principal de FullPOS.
///
/// Diseño compacto estilo POS/SaaS:
/// - Chip azul tecnológico con usuario activo/en línea.
/// - Accesos rápidos compactos para corte, licencia y configuración.
/// - Botón de cuenta/caja alineado al extremo derecho.
/// - Menú desplegable solo con Perfil, Licencia, Seguridad y Configuración.
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
  viewCurrentCut,
  support,
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

  String? _username;
  String? _displayName;
  String? _role;
  String? _terminalId;
  String? _profileImagePath;
  LicenseInfo? _licenseInfo;
  final LicenseStorage _licenseStorage = LicenseStorage();
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

    final today = DateTime.now();
    final baseDate = DateTime(today.year, today.month, today.day);
    final days = end.difference(baseDate).inDays;
    if (days < 0) return 'Licencia vencida';
    if (days == 0) return 'Vence hoy';
    if (days == 1) return 'Vence en 1 día';
    return 'Vence en $days días';
  }

  Color _licenseBadgeColor(ColorScheme scheme) {
    final info = _licenseInfo;
    if (info == null) return const Color(0xFFF59E0B);
    if (info.isExpired || info.isBlocked) return scheme.error;
    if (info.isActive) return const Color(0xFF16A34A);
    return const Color(0xFFF59E0B);
  }

  Future<void> _showLicenseDetailsDialog() async {
    final scheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<AppTokens>() ?? AppTokens.defaultTokens;
    final accent = ColorUtils.ensureReadableColor(
      tokens.buttonPrimary,
      Colors.white,
      minRatio: 3.0,
    );
    final badgeColor = _licenseBadgeColor(scheme);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _LicenseDetailsDialog(
          title: _licenseBadgeTitle(),
          subtitle: _licenseBadgeSubtitle(),
          badgeColor: badgeColor,
          accentColor: accent,
          onOpenLicense: () {
            Navigator.of(dialogContext).pop();
            context.go('/settings/license');
          },
        );
      },
    );
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
      case _UserMenuAction.support:
        _showSnack('Soporte estará disponible pronto.');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.extension<AppTokens>() ?? AppTokens.defaultTokens;

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
          _topbarBackground,
          minRatio: 3.0,
        );
        final profileName = (_displayName ?? _username ?? 'Usuario').trim();
        final username = (_username ?? 'usuario').trim();
        final showUserLabel = constraints.maxWidth >= 620;
        final showUserDetails = constraints.maxWidth >= 720;
        final accountTriggerLabel = _openCashSessionId == null
            ? profileName
            : _cashChipLabel();
        final menuWidth = constraints.maxWidth < 430 ? 230.0 : 254.0;

        final menuItems = <PopupMenuEntry<_UserMenuAction>>[
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
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _UserStatusChip(
                      scale: s,
                      visibleLabel: showUserLabel,
                      color: brandAccent,
                      label: profileName,
                      roleLabel: _roleLabel(),
                      pulseValue: _cashPulseController.value,
                    ),
                    SizedBox(width: (8 * s).clamp(6.0, 9.0)),
                    _TurnCutAction(
                      scale: s,
                      visibleLabel: constraints.maxWidth >= 760,
                      accentColor: brandAccent,
                      borderColor: chromeBorderColor,
                      isOpen: _openCashSessionId != null,
                      onTap: () => unawaited(
                        _handleUserMenuAction(_UserMenuAction.viewCurrentCut),
                      ),
                    ),
                    SizedBox(width: (5 * s).clamp(4.0, 7.0)),
                    _TopbarIconAction(
                      scale: s,
                      icon: Icons.workspace_premium_outlined,
                      tooltip: 'Ver licencia',
                      color: _licenseBadgeColor(scheme),
                      borderColor: chromeBorderColor,
                      onTap: () => unawaited(_showLicenseDetailsDialog()),
                    ),
                    if (!isCompact) ...[
                      SizedBox(width: (5 * s).clamp(4.0, 7.0)),
                      _TopbarIconAction(
                        scale: s,
                        icon: Icons.apps_rounded,
                        tooltip: 'Configuración',
                        color: _softTextColor,
                        borderColor: chromeBorderColor,
                        onTap: () => unawaited(
                          _handleUserMenuAction(_UserMenuAction.settings),
                        ),
                      ),
                    ],
                    SizedBox(width: (8 * s).clamp(6.0, 9.0)),
                    PopupMenuButton<_UserMenuAction>(
                      tooltip: 'Cuenta y empresa',
                      position: PopupMenuPosition.under,
                      offset: const Offset(0, 8),
                      constraints: BoxConstraints(
                        minWidth: menuWidth,
                        maxWidth: menuWidth,
                      ),
                      elevation: 10,
                      color: _topbarBackground,
                      surfaceTintColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: brandAccent.withOpacity(0.12)),
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
                            brandAccent.withOpacity(0.04),
                            Colors.white,
                          ),
                          displayName: accountTriggerLabel,
                          subtitle: _roleLabel(),
                          showDetails: showUserDetails,
                          imagePath: _profileImagePath,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UserStatusChip extends StatelessWidget {
  const _UserStatusChip({
    required this.scale,
    required this.visibleLabel,
    required this.color,
    required this.label,
    required this.roleLabel,
    required this.pulseValue,
  });

  final double scale;
  final bool visibleLabel;
  final Color color;
  final String label;
  final String roleLabel;
  final double pulseValue;

  @override
  Widget build(BuildContext context) {
    final displayLabel = label.trim().isEmpty ? 'Usuario activo' : label.trim();
    final normalizedRole = roleLabel.trim().isEmpty ? 'Operando ahora' : roleLabel.trim();
    final pulseOpacity = 0.18 + (pulseValue * 0.18);
    final background = Color.alphaBlend(color.withOpacity(0.075), Colors.white);
    final borderColor = color.withOpacity(0.28 + (pulseValue * 0.10));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: (36 * scale).clamp(34.0, 38.0),
      padding: EdgeInsets.symmetric(
        horizontal: visibleLabel ? (10 * scale).clamp(9.0, 12.0) : 8,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08 + (pulseValue * 0.05)),
            blurRadius: 12,
            spreadRadius: -8,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: (23 * scale).clamp(21.0, 25.0),
                height: (23 * scale).clamp(21.0, 25.0),
                decoration: BoxDecoration(
                  color: color.withOpacity(pulseOpacity),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: (17 * scale).clamp(16.0, 19.0),
                height: (17 * scale).clamp(16.0, 19.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.28)),
                ),
                child: Icon(
                  Icons.support_agent_rounded,
                  size: (11.5 * scale).clamp(10.0, 13.0),
                  color: color,
                ),
              ),
              Positioned(
                right: 1,
                bottom: 1,
                child: Container(
                  width: (7.5 * scale).clamp(6.5, 8.5),
                  height: (7.5 * scale).clamp(6.5, 8.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.2),
                  ),
                ),
              ),
            ],
          ),
          if (visibleLabel) ...[
            SizedBox(width: (7 * scale).clamp(5.0, 8.0)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 162),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      displayLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _TopbarState._strongTextColor,
                        fontSize: (12.2 * scale).clamp(11.5, 13.0),
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      normalizedRole,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: (9.7 * scale).clamp(9.0, 10.5),
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TurnCutAction extends StatelessWidget {
  const _TurnCutAction({
    required this.scale,
    required this.visibleLabel,
    required this.accentColor,
    required this.borderColor,
    required this.isOpen,
    required this.onTap,
  });

  final double scale;
  final bool visibleLabel;
  final Color accentColor;
  final Color borderColor;
  final bool isOpen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final height = (34 * scale).clamp(32.0, 38.0);
    final bg = Color.alphaBlend(accentColor.withOpacity(0.10), Colors.white);

    return Tooltip(
      message: isOpen ? 'Ver corte actual' : 'Abrir módulo de caja',
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Ink(
            height: height,
            padding: EdgeInsets.symmetric(
              horizontal: visibleLabel ? (10 * scale).clamp(9.0, 12.0) : 0,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: accentColor.withOpacity(0.34)),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.14),
                  blurRadius: 12,
                  spreadRadius: -8,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: (22 * scale).clamp(20.0, 24.0),
                  height: (22 * scale).clamp(20.0, 24.0),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    size: (14.5 * scale).clamp(13.0, 16.0),
                    color: accentColor,
                  ),
                ),
                if (visibleLabel) ...[
                  SizedBox(width: (7 * scale).clamp(5.0, 8.0)),
                  Text(
                    'Corte',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: (12 * scale).clamp(11.2, 12.8),
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
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

class _TopbarUserMenuButton extends StatelessWidget {
  const _TopbarUserMenuButton({
    required this.scale,
    required this.accentColor,
    required this.borderColor,
    required this.backgroundColor,
    required this.displayName,
    required this.subtitle,
    required this.showDetails,
    required this.imagePath,
  });

  final double scale;
  final Color accentColor;
  final Color borderColor;
  final Color backgroundColor;
  final String displayName;
  final String subtitle;
  final bool showDetails;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      height: (36 * scale).clamp(34.0, 40.0),
      padding: EdgeInsets.only(
        left: showDetails ? (11 * scale).clamp(9.0, 12.0) : 7,
        right: (8 * scale).clamp(7.0, 10.0),
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withOpacity(0.85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDetails) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _TopbarState._strongTextColor,
                  fontSize: (12.8 * scale).clamp(12.0, 13.4),
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
            SizedBox(width: (9 * scale).clamp(7.0, 10.0)),
          ],
          _UserAvatar(
            size: (25 * scale).clamp(23.0, 27.0),
            accentColor: accentColor,
            name: displayName.isEmpty ? subtitle : displayName,
            imagePath: imagePath,
          ),
          SizedBox(width: (5 * scale).clamp(4.0, 6.0)),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: (18 * scale).clamp(16.0, 20.0),
            color: _TopbarState._softTextColor,
          ),
        ],
      ),
    );
  }
}

class _LicenseDetailsDialog extends StatelessWidget {
  const _LicenseDetailsDialog({
    required this.title,
    required this.subtitle,
    required this.badgeColor,
    required this.accentColor,
    required this.onOpenLicense,
  });

  final String title;
  final String subtitle;
  final Color badgeColor;
  final Color accentColor;
  final VoidCallback onOpenLicense;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accentColor.withOpacity(0.14)),
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
                padding: const EdgeInsets.fromLTRB(20, 18, 14, 12),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accentColor.withOpacity(0.14),
                            badgeColor.withOpacity(0.12),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: accentColor.withOpacity(0.14)),
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        color: badgeColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Licencia del cliente',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _TopbarState._strongTextColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Estado y vigencia del sistema',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _TopbarState._softTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: _TopbarState._softTextColor,
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(badgeColor.withOpacity(0.075), Colors.white),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: badgeColor.withOpacity(0.20)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          title.toLowerCase().contains('activa')
                              ? Icons.verified_rounded
                              : Icons.info_outline_rounded,
                          color: badgeColor,
                          size: 21,
                        ),
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
                              style: TextStyle(
                                color: badgeColor,
                                fontSize: 14,
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
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          side: BorderSide(color: accentColor.withOpacity(0.22)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cerrar',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onOpenLicense,
                        icon: const Icon(Icons.open_in_new_rounded, size: 17),
                        label: const Text('Ver licencia'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
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
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}
