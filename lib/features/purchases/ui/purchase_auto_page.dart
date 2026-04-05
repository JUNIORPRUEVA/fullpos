import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/utils/currency_display.dart';
import '../../settings/data/business_settings_repository.dart';
import '../providers/purchase_draft_provider.dart';
import '../services/purchase_order_auto_service.dart';
import 'widgets/purchase_ticket_panel.dart';
import 'widgets/purchase_ui.dart';
import '../../products/models/product_model.dart';

enum PurchaseAutoStrategy { stockMin, outOfStock, recentSales }

class PurchaseAutoPage extends ConsumerStatefulWidget {
  const PurchaseAutoPage({super.key});

  @override
  ConsumerState<PurchaseAutoPage> createState() => _PurchaseAutoPageState();
}

class _PurchaseAutoPageState extends ConsumerState<PurchaseAutoPage> {
  final PurchaseOrderAutoService _service = PurchaseOrderAutoService();

  PurchaseAutoStrategy _strategy = PurchaseAutoStrategy.stockMin;
  bool _loading = false;
  String? _error;

  int _lookbackDays = 30;
  int _replenishDays = 14;
  double _minQty = 1;

  List<PurchaseOrderAutoSuggestion> _suggestions = const [];

  BoxConstraints _ticketPanelConstraints(double width) {
    if (width < 1350) {
      final max = (width * 0.38).clamp(320.0, 450.0);
      final min = (max - 80).clamp(300.0, max);
      return BoxConstraints(minWidth: min, maxWidth: max);
    }
    if (width < 1600) {
      final max = (width * 0.35).clamp(400.0, 520.0);
      final min = (max - 90).clamp(360.0, max);
      return BoxConstraints(minWidth: min, maxWidth: max);
    }
    final max = (width * 0.33).clamp(460.0, 600.0);
    final min = (max - 100).clamp(380.0, max);
    return BoxConstraints(minWidth: min, maxWidth: max);
  }

  @override
  void initState() {
    super.initState();
    _loadDefaultTax();
  }

  Future<void> _loadDefaultTax() async {
    final repo = BusinessSettingsRepository();
    final tax = await repo.getDefaultTaxRate();
    if (!mounted) return;
    ref.read(purchaseDraftProvider.notifier).setTaxRatePercent(tax);
  }

  Future<void> _buildSuggestions() async {
    final supplier = ref.read(purchaseDraftProvider).supplier;
    if (supplier?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione un proveedor'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _suggestions = const [];
    });

    try {
      final id = supplier!.id!;
      final list = switch (_strategy) {
        PurchaseAutoStrategy.stockMin => await _service.suggestBySupplier(
          supplierId: id,
        ),
        PurchaseAutoStrategy.outOfStock => await _service.suggestOutOfStock(
          supplierId: id,
          minQty: _minQty,
        ),
        PurchaseAutoStrategy.recentSales => await _service.suggestByRecentSales(
          supplierId: id,
          lookbackDays: _lookbackDays,
          replenishDays: _replenishDays,
          minQty: _minQty,
        ),
      };

      if (!mounted) return;
      setState(() {
        _suggestions = list;
      });

      if (list.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay sugerencias con los criterios actuales'),
            backgroundColor: AppColors.info,
          ),
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      final ex = await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _buildSuggestions,
        module: 'purchases/v2/auto/suggest',
      );
      if (!mounted) return;
      setState(() {
        _error = ex.messageUser;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addSuggestion(PurchaseOrderAutoSuggestion s) {
    final fakeProduct = ProductModel(
      id: s.productId,
      code: s.productCode,
      name: s.productName,
      purchasePrice: s.unitCost,
      salePrice: 0,
      stock: s.currentStock,
      stockMin: s.minStock,
      isActive: true,
      createdAtMs: 0,
      updatedAtMs: 0,
    );

    ref
        .read(purchaseDraftProvider.notifier)
        .addProduct(fakeProduct, qty: s.suggestedQty, unitCost: s.unitCost);
  }

  void _addAllSuggestions() {
    for (final s in _suggestions) {
      _addSuggestion(s);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Agregadas ${_suggestions.length} sugerencias al ticket'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = CurrencyDisplay.currency();

    Widget strategySelector() {
      return DropdownButtonFormField<PurchaseAutoStrategy>(
        value: _strategy,
        decoration: const InputDecoration(
          labelText: 'Estrategia',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: const [
          DropdownMenuItem(
            value: PurchaseAutoStrategy.stockMin,
            child: Text('Mínimo de stock'),
          ),
          DropdownMenuItem(
            value: PurchaseAutoStrategy.outOfStock,
            child: Text('Productos agotados'),
          ),
          DropdownMenuItem(
            value: PurchaseAutoStrategy.recentSales,
            child: Text('Ventas recientes'),
          ),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _strategy = v;
            _suggestions = const [];
          });
        },
      );
    }

    Widget configRow() {
      final fields = <Widget>[];

      fields.add(
        Expanded(
          child: TextFormField(
            initialValue: _minQty.toStringAsFixed(0),
            decoration: const InputDecoration(
              labelText: 'Cantidad mínima',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            onChanged: (v) {
              final parsed = double.tryParse(v.replaceAll(',', '.'));
              if (parsed == null) return;
              _minQty = parsed <= 0 ? 1 : parsed;
            },
          ),
        ),
      );

      if (_strategy == PurchaseAutoStrategy.recentSales) {
        fields.add(const SizedBox(width: 10));
        fields.add(
          Expanded(
            child: TextFormField(
              initialValue: _lookbackDays.toString(),
              decoration: const InputDecoration(
                labelText: 'Días (histórico)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed == null) return;
                _lookbackDays = parsed <= 0 ? 1 : parsed;
              },
            ),
          ),
        );
        fields.add(const SizedBox(width: 10));
        fields.add(
          Expanded(
            child: TextFormField(
              initialValue: _replenishDays.toString(),
              decoration: const InputDecoration(
                labelText: 'Días (reponer)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed == null) return;
                _replenishDays = parsed <= 0 ? 1 : parsed;
              },
            ),
          ),
        );
      }

      return Row(children: fields);
    }

    Widget suggestionsList() {
      if (_loading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_error != null) {
        return Center(
          child: Text(_error!, style: TextStyle(color: scheme.error)),
        );
      }
      if (_suggestions.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.paddingL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 44, color: scheme.primary),
                const SizedBox(height: 10),
                Text(
                  'Genera sugerencias',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Selecciona proveedor en el ticket y luego pulsa “Generar sugerencias”.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.only(bottom: AppSizes.paddingL),
        itemCount: _suggestions.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.45)),
        itemBuilder: (context, index) {
          final s = _suggestions[index];
          return ListTile(
            title: Text(
              '${s.productCode} • ${s.productName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Stock: ${s.currentStock.toStringAsFixed(2)}  •  Min: ${s.minStock.toStringAsFixed(2)}',
            ),
            trailing: SizedBox(
              width: 220,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Sug: ${s.suggestedQty.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Costo: ${currency.format(s.unitCost)}',
                        style: TextStyle(
                          color: scheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _addSuggestion(s),
                    child: const Text('Agregar'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    final leftPanel = Container(
      decoration: purchaseSectionDecoration(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sugerencias',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _buildSuggestions,
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Generar sugerencias'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Configura la estrategia, genera propuestas y envíalas al ticket lateral.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                strategySelector(),
                const SizedBox(height: 10),
                configRow(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _suggestions.isEmpty
                            ? null
                            : _addAllSuggestions,
                        icon: const Icon(Icons.playlist_add),
                        label: const Text('Agregar todo al ticket'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.45)),
          Expanded(child: suggestionsList()),
        ],
      ),
    );

    final ticket = PurchaseTicketPanel(
      onOrderCreated: (orderId) =>
          context.go('/purchases/orders?orderId=$orderId'),
      isAuto: true,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 10,
        title: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              IconButton(
                onPressed: () => context.go('/purchases'),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Volver',
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Text(
                'Compra Automática',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => context.go('/purchases'),
                icon: const Icon(Icons.edit_note_rounded, size: 16),
                label: const Text('Manual'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => context.go('/purchases/orders'),
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('Órdenes'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        toolbarHeight: 48,
      ),
      body: Padding(
        padding: kPurchasePagePadding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 1100;
            final ticketConstraints = _ticketPanelConstraints(
              constraints.maxWidth,
            );

            final wideTicket = ConstrainedBox(
              constraints: ticketConstraints,
              child: ticket,
            );

            final content = isNarrow
                ? Column(
                    children: [
                      Expanded(child: leftPanel),
                      const SizedBox(height: 12),
                      SizedBox(height: 520, child: ticket),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: leftPanel),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: ticketConstraints.maxWidth,
                        child: wideTicket,
                      ),
                    ],
                  );

            return Column(children: [Expanded(child: content)]);
          },
        ),
      ),
    );
  }
}
