import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../products/data/suppliers_repository.dart';
import '../../products/models/supplier_model.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/purchases_repository.dart';
import '../services/purchase_order_auto_service.dart';

class PurchaseOrderCreateAutoPage extends StatefulWidget {
  const PurchaseOrderCreateAutoPage({super.key});

  @override
  State<PurchaseOrderCreateAutoPage> createState() =>
      _PurchaseOrderCreateAutoPageState();
}

class _AutoLineDraft {
  final PurchaseOrderAutoSuggestion suggestion;
  double qty;
  double unitCost;

  _AutoLineDraft({
    required this.suggestion,
    required this.qty,
    required this.unitCost,
  });

  double get total => qty * unitCost;
}

class _PurchaseOrderCreateAutoPageState
    extends State<PurchaseOrderCreateAutoPage> {
  final SuppliersRepository _suppliersRepo = SuppliersRepository();
  final PurchaseOrderAutoService _autoService = PurchaseOrderAutoService();
  final PurchasesRepository _purchasesRepo = PurchasesRepository();
  final BusinessSettingsRepository _settingsRepo = BusinessSettingsRepository();
  final TextEditingController _notesCtrl = TextEditingController();

  bool _loading = true;
  bool _building = false;
  bool _saving = false;
  String? _error;

  List<SupplierModel> _suppliers = const [];
  SupplierModel? _supplier;
  double _taxRate = 18.0;
  bool _itbisEnabled = false;

  final List<_AutoLineDraft> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final suppliers = await _suppliersRepo.getAll(includeInactive: false);
      final tax = await _settingsRepo.getDefaultTaxRate();
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _taxRate = tax;
        _itbisEnabled = false;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      final ex = await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _load,
        module: 'purchases/auto/load',
      );
      if (!mounted) return;
      setState(() {
        _error = ex.messageUser;
        _loading = false;
      });
    }
  }

  double get _subtotal => _lines.fold(0.0, (s, l) => s + l.total);
  double get _effectiveTaxRate => _itbisEnabled ? _taxRate : 0.0;
  double get _tax => _subtotal * (_effectiveTaxRate / 100.0);
  double get _total => _subtotal + _tax;

  Future<void> _buildSuggestions() async {
    if (_supplier?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione un suplidor'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _building = true;
      _lines.clear();
    });

    try {
      final suggestions = await _autoService.suggestBySupplier(
        supplierId: _supplier!.id!,
      );
      if (!mounted) return;
      setState(() {
        _lines.addAll(
          suggestions.map(
            (s) => _AutoLineDraft(
              suggestion: s,
              qty: s.suggestedQty,
              unitCost: s.unitCost,
            ),
          ),
        );
      });

      if (_lines.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay productos por debajo del stock mínimo'),
            backgroundColor: AppColors.info,
          ),
        );
      }
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _buildSuggestions,
        module: 'purchases/auto/suggest',
      );
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<void> _createOrder() async {
    if (_supplier?.id == null) return;
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay líneas para crear la orden'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final orderId = await _purchasesRepo.createOrder(
        supplierId: _supplier!.id!,
        taxRatePercent: _effectiveTaxRate,
        isAuto: true,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        items: _lines
            .where((l) => l.qty > 0)
            .map(
              (l) => _purchasesRepo.itemInput(
                productId: l.suggestion.productId,
                productCodeSnapshot: l.suggestion.productCode,
                productNameSnapshot: l.suggestion.productName,
                qty: l.qty,
                unitCost: l.unitCost,
              ),
            )
            .toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Orden creada #$orderId'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/purchases');
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _createOrder,
        module: 'purchases/auto/create',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00', 'en_US');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          'Crear Orden (Stock mínimo)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        toolbarHeight: 48,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                'Error: $_error',
                style: const TextStyle(color: Colors.red),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(AppSizes.paddingL),
              child: Column(
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.surfaceLightBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSizes.paddingM),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: _supplier?.id,
                                  items: _suppliers
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s.id,
                                          child: Text(s.name),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    final s = _suppliers
                                        .where((e) => e.id == v)
                                        .cast<SupplierModel?>()
                                        .firstOrNull;
                                    setState(() {
                                      _supplier = s;
                                      _lines.clear();
                                    });
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'Suplidor',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 180,
                                child: TextFormField(
                                  initialValue: _taxRate.toStringAsFixed(2),
                                  enabled: _itbisEnabled,
                                  decoration: const InputDecoration(
                                    labelText: 'ITBIS %',
                                  ),
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (v) {
                                    final parsed = double.tryParse(
                                      v.replaceAll(',', '.'),
                                    );
                                    if (parsed == null) return;
                                    setState(() => _taxRate = parsed);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: _building || _saving
                                    ? null
                                    : _buildSuggestions,
                                icon: _building
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome),
                                label: Text(
                                  _building ? 'Calculando...' : 'Generar',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notesCtrl,
                            decoration: const InputDecoration(
                              labelText:
                                  'Nota importante para suplidor (opcional)',
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch.adaptive(
                                  value: _itbisEnabled,
                                  onChanged: _saving
                                      ? null
                                      : (v) => setState(
                                          () => _itbisEnabled = v,
                                        ),
                                ),
                                Text(
                                  _itbisEnabled
                                      ? 'Aplicar ITBIS (${_taxRate.toStringAsFixed(2)}%)'
                                      : 'Aplicar ITBIS',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.paddingM),
                  Expanded(
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: AppColors.surfaceLightBorder),
                      ),
                      child: _lines.isEmpty
                          ? Center(
                              child: Text(
                                'Genere sugerencias para ver productos',
                                style: TextStyle(
                                  color: AppColors.textDarkSecondary,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _lines.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final line = _lines[index];
                                final s = line.suggestion;
                                return ListTile(
                                  title: Text(
                                    '${s.productCode} • ${s.productName}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Stock: ${s.currentStock.toStringAsFixed(2)} • Mín: ${s.minStock.toStringAsFixed(2)} • Sugerido: ${s.suggestedQty.toStringAsFixed(2)}',
                                  ),
                                  trailing: SizedBox(
                                    width: 320,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        SizedBox(
                                          width: 120,
                                          child: TextFormField(
                                            initialValue: line.qty
                                                .toStringAsFixed(2),
                                            decoration: const InputDecoration(
                                              labelText: 'Cant.',
                                            ),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            onChanged: (v) {
                                              final parsed = double.tryParse(
                                                v.replaceAll(',', '.'),
                                              );
                                              if (parsed == null) return;
                                              setState(() => line.qty = parsed);
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        SizedBox(
                                          width: 140,
                                          child: TextFormField(
                                            initialValue: line.unitCost
                                                .toStringAsFixed(2),
                                            decoration: const InputDecoration(
                                              labelText: 'Costo',
                                            ),
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                ),
                                            onChanged: (v) {
                                              final parsed = double.tryParse(
                                                v.replaceAll(',', '.'),
                                              );
                                              if (parsed == null) return;
                                              setState(
                                                () => line.unitCost = parsed,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.paddingM),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppColors.surfaceLightBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSizes.paddingM),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Subtotal: ${currency.format(_subtotal)} • ITBIS: ${currency.format(_tax)} (${_itbisEnabled ? _taxRate.toStringAsFixed(2) : 'OFF'}%) • Total: ${currency.format(_total)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _createOrder,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(
                              _saving ? 'Guardando...' : 'Crear orden',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
