import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/utils/currency_display.dart';
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
   
   String _searchQuery = '';
   String _orderFilter = 'all'; // all, pending, received, auto

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
  final currency = CurrencyDisplay.currency();
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final status = theme.extension<AppStatusTheme>();

  Color statusColor(bool isReceived) => isReceived
      ? (status?.success ?? scheme.tertiary)
      : (status?.warning ?? scheme.secondary);

  final filteredOrders = _orders.where((summary) {
    final order = summary.order;
    final query = _searchQuery.trim().toLowerCase();
    final supplier = summary.supplierName.toLowerCase();
    final orderNumber = 'orden #${order.id ?? ''}'.toLowerCase();
    final isReceived = order.status.toUpperCase() == 'RECIBIDA';

    final matchesSearch =
        query.isEmpty ||
        supplier.contains(query) ||
        orderNumber.contains(query) ||
        order.status.toLowerCase().contains(query);

    final matchesFilter = switch (_orderFilter) {
      'pending' => !isReceived,
      'received' => isReceived,
      'auto' => order.isAuto == 1,
      _ => true,
    };

    return matchesSearch && matchesFilter;
  }).toList();

  Widget buildTopControls() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Buscar orden de compra',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: scheme.primary, width: 1.2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          tooltip: 'Filtrar',
          position: PopupMenuPosition.under,
          onSelected: (value) => setState(() => _orderFilter = value),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'all', child: Text('Todas')),
            PopupMenuItem(value: 'pending', child: Text('Pendientes')),
            PopupMenuItem(value: 'received', child: Text('Recibidas')),
            PopupMenuItem(value: 'auto', child: Text('Stock mínimo')),
          ],
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 19, color: scheme.onSurface),
                const SizedBox(width: 8),
                const Text(
                  'Filtro',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildOrderCard(PurchaseOrderSummaryDto summary) {
    final order = summary.order;
    final created = DateTime.fromMillisecondsSinceEpoch(order.createdAtMs);
    final isReceived = order.status.toUpperCase() == 'RECIBIDA';
    final accent = statusColor(isReceived);

    return InkWell(
      onTap: order.id == null
          ? null
          : () => context.go('/purchases/receive/${order.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withOpacity(0.8)),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 18,
              child: Text(
                'Orden #${order.id ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 28,
              child: Text(
                summary.supplierName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface.withOpacity(0.72),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              flex: 22,
              child: Text(
                dateFormat.format(created),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              flex: 15,
              child: Text(
                isReceived ? 'Recibida' : 'Pendiente',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: accent, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              flex: 18,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  currency.format(order.total),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 34,
              child: PopupMenuButton<String>(
                tooltip: 'Acciones',
                padding: EdgeInsets.zero,
                position: PopupMenuPosition.under,
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
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'details',
                    child: Text('Ver detalle'),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    enabled: !isReceived,
                    child: const Text('Editar'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    enabled: !isReceived,
                    child: const Text('Eliminar'),
                  ),
                ],
                icon: Icon(
                  Icons.more_horiz_rounded,
                  color: scheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildBody() {
    if (_loading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Expanded(
        child: Center(child: Text('No se pudo cargar la lista')),
      );
    }

    if (filteredOrders.isEmpty) {
      return Expanded(
        child: Center(child: Text('No hay órdenes disponibles')),
      );
    }

    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        itemCount: filteredOrders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => buildOrderCard(filteredOrders[index]),
      ),
    );
  }

  return Scaffold(
    backgroundColor: const Color(0xFFF3F6F9),
    body: SafeArea(
      bottom: false,
      child: Center(
        child: SizedBox(
          width: 1550,
          height: 950,
          child: Container(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 26),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant.withOpacity(0.8)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Órdenes de compra',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${filteredOrders.length} registros encontrados',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                buildTopControls(),
                buildBody(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
