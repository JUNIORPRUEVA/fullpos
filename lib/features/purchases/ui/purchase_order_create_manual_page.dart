import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/utils/currency_display.dart';
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
  final ProductModel? product;
  final String productCodeSnapshot;
  final String productNameSnapshot;
  double qty;
  double unitCost;

  _LineDraft({
    required this.product,
    required this.productCodeSnapshot,
    required this.productNameSnapshot,
    required this.qty,
    required this.unitCost,
  });

  double get total => qty * unitCost;

  factory _LineDraft.fromProduct({
    required ProductModel product,
    required double qty,
    required double unitCost,
  }) {
    return _LineDraft(
      product: product,
      productCodeSnapshot: product.code,
      productNameSnapshot: product.name,
      qty: qty,
      unitCost: unitCost,
    );
  }

  factory _LineDraft.custom({
    required String code,
    required String name,
    required double qty,
    required double unitCost,
  }) {
    return _LineDraft(
      product: null,
      productCodeSnapshot: code.trim(),
      productNameSnapshot: name.trim(),
      qty: qty,
      unitCost: unitCost,
    );
  }
}

class _PurchaseOrderCreateManualPageState
    extends State<PurchaseOrderCreateManualPage> {
  final SuppliersRepository _suppliersRepo = SuppliersRepository();
  final ProductsRepository _productsRepo = ProductsRepository();
  final PurchasesRepository _purchasesRepo = PurchasesRepository();
  final BusinessSettingsRepository _settingsRepo = BusinessSettingsRepository();

  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _productSearchCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _loadingProducts = false;
  String? _error;

  List<SupplierModel> _suppliers = const [];
  List<ProductModel> _catalogProducts = const [];
  SupplierModel? _supplier;

  double _taxRate = 18.0;
  bool _itbisEnabled = false;
  DateTime _purchaseDate = DateTime.now();
  final List<_LineDraft> _lines = [];

  bool get _isEdit => widget.orderId != null;

  @override
  void initState() {
    super.initState();
    _load();
    _productSearchCtrl.addListener(_loadCatalogProducts);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _productSearchCtrl.dispose();
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
          final productId = it.item.productId;
          if (productId != null) {
            final p = await _productsRepo.getById(productId);
            if (p != null) {
              editLines.add(
                _LineDraft(
                  product: p,
                  productCodeSnapshot: it.productCode,
                  productNameSnapshot: it.productName,
                  qty: it.item.qty,
                  unitCost: it.item.unitCost,
                ),
              );
              continue;
            }
          }

          // Producto eliminado o línea sin inventario: usar snapshots.
          editLines.add(
            _LineDraft.custom(
              code: it.productCode,
              name: it.productName,
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
        _itbisEnabled = widget.orderId != null ? (editTaxRate ?? 0) > 0 : false;
        _supplier = editSupplier;
        _lines
          ..clear()
          ..addAll(editLines);
        _notesCtrl.text = (editNotes ?? '').trim();
        _purchaseDate = editPurchaseDate ?? DateTime.now();
        _loading = false;
      });
      await _loadCatalogProducts();
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
  double get _effectiveTaxRate => _itbisEnabled ? _taxRate : 0.0;
  double get _tax => _subtotal * (_effectiveTaxRate / 100.0);
  double get _total => _subtotal + _tax;

  Future<void> _loadCatalogProducts() async {
    if (!mounted) return;
    setState(() => _loadingProducts = true);
    try {
      final query = _productSearchCtrl.text.trim();
      final filters = _supplier?.id != null
          ? ProductFilters(supplierId: _supplier!.id)
          : null;

      var products = query.isEmpty
          ? await _productsRepo.getAll(filters: filters)
          : await _productsRepo.search(query, filters: filters);

      if (_supplier?.id != null && products.isEmpty) {
        products = query.isEmpty
            ? await _productsRepo.getAll()
            : await _productsRepo.search(query);
      }

      if (!mounted) return;
      setState(() {
        _catalogProducts = products;
        _loadingProducts = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loadingProducts = false);
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadCatalogProducts,
        module: 'purchases/catalog_products',
      );
    }
  }

  Future<int> _resolveSupplierIdForSave() async {
    if (_supplier?.id != null) return _supplier!.id!;

    const fallbackSupplierName = 'Sin suplidor';
    final existing = await _suppliersRepo.search(
      fallbackSupplierName,
      includeInactive: true,
      includeDeleted: true,
    );
    final exact = existing
        .where((s) => s.name.trim().toLowerCase() == fallbackSupplierName)
        .cast<SupplierModel?>()
        .firstOrNull;
    if (exact?.id != null) return exact!.id!;

    return _suppliersRepo.create(
      SupplierModel(
        name: fallbackSupplierName,
        note: 'Suplidor genérico creado automáticamente para compras sin suplidor.',
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  void _addProductToLines(ProductModel selected) {
    final existing = _lines.indexWhere((l) => l.product?.id == selected.id);
    setState(() {
      if (existing >= 0) {
        _lines[existing].qty += 1;
      } else {
        _lines.add(
          _LineDraft.fromProduct(
            product: selected,
            qty: 1,
            unitCost: selected.purchasePrice,
          ),
        );
      }
    });
  }

  Future<void> _save() async {
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
      final supplierId = await _resolveSupplierIdForSave();
      final items = _lines
          .map(
            (l) => _purchasesRepo.itemInput(
              productId: l.product?.id,
              productCodeSnapshot: l.productCodeSnapshot,
              productNameSnapshot: l.productNameSnapshot,
              qty: l.qty,
              unitCost: l.unitCost,
            ),
          )
          .toList();

      final purchaseDateMs = _purchaseDate.millisecondsSinceEpoch;

      if (_isEdit) {
        await _purchasesRepo.updateOrder(
          orderId: widget.orderId!,
          supplierId: supplierId,
          items: items,
          taxRatePercent: _effectiveTaxRate,
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
        context.go('/purchases/orders?orderId=${widget.orderId}');
      } else {
        final orderId = await _purchasesRepo.createOrder(
          supplierId: supplierId,
          items: items,
          taxRatePercent: _effectiveTaxRate,
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
        context.go('/purchases/orders?orderId=$orderId');
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

  // // ---------------------------------------------------------------------------
// BUILD – Two-column layout with fixed right purchase-detail panel
// ---------------------------------------------------------------------------

@override
Widget build(BuildContext context) {
  final currency = CurrencyDisplay.currency();
  final title = _isEdit ? 'Editar compra manual' : 'Registrar compra manual';

  return Scaffold(
    backgroundColor: const Color(0xFFF5F7FB),
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
            : LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = constraints.maxWidth;
                  final isDesktop = screenWidth >= 1180;

                  final panelWidth = screenWidth >= 1700
                      ? 720.0
                      : screenWidth >= 1500
                          ? 660.0
                          : screenWidth >= 1320
                              ? 610.0
                              : 560.0;

                  final leftPadding =
                      (screenWidth * 0.025).clamp(16.0, 44.0);

                  if (!isDesktop) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildHeaderCard(title),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 620,
                            child: _buildCatalogSection(currency),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 620,
                            child: _buildPurchaseDetailPanel(currency),
                          ),
                        ],
                      ),
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            leftPadding,
                            AppSizes.paddingM,
                            18,
                            AppSizes.paddingM,
                          ),
                          child: Column(
                            children: [
                              _buildHeaderCard(title),
                              const SizedBox(height: 14),
                              Expanded(
                                child: _buildCatalogSection(currency),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        width: panelWidth,
                        height: double.infinity,
                        child: _buildPurchaseDetailPanel(currency),
                      ),
                    ],
                  );
                },
              ),
  );
}

Widget _buildHeaderCard(String title) {
  return Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: AppColors.surfaceLightBorder.withOpacity(0.65),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withOpacity(0.04),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'GESTIÓN DE COMPRAS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: AppColors.gold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: _saving ? null : () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Volver'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 980;

            if (compact) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: _supplier?.id,
                    isExpanded: true,
                    menuMaxHeight: 300,
                    items: _suppliers
                        .where((s) => s.id != null)
                        .map(
                          (s) => DropdownMenuItem<int>(
                            value: s.id!,
                            child: Text(
                              s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      final s = _suppliers
                          .where((e) => e.id == v)
                          .cast<SupplierModel?>()
                          .firstOrNull;

                      setState(() => _supplier = s);
                      _loadCatalogProducts();
                    },
                    decoration: _compactInputDecoration(
                      label: 'Suplidor',
                      hint: 'Opcional',
                    ),
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _taxRate.toStringAsFixed(2),
                          enabled: _itbisEnabled,
                          decoration: _compactInputDecoration(
                            label: 'ITBIS %',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          readOnly: true,
                          decoration: _compactInputDecoration(
                            label: 'Fecha',
                            suffixIcon: Icons.calendar_today_outlined,
                          ),
                          controller: TextEditingController(
                            text: DateFormat('dd/MM/yyyy').format(_purchaseDate),
                          ),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _purchaseDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );

                            if (picked == null || !mounted) return;
                            setState(() => _purchaseDate = picked);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  _buildItbisAndNotesRow(compact: true),
                ],
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: DropdownButtonFormField<int>(
                        initialValue: _supplier?.id,
                        isExpanded: true,
                        menuMaxHeight: 300,
                        items: _suppliers
                            .where((s) => s.id != null)
                            .map(
                              (s) => DropdownMenuItem<int>(
                                value: s.id!,
                                child: Text(
                                  s.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          final s = _suppliers
                              .where((e) => e.id == v)
                              .cast<SupplierModel?>()
                              .firstOrNull;

                          setState(() => _supplier = s);
                          _loadCatalogProducts();
                        },
                        decoration: _compactInputDecoration(
                          label: 'Suplidor',
                          hint: 'Opcional',
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    SizedBox(
                      width: 105,
                      child: TextFormField(
                        initialValue: _taxRate.toStringAsFixed(2),
                        enabled: _itbisEnabled,
                        decoration: _compactInputDecoration(
                          label: 'ITBIS %',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
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

                    const SizedBox(width: 10),

                    SizedBox(
                      width: 150,
                      child: TextFormField(
                        readOnly: true,
                        decoration: _compactInputDecoration(
                          label: 'Fecha',
                          suffixIcon: Icons.calendar_today_outlined,
                        ),
                        controller: TextEditingController(
                          text: DateFormat('dd/MM/yyyy').format(_purchaseDate),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _purchaseDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );

                          if (picked == null || !mounted) return;
                          setState(() => _purchaseDate = picked);
                        },
                      ),
                    ),

                  ],
                ),

                const SizedBox(height: 10),

                _buildItbisAndNotesRow(),
              ],
            );
          },
        ),
      ],
    ),
  );
}

Widget _buildItbisAndNotesRow({bool compact = false}) {
  if (compact) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _buildItbisToggleBox(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notesCtrl,
          decoration: _compactInputDecoration(
            label: 'Nota importante para suplidor (opcional)',
            prefixIcon: Icons.notes_rounded,
          ),
          maxLines: 1,
        ),
      ],
    );
  }

  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      _buildItbisToggleBox(),
      const SizedBox(width: 10),
      Expanded(
        child: TextField(
          controller: _notesCtrl,
          decoration: _compactInputDecoration(
            label: 'Nota importante para suplidor (opcional)',
            prefixIcon: Icons.notes_rounded,
          ),
          maxLines: 1,
        ),
      ),
    ],
  );
}

Widget _buildItbisToggleBox() {
  return Container(
    height: 42,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(
        color: AppColors.surfaceLightBorder.withOpacity(0.85),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.scale(
          scale: 0.82,
          child: Switch.adaptive(
            value: _itbisEnabled,
            onChanged: _saving
                ? null
                : (v) => setState(() => _itbisEnabled = v),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          _itbisEnabled
              ? 'ITBIS ${_taxRate.toStringAsFixed(2)}%'
              : 'Aplicar ITBIS',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
      ],
    ),
  );
}

InputDecoration _compactInputDecoration({
  required String label,
  String? hint,
  IconData? prefixIcon,
  IconData? suffixIcon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 18),
    suffixIcon: suffixIcon == null ? null : Icon(suffixIcon, size: 18),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 12,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: AppColors.surfaceLightBorder.withOpacity(0.95),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(
        color: AppColors.gold,
        width: 1.2,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// _buildCatalogSection – Muestra los productos del catálogo en un grid
// ---------------------------------------------------------------------------
Widget _buildCatalogSection(NumberFormat currency) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: AppColors.surfaceLightBorder.withOpacity(0.65),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withOpacity(0.04),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.inventory_2_outlined, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Catálogo de productos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            if (_loadingProducts)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _productSearchCtrl,
          decoration: _compactInputDecoration(
            label: 'Buscar producto…',
            prefixIcon: Icons.search,
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _catalogProducts.isEmpty
              ? Center(
                  child: Text(
                    _loadingProducts
                        ? 'Cargando…'
                        : 'No hay productos disponibles',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                )
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisExtent: 240,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _catalogProducts.length,
                  itemBuilder: (context, i) {
                    final p = _catalogProducts[i];
                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _addProductToLines(p),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 2,
                              child: ProductThumbnail.fromProduct(
                                p,
                                width: double.infinity,
                                height: double.infinity,
                                showBorder: false,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.code,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      p.name,
                                      style: const TextStyle(fontSize: 10),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Stock: ${p.stock.toStringAsFixed(0)}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textDarkSecondary,
                                      ),
                                    ),
                                    Text(
                                      'Compra: ${CurrencyDisplay.format(p.purchasePrice)}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.success,
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
                  },
                ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// _buildPurchaseDetailPanel – Panel lateral/derecho con detalle de la compra
// ---------------------------------------------------------------------------
Widget _buildPurchaseDetailPanel(NumberFormat currency) {
  return Container(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: AppColors.surfaceLightBorder.withOpacity(0.65),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF0F172A).withOpacity(0.04),
          blurRadius: 20,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Título
        Row(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Detalle de compra',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            const Spacer(),
            Text(
              '${_lines.length} ${_lines.length == 1 ? 'ítem' : 'ítems'}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),

        // Lista de líneas
        Expanded(
          child: _lines.isEmpty
              ? const Center(
                  child: Text(
                    'Agregue productos desde el catálogo\no usando "No inventario"',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _lines.length,
                  itemBuilder: (context, i) {
                    final line = _lines[i];
                    return _buildLineTile(line, i);
                  },
                ),
        ),

        const Divider(height: 1),
        const SizedBox(height: 8),

        // Resumen de totales
        _buildSummaryRow('Subtotal', _subtotal, currency),
        if (_itbisEnabled) ...[
          const SizedBox(height: 4),
          _buildSummaryRow(
            'ITBIS (${_effectiveTaxRate.toStringAsFixed(2)}%)',
            _tax,
            currency,
          ),
        ],
        const SizedBox(height: 4),
        _buildSummaryRow(
          'Total',
          _total,
          currency,
          bold: true,
          fontSize: 18,
        ),

        const SizedBox(height: 14),

        // Botón guardar
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 20),
            label: Text(
              _isEdit ? 'Actualizar orden' : 'Crear orden',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildLineTile(_LineDraft line, int index) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info del producto
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.productNameSnapshot,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${line.productCodeSnapshot}  •  ${CurrencyDisplay.format(line.unitCost)} c/u',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),

        // Cantidad
        SizedBox(
          width: 70,
          child: TextFormField(
            initialValue: line.qty.toStringAsFixed(0),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (v) {
              final qty = double.tryParse(v.replaceAll(',', '.'));
              if (qty == null || qty <= 0) return;
              setState(() => _lines[index].qty = qty);
            },
          ),
        ),

        const SizedBox(width: 8),

        // Total de línea
        SizedBox(
          width: 90,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              CurrencyDisplay.format(line.total),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ),

        const SizedBox(width: 4),

        // Botón eliminar
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
            onPressed: () => setState(() => _lines.removeAt(index)),
          ),
        ),
      ],
    ),
  );
}

Widget _buildSummaryRow(
  String label,
  double amount,
  NumberFormat currency, {
  bool bold = false,
  double fontSize = 14,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: bold ? fontSize - 2 : fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: bold ? const Color(0xFF0F172A) : const Color(0xFF64748B),
        ),
      ),
      Text(
        CurrencyDisplay.format(amount),
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
          color: bold ? AppColors.gold : const Color(0xFF0F172A),
        ),
      ),
    ],
  );
}
}
