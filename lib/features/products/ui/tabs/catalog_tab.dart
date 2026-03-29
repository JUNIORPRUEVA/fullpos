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
import '../dialogs/product_details_dialog.dart';
import '../dialogs/product_filters_dialog.dart';
import '../dialogs/product_form_dialog.dart';
import '../dialogs/stock_adjust_dialog.dart';
import '../widgets/product_card.dart';
import '../widgets/product_thumbnail.dart';
import '../widgets/products_surface.dart';
import '../../../../theme/app_colors.dart' as ui_colors;

/// Tab de Catálogo de Productos
class CatalogTab extends StatefulWidget {
  const CatalogTab({
    super.key,
    required this.onGoToInventory,
    required this.onGoToCategories,
  });

  final VoidCallback onGoToInventory;
  final VoidCallback onGoToCategories;

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

  List<ProductModel> _products = [];
  ProductModel? _selectedProduct;
  List<CategoryModel> _categories = [];
  List<SupplierModel> _suppliers = [];
  bool _isLoading = false;
  ProductFilters? _currentFilters;

  bool _isAdmin = false;
  UserPermissions _permissions = UserPermissions.cashier();

  ProductFilters _mergeFilters({
    int? categoryId,
    bool updateCategoryId = false,
  }) {
    final current = _currentFilters;
    return ProductFilters(
      categoryId: updateCategoryId ? categoryId : current?.categoryId,
      supplierId: current?.supplierId,
      hasLowStock: current?.hasLowStock,
      isOutOfStock: current?.isOutOfStock,
      isActive: current?.isActive,
      createdAfter: current?.createdAfter,
      createdBefore: current?.createdBefore,
    );
  }

  Future<void> _applyQuickCategoryFilter(int? categoryId) async {
    if (!mounted) return;
    setState(() {
      _currentFilters = _mergeFilters(
        categoryId: categoryId,
        updateCategoryId: true,
      );
    });
    await _loadProducts();
  }

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

  Future<void> _exportProductsCatalogPdf() async {
    await CatalogPdfLauncher.open(context);
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
    super.dispose();
  }

  void _onSearchChanged() {
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
        setState(() {
          _products = products;
          if (_selectedProduct != null) {
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

  void _showProductDetails(ProductModel product) {
    final showPurchasePrice = _isAdmin || _permissions.canViewPurchasePrice;
    final showProfit = _isAdmin || _permissions.canViewProfit;

    showDialog(
      context: context,
      builder: (context) => ProductDetailsDialog(
        product: product,
        categoryName: _getCategoryName(product.categoryId),
        supplierName: _getSupplierName(product.supplierId),
        showPurchasePrice: showPurchasePrice,
        showProfit: showProfit,
      ),
    );
  }

  void _selectProduct(ProductModel product, {required bool showDetails}) {
    setState(() => _selectedProduct = product);
    if (showDetails) {
      _showProductDetails(product);
    }
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1280.0;
    final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2).clamp(12.0, 40.0);
    return EdgeInsets.fromLTRB(side, 8, side, 8);
  }

  Widget _buildDetailsPanel(ProductModel? product) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (product == null) {
      return const SizedBox.shrink();
    }
    final canViewPurchasePrice = _isAdmin || _permissions.canViewPurchasePrice;
    final canViewProfit = _isAdmin || _permissions.canViewProfit;

    return LayoutBuilder(
      builder: (context, constraints) {
        final ultraCompact =
            constraints.maxHeight < 760 || constraints.maxWidth < 360;
        final compact =
            ultraCompact ||
            constraints.maxHeight < 840 ||
            constraints.maxWidth < 390;
        final imageHeight = ultraCompact ? 112.0 : (compact ? 136.0 : 168.0);
        final metricColumns = constraints.maxWidth >= 340 ? 3 : 2;
        final metricSpacing = ultraCompact ? 6.0 : 8.0;
        final metricWidth =
            (constraints.maxWidth - (metricSpacing * (metricColumns - 1))) /
            metricColumns;
        final saleLabel = ultraCompact ? 'Venta' : 'Precio venta';
        final purchaseLabel = ultraCompact ? 'Compra' : 'Precio compra';
        final availableLabel = ultraCompact ? 'Disp.' : 'Disponible';
        final reservedLabel = ultraCompact ? 'Apart.' : 'Apartado';
        final minimumLabel = ultraCompact ? 'Min.' : 'Stock mínimo';
        final metricWidgets = <Widget>[
          SizedBox(
            width: metricWidth,
            child: _buildDetailMetric(
              label: saleLabel,
              value: '\$${product.salePrice.toStringAsFixed(2)}',
              color: ui_colors.AppColors.primaryBlue,
              compact: compact,
            ),
          ),
          SizedBox(
            width: metricWidth,
            child: _buildDetailMetric(
              label: 'Stock',
              value: product.stock.toStringAsFixed(0),
              color: product.isOutOfStock
                  ? scheme.error
                  : (product.hasLowStock
                        ? scheme.tertiary
                        : ui_colors.AppColors.primaryBlue),
              compact: compact,
            ),
          ),
          SizedBox(
            width: metricWidth,
            child: _buildDetailMetric(
              label: availableLabel,
              value: product.availableStock.toStringAsFixed(0),
              color: scheme.secondary,
              compact: compact,
            ),
          ),
          SizedBox(
            width: metricWidth,
            child: _buildDetailMetric(
              label: reservedLabel,
              value: product.reservedStock.toStringAsFixed(0),
              color: scheme.outline,
              compact: compact,
            ),
          ),
          SizedBox(
            width: metricWidth,
            child: _buildDetailMetric(
              label: minimumLabel,
              value: product.stockMin.toStringAsFixed(0),
              color: scheme.tertiary,
              compact: compact,
            ),
          ),
          SizedBox(
            width: metricWidth,
            child: canViewPurchasePrice
                ? _buildDetailMetric(
                    label: purchaseLabel,
                    value: '\$${product.purchasePrice.toStringAsFixed(2)}',
                    color: scheme.secondary,
                    compact: compact,
                  )
                : _buildDetailMetric(
                    label: 'Actualizado',
                    value:
                        '${product.updatedAt.day.toString().padLeft(2, '0')}/${product.updatedAt.month.toString().padLeft(2, '0')}/${product.updatedAt.year}',
                    color: scheme.outline,
                    compact: compact,
                  ),
          ),
        ];

        if (canViewProfit) {
          metricWidgets.addAll([
            SizedBox(
              width: metricWidth,
              child: _buildDetailMetric(
                label: 'Ganancia',
                value: '\$${product.profit.toStringAsFixed(2)}',
                color: product.profit >= 0 ? scheme.tertiary : scheme.error,
                compact: compact,
              ),
            ),
            SizedBox(
              width: metricWidth,
              child: _buildDetailMetric(
                label: 'Margen',
                value: '${product.profitPercentage.toStringAsFixed(1)}%',
                color: product.profit >= 0 ? scheme.tertiary : scheme.error,
                compact: compact,
              ),
            ),
          ]);
        }

        return ProductsSurface(
          padding: EdgeInsets.all(ultraCompact ? 12 : (compact ? 14 : 16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: imageHeight,
                width: double.infinity,
                child: ProductThumbnail.fromProduct(
                  product,
                  width: double.infinity,
                  height: imageHeight,
                  borderRadius: BorderRadius.circular(16),
                  showBorder: false,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                product.code,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Inter',
                                  fontSize: ultraCompact ? 10 : null,
                                ),
                              ),
                            ),
                            if (product.isDeleted)
                              _buildStatusBadge('ELIMINADO', scheme.error),
                            if (!product.isActive && !product.isDeleted)
                              _buildStatusBadge('INACTIVO', scheme.outline),
                            if (product.isOutOfStock && product.isActive)
                              _buildStatusBadge('AGOTADO', scheme.error),
                            if (product.hasLowStock && product.isActive)
                              _buildStatusBadge('STOCK BAJO', scheme.tertiary),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 10 : 12,
                            vertical: compact ? 8 : 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                ui_colors.AppColors.lightBlueHover,
                                scheme.surface,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: ui_colors.AppColors.primaryBlue
                                  .withOpacity(0.12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vista operativa',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: ui_colors.AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                product.name,
                                maxLines: ultraCompact ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: ultraCompact
                                      ? 15
                                      : (compact ? 16 : 18),
                                  fontFamily: 'Inter',
                                  color: ui_colors.AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: ultraCompact ? 30 : 32,
                    height: ultraCompact ? 30 : 32,
                    child: IconButton(
                      onPressed: () => _showProductDetails(product),
                      tooltip: 'Ver detalle',
                      icon: Icon(
                        Icons.open_in_new,
                        size: ultraCompact ? 14 : 15,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: ui_colors.AppColors.cardBackgroundAlt,
                        foregroundColor: ui_colors.AppColors.primaryBlue,
                        side: BorderSide(color: ui_colors.AppColors.borderSoft),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (product.categoryId != null || product.supplierId != null) ...[
                SizedBox(height: ultraCompact ? 8 : 10),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    if (product.categoryId != null)
                      _buildContextChip(
                        icon: Icons.category_outlined,
                        text: _getCategoryName(product.categoryId) ?? '-',
                        compact: ultraCompact,
                      ),
                    if (product.supplierId != null)
                      _buildContextChip(
                        icon: Icons.business_outlined,
                        text: _getSupplierName(product.supplierId) ?? '-',
                        compact: ultraCompact,
                      ),
                  ],
                ),
              ],
              SizedBox(height: ultraCompact ? 8 : 10),
              Wrap(
                spacing: metricSpacing,
                runSpacing: metricSpacing,
                children: metricWidgets,
              ),
              SizedBox(height: ultraCompact ? 8 : 10),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 12,
                  vertical: compact ? 8 : 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ui_colors.AppColors.borderSoft),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildDetailMetric(
                        label: 'Estado',
                        value: product.isDeleted
                            ? 'Eliminado'
                            : (!product.isActive
                                  ? 'Inactivo'
                                  : (product.isOutOfStock
                                        ? 'Agotado'
                                        : (product.hasLowStock
                                              ? 'Stock bajo'
                                              : 'Operativo'))),
                        color: product.isDeleted
                            ? scheme.error
                            : (!product.isActive
                                  ? scheme.outline
                                  : (product.isOutOfStock
                                        ? scheme.error
                                        : (product.hasLowStock
                                              ? scheme.tertiary
                                              : scheme.secondary))),
                        compact: compact,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildDetailMetric(
                        label: 'Ubicación lógica',
                        value:
                            _getCategoryName(product.categoryId) ?? 'General',
                        color: ui_colors.AppColors.primaryBlue,
                        compact: compact,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 12,
                  vertical: compact ? 9 : 10,
                ),
                decoration: BoxDecoration(
                  color: ui_colors.AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ui_colors.AppColors.borderSoft),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registro',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Inter',
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildContextChip(
                      icon: Icons.calendar_today_outlined,
                      text:
                          'Creado ${product.createdAt.day.toString().padLeft(2, '0')}/${product.createdAt.month.toString().padLeft(2, '0')}/${product.createdAt.year}',
                      compact: ultraCompact,
                    ),
                    const SizedBox(height: 6),
                    _buildContextChip(
                      icon: Icons.update_outlined,
                      text:
                          'Actualizado ${product.updatedAt.day.toString().padLeft(2, '0')}/${product.updatedAt.month.toString().padLeft(2, '0')}/${product.updatedAt.year}',
                      compact: ultraCompact,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String text, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color == scheme.outline
              ? ui_colors.AppColors.textSecondary
              : scheme.onSurface,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildDetailMetric({
    required String label,
    required String value,
    required Color color,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 11,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: ui_colors.AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ui_colors.AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: ui_colors.AppColors.textSecondary,
              fontFamily: 'Inter',
              fontSize: compact ? 9 : null,
            ),
          ),
          SizedBox(height: compact ? 2 : 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
              fontFamily: 'Inter',
              fontSize: compact ? 13 : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildContextChip({
    required IconData icon,
    required String text,
    bool compact = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: ui_colors.AppColors.cardBackgroundAlt,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
        border: Border.all(color: ui_colors.AppColors.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: scheme.primary),
          SizedBox(width: compact ? 5 : 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 120 : 160),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10 : 11,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
                color: ui_colors.AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive(ProductModel product) async {
    try {
      await _productsRepo.toggleActive(product.id!, !product.isActive);
      _loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              product.isActive ? 'Producto desactivado' : 'Producto activado',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _softDelete(ProductModel product) async {
    final canDelete = await _authorizeAction(
      AppActions.deleteProduct,
      resourceType: 'product',
      resourceId: product.id?.toString(),
    );
    if (!canDelete) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          product.isDeleted ? 'Restaurar Producto' : 'Eliminar Producto',
        ),
        content: Text(
          product.isDeleted
              ? '¿Desea restaurar "${product.name}"?'
              : '¿Está seguro de eliminar "${product.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(product.isDeleted ? 'Restaurar' : 'Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (product.isDeleted) {
          await _productsRepo.restore(product.id!);
        } else {
          await _productsRepo.softDelete(product.id!);
        }
        _loadProducts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                product.isDeleted
                    ? 'Producto restaurado'
                    : 'Producto eliminado',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  String? _getCategoryName(int? categoryId) {
    if (categoryId == null) return null;
    try {
      return _categories.firstWhere((c) => c.id == categoryId).name;
    } catch (_) {
      return null;
    }
  }

  String? _getSupplierName(int? supplierId) {
    if (supplierId == null) return null;
    try {
      return _suppliers.firstWhere((s) => s.id == supplierId).name;
    } catch (_) {
      return null;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1200;
        final padding = _contentPadding(constraints);
        final selectedCategoryId = _currentFilters?.categoryId;
        final toolbarCompact = constraints.maxWidth < 1080;
        final categoryWidth = toolbarCompact ? 122.0 : 138.0;
        final actionSize = toolbarCompact ? 36.0 : 38.0;

        Widget navButton({
          required String label,
          required VoidCallback onPressed,
          required IconData icon,
        }) {
          return SizedBox(
            height: actionSize,
            child: OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: toolbarCompact ? 15 : 16),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                foregroundColor: ui_colors.AppColors.primaryBlue,
                backgroundColor: ui_colors.AppColors.lightBlueHover,
                side: BorderSide(
                  color: ui_colors.AppColors.primaryBlue.withOpacity(0.14),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: toolbarCompact ? 10 : 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                textStyle: TextStyle(
                  fontSize: toolbarCompact ? 11 : 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          );
        }

        Widget toolbarIconButton({
          required VoidCallback? onPressed,
          required IconData icon,
          required String tooltip,
          Color? foregroundColor,
          Color? backgroundColor,
          Color? borderColor,
        }) {
          return Tooltip(
            message: tooltip,
            child: SizedBox(
              width: actionSize,
              height: actionSize,
              child: IconButton(
                onPressed: onPressed,
                icon: Icon(icon, size: toolbarCompact ? 16 : 17),
                style: IconButton.styleFrom(
                  foregroundColor:
                      foregroundColor ?? ui_colors.AppColors.textPrimary,
                  backgroundColor: backgroundColor ?? Colors.white,
                  disabledBackgroundColor: Colors.white,
                  side: BorderSide(
                    color: borderColor ?? ui_colors.AppColors.borderSoft,
                  ),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          );
        }

        final searchField = TextField(
          controller: _searchController,
          decoration: InputDecoration(
            filled: true,
            fillColor: ui_colors.AppColors.cardBackgroundAlt,
            hintText: 'Buscar por código o nombre...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _loadProducts();
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        );

        final categoryFilter = DropdownButtonFormField<int?>(
          value: selectedCategoryId,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: ui_colors.AppColors.cardBackgroundAlt,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          icon: const Icon(Icons.expand_more, size: 18),
          hint: const Text('Categoría'),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('Todas', overflow: TextOverflow.ellipsis),
            ),
            ..._categories.map(
              (category) => DropdownMenuItem<int?>(
                value: category.id,
                child: Text(
                  category.name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ],
          onChanged: (value) => _applyQuickCategoryFilter(value),
        );

        final toolbarActions = [
          toolbarIconButton(
            onPressed: () => _showProductForm(),
            icon: Icons.add_box_outlined,
            tooltip: 'Crear producto',
            foregroundColor: Colors.white,
            backgroundColor: ui_colors.AppColors.primaryBlue,
            borderColor: ui_colors.AppColors.primaryBlue,
          ),
          toolbarIconButton(
            onPressed: _showFilters,
            icon: Icons.tune,
            tooltip: 'Filtros avanzados',
            foregroundColor: _currentFilters?.hasFilters == true
                ? scheme.primary
                : ui_colors.AppColors.textPrimary,
            backgroundColor: _currentFilters?.hasFilters == true
                ? scheme.primary.withOpacity(0.10)
                : Colors.white,
            borderColor: _currentFilters?.hasFilters == true
                ? scheme.primary.withOpacity(0.28)
                : ui_colors.AppColors.borderSoft,
          ),
          toolbarIconButton(
            onPressed: _exportProductsCatalogPdf,
            icon: Icons.picture_as_pdf_outlined,
            tooltip: 'Exportar PDF',
          ),
          toolbarIconButton(
            onPressed: _exportProductsToExcel,
            icon: Icons.table_view_outlined,
            tooltip: 'Exportar Excel',
          ),
          toolbarIconButton(
            onPressed: _importProductsFromExcel,
            icon: Icons.upload_file_outlined,
            tooltip: 'Importar productos',
          ),
          toolbarIconButton(
            onPressed: (_isAdmin || _permissions.canEditProducts)
                ? _handleDeleteAllProducts
                : null,
            icon: Icons.delete_sweep_outlined,
            tooltip: 'Eliminar productos',
            foregroundColor: scheme.error,
            backgroundColor: scheme.error.withOpacity(0.08),
            borderColor: scheme.error.withOpacity(0.22),
          ),
          toolbarIconButton(
            onPressed: (_isAdmin || _permissions.canEditProducts)
                ? _handleDeleteAllCategories
                : null,
            icon: Icons.category_outlined,
            tooltip: 'Eliminar categorías',
            foregroundColor: scheme.error,
            backgroundColor: scheme.error.withOpacity(0.08),
            borderColor: scheme.error.withOpacity(0.22),
          ),
        ];

        final compactToolbar = LayoutBuilder(
          builder: (context, toolbarConstraints) {
            final stackedToolbar = toolbarConstraints.maxWidth < 1160;

            final searchAndFilterRow = Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 8),
                SizedBox(width: categoryWidth, child: categoryFilter),
              ],
            );

            final actionsWrap = Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: toolbarActions,
            );

            final navRow = Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                navButton(
                  label: 'Inventario',
                  onPressed: widget.onGoToInventory,
                  icon: Icons.inventory_2_outlined,
                ),
                navButton(
                  label: 'Categorías',
                  onPressed: widget.onGoToCategories,
                  icon: Icons.category_outlined,
                ),
              ],
            );

            if (stackedToolbar) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  searchAndFilterRow,
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Flexible(child: actionsWrap),
                      const SizedBox(width: 8),
                      navRow,
                    ],
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: searchAndFilterRow),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: actionsWrap,
                ),
                const SizedBox(width: 10),
                navRow,
              ],
            );
          },
        );

        final listContent = Column(
          children: [
            ProductsSurface(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              radius: 18,
              child: compactToolbar,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ProductsSurface(
                padding: EdgeInsets.zero,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _products.isEmpty
                    ? ProductsEmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: _searchController.text.isNotEmpty
                            ? 'Sin resultados'
                            : 'Sin productos',
                        message: _searchController.text.isNotEmpty ? '' : '',
                        action: (_isAdmin || _permissions.canEditProducts)
                            ? FilledButton.icon(
                                onPressed: () => _showProductForm(),
                                icon: const Icon(Icons.add),
                                label: const Text('Crear producto'),
                              )
                            : null,
                      )
                    : RefreshIndicator(
                        onRefresh: _loadProducts,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _products.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final product = _products[index];
                            return ProductCard(
                              product: product,
                              isSelected: _selectedProduct?.id == product.id,
                              categoryName: _getCategoryName(
                                product.categoryId,
                              ),
                              supplierName: _getSupplierName(
                                product.supplierId,
                              ),
                              onTap: () =>
                                  _selectProduct(product, showDetails: !isWide),
                              onEdit: (_isAdmin || _permissions.canEditProducts)
                                  ? () => _showProductForm(product)
                                  : null,
                              onDelete: () => _softDelete(product),
                              onToggleActive:
                                  (_isAdmin || _permissions.canEditProducts)
                                  ? () => _toggleActive(product)
                                  : null,
                              onAddStock: () => _requestAdjustStock(product),
                              showPurchasePrice:
                                  _isAdmin || _permissions.canViewPurchasePrice,
                              showProfit:
                                  _isAdmin || _permissions.canViewProfit,
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        );

        if (!isWide) {
          return Padding(padding: padding, child: listContent);
        }

        final sideWidth = (constraints.maxWidth * 0.335).clamp(332.0, 450.0);

        return Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: listContent),
              if (_selectedProduct != null) ...[
                const SizedBox(width: 16),
                SizedBox(
                  width: sideWidth,
                  child: _buildDetailsPanel(_selectedProduct),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
