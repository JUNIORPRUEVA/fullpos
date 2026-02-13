import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
import '../dialogs/product_details_dialog.dart';
import '../dialogs/product_filters_dialog.dart';
import '../dialogs/product_form_dialog.dart';
import '../widgets/product_card.dart';
import '../widgets/product_thumbnail.dart';

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

  List<ProductModel> _products = [];
  ProductModel? _selectedProduct;
  List<CategoryModel> _categories = [];
  List<SupplierModel> _suppliers = [];
  bool _isLoading = false;
  ProductFilters? _currentFilters;

  bool _isAdmin = false;
  UserPermissions _permissions = UserPermissions.cashier();

  Future<void> _exportProductsToExcel() async {
    try {
      final products = await _productsRepo.getAll();
      final file = await ProductsExporter.exportProductsToExcel(
        products: products,
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
          'Importados: ${importResult.inserted}, actualizados: ${importResult.updated}, omitidos: ${importResult.skipped}';
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
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al importar: $e'),
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
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _loadProducts();
    });
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
      return Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle del producto',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Selecciona un producto para ver su información.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 240,
            width: double.infinity,
            child: ProductThumbnail.fromProduct(
              product,
              width: double.infinity,
              height: 240,
              borderRadius: BorderRadius.circular(14),
              showBorder: false,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Seleccionado',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurface.withOpacity(0.65),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _showProductDetails(product),
                icon: const Icon(Icons.open_in_new, size: 18),
                tooltip: 'Ver detalle',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            product.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            'Código: ${product.code}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDetailMetric(
                  label: 'Precio venta',
                  value: '\$${product.salePrice.toStringAsFixed(2)}',
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDetailMetric(
                  label: 'Stock',
                  value: product.stock.toStringAsFixed(0),
                  color: product.isOutOfStock
                      ? scheme.error
                      : (product.hasLowStock
                            ? scheme.tertiary
                            : scheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (product.categoryId != null || product.supplierId != null)
            Text(
              [
                if (product.categoryId != null)
                  _getCategoryName(product.categoryId) ?? '',
                if (product.supplierId != null)
                  _getSupplierName(product.supplierId) ?? '',
              ].where((e) => e.isNotEmpty).join(' • '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.65),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_isAdmin || _permissions.canEditProducts)
                      ? () => _showProductForm(product)
                      : null,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Editar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _requestAdjustStock(product),
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('Stock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
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
    final result = await context.push('/products/add-stock/${product.id}');
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

        final listContent = Column(
          children: [
            // Barra de búsqueda y filtros
            Material(
              elevation: 0,
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          isDense: true,
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
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        Icons.filter_list,
                        color: _currentFilters?.hasFilters == true
                            ? scheme.primary
                            : null,
                      ),
                      onPressed: _showFilters,
                      tooltip: 'Filtros',
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () => _showProductForm(),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar producto'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: _showCatalogActions,
                      tooltip: 'Acciones',
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.table_view),
                      onPressed: _exportProductsToExcel,
                      tooltip: 'Exportar a Excel',
                    ),
                    IconButton(
                      icon: const Icon(Icons.upload_file),
                      onPressed: _importProductsFromExcel,
                      tooltip: 'Importar Excel',
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf),
                      onPressed: _exportProductsCatalogPdf,
                      tooltip: 'Catálogo PDF',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Lista de productos
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: scheme.onSurface.withOpacity(0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isNotEmpty
                                ? 'No se encontraron productos'
                                : 'No hay productos registrados',
                            style: TextStyle(
                              fontSize: 18,
                              color: scheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed:
                                (_isAdmin || _permissions.canEditProducts)
                                ? () => _showProductForm()
                                : null,
                            icon: const Icon(Icons.add),
                            label: const Text('Crear Primer Producto'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadProducts,
                      child: ListView.builder(
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          return ProductCard(
                            product: product,
                            isSelected: _selectedProduct?.id == product.id,
                            categoryName: _getCategoryName(product.categoryId),
                            supplierName: _getSupplierName(product.supplierId),
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
                            showProfit: _isAdmin || _permissions.canViewProfit,
                          );
                        },
                      ),
                    ),
            ),
          ],
        );

        if (!isWide) {
          return Padding(padding: padding, child: listContent);
        }

        final sideWidth = (constraints.maxWidth * 0.28).clamp(280.0, 360.0);

        return Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: listContent),
              const SizedBox(width: 16),
              SizedBox(
                width: sideWidth,
                child: _buildDetailsPanel(_selectedProduct),
              ),
            ],
          ),
        );
      },
    );
  }
}
