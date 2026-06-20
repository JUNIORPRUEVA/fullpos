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
import '../dialogs/bulk_edit_dialog.dart';
import '../dialogs/product_filters_dialog.dart';
import '../dialogs/product_form_dialog.dart';
import '../dialogs/stock_adjust_dialog.dart';
import '../widgets/products_surface.dart';
import '../../../../theme/app_colors.dart' as ui_colors;
import '../../../../widgets/success_toast.dart';

enum _CatalogSelectionAction { edit, bulkEdit, delete, exportPdf }

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
      case _CatalogSelectionAction.bulkEdit:
        await _handleBulkEdit(selectedProducts);
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

  Future<void> _handleBulkEdit(List<ProductModel> selectedProducts) async {
    if (selectedProducts.isEmpty) return;

    final canEdit = await _authorizeAction(
      AppActions.updateProduct,
      resourceType: 'product',
      resourceId: 'batch:${selectedProducts.length}',
    );
    if (!canEdit) return;

    if (!mounted) return;
    final result = await showDialog<BulkEditResult>(
      context: context,
      builder: (context) => BulkEditDialog(
        productCount: selectedProducts.length,
        categories: _categories,
        suppliers: _suppliers,
      ),
    );

    if (result == null || !mounted) return;
    if (!result.hasChanges) return;

    // Actualizar localmente sin recargar toda la lista ni mostrar loading
    final ids = selectedProducts
        .where((p) => p.id != null)
        .map((p) => p.id!)
        .toList();

    // Actualizar inmediatamente en memoria para feedback instantáneo
    setState(() {
      _products = _products.map((p) {
        if (p.id != null && ids.contains(p.id)) {
          return p.copyWith(
            categoryId: result.categoryId ?? p.categoryId,
            supplierId: result.supplierId ?? p.supplierId,
            stockMin: result.stockMin ?? p.stockMin,
          );
        }
        return p;
      }).toList();
      // Deseleccionar todos los productos editados
      _selectedProductIds.removeAll(ids.toSet());
    });

    // Mostrar notificación tipo tarjeta en la esquina superior derecha
    if (mounted) {
      SuccessToast.show(
        context,
        message: '${ids.length} productos actualizados',
        subtitle: 'Los cambios se guardaron correctamente',
        icon: Icons.check_circle_rounded,
        backgroundColor: const Color(0xFF065F46),
        iconColor: const Color(0xFF34D399),
      );
    }

    // Ejecutar la operación en background sin bloquear
    unawaited(
      _productsRepo
          .batchUpdate(
            ids: ids,
            categoryId: result.categoryId,
            supplierId: result.supplierId,
            stockMin: result.stockMin,
          )
          .catchError((e) {
            if (mounted) {
              SuccessToast.show(
                context,
                message: 'Error al actualizar productos',
                subtitle: e.toString(),
                icon: Icons.error_outline_rounded,
                backgroundColor: const Color(0xFF991B1B),
                iconColor: const Color(0xFFFCA5A5),
              );
            }
            return 0;
          }),
    );
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

        const pageBackground = Color(0xFFEFF4FA);
        const maxContentWidth = 1540.0;

        final widthFactor = constraints.maxWidth >= 1600
            ? 0.94
            : constraints.maxWidth >= 1200
            ? 0.95
            : 0.97;

        final contentWidth = math.min(
          constraints.maxWidth * widthFactor,
          maxContentWidth,
        );

        final tableHeight = math.min(
          660.0,
          math.max(470.0, constraints.maxHeight - 245),
        );

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

        Widget buildSquareButton({
          required IconData icon,
          required String label,
          required VoidCallback? onPressed,
          bool primary = false,
          bool danger = false,
          bool selected = false,
        }) {
          final bgColor = primary
              ? ui_colors.AppColors.primaryBlue
              : danger
              ? const Color(0xFFFFF1F2)
              : selected
              ? const Color(0xFFEFF6FF)
              : Colors.white;

          final fgColor = primary
              ? Colors.white
              : danger
              ? const Color(0xFFB42318)
              : selected
              ? ui_colors.AppColors.primaryBlue
              : const Color(0xFF1F2937);

          final borderColor = primary
              ? ui_colors.AppColors.primaryBlue
              : danger
              ? const Color(0xFFFCA5A5)
              : selected
              ? ui_colors.AppColors.primaryBlue.withOpacity(0.25)
              : const Color(0xFFD7E1EC);

          return Opacity(
            opacity: onPressed == null ? 0.48 : 1,
            child: Material(
              color: bgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
                side: BorderSide(color: borderColor, width: 1.1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: onPressed,
                child: SizedBox(
                  height: 42,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: fgColor),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.7,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ).copyWith(color: fgColor),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        Widget buildSearchField() {
          return SizedBox(
            height: 46,
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              onSubmitted: _handleCatalogSearchSubmit,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14.4,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
              decoration: InputDecoration(
                hintText: 'Buscar producto, código o referencia',
                hintStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.4,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 21,
                  color: Color(0xFF64748B),
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
                  vertical: 13,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(
                    color: Color(0xFFD7E1EC),
                    width: 1.35,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(
                    color: Color(0xFFD7E1EC),
                    width: 1.35,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: BorderSide(
                    color: ui_colors.AppColors.primaryBlue.withOpacity(0.85),
                    width: 1.8,
                  ),
                ),
              ),
            ),
          );
        }

        Widget buildFilterButton() {
          final hasActiveFilters = _currentFilters?.hasFilters == true;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              buildSquareButton(
                icon: Icons.tune_rounded,
                label: hasActiveFilters ? 'Filtros activos' : 'Filtrar',
                selected: hasActiveFilters,
                onPressed: _showFilters,
              ),
              if (activeFilterCount > 0)
                Positioned(
                  top: -7,
                  right: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: ui_colors.AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text(
                      '$activeFilterCount',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        Widget buildTopActionsLine() {
          return Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                buildSquareButton(
                  icon: Icons.table_chart_rounded,
                  label: 'Exportar',
                  onPressed: _exportProductsToExcel,
                ),
                buildSquareButton(
                  icon: Icons.drive_folder_upload_rounded,
                  label: 'Importar',
                  onPressed: _importProductsFromExcel,
                ),
                buildSquareButton(
                  icon: Icons.settings_suggest_rounded,
                  label: 'Catálogo',
                  onPressed: _showCatalogActions,
                ),
                buildSquareButton(
                  icon: Icons.add_rounded,
                  label: 'Nuevo producto',
                  primary: true,
                  onPressed: () => _showProductForm(),
                ),
              ],
            ),
          );
        }

        Widget buildSelectionActions() {
          if (selectedVisibleCount <= 0) {
            return const SizedBox.shrink();
          }

          return Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              if (selectedVisibleCount == 1)
                buildSquareButton(
                  icon: Icons.edit_rounded,
                  label: 'Editar',
                  selected: true,
                  onPressed: () =>
                      _handleSelectionAction(_CatalogSelectionAction.edit),
                ),
              if (selectedVisibleCount > 1)
                buildSquareButton(
                  icon: Icons.edit_note_rounded,
                  label: 'Editar selección',
                  selected: true,
                  onPressed: () =>
                      _handleSelectionAction(_CatalogSelectionAction.bulkEdit),
                ),
              buildSquareButton(
                icon: Icons.picture_as_pdf_rounded,
                label: 'PDF',
                selected: true,
                onPressed: () =>
                    _handleSelectionAction(_CatalogSelectionAction.exportPdf),
              ),
              buildSquareButton(
                icon: Icons.delete_outline_rounded,
                label: 'Eliminar',
                danger: true,
                onPressed: () =>
                    _handleSelectionAction(_CatalogSelectionAction.delete),
              ),
            ],
          );
        }

        Widget buildControlBar() {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFD7E1EC)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.025),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, toolbarConstraints) {
                if (toolbarConstraints.maxWidth >= 920) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: buildSearchField()),
                      const SizedBox(width: 10),
                      buildFilterButton(),
                      if (selectedVisibleCount > 0) ...[
                        const SizedBox(width: 8),
                        Flexible(child: buildSelectionActions()),
                      ],
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildSearchField(),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.start,
                      children: [buildFilterButton(), buildSelectionActions()],
                    ),
                  ],
                );
              },
            ),
          );
        }

        Widget buildHeaderChip({
          required IconData icon,
          required String label,
          required String value,
        }) {
          return Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFD7E1EC)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: ui_colors.AppColors.primaryBlue,
                  ),
                ),
                const SizedBox(width: 9),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        Widget buildPageHeader() {
          final titleBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Productos',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFamily: 'Inter',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  color: const Color(0xFF111827),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Inventario y servicios',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                  height: 1.2,
                ),
              ),
            ],
          );

          final chips = Wrap(
            spacing: 9,
            runSpacing: 9,
            alignment: WrapAlignment.end,
            children: [
              buildHeaderChip(
                icon: Icons.inventory_2_outlined,
                label: 'productos',
                value: '${_products.length}',
              ),
              buildHeaderChip(
                icon: Icons.checklist_rounded,
                label: 'seleccionados',
                value: '$selectedVisibleCount',
              ),
            ],
          );

          return LayoutBuilder(
            builder: (context, headerConstraints) {
              if (headerConstraints.maxWidth >= 780) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: 18),
                    chips,
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [titleBlock, const SizedBox(height: 14), chips],
              );
            },
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
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Text(
                label,
                textAlign: textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.3,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.35,
                  height: 1,
                ),
              ),
            ),
          );
        }

        Widget buildFixedHeaderCell(
          String label, {
          required double width,
          TextAlign textAlign = TextAlign.left,
        }) {
          return SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7),
              child: Text(
                label,
                textAlign: textAlign,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.3,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.35,
                  height: 1,
                ),
              ),
            ),
          );
        }

        Widget tableFrame({required Widget child}) {
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFFD4DEE9)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.055),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
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
              final tableWidth = math.max(tableConstraints.maxWidth, 1180.0);

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
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 42,
                                child: Checkbox(
                                  value: allVisibleSelected
                                      ? true
                                      : (someVisibleSelected ? null : false),
                                  tristate: true,
                                  fillColor: WidgetStateProperty.resolveWith((
                                    states,
                                  ) {
                                    if (states.contains(WidgetState.selected)) {
                                      return const Color(0xFF1A56DB);
                                    }
                                    if (states.contains(WidgetState.hovered)) {
                                      return const Color(0xFFEFF6FF);
                                    }
                                    return Colors.white;
                                  }),
                                  checkColor: Colors.white,
                                  side: const BorderSide(
                                    color: Color(0xFFD1D9E6),
                                  ),
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
                              buildFixedHeaderCell('Imagen', width: 76),
                              buildHeaderCell('Producto', flex: 32),
                              buildHeaderCell('Código / Ref.', flex: 14),
                              buildHeaderCell(
                                'Precio venta',
                                flex: 13,
                                textAlign: TextAlign.right,
                              ),
                              buildHeaderCell(
                                'Costo',
                                flex: 13,
                                textAlign: TextAlign.right,
                              ),
                              buildHeaderCell(
                                'Stock',
                                flex: 8,
                                textAlign: TextAlign.right,
                              ),
                              buildHeaderCell(
                                'Stock mín.',
                                flex: 9,
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

        final headerContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildPageHeader(),
            const SizedBox(height: 14),
            buildTopActionsLine(),
            const SizedBox(height: 12),
            buildControlBar(),
          ],
        );

        return ColoredBox(
          color: pageBackground,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth),
              child: Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 24),
                child: Column(
                  children: [
                    headerContent,
                    const SizedBox(height: 14),
                    SizedBox(
                      height: tableHeight,
                      child: tableFrame(child: tableContent()),
                    ),
                  ],
                ),
              ),
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
  String? _productImagePath(ProductModel product) {
    final localPath = product.imagePath?.trim();
    if (localPath != null && localPath.isNotEmpty) {
      return localPath;
    }

    final remoteUrl = product.imageUrl?.trim();
    if (remoteUrl != null && remoteUrl.isNotEmpty) {
      return remoteUrl;
    }

    return null;
  }

  ImageProvider? _imageProviderFromPath(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) return null;

    final path = rawPath.trim();
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return NetworkImage(path);
    }

    final file = File(path);
    if (file.existsSync()) {
      return FileImage(file);
    }

    return null;
  }

  Widget _buildProductImage(ProductModel product) {
    final provider = _imageProviderFromPath(_productImagePath(product));

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: provider == null
          ? _buildProductImagePlaceholder()
          : Image(
              image: provider,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildProductImagePlaceholder(),
            ),
    );
  }

  Widget _buildProductImagePlaceholder() {
    return Container(
      alignment: Alignment.center,
      color: const Color(0xFFEFF6FF),
      child: const Icon(
        Icons.image_outlined,
        size: 20,
        color: ui_colors.AppColors.primaryBlue,
      ),
    );
  }

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
                bottom: BorderSide(color: const Color(0xFFF1F5F9)),
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
                SizedBox(
                  width: 76,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildProductImage(product),
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
