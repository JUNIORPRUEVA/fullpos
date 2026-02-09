import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_gradient_theme.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../data/purchase_order_models.dart';
import '../data/purchases_repository.dart';

class PurchaseOrdersListPage extends StatefulWidget {
  const PurchaseOrdersListPage({super.key});

  @override
  State<PurchaseOrdersListPage> createState() => _PurchaseOrdersListPageState();
}

class _PurchaseOrdersListPageState extends State<PurchaseOrdersListPage> {
  final PurchasesRepository _repo = PurchasesRepository();

  bool _loading = true;
  String? _error;
  List<PurchaseOrderSummaryDto> _orders = const [];

  Future<void> _deleteOrder(int orderId) async {
    try {
      await _repo.deleteOrder(orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Orden eliminada')));
      await _load();
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _deleteOrder(orderId),
        module: 'purchases/delete',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _repo.listOrders();
      if (!mounted) return;
      setState(() {
        _orders = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirmAndDelete(int orderId) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar orden'),
          content: const Text(
            'Seguro que deseas eliminar esta orden? Esta accion no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;
    await _deleteOrder(orderId);
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final currency = NumberFormat('#,##0.00', 'en_US');
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();
    final gradientTheme = theme.extension<AppGradientTheme>();
    final headerGradient =
        gradientTheme?.backgroundGradient ??
        LinearGradient(
          colors: [
            scheme.surface,
            scheme.surfaceVariant,
            scheme.primaryContainer,
          ],
          stops: const [0.0, 0.65, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    final gradientMid = gradientTheme?.mid ?? scheme.surfaceVariant;
    final headerTextColor = ColorUtils.ensureReadableColor(
      scheme.onSurface,
      gradientMid,
    );

    Color statusColor(bool isReceived) => isReceived
        ? (status?.success ?? scheme.tertiary)
        : (status?.warning ?? scheme.secondary);

    Widget buildHeader(double horizontalPadding) {
      Widget icon() {
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: headerTextColor.withOpacity(0.08),
            shape: BoxShape.circle,
            border: Border.all(color: headerTextColor.withOpacity(0.25)),
          ),
          child: Icon(
            Icons.inventory_2_outlined,
            color: headerTextColor,
            size: 22,
          ),
        );
      }

      Widget infoChip(String label, String value) {
        final chipBg = Color.alphaBlend(
          scheme.surface.withOpacity(0.75),
          gradientMid.withOpacity(0.22),
        );
        final chipFg = ColorUtils.ensureReadableColor(headerTextColor, chipBg);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: chipBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: headerTextColor.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: chipFg.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: chipFg,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: headerGradient,
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.18),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 12,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 820;
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _load,
                  style: IconButton.styleFrom(
                    foregroundColor: headerTextColor,
                    backgroundColor: headerTextColor.withOpacity(0.08),
                  ),
                  icon: const Icon(Icons.refresh),
                ),
                FilledButton.icon(
                  onPressed: () => context.go('/purchases/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Crear'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.go('/purchases/auto'),
                  icon: const Icon(Icons.auto_awesome_motion),
                  label: const Text('Stock minimo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: headerTextColor,
                    side: BorderSide(color: headerTextColor.withOpacity(0.35)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    textStyle: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );

            final titleSection = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ordenes',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: headerTextColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    infoChip('Total', _orders.length.toString()),
                    if (_loading) infoChip('Estado', 'Actualizando'),
                  ],
                ),
              ],
            );

            if (isCompact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      icon(),
                      const SizedBox(width: 10),
                      Expanded(child: titleSection),
                    ],
                  ),
                  const SizedBox(height: 12),
                  actions,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                icon(),
                const SizedBox(width: 12),
                Expanded(child: titleSection),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      );
    }

    Widget buildEmpty(double horizontalPadding) {
      final iconColor = scheme.onSurface.withOpacity(0.45);
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 32,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_cart_outlined, size: 72, color: iconColor),
              const SizedBox(height: 16),
              Text(
                'No hay ordenes',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Crea una nueva orden para comenzar',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.go('/purchases/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Crear orden manual'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/purchases/auto'),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Crear por stock minimo'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    Widget buildError(double horizontalPadding) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 24,
        ),
        child: Card(
          color: scheme.errorContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: scheme.onErrorContainer,
                  size: 32,
                ),
                const SizedBox(height: 10),
                Text(
                  'No se pudo cargar la lista',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _error ?? 'Error desconocido',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                  style: FilledButton.styleFrom(
                    foregroundColor: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildOrderCard(PurchaseOrderSummaryDto summary) {
      final order = summary.order;
      final created = DateTime.fromMillisecondsSinceEpoch(order.createdAtMs);
      final isReceived = order.status.toUpperCase() == 'RECIBIDA';
      final accent = statusColor(isReceived);
      final badgeBg = accent.withOpacity(0.12);
      final badgeFg = ColorUtils.ensureReadableColor(accent, badgeBg);

      return Card(
        elevation: 2,
        shadowColor: theme.shadowColor.withOpacity(0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.4)),
                ),
                child: Icon(
                  isReceived
                      ? Icons.inventory_2_rounded
                      : Icons.local_shipping_outlined,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Orden #${order.id ?? '-'} - ${summary.supplierName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${dateFormat.format(created)} - ${order.status} - Total: ${currency.format(order.total)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isReceived ? 'Recibida' : 'Pendiente',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: badgeFg,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (order.isAuto == 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Generada por stock minimo',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: ColorUtils.ensureReadableColor(
                                  scheme.onSecondaryContainer,
                                  scheme.secondaryContainer,
                                ),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  PopupMenuButton<String>(
                    tooltip: 'Acciones',
                    onSelected: (value) async {
                      final orderId = order.id;
                      if (orderId == null) return;
                      switch (value) {
                        case 'details':
                          context.go('/purchases/receive/$orderId');
                          break;
                        case 'edit':
                          context.go('/purchases/edit/$orderId');
                          break;
                        case 'delete':
                          await _confirmAndDelete(orderId);
                          break;
                      }
                    },
                    itemBuilder: (context) {
                      return [
                        const PopupMenuItem<String>(
                          value: 'details',
                          child: Text('Ver detalle'),
                        ),
                        PopupMenuItem<String>(
                          value: 'edit',
                          enabled: !isReceived,
                          child: const Text('Editar'),
                        ),
                        PopupMenuItem<String>(
                          value: 'delete',
                          enabled: !isReceived,
                          child: const Text('Eliminar'),
                        ),
                      ];
                    },
                    icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      );
    }

    Widget buildBody(double horizontalPadding, double cardSpacing) {
      if (_loading) {
        return Padding(
          padding: EdgeInsets.all(horizontalPadding),
          child: Center(
            child: CircularProgressIndicator(color: scheme.primary),
          ),
        );
      }

      if (_error != null) return buildError(horizontalPadding);

      if (_orders.isEmpty) return buildEmpty(horizontalPadding);

      return ListView.separated(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          cardSpacing,
          horizontalPadding,
          cardSpacing + 8,
        ),
        itemCount: _orders.length,
        separatorBuilder: (_, index) => SizedBox(height: cardSpacing),
        itemBuilder: (context, index) => buildOrderCard(_orders[index]),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = (constraints.maxWidth * 0.045)
                .clamp(12.0, 28.0)
                .toDouble();
            final cardSpacing = (constraints.maxWidth * 0.015)
                .clamp(8.0, 16.0)
                .toDouble();

            return Container(
              color: Colors.transparent,
              child: Column(
                children: [
                  buildHeader(horizontalPadding),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Card(
                          margin: EdgeInsets.symmetric(
                            horizontal: horizontalPadding,
                            vertical: cardSpacing,
                          ),
                          color: scheme.surface,
                          elevation: 2,
                          shadowColor: theme.shadowColor.withOpacity(0.14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(
                              color: scheme.outlineVariant.withOpacity(0.5),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: buildBody(horizontalPadding, cardSpacing),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
