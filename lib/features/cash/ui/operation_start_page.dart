import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/window/window_service.dart';
import '../../auth/data/auth_repository.dart';
import '../../settings/data/user_model.dart';
import '../data/daily_cash_close_ticket_printer.dart';
import '../data/operation_flow_service.dart';
import 'cashbox_open_dialog.dart';

class OperationStartPage extends StatefulWidget {
  const OperationStartPage({super.key});

  @override
  State<OperationStartPage> createState() => _OperationStartPageState();
}

class _OperationStartPageState extends State<OperationStartPage> {
  OperationGateState? _state;
  UserPermissions _permissions = UserPermissions.none();
  bool _isLoading = true;
  bool _isWorking = false;

  String _formatDateTimeDo(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    final date = DateFormat('dd/MM/yyyy', 'es_DO').format(dt);
    final time = DateFormat('hh:mm a', 'es_DO').format(dt).toUpperCase();
    return '$date $time';
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final gate = await OperationFlowService.loadGateState();
    final perms = await AuthRepository.getCurrentPermissions();
    if (!mounted) return;
    setState(() {
      _state = gate;
      _permissions = perms;
      _isLoading = false;
    });
  }

  Future<void> _onEnterOperate() async {
    if (_isWorking) return;
    setState(() => _isWorking = true);

    try {
      await _reload();
      final state = _state;
      if (state == null) return;

      if (state.hasStaleShift) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Turno abierto por más de 48 horas'),
            content: const Text(
              'Este turno tiene más de 48 horas abierto. Debes hacer el corte para continuar.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/cash?closeShift=1');
                },
                child: const Text('Hacer corte'),
              ),
            ],
          ),
        );
        return;
      }

      // Si ya tiene turno abierto, continuar en ese mismo turno.
      if (state.hasUserShiftOpen) {
        if (!mounted) return;
        context.go('/sales');
        return;
      }

      final cashboxReady = await _ensureCashboxOpen();
      if (!cashboxReady) return;

      final shiftReady = await _ensureShiftOpen();
      if (!shiftReady) return;

      final ready = await _reloadGateOnly();
      if (ready?.canOperate == true && mounted) {
        context.go('/sales');
      }
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<bool> _promptOpenCashbox() async {
    final canOpen = _permissions.canOpenCashbox || _permissions.canOpenCash;
    final amount = await CashboxOpenDialog.show(
      context: context,
      canOpen: canOpen,
      title: 'Abrir caja del día',
      subtitle:
          'No hay una caja abierta hoy. Registra el fondo inicial para continuar.',
      confirmLabel: 'Abrir caja',
      deniedMessage: 'Requiere supervisor/admin para abrir caja.',
    );
    if (amount == null) return false;

    try {
      await OperationFlowService.openDailyCashboxToday(
        openingAmount: amount,
        note: 'Apertura desde Iniciar operación',
      );
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return false;
    }
  }

  Future<OperationGateState?> _reloadGateOnly() async {
    final gate = await OperationFlowService.loadGateState();
    final perms = await AuthRepository.getCurrentPermissions();
    if (!mounted) return null;
    setState(() {
      _state = gate;
      _permissions = perms;
    });
    return gate;
  }

  Future<bool> _ensureCashboxOpen() async {
    final gate = await _reloadGateOnly();
    if (gate == null) return false;
    if (gate.hasCashboxTodayOpen) return true;

    final opened = await _promptOpenCashbox();
    if (!opened) return false;

    final latest = await _reloadGateOnly();
    return latest?.hasCashboxTodayOpen == true;
  }

  Future<bool> _ensureShiftOpen() async {
    final gate = await _reloadGateOnly();
    if (gate == null) return false;
    if (gate.hasUserShiftOpen) return true;

    final canOpenShift = _permissions.canOpenShift || _permissions.canOpenCash;
    if (!canOpenShift) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permiso para abrir turno.')),
      );
      return false;
    }

    try {
      await OperationFlowService.openShiftForCurrentUser();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return false;
    }

    final latest = await _reloadGateOnly();
    return latest?.hasUserShiftOpen == true;
  }

  Future<void> _closeCashboxFromStart() async {
    final canClose = _permissions.canCloseCashbox;
    if (!canClose) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Requiere supervisor/admin para cerrar caja.'),
        ),
      );
      return;
    }

    final current = _state;
    if (current?.hasUserShiftOpen == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se puede cerrar caja mientras exista un turno abierto.',
          ),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar caja (fin del día)'),
        content: const Text(
          'Este proceso cierra la caja del día y bloquea operar hasta abrir una nueva caja. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    final shouldPrint = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Imprimir ticket'),
        content: const Text(
          '¿Deseas imprimir el ticket de cierre de caja del día?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No imprimir'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Imprimir'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    final businessDate = OperationFlowService.businessDateOf();
    final cashboxBefore = await OperationFlowService.getDailyCashbox(
      businessDate,
    );
    final cashboxId = cashboxBefore?.id;

    try {
      await OperationFlowService.closeDailyCashboxToday(
        note: 'Cierre desde Iniciar operación',
      );

      if (shouldPrint == true && cashboxId != null) {
        try {
          await DailyCashCloseTicketPrinter.printDailyCloseTicket(
            cashboxDailyId: cashboxId,
            businessDate: businessDate,
            note: 'Cierre desde Iniciar operación',
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Caja cerrada, pero no se pudo imprimir: $e'),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caja del día cerrada correctamente.')),
      );
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradient = FullposBrandTheme.backgroundGradient;

    final onSurface = scheme.onSurface;
    final mutedText = onSurface.withOpacity(0.72);
    final cardBorder = scheme.primary.withOpacity(0.18);
    final dividerColor = scheme.onSurface.withOpacity(0.10);

    if (_isLoading) {
      return Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (!_isWorking) _onEnterOperate();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: scheme.surface,
              body: Container(
                decoration: BoxDecoration(gradient: gradient),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
        ),
      );
    }

    final state = _state;
    if (state == null) {
      return Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (!_isWorking) _onEnterOperate();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: scheme.surface,
              body: Container(
                decoration: BoxDecoration(gradient: gradient),
                child: Center(
                  child: ElevatedButton(
                    onPressed: _reload,
                    child: const Text('Reintentar'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final shift = state.userOpenShift;
    final cashbox = state.cashboxToday;
    final showCloseCashboxPrompt =
        cashbox?.isOpen == true && shift == null && !state.hasStaleShift;

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (!_isWorking) _onEnterOperate();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: scheme.surface,
            body: Container(
              decoration: BoxDecoration(gradient: gradient),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSizes.paddingL),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Card(
                      color: scheme.surface,
                      elevation: 14,
                      shadowColor: Colors.black.withOpacity(0.24),
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                        side: BorderSide(color: cardBorder),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: cardBorder),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    FullposBrandTheme.logoAsset,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) => Center(
                                          child: Icon(
                                            Icons.storefront,
                                            size: 36,
                                            color: scheme.primary,
                                          ),
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        FullposBrandTheme.appName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                              color: onSurface,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.2,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Iniciar operación',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(color: mutedText),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Minimizar',
                                  onPressed: _isWorking
                                      ? null
                                      : () => WindowService.minimize(),
                                  icon: const Icon(Icons.minimize_rounded),
                                ),
                                IconButton(
                                  tooltip: 'Cerrar aplicación',
                                  onPressed: _isWorking
                                      ? null
                                      : () => WindowService.close(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceVariant.withOpacity(0.40),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: dividerColor),
                              ),
                              child: Text(
                                'Valida caja diaria y turno antes de entrar al sistema.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: mutedText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.surfaceVariant.withOpacity(0.28),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: dividerColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Estado de CAJA',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    cashbox?.isOpen == true
                                        ? 'Abierta'
                                        : 'Cerrada',
                                  ),
                                  if (cashbox != null) ...[
                                    Text('Fecha: ${cashbox.businessDate}'),
                                    Text(
                                      'Apertura: ${_formatDateTimeDo(cashbox.openedAtMs)}',
                                    ),
                                    Text(
                                      'Fondo inicial: RD\$ ${cashbox.initialAmount.toStringAsFixed(2)}',
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.surfaceVariant.withOpacity(0.28),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: dividerColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Estado de TURNO',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    shift?.isOpen == true
                                        ? 'Abierto'
                                        : 'Cerrado',
                                  ),
                                  if (shift != null) ...[
                                    Text(
                                      'Apertura: ${_formatDateTimeDo(shift.openedAtMs)}',
                                    ),
                                  ],
                                  if (state.hasStaleShift)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Hay un turno anterior sin cerrar. Debes cerrarlo para continuar.',
                                        style: TextStyle(color: scheme.error),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),
                            if (showCloseCashboxPrompt) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: cardBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Caja abierta detectada',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: onSurface,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'No hay turno activo. ¿Deseas cerrar la caja del día?',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: mutedText),
                                    ),
                                    const SizedBox(height: 10),
                                    FilledButton.icon(
                                      onPressed: _isWorking
                                          ? null
                                          : () async {
                                              setState(() => _isWorking = true);
                                              try {
                                                await _closeCashboxFromStart();
                                              } finally {
                                                if (mounted) {
                                                  setState(
                                                    () => _isWorking = false,
                                                  );
                                                }
                                              }
                                            },
                                      icon: const Icon(
                                        Icons.lock_clock_outlined,
                                      ),
                                      label: const Text('Cerrar caja ahora'),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            FilledButton.icon(
                              onPressed: _isWorking ? null : _onEnterOperate,
                              icon: const Icon(Icons.login_rounded),
                              label: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: _isWorking
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                        ),
                                      )
                                    : const Text('Entrar a operar'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'El cierre de turno y cierre de caja se realizan dentro del módulo Caja y Corte.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: mutedText,
                              ),
                            ),
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
      ),
    );
  }
}
