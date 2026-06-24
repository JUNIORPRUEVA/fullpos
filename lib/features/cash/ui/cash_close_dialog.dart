// ignore_for_file: unused_element, unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/printing/models/company_info.dart';
import '../../../core/printing/models/ticket_layout_config.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/update/cash_close_activity_tracker.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authz/authz_service.dart';
import '../../../core/security/authz/permission.dart' as authz_perm;
import '../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../../core/utils/accounting_amount_formatter.dart';
import '../../../core/utils/currency_display.dart';
import '../../auth/services/logout_flow_service.dart';
import '../../settings/data/printer_settings_repository.dart';
import '../../settings/providers/theme_provider.dart';
import '../data/cash_movement_model.dart';
import '../data/cash_summary_model.dart';
import '../data/cash_repository.dart';
import '../data/cash_session_model.dart';
import '../data/session_close_ticket_composer.dart';
import '../data/cashbox_daily_model.dart';
import '../data/operation_flow_service.dart';
import '../providers/cash_providers.dart';

enum _SelectionKind { refund, movement }

/// Diálogo para cerrar la sesión operativa.
class CashCloseDialog extends ConsumerStatefulWidget {
  final int sessionId;
  final bool logoutAfterClose;
  final bool autoCloseImmediately;
  final CashSummaryModel? initialSummary;
  final CashSessionModel? initialSession;
  final List<CashMovementModel>? initialMovements;

  const CashCloseDialog({
    super.key,
    required this.sessionId,
    this.logoutAfterClose = true,
    this.autoCloseImmediately = false,
    this.initialSummary,
    this.initialSession,
    this.initialMovements,
  });

  static Future<bool?> show(
    BuildContext context, {
    required int sessionId,
    bool logoutAfterClose = true,
    bool autoCloseImmediately = false,
    CashSummaryModel? initialSummary,
    CashSessionModel? initialSession,
    List<CashMovementModel>? initialMovements,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CashCloseDialog(
        sessionId: sessionId,
        logoutAfterClose: logoutAfterClose,
        autoCloseImmediately: autoCloseImmediately,
        initialSummary: initialSummary,
        initialSession: initialSession,
        initialMovements: initialMovements,
      ),
    );
  }

  @override
  ConsumerState<CashCloseDialog> createState() => _CashCloseDialogState();
}

class _CashCloseDialogState extends ConsumerState<CashCloseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _closingAmountController = TextEditingController();
  final _noteController = TextEditingController();

  // Cache de formateadores/regex para evitar recrearlos en cada build.
  late final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  late final DateFormat _timeOnlyFormat = DateFormat('HH:mm');
  late final DateFormat _dateTimeShortFormat = DateFormat('dd/MM HH:mm');
  static final RegExp _ticketSanitizeRegExp = RegExp(
    r'''[^A-Za-z0-9\s\-_/.:,()#%+*&@'"'>$<]+''',
  );

  bool _isLoading = false;
  CashSummaryModel? _summary;
  bool _loadingSummary = true;
  CashSessionModel? _session;
  CashboxDailyModel? _cashboxDaily;
  List<Map<String, dynamic>> _refunds = [];
  bool _loadingRefunds = true;
  int? _selectedRefundIndex;

  List<CashMovementModel> _movements = [];
  bool _loadingMovements = true;
  int? _selectedMovementIndex;
  _SelectionKind? _selectedKind;
  List<CategoryCashSummary> _categorySummary = [];
  List<RefundItemByCategory> _refundItemsByCategory = [];
  List<TransferItemByCategory> _transferItemsByCategory = [];
  bool _loadingCategorySummary = true;
  bool _autoCloseTriggered = false;

  void _openCashHistory() {
    Navigator.of(context).pop(false);
    final rootContext = ErrorHandler.navigatorKey.currentContext;
    if (rootContext == null) return;
    GoRouter.of(rootContext).go('/cash/history');
  }

  @override
  void initState() {
    super.initState();
    _summary = widget.initialSummary;
    _session = widget.initialSession;
    _movements = widget.initialMovements == null
        ? []
        : List<CashMovementModel>.from(widget.initialMovements!);
    _loadingSummary = widget.initialSummary == null;
    _loadingMovements = widget.initialMovements == null;

    if (_loadingSummary) {
      _loadSummary();
    }
    if (widget.initialSession == null) {
      _loadSession();
    }
    _loadRefunds();
    if (_loadingMovements) {
      _loadMovements();
    }
    _loadCategorySummary();

    if (widget.autoCloseImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerAutoCloseIfReady();
      });
    }
  }

  void _triggerAutoCloseIfReady() {
    if (!mounted || _autoCloseTriggered || _isLoading || _loadingSummary) {
      return;
    }
    if (_summary == null) {
      return;
    }

    _autoCloseTriggered = true;
    unawaited(_closeCash());
  }

  Future<void> _loadSession() async {
    try {
      final session = await CashRepository.getSessionById(widget.sessionId);

      // FULLPOS SEGURIDAD: verificar que el turno pertenece al usuario actual.
      if (session != null) {
        final currentUserId = await SessionManager.userId();
        if (currentUserId != null && session.userId != currentUserId) {
          if (mounted) {
            Navigator.of(context).pop();
            final messenger = ScaffoldMessenger.maybeOf(context);
            messenger?.showSnackBar(
              SnackBar(
                content: const Text(
                  'Este turno pertenece a otro usuario y no puede cerrarse desde aquí.',
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
          return;
        }
      }

      final cashboxDaily = await OperationFlowService.getDailyCashboxById(
        session?.cashboxDailyId,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _cashboxDaily = cashboxDaily;
      });
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadSummary() async {
    try {
      final summary = await CashRepository.buildSummary(
        sessionId: widget.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loadingSummary = false;
        // El efectivo contado es opcional: no prellenar para que el usuario
        // pueda dejarlo vacío y usar el efectivo esperado.
        if (_closingAmountController.text.trim().isEmpty) {
          _closingAmountController.text = '';
        }
      });
      _triggerAutoCloseIfReady();
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadingSummary = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadSummary,
        module: 'cash/summary',
      );
    }
  }

  Future<void> _loadRefunds() async {
    try {
      final refunds = await CashRepository.listRefundsForSession(
        widget.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _refunds = refunds;
        if (refunds.isEmpty) {
          _selectedRefundIndex = null;
          if (_selectedKind == _SelectionKind.refund) {
            _selectedKind = null;
          }
        } else {
          final current = _selectedRefundIndex;
          _selectedRefundIndex = (current != null && current < refunds.length)
              ? current
              : 0;
          _selectedKind ??= _SelectionKind.refund;
        }
        _loadingRefunds = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadingRefunds = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadRefunds,
        module: 'cash/refunds',
      );
    }
  }

  Future<void> _loadMovements() async {
    try {
      final movements = await CashRepository.listMovements(
        sessionId: widget.sessionId,
      );
      if (!mounted) return;
      setState(() {
        _movements = movements;
        if (movements.isEmpty) {
          _selectedMovementIndex = null;
          if (_selectedKind == _SelectionKind.movement) {
            _selectedKind = null;
          }
        } else {
          final current = _selectedMovementIndex;
          _selectedMovementIndex =
              (current != null && current < movements.length) ? current : 0;
          _selectedKind ??= _SelectionKind.movement;
        }
        _loadingMovements = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadingMovements = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadMovements,
        module: 'cash/movements',
      );
    }
  }

  Future<void> _loadCategorySummary() async {
    try {
      final results = await Future.wait([
        CashRepository.listCategorySummaryForSession(widget.sessionId),
        CashRepository.listRefundItemsByCategoryForSession(widget.sessionId),
        CashRepository.listTransferItemsByCategoryForSession(widget.sessionId),
      ]);
      final summary = results[0] as List<CategoryCashSummary>;
      final refundItems = results[1] as List<RefundItemByCategory>;
      final transferItems = results[2] as List<TransferItemByCategory>;
      if (!mounted) return;
      setState(() {
        _categorySummary = summary;
        _refundItemsByCategory = refundItems;
        _transferItemsByCategory = transferItems;
        _loadingCategorySummary = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadingCategorySummary = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadCategorySummary,
        module: 'cash/category_summary',
      );
    }
  }

  @override
  void dispose() {
    _closingAmountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double get _closingAmount {
    final raw = _closingAmountController.text.trim();
    final parsed = raw.isEmpty ? null : AccountingAmountFormatter.parse(raw);
    if (parsed != null) return parsed;
    return _summary?.expectedCash ?? 0.0;
  }

  double get _difference {
    if (_summary == null) return 0.0;
    return _closingAmount - _summary!.expectedCash;
  }

  Future<void> _closeCash() async {
    if (!widget.autoCloseImmediately) {
      final formState = _formKey.currentState;
      if (formState != null && !formState.validate()) return;
    }

    if (widget.autoCloseImmediately) {
      final currentUser = await AuthzService.currentUser();
      final canClose =
          currentUser != null &&
          AuthzService.can(
            currentUser,
            authz_perm.Permission.action(AppActions.closeSession),
          );
      if (!canClose) {
        if (mounted) {
          final messenger = ScaffoldMessenger.maybeOf(
            ErrorHandler.navigatorKey.currentState?.overlay?.context ??
                ErrorHandler.navigatorKey.currentContext ??
                context,
          );
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('No tienes permiso para cerrar este turno.'),
            ),
          );
          Navigator.of(context).maybePop(false);
        }
        return;
      }
    } else {
      final ok = await AuthzService.runGuardedCurrent<bool>(
        context,
        authz_perm.Permission.action(AppActions.closeSession),
        () async => true,
        reason: 'Cerrar sesión',
        resourceType: 'cash_session',
        resourceId: widget.sessionId.toString(),
      );
      if (ok != true) return;
    }
    if (!mounted) return;

    setState(() => _isLoading = true);
    CashCloseActivityTracker.instance.markClosingStarted();

    try {
      final closeNote = _noteController.text.trim();
      final closedSummary = await OperationFlowService.closeActiveSession(
        sessionId: widget.sessionId,
        closingAmount: _closingAmount,
        note: closeNote,
      );
      await ref.read(activeSessionControllerProvider.notifier).refresh();

      final summaryForPrint = _summary ?? closedSummary;
      final appContext =
          ErrorHandler.navigatorKey.currentState?.overlay?.context ??
          ErrorHandler.navigatorKey.currentContext ??
          Navigator.of(context, rootNavigator: true).context;

      if (widget.logoutAfterClose) {
        Object? printError;
        try {
          await _printClosingArtifacts(
            summary: summaryForPrint,
            closingAmount: _closingAmount,
            note: closeNote,
          );
        } catch (error) {
          printError = error;
          debugPrint('Cierre de turno completado sin ticket impreso: $error');
        }

        if (mounted) Navigator.of(context).pop(true);
        await LogoutFlowService.defaultPerformLogout(appContext);

        if (printError != null) {
          final logoutContext =
              ErrorHandler.navigatorKey.currentState?.overlay?.context ??
              ErrorHandler.navigatorKey.currentContext;
          if (logoutContext != null && logoutContext.mounted) {
            ScaffoldMessenger.maybeOf(logoutContext)?.showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 8),
                content: const Text(
                  'El turno se cerró correctamente, pero no se pudo imprimir '
                  'el comprobante. Revisa la impresora y vuelve a imprimirlo '
                  'desde el historial de caja.',
                ),
                backgroundColor: Theme.of(logoutContext).colorScheme.error,
              ),
            );
          }
        }
        return;
      }

      Navigator.of(context).pop(true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          _printClosingArtifacts(
            summary: summaryForPrint,
            closingAmount: _closingAmount,
            note: closeNote,
          ).catchError((Object error, StackTrace stackTrace) {
            final messenger = ScaffoldMessenger.maybeOf(appContext);
            if (messenger == null) return;
            messenger.showSnackBar(
              SnackBar(
                content: const Text(
                  'El turno se cerró correctamente, pero no se pudo imprimir '
                  'el comprobante. Revisa la impresora y vuelve a imprimirlo '
                  'desde el historial de caja.',
                ),
                backgroundColor: Theme.of(messenger.context).colorScheme.error,
              ),
            );
          }),
        );

        final messenger = ScaffoldMessenger.maybeOf(appContext);
        if (messenger == null) return;
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Sesión cerrada correctamente'),
            backgroundColor: Theme.of(messenger.context).colorScheme.primary,
          ),
        );
      });
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _closeCash,
          module: 'cash/close',
        );
      }
    } finally {
      CashCloseActivityTracker.instance.markClosingCompleted();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printClosingArtifacts({
    required CashSummaryModel summary,
    required double closingAmount,
    required String note,
  }) async {
    final session = await CashRepository.getSessionById(widget.sessionId);
    if (session == null) return;

    await _printClosingTicket(
      session: session,
      summary: summary,
      closingAmount: closingAmount,
      note: note,
    );
  }

  Future<void> _printClosingTicket({
    required CashSessionModel session,
    required CashSummaryModel summary,
    required double closingAmount,
    required String note,
  }) async {
    final results = await Future.wait([
      CashRepository.listMovements(sessionId: widget.sessionId),
      CashRepository.listCategorySummaryForSession(widget.sessionId),
      CashRepository.listSoldProductsForSession(widget.sessionId),
      CashRepository.listRefundItemsByCategoryForSession(widget.sessionId),
      PrinterSettingsRepository.getOrCreate(),
      CompanyInfoRepository.getCurrentCompanyInfo(),
    ]);
    final movements = results[0] as List<CashMovementModel>;
    final categorySummary = results[1] as List<CategoryCashSummary>;
    final soldProducts = results[2] as List<SoldProductCashSummary>;
    final refundItems = results[3] as List<RefundItemByCategory>;
    final settings = results[4] as dynamic;
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    final company = results[5] as CompanyInfo;

    final lines = SessionCloseTicketComposer.buildLines(
      layout: layout,
      companyName: company.name,
      companyRnc: company.rnc,
      companyPhone: company.primaryPhone,
      session: session,
      summary: summary,
      closingAmount: closingAmount,
      note: note,
      movements: movements,
      cashboxInitialAmount: _cashboxDaily?.initialAmount,
      categorySummary: categorySummary,
      soldProducts: soldProducts,
      refundItems: refundItems,
    );

    final result = await UnifiedTicketPrinter.printCustomLines(
      lines: lines,
      ticketNumber: 'CASH-${widget.sessionId}',
      includeLogo: true,
      overrideCopies: 1,
      layoutOverride: layout,
    );

    if (!result.success) {
      throw Exception(result.message);
    }
  }

  String _sanitizeTicketText(String input) {
    final s = input
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('ñ', 'n')
        .replaceAll('Ñ', 'N')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'U')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'C');

    final filtered = s.replaceAll(_ticketSanitizeRegExp, '');
    return filtered.trim();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    if (widget.autoCloseImmediately) {
      return const Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.zero,
        child: SizedBox.shrink(),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(themeProvider);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final safeWidth = (screenSize.width - 20).clamp(260.0, 520.0);
    final safeHeight = (screenSize.height - viewInsets.vertical - 20).clamp(
      240.0,
      420.0,
    );
    final dialogWidth = (screenSize.width * 0.20).clamp(260.0, safeWidth);
    final dialogHeight = (screenSize.height * 0.30).clamp(250.0, safeHeight);
    final sidebarColor = settings.sidebarColor;
    final sidebarAccent = settings.sidebarActiveColor;
    final sidebarText = ColorUtils.ensureReadableColor(
      settings.sidebarTextColor,
      sidebarColor,
    );
    final money = CurrencyDisplay.currency();
    final summary = _summary;
    final session = _session;
    final expectedCash = money.format(summary?.expectedCash ?? 0.0);
    final totalSold = money.format(summary?.totalSold ?? 0.0);
    final tickets = '${summary?.totalTickets ?? 0}';
    final openedAt = session == null
        ? '--'
        : _dateTimeShortFormat.format(session.openedAt);

    return DialogKeyboardShortcuts(
      onSubmit: _isLoading ? null : _closeCash,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: (screenSize.width * 0.02).clamp(10.0, 28.0),
          vertical: (screenSize.height * 0.02).clamp(10.0, 24.0),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.92, end: 1.0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.scale(scale: value, child: child),
            );
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              maxHeight: dialogHeight,
              minWidth: 260,
              minHeight: 250,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: sidebarAccent.withOpacity(0.34),
                  width: 1.2,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.alphaBlend(
                      sidebarColor.withOpacity(0.24),
                      scheme.surface,
                    ),
                    Color.alphaBlend(
                      sidebarAccent.withOpacity(0.10),
                      scheme.surface,
                    ),
                    scheme.surface,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: sidebarColor.withOpacity(0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _loadingSummary
                  ? Center(
                      child: CircularProgressIndicator(color: sidebarAccent),
                    )
                  : Form(
                      key: _formKey,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Color.alphaBlend(
                                      sidebarAccent.withOpacity(0.16),
                                      scheme.surface,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    Icons.task_alt_rounded,
                                    color: sidebarAccent,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Cierre de turno',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              color: scheme.onSurface,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Resumen simple del cierre.',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurface
                                                  .withOpacity(0.66),
                                              fontSize: 10.5,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () => Navigator.pop(context),
                                  icon: Icon(
                                    Icons.close,
                                    color: scheme.onSurface.withOpacity(0.64),
                                    size: 18,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Color.alphaBlend(
                                  sidebarColor.withOpacity(0.12),
                                  scheme.surfaceContainerHighest,
                                ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: sidebarAccent.withOpacity(0.18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    totalSold,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                          color: scheme.onSurface,
                                        ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Total vendido del turno',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurface.withOpacity(0.66),
                                      fontSize: 10.4,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Efectivo esperado: $expectedCash',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: sidebarAccent,
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildStatChip(
                                  session?.userName ?? 'Cajero',
                                  'Cajero',
                                  sidebarAccent,
                                  fg: sidebarText,
                                  fontFamily: settings.fontFamily,
                                ),
                                _buildStatChip(
                                  tickets,
                                  'Tickets',
                                  sidebarAccent,
                                  fg: sidebarText,
                                  fontFamily: settings.fontFamily,
                                ),
                                _buildStatChip(
                                  totalSold,
                                  'Total vendido',
                                  scheme.tertiary,
                                  fg: sidebarText,
                                  fontFamily: settings.fontFamily,
                                ),
                                _buildStatChip(
                                  openedAt,
                                  'Apertura',
                                  scheme.secondary,
                                  fg: sidebarText,
                                  fontFamily: settings.fontFamily,
                                ),
                              ],
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _isLoading
                                        ? null
                                        : _openCashHistory,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: scheme.primary,
                                      side: BorderSide(
                                        color: scheme.primary.withOpacity(0.28),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.history_outlined,
                                      size: 16,
                                    ),
                                    label: const Text(
                                      'Ver cortes',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : () => Navigator.pop(context),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: scheme.onSurface,
                                      side: BorderSide(
                                        color: scheme.outlineVariant,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: const Text('Cancelar'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoading ? null : _closeCash,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: sidebarAccent,
                                      foregroundColor:
                                          ColorUtils.readableTextColor(
                                            sidebarAccent,
                                          ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    icon: _isLoading
                                        ? SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    ColorUtils.readableTextColor(
                                                      sidebarAccent,
                                                    ),
                                                  ),
                                            ),
                                          )
                                        : const Icon(
                                            Icons.check_circle_outline,
                                            size: 16,
                                          ),
                                    label: const Text(
                                      'Confirmar cierre',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

  Widget _buildStatChip(
    String value,
    String label,
    Color color, {
    Color? fg,
    String? fontFamily,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: fontFamily,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: (fg ?? color).withOpacity(0.7),
              fontSize: 10,
              fontFamily: fontFamily,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundsList({
    required Color bg,
    required Color fg,
    required Color accent,
    String? fontFamily,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = CurrencyDisplay.currency();
    final dateFormat = _dateTimeShortFormat;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _refunds.length,
      separatorBuilder: (_, index) => Divider(
        height: 10,
        thickness: 1,
        color: scheme.outlineVariant.withOpacity(0.35),
      ),
      itemBuilder: (context, index) {
        final refund = _refunds[index];
        final selected =
            _selectedKind == _SelectionKind.refund &&
            _selectedRefundIndex == index;

        final amount = (refund['total'] as num?)?.toDouble().abs() ?? 0.0;
        const previewLimit = 3;
        final productsPreview =
            (refund['products_preview'] as String?)?.trim() ?? '';
        final firstProductName =
            (refund['first_product_name'] as String?)?.trim() ?? '';
        final itemCount = (refund['item_count'] as int?) ?? 0;
        final createdAt = DateTime.fromMillisecondsSinceEpoch(
          refund['created_at_ms'] as int,
        );
        final returnCode = (refund['return_code'] as String?)?.trim() ?? '';

        final productLabel = productsPreview.isNotEmpty
            ? productsPreview
            : (firstProductName.isNotEmpty ? firstProductName : 'Devolución');
        final remaining = productsPreview.isNotEmpty
            ? (itemCount - previewLimit)
            : (itemCount - 1);
        final suffix = remaining > 0 ? ' (+$remaining)' : '';

        final tileBg = selected
            ? Color.alphaBlend(scheme.primary.withOpacity(0.14), bg)
            : bg;
        final tileBorder = selected
            ? scheme.primary.withOpacity(0.55)
            : scheme.outlineVariant.withOpacity(0.25);
        final tileFg = ColorUtils.ensureReadableColor(fg, tileBg);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedKind = _SelectionKind.refund;
                _selectedRefundIndex = index;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tileBorder, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$productLabel$suffix',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tileFg,
                              fontWeight: FontWeight.w800,
                              fontFamily: fontFamily,
                              height: 1.05,
                            ),
                          ),
                          TextSpan(
                            text: '  •  ${dateFormat.format(createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tileFg.withOpacity(0.75),
                              fontFamily: fontFamily,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                            ),
                          ),
                          if (returnCode.isNotEmpty)
                            TextSpan(
                              text: '  •  Ref: $returnCode',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tileFg.withOpacity(0.75),
                                fontFamily: fontFamily,
                                fontWeight: FontWeight.w700,
                                height: 1.05,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent.withOpacity(0.18)),
                    ),
                    child: Text(
                      currency.format(amount),
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        fontFamily: fontFamily,
                        letterSpacing: 0.2,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMovementsList({
    required Color bg,
    required Color fg,
    required Color accent,
    String? fontFamily,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = CurrencyDisplay.currency();
    final timeFormat = _dateTimeShortFormat;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: _movements.length,
      separatorBuilder: (_, index) => Divider(
        height: 10,
        thickness: 1,
        color: scheme.outlineVariant.withOpacity(0.35),
      ),
      itemBuilder: (context, index) {
        final m = _movements[index];
        final selected =
            _selectedKind == _SelectionKind.movement &&
            _selectedMovementIndex == index;

        final movementColor = m.isIn
            ? (scheme.tertiary)
            : ColorUtils.ensureReadableColor(scheme.error, bg);

        final tileBg = selected
            ? Color.alphaBlend(scheme.primary.withOpacity(0.14), bg)
            : bg;
        final tileBorder = selected
            ? scheme.primary.withOpacity(0.55)
            : scheme.outlineVariant.withOpacity(0.25);
        final tileFg = ColorUtils.ensureReadableColor(fg, tileBg);

        final sign = m.isIn ? '+' : '-';
        final amountText = '$sign${currency.format(m.amount)}';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedKind = _SelectionKind.movement;
                _selectedMovementIndex = index;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tileBorder, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: movementColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: (m.reason.trim().isEmpty
                                ? 'Movimiento'
                                : m.reason.trim()),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: tileFg,
                              fontWeight: FontWeight.w800,
                              fontFamily: fontFamily,
                              height: 1.05,
                            ),
                          ),
                          TextSpan(
                            text: '  •  ${timeFormat.format(m.createdAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: tileFg.withOpacity(0.75),
                              fontFamily: fontFamily,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: movementColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: movementColor.withOpacity(0.18),
                      ),
                    ),
                    child: Text(
                      amountText,
                      style: TextStyle(
                        color: movementColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        fontFamily: fontFamily,
                        letterSpacing: 0.2,
                        height: 1.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
