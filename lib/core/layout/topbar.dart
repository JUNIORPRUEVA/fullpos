import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_sizes.dart';
import '../theme/app_status_theme.dart';
import '../theme/color_utils.dart';
import '../session/session_manager.dart';
import '../window/window_service.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/cash/data/cash_repository.dart';
import '../../features/cash/ui/cash_open_dialog.dart';
import '../../features/cash/ui/cash_panel_sheet.dart';
import '../../features/settings/providers/theme_provider.dart';

/// Topbar del layout principal con fecha/hora y usuario
class Topbar extends ConsumerStatefulWidget {
  final bool showMenuButton;
  final VoidCallback? onMenuPressed;
  final double scale;
  final bool showBottomBorder;

  const Topbar({
    super.key,
    this.showMenuButton = false,
    this.onMenuPressed,
    this.scale = 1.0,
    this.showBottomBorder = true,
  });

  @override
  ConsumerState<Topbar> createState() => _TopbarState();
}

class _TopbarState extends ConsumerState<Topbar> {
  late Timer _cashTimer;
  StreamSubscription<void>? _sessionSub;
  String? _username;
  String? _displayName;

  bool _canAccessCash = false;
  int? _openCashSessionId;

  Future<void> _logout() async {
    await SessionManager.logout();
    if (mounted) context.go('/login');
  }

  Future<void> _minimize() async {
    await WindowService.minimize();
  }

  Future<void> _closeApp() async {
    await WindowService.close();
  }

  @override
  void initState() {
    super.initState();
    _loadUserSummary();
    _sessionSub = SessionManager.changes.listen((_) {
      if (!mounted) return;
      _loadUserSummary();
      _loadCashAccess();
      _loadOpenCashSessionId();
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
    _cashTimer.cancel();
    _sessionSub?.cancel();
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
    try {
      final id = await CashRepository.getCurrentSessionId();
      if (mounted) setState(() => _openCashSessionId = id);
    } catch (_) {
      // Si falla, no bloquear la UI
    }
  }

  Future<void> _onCashPressed() async {
    // Re-validar estado al momento del click
    final sessionId = await CashRepository.getCurrentSessionId();

    if (!mounted) return;

    if (sessionId != null) {
      await CashPanelSheet.show(context, sessionId: sessionId);
      await _loadOpenCashSessionId();
      return;
    }

    final opened = await CashOpenDialog.show(context);

    if (!mounted) return;
    if (opened == true) {
      final newSessionId = await CashRepository.getCurrentSessionId();

      if (!mounted) return;
      if (newSessionId != null) {
        await CashPanelSheet.show(context, sessionId: newSessionId);
      }
      await _loadOpenCashSessionId();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(themeProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final appBarBg = settings.appBarColor;
    final appBarFg = ColorUtils.ensureReadableColor(
      settings.appBarTextColor,
      appBarBg,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 900;
        final s = widget.scale.clamp(0.85, 1.12);
        final topbarHeight = (AppSizes.topbarHeight * s).clamp(52.0, 72.0);
        final padM = AppSizes.paddingM * s;
        final padL = AppSizes.paddingL * s;
        final spaceS = AppSizes.spaceS * s;
        final spaceM = AppSizes.spaceM * s;
        final radiusM = AppSizes.radiusM * s;

        Widget cashControl() {
          final isOpen = _openCashSessionId != null;
          final statusColor = isOpen
              ? (status?.success ?? scheme.tertiary)
              : (status?.error ?? scheme.error);

          final tooltip = isOpen
              ? 'Caja abierta (turno #$_openCashSessionId)\nClic para ver panel'
              : 'Caja cerrada\nClic para abrir';

          // Botón compacto (solo ícono) para una Topbar más limpia.
          final icon = isOpen ? Icons.lock_open_outlined : Icons.lock_outline;
          final btnSize = (40 * s).clamp(36.0, 44.0);
          final iconSize = (20 * s).clamp(18.0, 22.0);
          final bg = Color.alphaBlend(
            scheme.surface.withValues(alpha: 0.72),
            appBarBg.withValues(alpha: 0.18),
          );
          final border = scheme.outlineVariant.withValues(alpha: 0.35);

          return Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 350),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _onCashPressed,
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: btnSize,
                  height: btnSize,
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: iconSize, color: statusColor),
                ),
              ),
            ),
          );
        }

        Widget actionIconButton({
          required IconData icon,
          required String tooltip,
          required VoidCallback onTap,
          Color? customFg,
          Color? customBg,
        }) {
          final btnSize = (40 * s).clamp(36.0, 44.0);
          final iconSize = (20 * s).clamp(18.0, 22.0);
          final bg =
              customBg ??
              Color.alphaBlend(
                scheme.surface.withValues(alpha: 0.72),
                appBarBg.withValues(alpha: 0.18),
              );
          final border = scheme.outlineVariant.withValues(alpha: 0.35);
          final fg = customFg ?? ColorUtils.ensureReadableColor(appBarFg, bg);

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
                    border: Border.all(color: border, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.16),
                        blurRadius: 10,
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

        Widget rightInfoCluster() {
          final userLabel = (_displayName ?? _username ?? 'Usuario').trim();

          final clusterBg = Color.alphaBlend(
            scheme.surface.withValues(alpha: 0.70),
            appBarBg.withValues(alpha: 0.20),
          );
          final clusterBorder = scheme.outlineVariant.withValues(alpha: 0.45);
          final clusterFg = ColorUtils.ensureReadableColor(appBarFg, clusterBg);
          final clusterRadius = (radiusM * 1.05).clamp(10.0, 16.0);
          final vPad = (AppSizes.paddingXS * s).clamp(4.0, 7.0);
          final hPad = (padM * 0.75).clamp(10.0, 16.0);

          final nameMaxWidth = (isCompact ? 140.0 : 260.0) * s;
          final nameStyle = TextStyle(
            color: clusterFg,
            fontSize: (13.5 * s).clamp(12.0, 15.0),
            fontWeight: FontWeight.w800,
            fontFamily: settings.fontFamily,
            height: 1.05,
          );

          return Container(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            decoration: BoxDecoration(
              color: clusterBg,
              borderRadius: BorderRadius.circular(clusterRadius),
              border: Border.all(color: clusterBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.14),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: nameMaxWidth),
                  child: Text(
                    userLabel.isNotEmpty ? userLabel : 'Usuario',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nameStyle,
                  ),
                ),
                SizedBox(width: spaceS),
                actionIconButton(
                  icon: Icons.person_outline,
                  tooltip: 'Perfil',
                  onTap: () => context.go('/account'),
                ),
              ],
            ),
          );
        }

        Widget windowControls() {
          if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
            return const SizedBox.shrink();
          }

          return Row(
            children: [
              actionIconButton(
                icon: Icons.remove,
                tooltip: 'Minimizar',
                onTap: _minimize,
                customFg: appBarFg,
                customBg: Colors.transparent,
              ),
              SizedBox(width: spaceS),
              actionIconButton(
                icon: Icons.logout,
                tooltip: 'Cerrar sesión',
                onTap: _logout,
                customFg: scheme.error,
                customBg: Colors.transparent,
              ),
              SizedBox(width: spaceS),
              actionIconButton(
                icon: Icons.close,
                tooltip: 'Cerrar aplicación',
                onTap: _closeApp,
                customFg: scheme.error,
                customBg: Colors.transparent,
              ),
            ],
          );
        }

        return Container(
          height: topbarHeight,
          decoration: BoxDecoration(
            color: appBarBg,
            border: widget.showBottomBorder
                ? Border(
                    bottom: BorderSide(
                      color: scheme.primary.withValues(alpha: 0.35),
                      width: 2,
                    ),
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: scheme.surface.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, -2),
                spreadRadius: -1,
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(horizontal: isCompact ? padM : padL),
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
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: appBarFg,
                    fontSize: ((isCompact ? 18 : 20) * s).clamp(16.0, 22.0),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.35,
                    height: 1.05,
                    // Evita que una fuente configurada "rara" se vea fea en el título.
                    // En Windows, Segoe UI suele verse muy profesional.
                    fontFamilyFallback: const ['Segoe UI', 'Roboto', 'Arial'],
                  ),
                ),
              ),
              if (_canAccessCash) ...[
                SizedBox(width: spaceS),
                cashControl(),
                SizedBox(width: spaceM),
                Container(
                  width: 1,
                  height: (topbarHeight * 0.60).clamp(28.0, 44.0),
                  decoration: BoxDecoration(
                    color: appBarFg.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                SizedBox(width: spaceM),
              ],
              rightInfoCluster(),
              SizedBox(width: spaceS),
              windowControls(),
            ],
          ),
        );
      },
    );
  }
}
