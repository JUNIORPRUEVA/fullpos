import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/categories_repository.dart';
import '../../data/products_repository.dart';
import '../../data/suppliers_repository.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../models/supplier_model.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/window/window_service.dart';
import '../../../../core/security/app_actions.dart';
import '../../../../core/security/authorization_guard.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../settings/data/user_model.dart';
import '../../utils/products_exporter.dart';
import '../../utils/products_importer.dart';
import '../../utils/catalog_pdf_launcher.dart';
import '../../../../core/sync/product_sync_event_bus.dart';
import '../dialogs/product_filters_dialog.dart';
import '../dialogs/product_form_dialog.dart';
import '../dialogs/stock_adjust_dialog.dart';
import '../widgets/products_surface.dart';
import '../../../../theme/app_colors.dart' as ui_colors;

enum _CatalogSelectionAction { edit, delete, exportPdf }

enum _CatalogOverflowAction { exportExcel, catalogActions }

/// Tab de Catálogo de Productos
class CatalogTab extends StatefulWidget {
  const CatalogTab({super.key});

  @override
  State<CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<CatalogTab> {
  final ProductsRepository _productsRepo = ProductsRepository();
  final CategoriesRepository _categoriesRepo = CategoriesRepository();
  final SuppliersRepository _suppliersRepo = SuppliersRepository();

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  Timer? _syncRefreshDebounce;
  StreamSubscription<ProductSyncChange>? _syncSubscription;
  final ScrollController _tableHorizontalController = ScrollController();

  List<ProductModel> _products = [];
  ProductModel? _selectedProduct;
  final Set<int> _selectedProductIds = <int>{};
  List<CategoryModel> _categories = [];
  List<SupplierModel> _suppliers = [];
  bool _isLoading = false;
  ProductFilters? _currentFilters;

  bool _isAdmin = false;
  UserPermissions _permissions = UserPermissions.cashier();

  Future<void> _exportProductsToExcel() async {
    try {
      final results = await Future.wait([
        _productsRepo.getAll(),
        _categoriesRepo.getAll(includeInactive: true),
        _suppliersRepo.getAll(includeInactive: true),
      ]);

      final products = results[0] as List<ProductModel>;
      final categories = results[1] as List<CategoryModel>;
      final suppliers = results[2] as List<SupplierModel>;
      final file = await ProductsExporter.exportProductsToExcel(
        products: products,
        categories: categories,
        suppliers: suppliers,
        includePurchasePrice: _isAdmin || _permissions.canViewPurchasePrice,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel exportado: ${file.path}'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al exportar Excel: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _importProductsFromExcel() async {
    if (!(_isAdmin || _permissions.canViewPurchasePrice)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No tienes permiso para importar productos'),
        ),
      );
      return;
    }

    final result = await WindowService.runWithSystemDialog(
      () => FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      ),
    );
    if (result == null || result.files.single.path == null) return;
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      final file = File(result.files.single.path!);
      final importResult = await ProductsImporter.importProductsFromExcel(
        file: file,
        repository: _productsRepo,
        requirePurchasePrice: true,
      );

      await _loadProducts();
      if (!mounted) return;

      final message =
          'Importados: ${importResult.inserted}, actualizados: ${importResult.updated}, omitidos: ${importResult.skipped} (inválidos: ${importResult.invalidRows}, duplicados en archivo: ${importResult.duplicateRows}), categorías: ${importResult.categoriesUpserted}, suplidores: ${importResult.suppliersUpserted}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.success),
      );

      if (importResult.errors.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Detalle de importacion'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Text(importResult.errors.join('\n')),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    final reportFile = await _exportImportErrorsReportCsv(
                      importResult.errors,
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Reporte de errores exportado: ${reportFile.path}',
                        ),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'No se pudo exportar el reporte de errores. Qué hacer: verifica permisos de carpeta Descargas e inténtalo de nuevo. Detalle: $e',
                        ),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                },
                child: const Text('Exportar reporte CSV'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final rawError = e.toString().replaceFirst('Exception: ', '').trim();
      final lower = rawError.toLowerCase();

      String quickFix =
          'Revisa el archivo Excel e inténtalo de nuevo. Si persiste, corrige las filas reportadas en el detalle.';

      if (lower.contains('faltan columnas requeridas')) {
        quickFix =
            'Agrega todas las columnas obligatorias (Código, Nombre, Precio Venta, Stock, Stock Min) en la primera fila de encabezados.';
      } else if (lower.contains('precio compra') &&
          lower.contains('requerida')) {
        quickFix =
            'Agrega la columna Precio Compra y coloca valores mayores que 0 en cada producto.';
      } else if (lower.contains('no se encontró la hoja') ||
          lower.contains('no se encontro la hoja')) {
        quickFix =
            'Renombra la hoja principal como Productos o colócala como primera hoja del archivo.';
      } else if (lower.contains('no contiene filas')) {
        quickFix =
            'Asegura que el Excel tenga encabezados y al menos una fila de productos con datos.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al importar: $rawError\nQué hacer: $quickFix'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
    _syncSubscription = ProductSyncEventBus.instance.stream.listen((_) {
      _syncRefreshDebounce?.cancel();
      _syncRefreshDebounce = Timer(
        const Duration(milliseconds: 200),
        _loadProducts,
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _syncRefreshDebounce?.cancel();
    _syncSubscription?.cancel();
    _tableHorizontalController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _loadProducts();
    });
  }

  Future<File> _exportImportErrorsReportCsv(List<String> errors) async {
    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir == null) {
      throw StateError(
        'No se pudo acceder al directorio de descargas para guardar el reporte.',
      );
    }

    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(
      '${downloadsDir.path}/ImportacionProductos_Errores_$ts.csv',
    );

    final lines = <String>['Fila,Problema,Solucion'];
    for (final error in errors) {
      final parsed = _parseImportError(error);
      lines.add(
        '${_csvCell(parsed.row)},${_csvCell(parsed.issue)},${_csvCell(parsed.fix)}',
      );
    }

    final csv = lines.join('\n');
    await file.writeAsString(csv, flush: true);
    return file;
  }

  ({String row, String issue, String fix}) _parseImportError(String error) {
    final regex = RegExp(
      r'^Fila\s+(\d+)\:\s*(.*?)(?:\.\s*Solución\:\s*(.*))?\.?$',
    );
    final match = regex.firstMatch(error.trim());
    if (match == null) {
      return (
        row: '',
        issue: error.trim(),
        fix:
            'Revisa este mensaje y corrige el valor en el Excel antes de reintentar.',
      );
    }

    final row = match.group(1)?.trim() ?? '';
    final issue = match.group(2)?.trim() ?? error.trim();
    final fix = (match.group(3)?.trim().isNotEmpty ?? false)
        ? match.group(3)!.trim()
        : 'Corrige esta fila en el Excel y vuelve a importar.';

    return (row: row, issue: issue, fix: fix);
  }

  String _csvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final permsResults = await Future.wait([
        AuthRepository.getCurrentPermissions(),
        AuthRepository.isAdmin(),
      ]);
      _permissions = permsResults[0] as UserPermissions;
      _isAdmin = permsResults[1] as bool;

      final results = await Future.wait([
        _categoriesRepo.getAll(),
        _suppliersRepo.getAll(),
      ]);

      _categories = results[0] as List<CategoryModel>;
      _suppliers = results[1] as List<SupplierModel>;

      await _loadProducts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProducts() async {
    try {
      final query = _searchController.text.trim();
      final products = query.isEmpty
          ? await _productsRepo.getAll(filters: _currentFilters)
          : await _productsRepo.search(query, filters: _currentFilters);

      if (mounted) {
        final visibleIds = products
            .where((product) => product.id != null)
            .map((product) => product.id!)
            .toSet();
        setState(() {
          _products = products;
          _selectedProductIds.retainWhere(visibleIds.contains);
          if (products.isEmpty) {
            _selectedProduct = null;
          } else if (_selectedProduct != null) {
            _selectedProduct = products.firstWhere(
              (p) => p.id == _selectedProduct!.id,
              orElse: () => _selectedProduct!,
            );
            if (!_products.any((p) => p.id == _selectedProduct!.id)) {
              _selectedProduct = null;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar productos: $e')),
        );
      }
    }
  }

  Future<void> _showFilters() async {
    final filters = await showDialog<ProductFilters>(
      context: context,
      builder: (context) => ProductFiltersDialog(
        initialFilters: _currentFilters,
        categories: _categories,
        suppliers: _suppliers,
      ),
    );

    if (filters == null) return;
    if (!mounted) return;
    setState(() => _currentFilters = filters);
    _loadProducts();
  }

  Future<void> _showCatalogActions() async {
    if (_isLoading) return;

    if (!(_isAdmin || _permissions.canEditProducts)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No tienes permiso para esta acción.')),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Acciones del catálogo'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _handleDeleteAllProducts();
            },
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.delete_forever, color: Colors.redAccent),
              title: Text('Eliminar todos los productos'),
              subtitle: Text('Acción irreversible (se borran del catálogo).'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _handleDeleteAllCategories();
            },
            child: const ListTile(
              dense: true,
              leading: Icon(Icons.delete_sweep, color: Colors.redAccent),
              title: Text('Eliminar todas las categorías'),
              subtitle: Text('Puede dejar productos sin categoría.'),
            ),
          ),
          const SizedBox(height: 4),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Align(
              alignment: Alignment.centerRight,
              child: Text('Cancelar'),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmTyped({
    required String title,
    required String message,
    String keyword = 'BORRAR',
  }) async {
    if (!mounted) return false;

    final controller = TextEditingController();
    var canConfirm = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              Text(
                'Escribe "$keyword" para confirmar:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                onChanged: (v) {
                  final ok = v.trim().toUpperCase() == keyword;
                  if (ok != canConfirm) {
                    setLocalState(() => canConfirm = ok);
                  }
                },
                decoration: InputDecoration(
                  hintText: keyword,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: canConfirm ? () => Navigator.pop(ctx, true) : null,
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );

    // Evita dispose antes de que termine la animación de cierre del diálogo.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return result == true;
  }

  Future<void> _handleDeleteAllProducts() async {
    if (_isLoading) return;
    try {
      final count = await _productsRepo.count(includeDeleted: false);
      if (!mounted) return;

      if (count <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay productos para eliminar.')),
        );
        return;
      }

      final confirmed = await _confirmTyped(
        title: 'Confirmar eliminación de productos',
        message:
            'Se eliminarán $count productos del catálogo.\n\nEsta acción no se puede deshacer.',
      );
      if (!confirmed) return;

      final authorized = await _authorizeAction(
        AppActions.deleteProduct,
        resourceType: 'catalog',
        resourceId: 'products:all',
      );
      if (!authorized) return;

      if (mounted) setState(() => _isLoading = true);
      await _productsRepo.softDeleteAll();
      await _loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Productos eliminados correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar productos: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDeleteAllCategories() async {
    if (_isLoading) return;
    try {
      final cats = await _categoriesRepo.count(
        includeInactive: true,
        includeDeleted: false,
      );
      final products = await _productsRepo.count(includeDeleted: false);
      if (!mounted) return;

      if (cats <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay categorías para eliminar.')),
        );
        return;
      }

      final confirmed = await _confirmTyped(
        title: 'Confirmar eliminación de categorías',
        message:
            'Se eliminarán $cats categorías.\n\nAdvertencia: hay $products productos activos; pueden quedar sin categoría.\n\nEsta acción no se puede deshacer.',
      );
      if (!confirmed) return;

      final authorized = await _authorizeAction(
        AppActions.deleteCategory,
        resourceType: 'catalog',
        resourceId: 'categories:all',
      );
      if (!authorized) return;

      if (mounted) setState(() => _isLoading = true);
      await _categoriesRepo.softDeleteAll();
      await _loadData();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Categorías eliminadas correctamente.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar categorías: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _authorizeAction(
    AppAction action, {
    String resourceType = 'product',
    String? resourceId,
  }) async {
    return requireAuthorizationIfNeeded(
      context: context,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      isOnline: true,
    );
  }

  Future<void> _showProductForm([ProductModel? product]) async {
    if (product == null) {
      final canCreate = await _authorizeAction(
        AppActions.createProduct,
        resourceType: 'product',
      );
      if (!canCreate) return;
    } else {
      final canEdit = await _authorizeAction(
        AppActions.updateProduct,
        resourceType: 'product',
        resourceId: product.id?.toString(),
      );
      if (!canEdit) return;
    }

    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ProductFormDialog(
        product: product,
        categories: _categories,
        suppliers: _suppliers,
      ),
    );

    if (!mounted) return;
    if (result == true) {
      _loadProducts();
    }
  }

  Future<void> _requestAdjustStock(ProductModel product) async {
    final canAdjust = await _authorizeAction(
      AppActions.adjustStock,
      resourceType: 'product',
      resourceId: product.id?.toString(),
    );
    if (!canAdjust) return;
    if (!mounted) return;
    final freshProduct = await _productsRepo.getById(product.id!);
    if (!mounted || freshProduct == null) return;

    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StockAdjustDialog(product: freshProduct),
    );

    if (result is Map) {
      final ok = result['ok'] == true;
      final productId = result['productId'] as int?;
      final updatedStockNum = result['updatedStock'] as num?;
      if (ok && productId != null && updatedStockNum != null) {
        final updatedStock = updatedStockNum.toDouble();
        if (mounted) {
          setState(() {
            _products = _products
                .map(
                  (item) => item.id == productId
                      ? item.copyWith(stock: updatedStock)
                      : item,
                )
                .toList();
            if (_selectedProduct?.id == productId) {
              _selectedProduct = _selectedProduct?.copyWith(
                stock: updatedStock,
              );
            }
          });
        }
        await _loadProducts();
        return;
      }
    }

    if (result == true) {
      await _loadProducts();
    }
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    _loadProducts();
  }

  String _normalizeCode(String value) {
    return value.trim().toLowerCase();
  }

  Future<void> _handleCatalogSearchSubmit(String rawValue) async {
    final query = rawValue.trim();
    if (query.isEmpty) {
      await _loadProducts();
      return;
    }

    FocusScope.of(context).unfocus();
    await _loadProducts();
    if (!mounted) return;

    final normalizedQuery = _normalizeCode(query);
    ProductModel? match;

    for (final product in _products) {
      if (_normalizeCode(product.code) == normalizedQuery) {
        match = product;
        break;
      }
    }

    if (match == null) return;
    await _requestAdjustStock(match);
  }

  List<ProductModel> _selectedProducts() {
    return _products
        .where(
          (product) =>
              product.id != null && _selectedProductIds.contains(product.id),
        )
        .toList();
  }

  Future<void> _handleSelectionAction(_CatalogSelectionAction action) async {
    final selectedProducts = _selectedProducts();
    if (selectedProducts.isEmpty) return;

    switch (action) {
      case _CatalogSelectionAction.edit:
        if (selectedProducts.length != 1) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selecciona un solo producto para editar.'),
            ),
          );
          return;
        }
        await _showProductForm(selectedProducts.first);
        return;
      case _CatalogSelectionAction.delete:
        await _deleteProducts(selectedProducts);
        return;
      case _CatalogSelectionAction.exportPdf:
        await CatalogPdfLauncher.openForProducts(
          context,
          products: selectedProducts,
          title: 'Catálogo de productos seleccionados',
          fileNameSuffix: 'Seleccion',
        );
        return;
    }
  }

  Future<bool> _confirmDeleteProducts(List<ProductModel> products) async {
    if (!mounted) return false;

    final message = products.length == 1
        ? '¿Estás seguro de eliminar este producto?'
        : '¿Estás seguro de eliminar estos productos?';

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirmar eliminación'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteProducts(List<ProductModel> products) async {
    final deletable = products.where((product) => !product.isDeleted).toList();
    if (deletable.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay productos activos para eliminar.'),
        ),
      );
      return;
    }

    for (final product in deletable) {
      final canDelete = await _authorizeAction(
        AppActions.deleteProduct,
        resourceType: 'product',
        resourceId: product.id?.toString(),
      );
      if (!canDelete) return;
    }

    final confirm = await _confirmDeleteProducts(deletable);
    if (!confirm) return;

    try {
      for (final product in deletable) {
        await _productsRepo.softDelete(product.id!);
      }
      await _loadProducts();
      if (!mounted) return;
      setState(() {
        _selectedProductIds.removeAll(
          deletable
              .where((product) => product.id != null)
              .map((product) => product.id!),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletable.length == 1
                ? 'Producto eliminado'
                : '${deletable.length} productos eliminados',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar productos: $e')),
      );
    }
  }

  void _toggleSelectAllVisible(bool? selected) {
    final visibleIds = _products
        .where((product) => product.id != null)
        .map((product) => product.id!)
        .toSet();
    if (visibleIds.isEmpty) return;

    setState(() {
      if (selected ?? false) {
        _selectedProductIds.addAll(visibleIds);
      } else {
        _selectedProductIds.removeAll(visibleIds);
      }
    });
  }

  void _toggleProductSelection(ProductModel product, bool? selected) {
    final productId = product.id;
    if (productId == null) return;

    setState(() {
      if (selected ?? false) {
        _selectedProductIds.add(productId);
      } else {
        _selectedProductIds.remove(productId);
      }
      _selectedProduct = product;
    });
  }

  @override
Widget build(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;

      // Fondo un poquito más marcado para que el contenido blanco resalte mejor.
      const pageBackground = Color(0xFFEFF4FA);

      // Más centrado para que la tabla se vea más ejecutiva.
      const maxContentWidth = 780.0;
      final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
      final side = ((constraints.maxWidth - contentWidth) / 2).clamp(
        60.0,
        220.0,
      );
      final padding = EdgeInsets.fromLTRB(side, 28, side, 24);

      final canViewPurchasePrice =
          _isAdmin || _permissions.canViewPurchasePrice;

      final visibleSelectableIds = _products
          .where((product) => product.id != null)
          .map((product) => product.id!)
          .toSet();

      final selectedVisibleCount = visibleSelectableIds
          .where(_selectedProductIds.contains)
          .length;

      final allVisibleSelected =
          visibleSelectableIds.isNotEmpty &&
          selectedVisibleCount == visibleSelectableIds.length;

      final someVisibleSelected =
          selectedVisibleCount > 0 &&
          selectedVisibleCount < visibleSelectableIds.length;

      final activeFilterCount = [
        _currentFilters?.categoryId,
        _currentFilters?.supplierId,
        _currentFilters?.hasLowStock,
        _currentFilters?.isOutOfStock,
      ].where((value) => value != null).length;

      Widget buildSearchField() {
        return SizedBox(
          height: 44,
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            textAlignVertical: TextAlignVertical.center,
            onSubmitted: _handleCatalogSearchSubmit,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter',
              fontSize: 14,
              color: scheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText: 'Buscar producto, código o referencia',
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Limpiar búsqueda',
                      onPressed: _clearSearch,
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: scheme.outlineVariant.withOpacity(0.60),
                  width: 1.5,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: scheme.outlineVariant.withOpacity(0.60),
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: ui_colors.AppColors.primaryBlue.withOpacity(0.85),
                  width: 2,
                ),
              ),
            ),
          ),
        );
      }

      Widget buildSelectionActionsButton() {
        final actionsLabel = 'Acciones ($selectedVisibleCount)';

        return PopupMenuButton<_CatalogSelectionAction>(
          onSelected: _handleSelectionAction,
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _CatalogSelectionAction.edit,
              enabled: selectedVisibleCount == 1,
              child: const Text('Editar'),
            ),
            const PopupMenuItem(
              value: _CatalogSelectionAction.delete,
              child: Text('Eliminar'),
            ),
            const PopupMenuItem(
              value: _CatalogSelectionAction.exportPdf,
              child: Text('Exportar PDF'),
            ),
          ],
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: ui_colors.AppColors.lightBlueHover,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: ui_colors.AppColors.primaryBlue.withOpacity(0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bolt_outlined,
                  size: 17,
                  color: ui_colors.AppColors.primaryBlue,
                ),
                const SizedBox(width: 7),
                Text(
                  actionsLabel,
                  style: const TextStyle(
                    color: ui_colors.AppColors.primaryBlue,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.expand_more_rounded,
                  size: 17,
                  color: ui_colors.AppColors.primaryBlue,
                ),
              ],
            ),
          ),
        );
      }

      Widget buildUtilityIconButton({
        required IconData icon,
        required String tooltip,
        required VoidCallback? onPressed,
        String? label,
        String? description,
        Color? foregroundColor,
        Color? backgroundColor,
        Color? borderColor,
      }) {
        final effectiveForeground =
            foregroundColor ?? scheme.onSurfaceVariant;

        return Tooltip(
          message: tooltip,
          child: Material(
            color: backgroundColor ?? Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: borderColor ?? scheme.outlineVariant.withOpacity(0.70),
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onPressed,
              child: SizedBox(
                height: 40,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: label == null ? 0 : 12,
                  ),
                  child: label == null
                      ? SizedBox(
                          width: 40,
                          child: Icon(
                            icon,
                            size: 19,
                            color: effectiveForeground,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              icon,
                              size: 18,
                              color: effectiveForeground,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              label,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: backgroundColor ==
                                        ui_colors.AppColors.primaryBlue
                                    ? Colors.white
                                    : scheme.onSurface,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'Inter',
                                fontSize: 12.5,
                              ),
                            ),
                            if (description != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                description,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Inter',
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      }

      Widget buildFilterButton() {
        final hasActiveFilters = _currentFilters?.hasFilters == true;

        return SizedBox(
          height: 40,
          child: OutlinedButton.icon(
            onPressed: _showFilters,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 17,
                  color: hasActiveFilters
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                if (activeFilterCount > 0)
                  Positioned(
                    right: -7,
                    top: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$activeFilterCount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              side: BorderSide(
                color: hasActiveFilters
                    ? scheme.primary.withOpacity(0.28)
                    : scheme.outlineVariant.withOpacity(0.65),
              ),
              backgroundColor: hasActiveFilters
                  ? scheme.primary.withOpacity(0.06)
                  : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            label: Text(
              hasActiveFilters ? 'Filtros activos' : 'Filtrar',
              style: TextStyle(
                color: hasActiveFilters ? scheme.primary : scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontFamily: 'Inter',
                fontSize: 12.5,
              ),
            ),
          ),
        );
      }

      Widget buildOverflowButton() {
        return PopupMenuButton<_CatalogOverflowAction>(
          tooltip: 'Más opciones',
          padding: EdgeInsets.zero,
          onSelected: (action) {
            switch (action) {
              case _CatalogOverflowAction.exportExcel:
                _exportProductsToExcel();
                break;
              case _CatalogOverflowAction.catalogActions:
                _showCatalogActions();
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _CatalogOverflowAction.exportExcel,
              child: Text('Exportar Excel'),
            ),
            PopupMenuItem(
              value: _CatalogOverflowAction.catalogActions,
              child: Text('Acciones del catálogo'),
            ),
          ],
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                color: scheme.outlineVariant.withOpacity(0.65),
              ),
            ),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.more_horiz_rounded,
                size: 19,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }

      Widget buildToolbarActions() {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              buildFilterButton(),
              if (selectedVisibleCount > 0) ...[
                const SizedBox(width: 8),
                buildSelectionActionsButton(),
              ],
              const SizedBox(width: 8),
              buildOverflowButton(),
            ],
          ),
        );
      }

      Widget buildHeaderCell(
        String label, {
        int flex = 1,
        TextAlign textAlign = TextAlign.left,
      }) {
        return Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              label,
              textAlign: textAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'Inter',
                fontSize: 11.8,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.35,
              ),
            ),
          ),
        );
      }

      final headerContent = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductsSectionHeader(
            title: 'Productos y servicios',
            subtitle:
                'Crea, edita y administra cada detalle de los productos o servicios que vendes.',
            trailing: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              children: [
                buildUtilityIconButton(
                  icon: Icons.drive_folder_upload_rounded,
                  tooltip: 'Importar productos',
                  label: 'Importar productos',
                  onPressed: _importProductsFromExcel,
                  foregroundColor: ui_colors.AppColors.primaryBlue,
                  borderColor: ui_colors.AppColors.primaryBlue.withOpacity(
                    0.18,
                  ),
                  backgroundColor: Colors.white,
                ),
                buildUtilityIconButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Nuevo producto',
                  label: 'Nuevo producto',
                  onPressed: () => _showProductForm(),
                  foregroundColor: Colors.white,
                  borderColor: ui_colors.AppColors.primaryBlue,
                  backgroundColor: ui_colors.AppColors.primaryBlue,
                ),
              ],
            ),
          ),

          // Separación limpia entre encabezado y controles.
          const SizedBox(height: 22),

          // Barra limpia: sin tarjeta exterior, sin doble borde.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: buildSearchField()),
              const SizedBox(width: 10),
              Flexible(child: buildToolbarActions()),
            ],
          ),
        ],
      );

      Widget tableFrame({required Widget child}) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFD1D9E6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        );
      }

      Widget tableContent() {
        if (_isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (_products.isEmpty) {
          return ProductsEmptyState(
            icon: Icons.inventory_2_outlined,
            title: _searchController.text.isNotEmpty
                ? 'No se encontraron productos'
                : 'No hay productos registrados',
            message: _searchController.text.isNotEmpty
                ? 'Prueba otro término de búsqueda o ajusta los filtros activos.'
                : 'Empieza agregando el primer producto del catálogo.',
            action: FilledButton.icon(
              onPressed: () => _showProductForm(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Crear producto'),
            ),
          );
        }

        return LayoutBuilder(
          builder: (context, tableConstraints) {
            final tableWidth = math.max(tableConstraints.maxWidth, 780.0);

            return Scrollbar(
              controller: _tableHorizontalController,
              thumbVisibility: tableWidth > tableConstraints.maxWidth,
              child: SingleChildScrollView(
                controller: _tableHorizontalController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  height: tableConstraints.maxHeight,
                  child: Column(
                    children: [
                      Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          border: Border(
                            bottom: BorderSide(
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 38,
                              child: Checkbox(
                                value: allVisibleSelected
                                    ? true
                                    : (someVisibleSelected ? null : false),
                                tristate: true,
                                fillColor: WidgetStateProperty.resolveWith(
                                  (states) {
                                    if (states.contains(WidgetState.selected)) {
                                      return const Color(0xFF1A56DB);
                                    }
                                    if (states.contains(WidgetState.hovered)) {
                                      return const Color(0xFFEFF6FF);
                                    }
                                    return Colors.white;
                                  },
                                ),
                                checkColor: Colors.white,
                                side: const BorderSide(color: Color(0xFFD1D9E6)),
                                visualDensity: const VisualDensity(
                                  horizontal: -4,
                                  vertical: -4,
                                ),
                                onChanged: visibleSelectableIds.isEmpty
                                    ? null
                                    : (value) =>
                                        _toggleSelectAllVisible(value),
                              ),
                            ),
                            buildHeaderCell('Nombre', flex: 28),
                            buildHeaderCell('Código / Ref.', flex: 15),
                            buildHeaderCell(
                              'Precio venta',
                              flex: 12,
                              textAlign: TextAlign.right,
                            ),
                            buildHeaderCell(
                              'Costo',
                              flex: 12,
                              textAlign: TextAlign.right,
                            ),
                            buildHeaderCell(
                              'Stock',
                              flex: 8,
                              textAlign: TextAlign.right,
                            ),
                            buildHeaderCell(
                              'Stock mín.',
                              flex: 10,
                              textAlign: TextAlign.right,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _loadProducts,
                          child: ListView.builder(
                            itemCount: _products.length,
                            itemBuilder: (context, index) {
                              final product = _products[index];
                              final productId = product.id;
                              final isChecked =
                                  productId != null &&
                                  _selectedProductIds.contains(productId);
                              final isFocused =
                                  _selectedProduct?.id == product.id;

                              return _CatalogProductRow(
                                product: product,
                                isChecked: isChecked,
                                isFocused: isFocused,
                                showPurchasePrice: canViewPurchasePrice,
                                onSelectRow: () {
                                  setState(() => _selectedProduct = product);
                                },
                                onToggleSelected: (selected) =>
                                    _toggleProductSelection(
                                  product,
                                  selected,
                                ),
                              );
                            },
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

      return ColoredBox(
        color: pageBackground,
        child: Padding(
          padding: padding,
          child: Column(
            children: [
              headerContent,
              const SizedBox(height: 14),
              Expanded(child: tableFrame(child: tableContent())),
            ],
          ),
        ),
      );
    },
  );
}
}

 class _CatalogProductRow extends StatefulWidget {
  const _CatalogProductRow({
    required this.product,
    required this.isChecked,
    required this.isFocused,
    required this.showPurchasePrice,
    required this.onSelectRow,
    required this.onToggleSelected,
  });

  final ProductModel product;
  final bool isChecked;
  final bool isFocused;
  final bool showPurchasePrice;
  final VoidCallback onSelectRow;
  final ValueChanged<bool?> onToggleSelected;

  @override
  State<_CatalogProductRow> createState() => _CatalogProductRowState();
}

class _CatalogProductRowState extends State<_CatalogProductRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currency = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );
    final number = NumberFormat.decimalPattern('en_US');
    final product = widget.product;

    final purchaseText = widget.showPurchasePrice
        ? currency.format(product.purchasePrice)
        : '---';

    final stockColor = product.isOutOfStock
        ? scheme.error
        : (product.hasLowStock ? scheme.tertiary : scheme.onSurface);

    final rowColor = widget.isChecked
    ? const Color(0xFFEFF6FF)
    : Colors.transparent;

    Widget buildCell(
      String value, {
      required int flex,
      TextAlign textAlign = TextAlign.left,
      Color? color,
      FontWeight fontWeight = FontWeight.w600,
      TextDecoration? decoration,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            value,
            textAlign: textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color ?? scheme.onSurface,
              fontWeight: fontWeight,
              fontSize: 13.5,
              height: 1.15,
              decoration: decoration,
              fontFamily: 'Inter',
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onSelectRow,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return const Color(0xFFEFF6FF).withOpacity(0.14);
            }
            return Colors.transparent;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: rowColor,
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFFF1F5F9),
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 38,
                  child: Checkbox(
                    value: widget.isChecked,
                    visualDensity: const VisualDensity(
                      horizontal: -4,
                      vertical: -4,
                    ),
                    onChanged: product.id == null
                        ? null
                        : widget.onToggleSelected,
                  ),
                ),
                Expanded(
                  flex: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13.8,
                        height: 1.08,
                        color: scheme.onSurface,
                        fontFamily: 'Inter',
                        decoration: product.isDeleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ),
                buildCell(
                  product.code,
                  flex: 15,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                buildCell(
                  currency.format(product.salePrice),
                  flex: 12,
                  textAlign: TextAlign.right,
                  fontWeight: FontWeight.w600,
                ),
                buildCell(
                  purchaseText,
                  flex: 12,
                  textAlign: TextAlign.right,
                  color: widget.showPurchasePrice
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                ),
                buildCell(
                  number.format(product.stock),
                  flex: 8,
                  textAlign: TextAlign.right,
                  color: stockColor,
                  fontWeight: FontWeight.w600,
                ),
                buildCell(
                  number.format(product.stockMin),
                  flex: 10,
                  textAlign: TextAlign.right,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
