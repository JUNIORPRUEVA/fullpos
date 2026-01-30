import 'package:flutter/material.dart';

import '../../clients/data/clients_repository.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/authz/authz_service.dart';
import '../../../core/security/authz/permission.dart';
import '../data/returns_repository.dart';
import '../data/sales_repository.dart';
import 'dialogs/refund_reason_dialog.dart';

class ReturnsPage extends StatefulWidget {
  const ReturnsPage({super.key});

  @override
  State<ReturnsPage> createState() => _ReturnsPageState();
}

class _ReturnsPageState extends State<ReturnsPage> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _loading = false;
  String _filterType = 'ticket_code';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _loading = true);

    try {
      late List<Map<String, dynamic>> results;

      if (_filterType == 'ticket_code') {
        final sales = await SalesRepository.searchSales(query);
        results = sales.map((s) => {'sale': s}).toList();
      } else {
        final clients = await ClientsRepository.search(query);
        results = [];
        for (final client in clients) {
          final sales = await SalesRepository.listSales(customerId: client.id);
          for (final sale in sales) {
            results.add({'sale': sale, 'client': client});
          }
        }
      }

      if (!mounted) return;
      setState(() => _searchResults = results);
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _search,
          module: 'sales/returns/search',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devoluciones'), elevation: 0),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText:
                          'Buscar por ${_filterType == 'ticket_code' ? 'código de venta' : 'cliente'}...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _filterType,
                  items: const [
                    DropdownMenuItem(value: 'ticket_code', child: Text('Código')),
                    DropdownMenuItem(value: 'client', child: Text('Cliente')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _filterType = value);
                    _search();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _searchResults.isEmpty
                    ? const Center(child: Text('Sin resultados'))
                    : ListView.builder(
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final item = _searchResults[index];
                          final sale = item['sale'];
                          return _ReturnCard(sale: sale);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ReturnCard extends StatefulWidget {
  final dynamic sale;

  const _ReturnCard({required this.sale});

  @override
  State<_ReturnCard> createState() => _ReturnCardState();
}

class _ReturnCardState extends State<_ReturnCard> {
  bool _expanded = false;
  bool _loading = false;
  List<dynamic> _items = [];

  Future<void> _loadItems() async {
    if (_expanded) {
      setState(() => _expanded = false);
      return;
    }

    setState(() => _loading = true);
    try {
      _items = await SalesRepository.getItemsBySaleId(widget.sale.id);
      if (!mounted) return;
      setState(() => _expanded = true);
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _loadItems,
          module: 'sales/returns/items',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleReturn(dynamic item) async {
    await AuthzService.runGuardedCurrent<void>(
      context,
      Permissions.processReturn,
      () async {
        final motivo = await showRefundReasonDialog(context);
        if (motivo == null || motivo.trim().isEmpty) return;

        await ReturnsRepository.createReturn(
          originalSaleId: widget.sale.id,
          returnItems: [
            {
              'sale_item_id': item.id,
              'product_id': item.productId,
              'description': item.productNameSnapshot,
              'qty': item.qty,
              'price': item.unitPrice,
            },
          ],
          note: motivo.trim(),
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Devolución registrada')),
        );
      },
      reason: 'Procesar devolución',
      resourceType: 'sale',
      resourceId: widget.sale.id?.toString(),
      isOnline: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.receipt),
            title: Text(widget.sale.localCode ?? 'N/A'),
            subtitle: Text(
              '${widget.sale.customerNameSnapshot ?? 'S/C'} - \$${widget.sale.total.toStringAsFixed(2)}',
            ),
            trailing: IconButton(
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              onPressed: _loadItems,
            ),
          ),
          if (_expanded)
            _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                : Column(
                    children: [
                      const Divider(height: 1),
                      ..._items.map(
                        (item) => Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.productNameSnapshot ?? 'Item',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${item.qty} x \$${item.unitPrice.toStringAsFixed(2)}',
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () => _handleReturn(item),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: scheme.tertiary,
                                  foregroundColor: scheme.onTertiary,
                                ),
                                child: const Text('Devolver'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
        ],
      ),
    );
  }
}
