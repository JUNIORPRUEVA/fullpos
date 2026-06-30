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
import '../session/ui_preferences.dart';
import '../theme/app_tokens.dart';
import '../theme/color_utils.dart';
import 'topbar_utility_panels.dart';

/// Topbar principal de FullPOS.
///
/// Diseño limpio:
/// Menú | Facturación                                      Turno | Empresa
///
/// Cambios aplicados:
/// - Eliminado el icono al lado de "Facturación".
/// - Eliminado el botón de productos/apps del lado derecho.
/// - Eliminado el chip separado del usuario.
/// - El usuario activo ahora aparece dentro del menú de Turno.
/// - La versión ya no aparece al lado del nombre de la empresa.
/// - La versión aparece en el extremo derecho del footer.
/// - El botón Turno tiene fondo y borde más sutiles.
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
  updates,
  logout,
  makeShiftCut,
  currentShift,
  shiftHistory,
}

class _TopbarState extends ConsumerState<Topbar> {
  static const Color _strongTextColor = Color(0xFF0F172A);
  static const Color _topbarBg = Color(0xFFFCFDFE);
  static const Color _chromeBorder = Color(0xFFDDE6F0);
  static const Color _chromeBorderHover = Color(0xFFC9D7E8);
  static const Color _chromeFillHover = Color(0xFFF7FAFD);
  static const Color _subtleIconColor = Color(0xFF52647A);

  Timer? _cashTimer;
  StreamSubscription<void>? _sessionSub;
  StreamSubscription<void>? _uiPreferencesSub;

  String? _username;
  String? _displayName;
  String? _profileImagePath;

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

    _uiPreferencesSub = UiPreferences.changes.listen((_) {
      if (!mounted) return;
      unawaited(_loadUserSummary());
    });

    _cashTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_loadOpenCashSessionId());
    });
  }

  @override
  void dispose() {
    _cashTimer?.cancel();
    _sessionSub?.cancel();
    _uiPreferencesSub?.cancel();
    super.dispose();
  }

  void _refreshTopbarData() {
    unawaited(_loadUserSummary());
    unawaited(_loadOpenCashSessionId());
  }

  Future<void> _loadUserSummary() async {
    final userId = await SessionManager.userId();
    final username = await SessionManager.username();
    final displayName = await SessionManager.displayName();
    final profileImagePath = await _loadProfileImagePath(
      userId: userId,
      username: username,
    );

    if (!mounted) return;
    setState(() {
      _username = _cleanText(username) ?? 'Usuario';
      _displayName = _cleanText(displayName);
      _profileImagePath = _cleanText(profileImagePath);
    });
  }

  Future<String?> _loadProfileImagePath({
    required int? userId,
    required String? username,
  }) async {
    final cleanUsername = _cleanText(username);
    final candidateKeys = <String>[
      if (userId != null) 'id:$userId',
      if (cleanUsername != null) 'u:$cleanUsername',
    ];

    for (final userKey in candidateKeys) {
      final path = await UiPreferences.getProfileImagePath(userKey);
      final cleanPath = _cleanText(path);
      if (cleanPath == null) continue;

      if (File(cleanPath).existsSync()) return cleanPath;

      await UiPreferences.setProfileImagePath(userKey, null);
    }

    return null;
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
      case _TopbarMenuAction.updates:
        context.go('/settings/updates');
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
        context.go('/cash/history?view=sessions');
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
    final readableColor = ColorUtils.ensureReadableColor(
      itemColor,
      scheme.surface,
      minRatio: 4.0,
    );

    const itemRadius = BorderRadius.only(
      topLeft: Radius.circular(12),
      topRight: Radius.circular(5),
      bottomLeft: Radius.circular(5),
      bottomRight: Radius.circular(12),
    );

    const iconRadius = BorderRadius.only(
      topLeft: Radius.circular(10),
      topRight: Radius.circular(4),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(10),
    );

    return PopupMenuItem<_TopbarMenuAction>(
      value: value,
      height: 48,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Material(
            color: Colors.transparent,
            borderRadius: itemRadius,
            child: InkWell(
              borderRadius: itemRadius,
              hoverColor: itemColor.withOpacity(0.045),
              splashColor: itemColor.withOpacity(0.08),
              highlightColor: itemColor.withOpacity(0.025),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
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
                        borderRadius: iconRadius,
                        border: Border.all(
                          color: itemColor.withOpacity(0.16),
                          width: 0.9,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: itemColor.withOpacity(0.07),
                            blurRadius: 7,
                            spreadRadius: -4,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, size: 17, color: itemColor),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: readableColor,
                          fontSize: 13.2,
                          fontWeight: fontWeight,
                          height: 1.1,
                          letterSpacing: -0.08,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: itemColor.withOpacity(0.46),
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
      _buildMenuItem(
        context,
        value: _TopbarMenuAction.updates,
        icon: Icons.system_update_alt_rounded,
        label: 'Actualizaciones',
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
    String activeUser,
    String? profileImagePath,
  ) {
    return [
      PopupMenuItem<_TopbarMenuAction>(
        enabled: false,
        height: 52,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: menuWidth,
          height: 52,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 18, 6),
            child: SizedBox(
              height: 37,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (profileImagePath != null) ...[
                    _TurnMenuUserAvatar(imagePath: profileImagePath),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: SizedBox(
                      height: 32,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Usuario activo',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.25,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            activeUser,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _strongTextColor,
                              fontSize: 12.4,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const PopupMenuDivider(height: 8),
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

    const topbarBg = _topbarBg;

    final appBarFg = ColorUtils.ensureReadableColor(
      tokens.topbarText,
      topbarBg,
      minRatio: 4.5,
    );

    final chromeBorderColor = theme.brightness == Brightness.dark
        ? Color.alphaBlend(tokens.outline.withOpacity(0.42), topbarBg)
        : _chromeBorder;

    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isCompactWidth = screenWidth <= 1366;
    final isShortHeight = screenHeight <= 900;
    final useCompactChrome = isCompactWidth || isShortHeight;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = screenWidth < 900;
        final s = widget.scale.clamp(0.85, 1.12);

        final compactScale = useCompactChrome ? 0.88 : 1.0;
        final effectiveScale = s * compactScale;

        final topbarHeight = useCompactChrome
            ? (46.0 * s).clamp(44.0, 48.0).toDouble()
            : (AppSizes.topbarHeight * s).clamp(48.0, 56.0).toDouble();
        final topInset = (widget.topPadding * effectiveScale).clamp(0.0, 10.0);

        final padM = AppSizes.paddingM * effectiveScale;
        final padL = AppSizes.paddingL * effectiveScale;

        final horizontalPad = ((isCompact ? padM : padL) * 0.55).clamp(
          6.0,
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
        final showTurnLabel = screenWidth >= 690;
        final menuButtonSize = useCompactChrome ? 36.0 : 40.0;
        final menuIconSize = useCompactChrome ? 19.0 : 21.0;

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
                ? const Border(
                    bottom: BorderSide(color: Color(0xFFD7E1EC), width: 1),
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 4,
                spreadRadius: -3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.showMenuButton) ...[
                Tooltip(
                  message: widget.isMenuOpen ? 'Cerrar menú' : 'Abrir menú',
                  waitDuration: const Duration(milliseconds: 350),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onMenuPressed,
                      borderRadius: BorderRadius.circular(10),
                      hoverColor: brandAccent.withOpacity(0.055),
                      splashColor: brandAccent.withOpacity(0.08),
                      highlightColor: brandAccent.withOpacity(0.045),
                      focusColor: brandAccent.withOpacity(0.075),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 190),
                        curve: Curves.easeOutCubic,
                        width: menuButtonSize,
                        height: menuButtonSize,
                        decoration: BoxDecoration(
                          color: widget.isMenuOpen
                              ? brandAccent
                              : Color.alphaBlend(
                                  brandAccent.withOpacity(0.055),
                                  topbarBg,
                                ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: widget.isMenuOpen
                                ? brandAccent
                                : brandAccent.withOpacity(0.20),
                            width: 1,
                          ),
                          boxShadow: widget.isMenuOpen
                              ? [
                                  BoxShadow(
                                    color: brandAccent.withOpacity(0.18),
                                    blurRadius: 12,
                                    spreadRadius: -4,
                                    offset: const Offset(0, 5),
                                  ),
                                ]
                              : const [],
                        ),
                        alignment: Alignment.center,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 190),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(
                                  begin: 0.86,
                                  end: 1,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: Icon(
                            widget.isMenuOpen
                                ? Icons.close_rounded
                                : Icons.menu_rounded,
                            key: ValueKey<bool>(widget.isMenuOpen),
                            size: menuIconSize,
                            color: widget.isMenuOpen
                                ? Colors.white
                                : brandAccent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: useCompactChrome ? 8 : 10),
              ],

              Flexible(
                flex: 0,
                child: Text(
                  'Facturación',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: appBarFg,
                    fontSize:
                        ((isCompact || useCompactChrome ? 16.5 : 18.0) * s)
                            .clamp(15.5, 19.0)
                            .toDouble(),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.08,
                    height: 1.08,
                    fontFamilyFallback: const [
                      'Poppins',
                      'Segoe UI',
                      'Roboto',
                      'Arial',
                    ],
                  ),
                ),
              ),

              SizedBox(width: useCompactChrome ? 10 : 14),

              Container(
                width: 1,
                height: useCompactChrome ? 24 : 28,
                color: chromeBorderColor.withOpacity(0.75),
              ),

              const Spacer(),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(7),
                        bottomLeft: Radius.circular(7),
                        bottomRight: Radius.circular(16),
                      ),
                      side: BorderSide(
                        color: brandAccent.withOpacity(0.14),
                        width: 0.9,
                      ),
                    ),
                    onSelected: _handleMenuAction,
                    itemBuilder: (_) {
                      return _turnMenuItems(
                        context,
                        turnMenuWidth,
                        activeUser,
                        _profileImagePath,
                      );
                    },
                    child: _TurnMenuButton(
                      scale: useCompactChrome ? effectiveScale : s,
                      visibleLabel: showTurnLabel,
                      accentColor: brandAccent,
                      borderColor: chromeBorderColor,
                      isOpen: _openCashSessionId != null,
                    ),
                  ),

                  SizedBox(
                    width: ((useCompactChrome ? 5 : 7) * s)
                        .clamp(4.0, 8.0)
                        .toDouble(),
                  ),

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
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(7),
                        bottomLeft: Radius.circular(7),
                        bottomRight: Radius.circular(16),
                      ),
                      side: BorderSide(
                        color: brandAccent.withOpacity(0.14),
                        width: 0.9,
                      ),
                    ),
                    onSelected: _handleMenuAction,
                    itemBuilder: (_) {
                      return _businessMenuItems(context, businessMenuWidth);
                    },
                    child: Tooltip(
                      message: businessName,
                      waitDuration: const Duration(milliseconds: 350),
                      child: _BusinessMenuButton(
                        scale: useCompactChrome ? effectiveScale : s,
                        businessName: businessName,
                        logoPath: businessLogoPath,
                        showText: showBusinessText,
                        accentColor: brandAccent,
                        borderColor: chromeBorderColor,
                        hoverBorderColor: _chromeBorderHover,
                        hoverFillColor: _chromeFillHover,
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
    required this.hoverBorderColor,
    required this.hoverFillColor,
  });

  final double scale;
  final String businessName;
  final String? logoPath;
  final bool showText;
  final Color accentColor;
  final Color borderColor;
  final Color hoverBorderColor;
  final Color hoverFillColor;

  @override
  Widget build(BuildContext context) {
    final height = (36 * scale).clamp(30.0, 40.0).toDouble();

    final cleanName = businessName.trim().isEmpty
        ? 'Mi negocio'
        : businessName.trim();
    final normalizedPath = (logoPath ?? '').trim();

    final buttonRadius = BorderRadius.circular(11);

    return _TopbarHoverSurface(
      height: height,
      padding: EdgeInsets.only(
        left: (7 * scale).clamp(6.0, 8.0).toDouble(),
        right: (8 * scale).clamp(7.0, 10.0).toDouble(),
      ),
      borderRadius: buttonRadius,
      borderColor: borderColor,
      hoverBorderColor: hoverBorderColor,
      hoverFillColor: hoverFillColor,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BusinessLogoMark(
            size: (28 * scale).clamp(24.0, 30.0).toDouble(),
            accentColor: accentColor,
            logoPath: normalizedPath,
          ),
          if (showText) ...[
            SizedBox(width: (8 * scale).clamp(6.0, 9.0).toDouble()),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                cleanName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _TopbarState._strongTextColor,
                  fontSize: (12.8 * scale).clamp(12.2, 13.4).toDouble(),
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
          SizedBox(width: (4 * scale).clamp(3.0, 5.0).toDouble()),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: (16 * scale).clamp(14.0, 17.0).toDouble(),
            color: _TopbarState._subtleIconColor,
          ),
        ],
      ),
    );
  }
}

class _TurnMenuUserAvatar extends StatelessWidget {
  const _TurnMenuUserAvatar({required this.imagePath});

  final String imagePath;

  @override
  Widget build(BuildContext context) {
    const accentColor = Color(0xFF1A56DB);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCAD8EE), width: 0.9),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.08),
            blurRadius: 9,
            spreadRadius: -5,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.file(
        File(imagePath),
        width: 32,
        height: 32,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _BusinessLogoMark extends StatelessWidget {
  const _BusinessLogoMark({
    required this.size,
    required this.accentColor,
    required this.logoPath,
  });

  final double size;
  final Color accentColor;
  final String logoPath;

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoPath.trim().isNotEmpty && File(logoPath).existsSync();
    final logoRadius = BorderRadius.circular(8);

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: logoRadius,
        color: const Color(0xFFF2F7FF),
        border: Border.all(color: const Color(0xFFD8E4F2), width: 0.85),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? Image.file(
              File(logoPath),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) =>
                  _BusinessLogoPlaceholder(accentColor: accentColor),
            )
          : _BusinessLogoPlaceholder(accentColor: accentColor),
    );
  }
}

class _BusinessLogoPlaceholder extends StatelessWidget {
  const _BusinessLogoPlaceholder({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.storefront_rounded, size: 16.5, color: accentColor);
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
    final height = (36 * scale).clamp(32.0, 38.0).toDouble();

    final buttonRadius = BorderRadius.circular(11);

    final iconRadius = BorderRadius.circular(8);

    return Tooltip(
      message: isOpen ? 'Turno abierto' : 'Gestionar turno',
      waitDuration: const Duration(milliseconds: 350),
      child: _TopbarHoverSurface(
        height: height,
        padding: EdgeInsets.symmetric(
          horizontal: visibleLabel
              ? (10 * scale).clamp(9.0, 12.0).toDouble()
              : 7,
        ),
        borderRadius: buttonRadius,
        borderColor: borderColor,
        hoverBorderColor: _TopbarState._chromeBorderHover,
        hoverFillColor: _TopbarState._chromeFillHover,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: (23 * scale).clamp(21.0, 25.0).toDouble(),
              height: (23 * scale).clamp(21.0, 25.0).toDouble(),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7FF),
                borderRadius: iconRadius,
                border: Border.all(color: const Color(0xFFD8E4F2), width: 0.8),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.point_of_sale_rounded,
                size: (14.5 * scale).clamp(13.0, 16.0).toDouble(),
                color: accentColor,
              ),
            ),
            if (visibleLabel) ...[
              SizedBox(width: (7 * scale).clamp(5.0, 8.0).toDouble()),
              Text(
                'Turno',
                style: TextStyle(
                  color: accentColor,
                  fontSize: (12 * scale).clamp(11.2, 12.8).toDouble(),
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(width: (3 * scale).clamp(2.0, 4.0).toDouble()),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: (17 * scale).clamp(15.0, 18.0).toDouble(),
                color: _TopbarState._subtleIconColor,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopbarHoverSurface extends StatefulWidget {
  const _TopbarHoverSurface({
    required this.height,
    required this.padding,
    required this.borderRadius,
    required this.borderColor,
    required this.hoverBorderColor,
    required this.hoverFillColor,
    required this.child,
  });

  final double height;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color borderColor;
  final Color hoverBorderColor;
  final Color hoverFillColor;
  final Widget child;

  @override
  State<_TopbarHoverSurface> createState() => _TopbarHoverSurfaceState();
}

class _TopbarHoverSurfaceState extends State<_TopbarHoverSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        height: widget.height,
        padding: widget.padding,
        decoration: BoxDecoration(
          color: _hovered ? widget.hoverFillColor : Colors.white,
          borderRadius: widget.borderRadius,
          border: Border.all(
            color: _hovered ? widget.hoverBorderColor : widget.borderColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_hovered ? 0.022 : 0.014),
              blurRadius: _hovered ? 7 : 5,
              spreadRadius: -3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}
