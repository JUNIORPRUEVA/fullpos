import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_sizes.dart';
import '../theme/app_status_theme.dart';
import '../theme/color_utils.dart';
import '../session/session_manager.dart';
import '../session/ui_preferences.dart';
import '../window/window_service.dart';
import '../../features/settings/providers/theme_provider.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/cash/data/operation_flow_service.dart';
import '../../features/cash/ui/cash_open_dialog.dart';
import '../../features/cash/ui/cash_close_dialog.dart';
import '../../features/cash/ui/cash_panel_sheet.dart';

/// Topbar del layout principal con fecha/hora y usuario
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
  int? _openCashSessionId;
  bool _loadingOpenCashSessionId = false;
  bool _isCashHover = false;

  Future<void> _minimize() async {
    await WindowService.minimize();
  }

  Future<void> _closeApp() async {
    // Con sesión activa no se permite salir sin cierre.
    if (_openCashSessionId != null) {
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sesión activa'),
          content: Text(
            'La sesión #$_openCashSessionId sigue activa. Debes cerrarla antes de salir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'close_session'),
              child: const Text('Cerrar sesión'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      );

      if (action == 'close_session') {
        final sessionId = _openCashSessionId;
        if (sessionId == null || !context.mounted) return;

        final closed = await CashCloseDialog.show(
          context,
          sessionId: sessionId,
          logoutAfterClose: true,
        );
        await _loadOpenCashSessionId();
        if (!context.mounted) return;

        if (closed == true) return;
        return;
      }

      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar aplicación'),
        content: const Text('¿Estás seguro que deseas cerrar la aplicación?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Cerrar aplicación'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await WindowService.close();
    }
  }

  @override
  void initState() {
    super.initState();
    _cashPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _cashPulseController?.repeat(reverse: true);
    _loadUserSummary();
    _loadProfileImage();
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
    _loadCashAccess();
    _loadOpenCashSessionId();

    // Refrescar estado de caja sin recargar la UI completa (cada 10s)
    _cashTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadOpenCashSessionId();
    });
  }

  @override
  void dispose() {
    _cashPulseController?.dispose();
    _cashPulseController = null;
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
      _displayName = (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : null;
    });
  }

  String? _buildUserKey({required int? userId, required String? username}) {
    if (userId != null) return 'id:$userId';
    final u = username?.trim();
    if (u == null || u.isEmpty) return null;
    return 'u:$u';
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
      final perms = await AuthRepository.getCurrentPermissions();
      final isAdmin = await AuthRepository.isAdmin();
      final allowed = isAdmin || perms.canOpenCash || perms.canCloseCash;
      if (mounted) {
        setState(() => _canAccessCash = allowed);
      }
    } catch (_) {
      if (mounted) setState(() => _canAccessCash = false);
    }
  }

  Future<void> _loadOpenCashSessionId() async {
    if (_loadingOpenCashSessionId) return;
    _loadingOpenCashSessionId = true;
    try {
      final id = (await OperationFlowService.loadActiveSession())?.shiftId;
      if (!mounted) return;

      // Evitar rebuilds innecesarios si no hay cambios.
      if (id == _openCashSessionId) return;
      setState(() => _openCashSessionId = id);
    } catch (_) {
      // Si falla, no bloquear la UI
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

    // Re-validar estado al momento del click solo si no hay cache local.
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
    final themeSettings = ref.watch(themeProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final appBarBg = themeSettings.topbarColor;
    final appBarFg = ColorUtils.ensureReadableColor(
      themeSettings.topbarTextColor,
      appBarBg,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        final s = widget.scale.clamp(0.85, 1.12);
        final topbarHeight = (AppSizes.topbarHeight * s).clamp(46.0, 66.0);
        final topInset = (widget.topPadding * s).clamp(0.0, 12.0);
        final padM = AppSizes.paddingM * s;
        final padL = AppSizes.paddingL * s;
        final spaceS = AppSizes.spaceS * s;
        final spaceM = AppSizes.spaceM * s;
        final horizontalPad = ((isCompact ? padM : padL) * 0.75).clamp(
          10.0,
          20.0,
        );

        Widget actionIconButton({
          required IconData icon,
          required String tooltip,
          required VoidCallback onTap,
          Color? customFg,
          Color? customBg,
          Color? borderColor,
          double borderWidth = 0.0,
        }) {
          final btnSize = (36 * s).clamp(32.0, 40.0);
          final iconSize = (18 * s).clamp(16.0, 20.0);
          final bg =
              customBg ??
              Color.alphaBlend(
                scheme.surface.withValues(alpha: 0.72),
                appBarBg.withValues(alpha: 0.18),
              );
          final border =
              borderColor ?? scheme.outlineVariant.withValues(alpha: 0.25);
          final fg = customFg ?? ColorUtils.ensureReadableColor(appBarFg, bg);

          final shadowAlpha = borderWidth > 0 ? 0.12 : 0.06;
          final blur = borderWidth > 0 ? 10.0 : 6.0;

          return Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 350),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: btnSize,
                  height: btnSize,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                    border: borderWidth > 0
                        ? Border.all(color: border, width: borderWidth)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: shadowAlpha),
                        blurRadius: blur,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: iconSize, color: fg),
                ),
              ),
            ),
          );
        }

        Widget windowControls() {
          if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
            return const SizedBox.shrink();
          }

          final winBtnBg = Color.alphaBlend(
            scheme.surface.withValues(alpha: 0.12),
            appBarBg.withValues(alpha: 0.06),
          );
          // Borde ligeramente más oscuro para un look más profesional
          final winBtnBorder = appBarFg.withValues(alpha: 0.28);

          return Row(
            children: [
              actionIconButton(
                icon: Icons.remove,
                tooltip: 'Minimizar',
                onTap: _minimize,
                customFg: appBarFg,
                customBg: winBtnBg,
                borderColor: winBtnBorder,
                borderWidth: 1.2,
              ),
              SizedBox(width: spaceS * 0.6),
              actionIconButton(
                icon: Icons.close,
                tooltip: 'Cerrar aplicación',
                onTap: _closeApp,
                customFg: scheme.error,
                customBg: winBtnBg,
                borderColor: winBtnBorder,
                borderWidth: 1.2,
              ),
            ],
          );
        }

        return Container(
          height: topbarHeight + topInset,
          decoration: BoxDecoration(
            color: appBarBg,
            border: widget.showBottomBorder
                ? Border(
                    bottom: BorderSide(
                      color: appBarFg.withValues(alpha: 0.16),
                      width: 1,
                    ),
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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

              // Icono de estado de caja (caja de dinero realista) — colocado antes del perfil
              Builder(
                builder: (context) {
                  final isOpen = _openCashSessionId != null;
                  final statusColor = isOpen
                      ? (status?.success ?? scheme.tertiary)
                      : (status?.error ?? scheme.error);
                  final tooltipBase = isOpen
                      ? 'Sesión activa (#$_openCashSessionId)\nClic para ver panel'
                      : 'Sin sesión activa\nClic para abrir caja';
                  final tooltip = _canAccessCash
                      ? tooltipBase
                      : '$tooltipBase\nSi no tienes permiso, te pedirá autorización (PIN).';

                  final boxBg = Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.10),
                    appBarBg.withValues(alpha: 0.08),
                  );
                  final boxBorder = isOpen
                      ? statusColor.withValues(alpha: 0.45)
                      : appBarFg.withValues(alpha: 0.22);
                  final hoverBg = Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.16),
                    appBarBg.withValues(alpha: 0.12),
                  );
                  final hoverBorder = Colors.white.withValues(alpha: 0.3);
                  final pulse = CurvedAnimation(
                    parent: _cashPulseController ?? kAlwaysDismissedAnimation,
                    curve: Curves.easeInOut,
                  );

                  return Tooltip(
                    message: tooltip,
                    waitDuration: const Duration(milliseconds: 350),
                    child: AnimatedBuilder(
                      animation: pulse,
                      builder: (context, child) {
                        final pulseValue = isOpen && !_isCashHover
                            ? pulse.value
                            : 0.0;
                        final scale = 1.0 + (pulseValue * 0.03);

                        return Transform.scale(scale: scale, child: child);
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => setState(() => _isCashHover = true),
                        onExit: (_) => setState(() => _isCashHover = false),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: _onCashPressed,
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: EdgeInsets.symmetric(
                                horizontal: 10.0 * s,
                                vertical: 7.0 * s,
                              ),
                              decoration: BoxDecoration(
                                color: _isCashHover ? hoverBg : boxBg,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _isCashHover
                                      ? hoverBorder
                                      : (isOpen
                                            ? statusColor.withValues(
                                                alpha: 0.72,
                                              )
                                            : boxBorder),
                                  width: isOpen ? 1.25 : 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (isOpen ? statusColor : scheme.shadow)
                                            .withValues(
                                              alpha: isOpen
                                                  ? (_isCashHover ? 0.22 : 0.18)
                                                  : (_isCashHover
                                                        ? 0.12
                                                        : 0.06),
                                            ),
                                    blurRadius: isOpen
                                        ? (_isCashHover ? 18 : 14)
                                        : (_isCashHover ? 12 : 8),
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Icon(
                                        isOpen
                                            ? Icons.account_balance_wallet
                                            : Icons.inventory_2_rounded,
                                        size: (19 * s).clamp(17.0, 24.0),
                                        color: appBarFg.withValues(
                                          alpha: _isCashHover ? 1.0 : 0.96,
                                        ),
                                      ),
                                      if (isOpen)
                                        Positioned(
                                          top: -5 * s,
                                          right: -5 * s,
                                          child: Container(
                                            padding: EdgeInsets.all(3.0 * s),
                                            decoration: BoxDecoration(
                                              color: statusColor,
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: statusColor.withValues(
                                                    alpha: 0.24,
                                                  ),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              Icons.attach_money,
                                              size: (10 * s).clamp(9.0, 12.0),
                                              color: scheme.onPrimary,
                                            ),
                                          ),
                                        )
                                      else
                                        Positioned(
                                          top: -5 * s,
                                          right: -5 * s,
                                          child: Container(
                                            padding: EdgeInsets.all(3.0 * s),
                                            decoration: BoxDecoration(
                                              color: appBarFg.withValues(
                                                alpha: 0.10,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.lock_outline,
                                              size: (10 * s).clamp(9.0, 12.0),
                                              color: appBarFg.withValues(
                                                alpha: 0.70,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  SizedBox(width: (8 * s).clamp(6.0, 10.0)),
                                  Text(
                                    isOpen ? 'Corte' : 'Caja',
                                    style: TextStyle(
                                      color: appBarFg,
                                      fontSize: (11.5 * s).clamp(10.0, 12.5),
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.15,
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
                },
              ),

              SizedBox(width: spaceS / 1.5),
              // Línea vertical elegante separando icono de caja y perfil/nombre
              Container(
                width: 1,
                height: (topbarHeight * 0.52).clamp(20.0, 34.0),
                decoration: BoxDecoration(
                  color: appBarFg.withValues(alpha: 0.20),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              SizedBox(width: spaceM),
              Tooltip(
                message: 'Perfil',
                waitDuration: const Duration(milliseconds: 350),
                child: InkWell(
                  onTap: () => context.go('/account'),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: (isCompact ? 160.0 : 240.0) * s,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: (12 * s).clamp(10.0, 14.0),
                      vertical: (8 * s).clamp(7.0, 10.0),
                    ),
                    decoration: BoxDecoration(
                      color: appBarFg.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: appBarFg.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: (14 * s).clamp(12.0, 14.0),
                          backgroundColor: scheme.secondary,
                          backgroundImage: (_profileImagePath != null)
                              ? FileImage(File(_profileImagePath!))
                              : null,
                          child: (_profileImagePath == null)
                              ? Icon(
                                  Icons.person,
                                  size: (14 * s).clamp(12.0, 14.0),
                                  color: ColorUtils.ensureReadableColor(
                                    scheme.onSecondary,
                                    scheme.secondary,
                                  ),
                                )
                              : null,
                        ),
                        SizedBox(width: (8 * s).clamp(6.0, 10.0)),
                        Flexible(
                          child: Text(
                            (_displayName ?? _username ?? 'Usuario').trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: appBarFg,
                              fontSize: (13.5 * s).clamp(12.0, 14.5),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: spaceM),
              SizedBox(width: spaceS * 1.2),
              // Window controls at the corner
              windowControls(),
            ],
          ),
        );
      },
    );
  }
}
