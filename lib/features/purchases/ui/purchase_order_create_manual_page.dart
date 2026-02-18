import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../products/data/products_repository.dart';
import '../../products/data/suppliers_repository.dart';
import '../../products/models/product_model.dart';
import '../../products/ui/widgets/product_thumbnail.dart';
import '../../products/models/supplier_model.dart';
import '../../settings/data/business_settings_repository.dart';
import '../data/purchases_repository.dart';

class PurchaseOrderCreateManualPage extends StatefulWidget {
  final int? orderId;

  const PurchaseOrderCreateManualPage({super.key, this.orderId});

  @override
  State<PurchaseOrderCreateManualPage> createState() =>
      _PurchaseOrderCreateManualPageState();
}

class _LineDraft {
  final ProductModel product;
  double qty;
  double unitCost;

  _LineDraft({
    required this.product,
    required this.qty,
    required this.unitCost,
  });

  double get total => qty * unitCost;
}

class _PurchaseOrderCreateManualPageState
    extends State<PurchaseOrderCreateManualPage> {
  final SuppliersRepository _suppliersRepo = SuppliersRepository();
  final ProductsRepository _productsRepo = ProductsRepository();
  final PurchasesRepository _purchasesRepo = PurchasesRepository();
  final BusinessSettingsRepository _settingsRepo = BusinessSettingsRepository();

  final TextEditingController _notesCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<SupplierModel> _suppliers = const [];
  SupplierModel? _supplier;

  double _taxRate = 18.0;
  DateTime _purchaseDate = DateTime.now();
  final List<_LineDraft> _lines = [];

  bool get _isEdit => widget.orderId != null;

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

      // Si es edición, precargar cabecera + detalle
      SupplierModel? editSupplier;
      double? editTaxRate;
      String? editNotes;
      DateTime? editPurchaseDate;
      final editLines = <_LineDraft>[];

      if (widget.orderId != null) {
        final detail = await _purchasesRepo.getOrderById(widget.orderId!);
        if (detail == null) {
          throw ArgumentError('Orden no encontrada');
        }

        editSupplier = await _suppliersRepo.getById(detail.order.supplierId);
        editTaxRate = detail.order.taxRate;
        editNotes = detail.order.notes;
        if (detail.order.purchaseDateMs != null) {
          editPurchaseDate = DateTime.fromMillisecondsSinceEpoch(
            detail.order.purchaseDateMs!,
          );
        }

        for (final it in detail.items) {
          final p = await _productsRepo.getById(it.item.productId);
          if (p == null) continue;
          editLines.add(
            _LineDraft(
              product: p,
              qty: it.item.qty,
              unitCost: it.item.unitCost,
            ),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _taxRate = editTaxRate ?? tax;
        _supplier = editSupplier;
        _lines
          ..clear()
          ..addAll(editLines);
        _notesCtrl.text = (editNotes ?? '').trim();
        _purchaseDate = editPurchaseDate ?? DateTime.now();
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      final ex = await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _load,
        module: 'purchases/order_load',
      );
      if (!mounted) return;
      setState(() {
        _error = ex.messageUser;
        _loading = false;
      });
    }
  }

  double get _subtotal => _lines.fold(0.0, (s, l) => s + l.total);
  double get _tax => _subtotal * (_taxRate / 100.0);
  double get _total => _subtotal + _tax;

  Future<void> _save() async {
    if (_supplier?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione un suplidor'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agregue al menos 1 producto'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final items = _lines
          .map(
            (l) => _purchasesRepo.itemInput(
              productId: l.product.id ?? 0,
              qty: l.qty,
              unitCost: l.unitCost,
            ),
          )
          .where((e) => e.productId > 0)
          .toList();

      final purchaseDateMs = _purchaseDate.millisecondsSinceEpoch;

      if (_isEdit) {
        await _purchasesRepo.updateOrder(
          orderId: widget.orderId!,
          supplierId: _supplier!.id!,
          items: items,
          taxRatePercent: _taxRate,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          purchaseDateMs: purchaseDateMs,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Orden actualizada'),
            backgroundColor: AppColors.success,
          ),
        );
        context.go('/purchases/receive/${widget.orderId}');
      } else {
        final orderId = await _purchasesRepo.createOrder(
          supplierId: _supplier!.id!,
          items: items,
          taxRatePercent: _taxRate,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          isAuto: false,
          purchaseDateMs: purchaseDateMs,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Orden creada'),
            backgroundColor: AppColors.success,
          ),
        );
        context.go('/purchases/receive/$orderId');
      }
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _save,
        module: 'purchases/save',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addProductDialog() async {
    if (_supplier?.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleccione un suplidor primero'),
          backgroundColor: AppColors.info,
        ),
      );
      return;
    }

    final selected = await showDialog<ProductModel>(
      context: context,
      builder: (dialogContext) {
        final searchCtrl = TextEditingController();
        var loading = true;
        var products = <ProductModel>[];
        String? error;
        var hasLoaded = false;
        var onlySupplier = true;
        var showingFallbackAll = false;

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> runSearch() async {
              final q = searchCtrl.text.trim();
              if (!context.mounted) return;
              setState(() {
                loading = true;
                error = null;
                showingFallbackAll = false;
              });
              try {
                final supplierId = _supplier!.id!;

                Future<List<ProductModel>> fetch({
                  required bool filterBySupplier,
                }) {
                  final filters = filterBySupplier
                      ? ProductFilters(supplierId: supplierId)
                      : null;
                  return q.isEmpty
                      ? _productsRepo.getAll(filters: filters)
                      : _productsRepo.search(q, filters: filters);
                }

                var result = await fetch(filterBySupplier: onlySupplier);
                if (!context.mounted) return;

                // Si el suplidor no tiene productos asociados, no bloquear el flujo:
                // mostrar todos los productos para que el usuario pueda comprar.
                if (onlySupplier && result.isEmpty) {
                  result = await fetch(filterBySupplier: false);
                  if (!context.mounted) return;
                  setState(() {
                    onlySupplier = false;
                    showingFallbackAll = true;
                  });
                }

                if (!context.mounted) return;
                setState(() {
                  products = result;
                  loading = false;
                  hasLoaded = true;
                });
              } catch (e, st) {
                if (!dialogContext.mounted) return;
                final ex = await ErrorHandler.instance.handle(
                  e,
                  stackTrace: st,
                  context: dialogContext,
                  onRetry: runSearch,
                  module: 'purchases/products_search',
                );
                if (!context.mounted) return;
                setState(() {
                  error = ex.messageUser;
                  loading = false;
                  hasLoaded = true;
                });
              }
            }

            // Cargar productos al abrir (una sola vez)
            if (!hasLoaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!hasLoaded) runSearch();
              });
            }

            return AlertDialog(
              title: const Text('Agregar producto'),
              contentPadding: const EdgeInsets.all(0),
              content: SizedBox(
                width: 700,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextField(
                            controller: searchCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Buscar producto',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => runSearch(),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              FilterChip(
                                label: Text(
                                  onlySupplier
                                      ? 'Solo este suplidor'
                                      : 'Todos los productos',
                                ),
                                selected: onlySupplier,
                                onSelected: (v) {
                                  setState(() {
                                    onlySupplier = v;
                                  });
                                  runSearch();
                                },
                              ),
                              if (showingFallbackAll) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Este suplidor no tiene productos asociados. Mostrando todos.',
                                    style: TextStyle(
                                      color: AppColors.textDarkSecondary,
                                      fontSize: 12,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    SizedBox(
                      height: 400,
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : error != null
                          ? Center(
                              child: Text(
                                'Error: $error',
                                style: const TextStyle(color: Colors.red),
                              ),
                            )
                          : products.isEmpty
                          ? const Center(child: Text('No hay productos'))
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 210,
                                    mainAxisExtent: 260,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                              itemCount: products.length,
                              itemBuilder: (context, i) {
                                final p = products[i];
                                return Center(
                                  child: SizedBox(
                                    width: 190,
                                    height: 260,
                                    child: Card(
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: InkWell(
                                        onTap: () =>
                                            Navigator.of(dialogContext).pop(p),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              flex: 2,
                                              child: ProductThumbnail.fromProduct(
                                                p,
                                                width: double.infinity,
                                                height: double.infinity,
                                                showBorder: false,
                                                borderRadius:
                                                    const BorderRadius.vertical(
                                                      top: Radius.circular(8),
                                                    ),
                                              ),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  8,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      p.code,
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      p.name,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Stock: ${p.stock.toStringAsFixed(0)}',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: AppColors
                                                            .textDarkSecondary,
                                                      ),
                                                    ),
                                                    Text(
                                                      'Compra: ${p.purchasePrice.toStringAsFixed(2)}',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color:
                                                            AppColors.success,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected == null) return;

    final existing = _lines.indexWhere((l) => l.product.id == selected.id);
    setState(() {
      if (existing >= 0) {
        _lines[existing].qty += 1;
      } else {
        _lines.add(
          _LineDraft(
            product: selected,
            qty: 1,
            unitCost: selected.purchasePrice,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat('#,##0.00', 'en_US');

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(
          _isEdit ? 'Editar Orden (Manual)' : 'Crear Orden (Manual)',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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
                                  decoration: const InputDecoration(
                                    labelText: 'Impuesto %',
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
                              SizedBox(
                                width: 180,
                                child: TextFormField(
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: 'Fecha de compra',
                                    suffixIcon: const Icon(
                                      Icons.calendar_today,
                                    ),
                                  ),
                                  controller: TextEditingController(
                                    text: DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(_purchaseDate),
                                  ),
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _purchaseDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );
                                    if (picked == null) return;
                                    if (!mounted) return;
                                    setState(() => _purchaseDate = picked);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: _saving ? null : _addProductDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Agregar producto'),
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
                                'Agregue productos para continuar',
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
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Card(
                                    elevation: 1,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Imagen del producto
                                          ProductThumbnail.fromProduct(
                                            line.product,
                                            size: 70,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Información del producto
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  line.product.code,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.gold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  line.product.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Total línea: ${currency.format(line.total)}',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.success,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Campos de cantidad y costo
                                          SizedBox(
                                            width: 370,
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                // Cantidad
                                                Expanded(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 8,
                                                        ),
                                                    child: TextFormField(
                                                      initialValue: line.qty
                                                          .toStringAsFixed(2),
                                                      decoration: InputDecoration(
                                                        labelText: 'Cantidad',
                                                        isDense: true,
                                                        border: OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                      ),
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                      onChanged: (v) {
                                                        final parsed =
                                                            double.tryParse(
                                                              v.replaceAll(
                                                                ',',
                                                                '.',
                                                              ),
                                                            );
                                                        if (parsed == null) {
                                                          return;
                                                        }
                                                        setState(
                                                          () =>
                                                              line.qty = parsed,
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                // Costo unitario
                                                Expanded(
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          right: 8,
                                                        ),
                                                    child: TextFormField(
                                                      initialValue: line
                                                          .unitCost
                                                          .toStringAsFixed(2),
                                                      decoration: InputDecoration(
                                                        labelText: 'Costo',
                                                        isDense: true,
                                                        border: OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                        ),
                                                      ),
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                      onChanged: (v) {
                                                        final parsed =
                                                            double.tryParse(
                                                              v.replaceAll(
                                                                ',',
                                                                '.',
                                                              ),
                                                            );
                                                        if (parsed == null) {
                                                          return;
                                                        }
                                                        setState(
                                                          () => line.unitCost =
                                                              parsed,
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                // Botón eliminar
                                                IconButton(
                                                  tooltip: 'Quitar producto',
                                                  onPressed: _saving
                                                      ? null
                                                      : () => setState(
                                                          () => _lines.removeAt(
                                                            index,
                                                          ),
                                                        ),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red,
                                                  ),
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
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
                            'Subtotal: ${currency.format(_subtotal)} • Impuesto: ${currency.format(_tax)} • Total: ${currency.format(_total)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
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
                            label: Text(_saving ? 'Guardando...' : 'Guardar'),
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
