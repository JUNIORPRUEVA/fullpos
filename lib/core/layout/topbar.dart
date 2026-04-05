import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/services/logout_flow_service.dart';
import '../../features/cash/data/operation_flow_service.dart';
import '../../features/cash/ui/cash_close_dialog.dart';
import '../../features/cash/ui/cash_open_dialog.dart';
import '../../features/cash/ui/cash_panel_sheet.dart';
import '../constants/app_sizes.dart';
import '../session/session_manager.dart';
import '../session/ui_preferences.dart';
import '../theme/app_status_theme.dart';
import '../theme/app_tokens.dart';
import '../theme/color_utils.dart';

/// Topbar del layout principal con fecha/hora y usuario.
class Topbar extends ConsumerStatefulWidget {
  final bool showMenuButton;
  final VoidCallback? onMenuPressed;
  final double scale;
  final bool showBottomBorder;
  final double topPadding;

  const Topbar({
    super.key,
    this.showMenuButton = false,
    this.onMenuPressed,
    this.scale = 1.0,
    this.showBottomBorder = true,
    this.topPadding = 0.0,
  });

  @override
  ConsumerState<Topbar> createState() => _TopbarState();
}

enum _UserMenuAction {
  profile,
  finishShift,
  viewCurrentCut,
  cutHistory,
  logout,
}

class _TopbarState extends ConsumerState<Topbar>
    with SingleTickerProviderStateMixin {
  late Timer _cashTimer;
  AnimationController? _cashPulseController;
  StreamSubscription<void>? _sessionSub;
  StreamSubscription<void>? _uiPrefsSub;

  String? _username;
  String? _displayName;
  String? _profileImagePath;

  bool _canAccessCash = false;
  bool _canViewCashHistory = false;
  bool _canCloseShift = false;
  bool _canOpenCashbox = false;
  int? _openCashSessionId;
  bool _loadingOpenCashSessionId = false;

  @override
  void initState() {
    super.initState();
    _cashPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _loadUserSummary();
    _loadProfileImage();
    _loadCashAccess();
    _loadOpenCashSessionId();

    _sessionSub = SessionManager.changes.listen((_) {
      if (!mounted) return;
      _loadUserSummary();
      _loadProfileImage();
      _loadCashAccess();
      _loadOpenCashSessionId();
    });

    _uiPrefsSub = UiPreferences.changes.listen((_) {
      if (!mounted) return;
      _loadProfileImage();
    });

    _cashTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadOpenCashSessionId();
    });
  }

  @override
  void dispose() {
    _cashPulseController?.dispose();
    _cashTimer.cancel();
    _sessionSub?.cancel();
    _uiPrefsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserSummary() async {
    final username = await SessionManager.username();
    final displayName = await SessionManager.displayName();

    if (!mounted) return;
    setState(() {
      _username = username ?? 'Usuario';
      _displayName = displayName != null && displayName.trim().isNotEmpty
          ? displayName.trim()
          : null;
    });
  }

  String? _buildUserKey({required int? userId, required String? username}) {
    if (userId != null) return 'id:$userId';
    final trimmedUsername = username?.trim();
    if (trimmedUsername == null || trimmedUsername.isEmpty) return null;
    return 'u:$trimmedUsername';
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
    if (path != null) {
      final exists = await File(path).exists();
      if (!exists) {
        await UiPreferences.setProfileImagePath(userKey, null);
        path = null;
      }
    }

    if (!mounted) return;
    setState(() => _profileImagePath = path);
  }

  Future<void> _loadCashAccess() async {
    try {
      final permissions = await AuthRepository.getCurrentPermissions();
      final isAdmin = await AuthRepository.isAdmin();
      final allowed = isAdmin ||
          permissions.canOpenCash ||
          permissions.canCloseCash;
      final canHistory = isAdmin || permissions.canViewCashHistory;
      final canCloseShift =
          isAdmin || permissions.canCloseShift || permissions.canCloseCash;
      final canOpenCashbox =
          isAdmin || permissions.canOpenCashbox || permissions.canOpenCash;
      if (!mounted) return;
      setState(() {
        _canAccessCash = allowed;
        _canViewCashHistory = canHistory;
        _canCloseShift = canCloseShift;
        _canOpenCashbox = canOpenCashbox;
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

  Future<void> _handleUserMenuAction(_UserMenuAction action) async {
    switch (action) {
      case _UserMenuAction.profile:
        context.go('/account');
        return;
      case _UserMenuAction.finishShift:
        final sessionId = _openCashSessionId;
        if (sessionId == null) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('No hay turno abierto.')),
          );
          return;
        }
        await CashCloseDialog.show(
          context,
          sessionId: sessionId,
          logoutAfterClose: true,
          autoCloseImmediately: true,
        );
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
      case _UserMenuAction.logout:
        if (_openCashSessionId != null) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                'Finaliza el turno antes de cerrar sesión.',
              ),
            ),
          );
          return;
        }
        try {
          await LogoutFlowService.defaultPerformLogout(context);
        } catch (e) {
          if (!mounted) return;
          final scheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('No se pudo cerrar sesión: $e'),
              backgroundColor: scheme.error,
            ),
          );
        }
        return;
    }
  }

  Future<void> _loadOpenCashSessionId() async {
    if (_loadingOpenCashSessionId) return;
    _loadingOpenCashSessionId = true;

    try {
      final sessionId =
          (await OperationFlowService.loadActiveSession())?.shiftId;
      if (!mounted) return;
      if (sessionId == _openCashSessionId) return;
      setState(() => _openCashSessionId = sessionId);
    } catch (_) {
      // No bloquear la UI si falla la consulta del estado de caja.
    } finally {
      _loadingOpenCashSessionId = false;
    }
  }

  Future<void> _onCashPressed() async {
    final cachedSessionId = _openCashSessionId;

    if (cachedSessionId != null) {
      await CashPanelSheet.show(context, sessionId: cachedSessionId);
      unawaited(_loadOpenCashSessionId());
      return;
    }

    final sessionId = (await OperationFlowService.loadActiveSession())?.shiftId;
    if (!mounted) return;

    if (sessionId != null) {
      await CashPanelSheet.show(context, sessionId: sessionId);
      await _loadOpenCashSessionId();
      return;
    }

    final opened = await CashOpenDialog.show(context);
    if (!mounted) return;

    if (opened == true) {
      final newSessionId =
          (await OperationFlowService.loadActiveSession())?.shiftId;
      if (!mounted) return;

      if (newSessionId != null) {
        await CashPanelSheet.show(context, sessionId: newSessionId);
      }
      await _loadOpenCashSessionId();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final tokens = theme.extension<AppTokens>() ?? AppTokens.defaultTokens;
    final appBarBg = tokens.topbarBackground;
    final appBarFg = ColorUtils.ensureReadableColor(
      tokens.topbarText,
      appBarBg,
      minRatio: 4.5,
    );
    final chromeBorderColor = Color.alphaBlend(
      tokens.outline.withOpacity(
        theme.brightness == Brightness.dark ? 0.34 : 0.52,
      ),
      appBarBg,
    );
    final chromeShadowColor = Color.alphaBlend(
      theme.shadowColor.withOpacity(
        theme.brightness == Brightness.dark ? 0.28 : 0.12,
      ),
      appBarBg,
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

        return Container(
          height: topbarHeight + topInset,
          decoration: BoxDecoration(
            color: appBarBg,
            boxShadow: [
              BoxShadow(
                color: chromeShadowColor,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: widget.showBottomBorder
                ? Border(bottom: BorderSide(color: chromeBorderColor, width: 1))
                : null,
          ),
          padding: EdgeInsets.fromLTRB(
            horizontalPad,
            topInset,
            horizontalPad,
            0,
          ),
          child: Row(
            children: [
              if (widget.showMenuButton) ...[
                IconButton(
                  onPressed: widget.onMenuPressed,
                  tooltip: 'Menú',
                  icon: Icon(Icons.menu, color: appBarFg),
                ),
                SizedBox(width: spaceS),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: 'Sistema ',
                    children: [
                      TextSpan(
                        text: 'POS',
                        style: TextStyle(
                          color: ColorUtils.ensureReadableColor(
                            scheme.secondary,
                            appBarBg,
                            minRatio: 3.0,
                          ),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: appBarFg,
                    fontSize: ((isCompact ? 16 : 18) * s).clamp(14.0, 20.0),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.35,
                    height: 1.0,
                    fontFamilyFallback: const [
                      'Inter',
                      'Segoe UI',
                      'Roboto',
                      'Arial',
                    ],
                  ),
                ),
              ),
              SizedBox(width: spaceS * 0.6),
              Builder(
                builder: (context) {
                  final isOpen = _openCashSessionId != null;
                  final statusColor = isOpen
                      ? (status?.success ?? scheme.tertiary)
                      : (status?.error ?? scheme.error);
                  final brandAccent = ColorUtils.ensureReadableColor(
                    tokens.buttonPrimary,
                    appBarBg,
                    minRatio: 3.0,
                  );
                  final capsuleBg = Color.alphaBlend(
                    brandAccent.withOpacity(0.05),
                    appBarBg,
                  );
                  final capsuleBorder = Color.alphaBlend(
                    brandAccent.withOpacity(0.24),
                    appBarFg.withOpacity(0.06),
                  );
                  final neutralSectionTint = Color.alphaBlend(
                    appBarFg.withOpacity(0.035),
                    appBarBg,
                  );
                  final statusSectionTint = Color.alphaBlend(
                    statusColor.withOpacity(isOpen ? 0.08 : 0.05),
                    neutralSectionTint,
                  );
                  final sectionStroke = Color.alphaBlend(
                    brandAccent.withOpacity(0.12),
                    appBarFg.withOpacity(0.05),
                  );
                  final pulse = CurvedAnimation(
                    parent: _cashPulseController ?? kAlwaysDismissedAnimation,
                    curve: Curves.easeInOut,
                  );
                  final cashLabel = isOpen ? 'Caja abierta' : 'Caja cerrada';
                  final profileName = (_displayName ?? _username ?? 'Usuario')
                      .trim();
                  final cashDetail = isOpen
                      ? 'Corte #$_openCashSessionId'
                      : (_canAccessCash
                            ? 'Abrir o consultar caja'
                            : 'Sin acceso de caja');
                  final capsuleRadius = (18 * s).clamp(17.0, 21.0);
                  final sectionRadius = (14 * s).clamp(13.0, 16.0);
                  final sectionHorizontalPadding = (10 * s).clamp(9.0, 12.0);
                  final sectionVerticalPadding = (4.5 * s).clamp(4.0, 5.5);
                  final labelTextStyle = TextStyle(
                    color: appBarFg.withOpacity(0.58),
                    fontSize: (7.9 * s).clamp(7.6, 8.8),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.18,
                    height: 1.0,
                  );
                  final valueTextStyle = TextStyle(
                    color: appBarFg,
                    fontSize: (11.3 * s).clamp(10.8, 12.4),
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.04,
                    height: 1.02,
                  );

                  return Align(
                    alignment: Alignment.centerRight,
                    child: AnimatedBuilder(
                    animation: pulse,
                    builder: (context, child) {
                      final glowStrength = isOpen ? pulse.value : 0.0;
                      final animatedBorder = Color.lerp(
                        capsuleBorder,
                        brandAccent.withOpacity(0.30),
                        glowStrength * 0.55,
                      )!;
                      final animatedShadow = Color.lerp(
                        brandAccent.withOpacity(0.06),
                        brandAccent.withOpacity(0.14),
                        glowStrength,
                      )!;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        constraints: BoxConstraints(
                          maxWidth: (isCompact ? 278.0 : 432.0) * s,
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: (10 * s).clamp(9.0, 13.0),
                          vertical: (4.5 * s).clamp(4.0, 5.5),
                        ),
                        decoration: BoxDecoration(
                          color: capsuleBg,
                          borderRadius: BorderRadius.circular(capsuleRadius),
                          border: Border.all(color: animatedBorder),
                          boxShadow: [
                            BoxShadow(
                              color: animatedShadow,
                              blurRadius: 12 + (glowStrength * 6),
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: child,
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          flex: 5,
                          child: Tooltip(
                            message: '$cashLabel. $cashDetail',
                            waitDuration: const Duration(milliseconds: 350),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: null,
                                borderRadius: BorderRadius.circular(
                                  sectionRadius,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  padding: EdgeInsets.symmetric(
                                    horizontal: sectionHorizontalPadding,
                                    vertical: sectionVerticalPadding,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusSectionTint,
                                    borderRadius: BorderRadius.circular(
                                      sectionRadius,
                                    ),
                                    border: Border.all(color: sectionStroke),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: (28 * s).clamp(25.0, 30.0),
                                        height: (28 * s).clamp(25.0, 30.0),
                                        decoration: BoxDecoration(
                                          color: brandAccent.withOpacity(0.10),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          alignment: Alignment.center,
                                          children: [
                                            Icon(
                                              isOpen
                                                  ? Icons.account_balance_wallet_outlined
                                                  : Icons.lock_outline_rounded,
                                              size: (13 * s).clamp(11.0, 14.0),
                                              color: brandAccent,
                                            ),
                                            Positioned(
                                              right: -1,
                                              top: -1,
                                              child: Container(
                                                width: (8 * s).clamp(7.0, 9.0),
                                                height: (8 * s).clamp(7.0, 9.0),
                                                decoration: BoxDecoration(
                                                  color: statusColor,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: capsuleBg,
                                                    width: 1.1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: (8 * s).clamp(6.0, 10.0),
                                      ),
                                      Flexible(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Estado de caja',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: labelTextStyle,
                                            ),
                                            SizedBox(
                                              height: (2.5 * s).clamp(2.0, 3.0),
                                            ),
                                            Text(
                                              isOpen && !isCompact
                                                  ? 'Caja abierta #$_openCashSessionId'
                                                  : cashLabel,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: valueTextStyle,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: (9 * s).clamp(7.0, 11.0)),
                        Container(
                          width: 1,
                          height: (topbarHeight * 0.42).clamp(16.0, 26.0),
                          decoration: BoxDecoration(
                            color: appBarFg.withOpacity(0.16),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        SizedBox(width: (9 * s).clamp(7.0, 11.0)),
                        Flexible(
                          flex: 5,
                          child: Tooltip(
                            message:
                                '$profileName · @${(_username ?? 'usuario').trim()}',
                            waitDuration: const Duration(milliseconds: 350),
                            child: PopupMenuButton<_UserMenuAction>(
                              tooltip: '',
                              offset: const Offset(0, 10),
                              onSelected: _handleUserMenuAction,
                              itemBuilder: (context) {
                                final canCash = _canAccessCash;
                                final canHistory = _canViewCashHistory || canCash;
                                final canFinishShift = _canCloseShift;
                                final canViewCurrentCut =
                                    canCash || _canCloseShift || _canOpenCashbox;
                                final hasShift = _openCashSessionId != null;
                                final warn = status?.warning ?? scheme.tertiary;

                                Widget row(
                                  IconData icon,
                                  String text, {
                                  Color? color,
                                  FontWeight? weight,
                                }) {
                                  final effectiveColor =
                                      color ?? Theme.of(context).colorScheme.onSurface;
                                  return Row(
                                    children: [
                                      Icon(icon, size: 18, color: effectiveColor),
                                      const SizedBox(width: 10),
                                      Text(
                                        text,
                                        style: TextStyle(
                                          color: effectiveColor,
                                          fontWeight: weight ?? FontWeight.w700,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                return [
                                  PopupMenuItem(
                                    value: _UserMenuAction.profile,
                                    child: row(
                                      Icons.person_outline_rounded,
                                      'Perfil',
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: _UserMenuAction.finishShift,
                                    enabled: canFinishShift && hasShift,
                                    child: row(
                                      Icons.flag_outlined,
                                      'Finalizar turno',
                                      color: warn,
                                      weight: FontWeight.w900,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: _UserMenuAction.viewCurrentCut,
                                    enabled: canViewCurrentCut,
                                    child: row(
                                      Icons.receipt_long_outlined,
                                      'Ver corte actual',
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: _UserMenuAction.cutHistory,
                                    enabled: canHistory,
                                    child: row(
                                      Icons.history_rounded,
                                      'Historial de cortes',
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: _UserMenuAction.logout,
                                    child: row(
                                      Icons.logout_rounded,
                                      'Cerrar sesión',
                                      color: scheme.error,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                ];
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                decoration: BoxDecoration(
                                  color: neutralSectionTint,
                                  borderRadius: BorderRadius.circular(
                                    sectionRadius,
                                  ),
                                  border: Border.all(color: sectionStroke),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: sectionHorizontalPadding,
                                  vertical: sectionVerticalPadding,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: brandAccent.withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: CircleAvatar(
                                        radius: (13 * s).clamp(11.0, 13.0),
                                        backgroundColor: brandAccent,
                                        backgroundImage: _profileImagePath != null
                                            ? FileImage(
                                                File(_profileImagePath!),
                                              )
                                            : null,
                                        child: _profileImagePath == null
                                            ? Icon(
                                                Icons.person,
                                                size: (12 * s).clamp(
                                                  10.0,
                                                  12.0,
                                                ),
                                                color:
                                                    ColorUtils.ensureReadableColor(
                                                  scheme.onPrimary,
                                                  brandAccent,
                                                ),
                                              )
                                            : null,
                                      ),
                                    ),
                                    SizedBox(
                                      width: (8 * s).clamp(6.0, 10.0),
                                    ),
                                    Flexible(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Usuario activo',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: labelTextStyle,
                                          ),
                                          SizedBox(
                                            height: (2.5 * s).clamp(2.0, 3.0),
                                          ),
                                          Text(
                                            profileName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: valueTextStyle,
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: (4 * s).clamp(3.0, 6.0),
                                    ),
                                    Container(
                                      width: (22 * s).clamp(20.0, 24.0),
                                      height: (22 * s).clamp(20.0, 24.0),
                                      decoration: BoxDecoration(
                                        color: brandAccent.withOpacity(0.10),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.expand_more_rounded,
                                        size: (14 * s).clamp(12.0, 16.0),
                                        color: brandAccent,
                                      ),
                                    ),
                                  ],
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
              ),
              SizedBox(width: spaceM),
            ],
          ),
        );
      },
    );
  }
}
