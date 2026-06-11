import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/window/window_service.dart';
import '../../../../core/utils/color_utils.dart';
import '../../../../core/security/app_actions.dart';
import '../../../../core/security/authorization_guard.dart';
import '../../data/categories_repository.dart';
import '../../data/products_repository.dart';
import '../../data/suppliers_repository.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../models/supplier_model.dart';
import '../widgets/product_thumbnail.dart';
import '../widgets/products_surface.dart';
import 'category_form_dialog.dart';
import 'supplier_form_dialog.dart';

/// Diálogo para crear/editar productos
class ProductFormDialog extends StatefulWidget {
  final ProductModel? product;
  final List<CategoryModel> categories;
  final List<SupplierModel> suppliers;

  const ProductFormDialog({
    super.key,
    this.product,
    required this.categories,
    required this.suppliers,
  });

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _SelectorValueRow extends StatefulWidget {
  const _SelectorValueRow({
    required this.title,
    required this.leading,
    required this.isSelected,
    required this.onTap,
    this.trailing,
  });

  final String title;
  final Widget leading;
  final bool isSelected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  State<_SelectorValueRow> createState() => _SelectorValueRowState();
}

class _SelectorValueRowState extends State<_SelectorValueRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = widget.isSelected
        ? const Color(0xFFEAF2FF)
        : _hovered
        ? const Color(0xFFF8FAFC)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              widget.leading,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: widget.isSelected
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 8),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectorActionRow extends StatelessWidget {
  const _SelectorActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withOpacity(0.45),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF1A56DB)),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF1A56DB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _salePriceController = TextEditingController();
  final _stockController = TextEditingController();
  final _stockMinController = TextEditingController();

  final ProductsRepository _productsRepo = ProductsRepository();
  final CategoriesRepository _categoriesRepo = CategoriesRepository();
  final SuppliersRepository _suppliersRepo = SuppliersRepository();
  final MenuController _categoryMenuController = MenuController();
  final MenuController _supplierMenuController = MenuController();

  bool _isLoading = false;
  bool _isEdit = false;
  int? _selectedCategoryId;
  int? _selectedSupplierId;
  List<CategoryModel> _categories = [];
  List<SupplierModel> _suppliers = [];

  String? _imagePath;
  String? _pendingImageSourcePath;
  bool _removeImage = false;
  String _placeholderType = 'image';
  String? _placeholderColorHex;

  CategoryModel? get _selectedCategory {
    for (final category in _categories) {
      if (category.id == _selectedCategoryId) return category;
    }
    return null;
  }

  SupplierModel? get _selectedSupplier {
    for (final supplier in _suppliers) {
      if (supplier.id == _selectedSupplierId) return supplier;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _categories = List.from(widget.categories);
    _suppliers = List.from(widget.suppliers);
    _isEdit = widget.product != null;

    if (_isEdit) {
      final p = widget.product!;
      _codeController.text = p.code;
      _nameController.text = p.name;
      _purchasePriceController.text = p.purchasePrice.toString();
      _salePriceController.text = p.salePrice.toString();
      _stockController.text = p.stock.toString();
      _stockMinController.text = p.stockMin.toString();
      _selectedCategoryId = p.categoryId;
      _selectedSupplierId = p.supplierId;
      _imagePath = p.imagePath;
      _placeholderType = p.placeholderType;
      _placeholderColorHex =
          p.placeholderColorHex ??
          ColorUtils.generateDeterministicColorHex(
            p.name,
            categoryId: p.categoryId,
          );
    } else {
      _stockController.text = '0';
      _stockMinController.text = '0';
      _purchasePriceController.text = '0';
      _salePriceController.text = '0';
      _placeholderColorHex = ColorUtils.generateDeterministicColorHex(
        '',
        categoryId: _selectedCategoryId,
      );
    }
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _codeController.dispose();
    _nameController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _stockController.dispose();
    _stockMinController.dispose();
    super.dispose();
  }

  String? get _previewImagePath => _placeholderType == 'color'
      ? null
      : (_pendingImageSourcePath ?? _imagePath);

  String _resolvePlaceholderColor() {
    if (_placeholderColorHex != null &&
        _placeholderColorHex!.trim().isNotEmpty) {
      return _placeholderColorHex!.trim();
    }
    return ColorUtils.generateDeterministicColorHex(
      _nameController.text.trim(),
      categoryId: _selectedCategoryId,
    );
  }

  void _onNameChanged() {
    if (!mounted) return;
    if (_placeholderType == 'color' &&
        (_placeholderColorHex == null || _placeholderColorHex!.isEmpty)) {
      setState(() {
        _placeholderColorHex = _resolvePlaceholderColor();
      });
    } else {
      setState(() {});
    }
  }

  Future<Directory> _ensureProductsImagesDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'product_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _copyImageToAppDir({
    int? productId,
    required String sourcePath,
  }) async {
    final imagesDir = await _ensureProductsImagesDir();
    final ext = p.extension(sourcePath);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = productId != null
        ? 'product_${productId}_$ts${ext.isEmpty ? '.png' : ext}'
        : 'product_$ts${ext.isEmpty ? '.png' : ext}';
    final destPath = p.join(imagesDir.path, fileName);
    final copied = await File(sourcePath).copy(destPath);
    return copied.path;
  }

  Future<void> _pickImage() async {
    final result = await WindowService.runWithSystemDialog(
      () => FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      ),
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    if (!mounted) return;

    setState(() {
      _pendingImageSourcePath = path;
      _removeImage = false;
      _placeholderType = 'image';
    });
  }

  void _removeSelectedImage() {
    setState(() {
      _pendingImageSourcePath = null;
      _imagePath = null;
      _removeImage = true;
      _placeholderType = 'color';
      _placeholderColorHex = _resolvePlaceholderColor();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final usingColor = _placeholderType == 'color';
    final previewPath = _previewImagePath;
    final hasImage = previewPath != null && previewPath.trim().isNotEmpty;

    if (!usingColor && !hasImage) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Debe seleccionar una imagen para el producto.'),
          ),
        );
      }
      return;
    }

    if (usingColor) {
      _placeholderColorHex = _resolvePlaceholderColor();
    }

    // Autorizaciones por accion (solo para edicion).
    if (_isEdit) {
      final old = widget.product;
      final productId = old?.id;
      if (old == null || productId == null) {
        throw StateError('El producto no tiene ID');
      }

      final code = _codeController.text.trim();
      final name = _nameController.text.trim();
      final purchasePrice =
          double.tryParse(_purchasePriceController.text.trim()) ?? 0.0;
      final salePrice =
          double.tryParse(_salePriceController.text.trim()) ?? 0.0;
      final stock = double.tryParse(_stockController.text.trim()) ?? 0.0;

      bool differsDouble(double a, double b) => (a - b).abs() > 0.0001;

      final purchaseChanged = differsDouble(purchasePrice, old.purchasePrice);
      final salePriceChanged = differsDouble(salePrice, old.salePrice);
      final stockChanged = differsDouble(stock, old.stock);

      final placeholderColor = _resolvePlaceholderColor();
      final placeholderType = _placeholderType;
      final placeholderChanged =
          old.placeholderType != placeholderType ||
          (old.placeholderColorHex ?? '') != placeholderColor;

      final otherChanged =
          old.code != code ||
          old.name != name ||
          old.categoryId != _selectedCategoryId ||
          old.supplierId != _selectedSupplierId ||
          placeholderChanged ||
          _removeImage ||
          _pendingImageSourcePath != null;

      if (purchaseChanged) {
        final ok = await requireAuthorizationIfNeeded(
          context: context,
          action: AppActions.editCost,
          resourceType: 'product',
          resourceId: productId.toString(),
          reason: 'Editar costo',
        );
        if (!ok) return;
      }
      if (salePriceChanged) {
        final ok = await requireAuthorizationIfNeeded(
          context: context,
          action: AppActions.editSalePrice,
          resourceType: 'product',
          resourceId: productId.toString(),
          reason: 'Editar precio de venta',
        );
        if (!ok) return;
      }
      if (stockChanged) {
        final ok = await requireAuthorizationIfNeeded(
          context: context,
          action: AppActions.adjustStock,
          resourceType: 'product',
          resourceId: productId.toString(),
          reason: 'Ajustar stock',
        );
        if (!ok) return;
      }
      if (otherChanged) {
        final ok = await requireAuthorizationIfNeeded(
          context: context,
          action: AppActions.updateProduct,
          resourceType: 'product',
          resourceId: productId.toString(),
          reason: 'Editar producto',
        );
        if (!ok) return;
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final code = _codeController.text.trim();
      final name = _nameController.text.trim();
      final purchasePrice =
          double.tryParse(_purchasePriceController.text.trim()) ?? 0.0;
      final salePrice =
          double.tryParse(_salePriceController.text.trim()) ?? 0.0;
      final stock = double.tryParse(_stockController.text.trim()) ?? 0.0;
      final stockMin = double.tryParse(_stockMinController.text.trim()) ?? 0.0;
      final placeholderColor = _resolvePlaceholderColor();
      final placeholderType = _placeholderType;

      final oldImagePath = widget.product?.imagePath;

      if (_isEdit) {
        final productId = widget.product!.id;
        if (productId == null) {
          throw StateError('El producto no tiene ID');
        }

        String? finalImagePath = oldImagePath;
        if (usingColor) {
          finalImagePath = null;
        } else if (_removeImage) {
          finalImagePath = null;
        } else if (_pendingImageSourcePath != null) {
          finalImagePath = await _copyImageToAppDir(
            productId: productId,
            sourcePath: _pendingImageSourcePath!,
          );
        }

        final updated = widget.product!.copyWith(
          code: code,
          name: name,
          categoryId: _selectedCategoryId,
          supplierId: _selectedSupplierId,
          imagePath: finalImagePath,
          placeholderColorHex: placeholderColor,
          placeholderType: placeholderType,
          purchasePrice: purchasePrice,
          salePrice: salePrice,
          stock: stock,
          stockMin: stockMin,
        );
        await _productsRepo.update(updated);

        _imagePath = finalImagePath;
        _pendingImageSourcePath = null;
      } else {
        final now = DateTime.now().millisecondsSinceEpoch;

        String? copiedImagePath;
        if (!usingColor) {
          copiedImagePath = await _copyImageToAppDir(
            productId: null,
            sourcePath: _pendingImageSourcePath!,
          );
        }

        final product = ProductModel(
          code: code,
          name: name,
          categoryId: _selectedCategoryId,
          supplierId: _selectedSupplierId,
          imagePath: copiedImagePath,
          placeholderColorHex: placeholderColor,
          placeholderType: placeholderType,
          purchasePrice: purchasePrice,
          salePrice: salePrice,
          stock: stock,
          stockMin: stockMin,
          createdAtMs: now,
          updatedAtMs: now,
        );

        await _productsRepo.create(product);
        _imagePath = copiedImagePath;
        _pendingImageSourcePath = null;
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit
                  ? 'Producto actualizado correctamente'
                  : 'Producto creado correctamente',
            ),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Error al guardar producto: $e');
      debugPrint('$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            content: Text('Error al guardar: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reloadCategories({int? autoSelectId}) async {
    final categories = await _categoriesRepo.getAll();
    if (!mounted) return;
    setState(() {
      _categories = categories;
      if (autoSelectId != null && categories.any((c) => c.id == autoSelectId)) {
        _selectedCategoryId = autoSelectId;
      } else if (_selectedCategoryId != null &&
          !categories.any((c) => c.id == _selectedCategoryId)) {
        _selectedCategoryId = null;
      }
    });
  }

  Future<void> _reloadSuppliers({int? autoSelectId}) async {
    final suppliers = await _suppliersRepo.getAll();
    if (!mounted) return;
    setState(() {
      _suppliers = suppliers;
      if (autoSelectId != null && suppliers.any((s) => s.id == autoSelectId)) {
        _selectedSupplierId = autoSelectId;
      } else if (_selectedSupplierId != null &&
          !suppliers.any((s) => s.id == _selectedSupplierId)) {
        _selectedSupplierId = null;
      }
    });
  }

  Future<void> _quickCreateCategory() async {
    _categoryMenuController.close();
    final previousCategoryIds = _categories
        .map((c) => c.id)
        .whereType<int>()
        .toSet();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CategoryFormDialog(),
    );
    if (!mounted || result != true) return;

    var categories = await _categoriesRepo.getAll();
    if (categories.length == _categories.length) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      categories = await _categoriesRepo.getAll();
    }

    int? newCategoryId;
    for (final category in categories) {
      final id = category.id;
      if (id != null && !previousCategoryIds.contains(id)) {
        newCategoryId = id;
        break;
      }
    }
    await _reloadCategories(autoSelectId: newCategoryId);
  }

  Future<void> _editCategory(CategoryModel category) async {
    _categoryMenuController.close();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CategoryFormDialog(category: category),
    );
    if (result == true) {
      await _reloadCategories(autoSelectId: category.id);
    }
  }

  Future<void> _deleteCategory(CategoryModel category) async {
    _categoryMenuController.close();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar categoría'),
        content: Text('¿Está seguro de eliminar "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.deleteCategory,
      resourceType: 'category',
      resourceId: category.id?.toString(),
      reason: 'Eliminar categoria',
    );
    if (!authorized || category.id == null) return;

    await _categoriesRepo.softDelete(category.id!);
    await _reloadCategories(
      autoSelectId: _selectedCategoryId == category.id
          ? null
          : _selectedCategoryId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Categoría "${category.name}" eliminada')),
    );
  }

  Future<void> _quickCreateSupplier() async {
    _supplierMenuController.close();
    final previousSupplierIds = _suppliers
        .map((s) => s.id)
        .whereType<int>()
        .toSet();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const SupplierFormDialog(),
    );
    if (!mounted || result != true) return;

    final suppliers = await _suppliersRepo.getAll();
    int? newSupplierId;
    for (final supplier in suppliers) {
      final id = supplier.id;
      if (id != null && !previousSupplierIds.contains(id)) {
        newSupplierId = id;
        break;
      }
    }
    await _reloadSuppliers(autoSelectId: newSupplierId);
  }

  Widget _buildSectionLabel(
    BuildContext context,
    String title,
    String? subtitle,
  ) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label, {String? prefixText}) {
    return InputDecoration(
      labelText: label,
      prefixText: prefixText,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _buildCategoryAvatar(CategoryModel? category, {double size = 28}) {
    final label = category?.name.trim() ?? 'Sin categoría';
    final imagePath = category?.imagePath?.trim() ?? '';
    final hasImage = imagePath.isNotEmpty && File(imagePath).existsSync();
    final initial = label.isEmpty ? '?' : label.substring(0, 1).toUpperCase();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Image.file(File(imagePath), fit: BoxFit.cover)
          : Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Color(0xFF1A56DB),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
    );
  }

  Widget _buildSelectorField({
    required BuildContext context,
    required String label,
    required String value,
    required VoidCallback onTap,
    Widget? leading,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 9,
          ),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 10)],
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.expand_more_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySelector(BuildContext context) {
    final selectedCategory = _selectedCategory;
    final menuWidth =
        ((MediaQuery.sizeOf(context).width - 96).clamp(560.0, 700.0) - 64) / 2;

    return MenuAnchor(
      controller: _categoryMenuController,
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.white),
        elevation: const WidgetStatePropertyAll(10),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withOpacity(0.55),
          ),
        ),
      ),
      menuChildren: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: menuWidth, maxHeight: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SelectorActionRow(
                icon: Icons.add_rounded,
                label: 'Nueva categoría',
                onTap: _quickCreateCategory,
              ),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SelectorValueRow(
                        title: 'Sin categoría',
                        leading: _buildCategoryAvatar(null),
                        isSelected: _selectedCategoryId == null,
                        onTap: () {
                          setState(() => _selectedCategoryId = null);
                          _categoryMenuController.close();
                        },
                      ),
                      ..._categories.map(
                        (category) => _SelectorValueRow(
                          title: category.name,
                          leading: _buildCategoryAvatar(category),
                          isSelected: _selectedCategoryId == category.id,
                          onTap: () {
                            setState(() => _selectedCategoryId = category.id);
                            _categoryMenuController.close();
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Editar',
                                onPressed: () => _editCategory(category),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Eliminar',
                                onPressed: () => _deleteCategory(category),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
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
            ],
          ),
        ),
      ],
      builder: (context, controller, child) {
        return _buildSelectorField(
          context: context,
          label: 'Categoría',
          value: selectedCategory?.name ?? 'Sin categoría',
          leading: _buildCategoryAvatar(selectedCategory),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
        );
      },
    );
  }

  Widget _buildSupplierSelector(BuildContext context) {
    final selectedSupplier = _selectedSupplier;
    final menuWidth =
        ((MediaQuery.sizeOf(context).width - 96).clamp(560.0, 700.0) - 64) / 2;

    return MenuAnchor(
      controller: _supplierMenuController,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        elevation: const WidgetStatePropertyAll(10),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withOpacity(0.55),
          ),
        ),
      ),
      menuChildren: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: menuWidth, maxHeight: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SelectorActionRow(
                icon: Icons.add_business_rounded,
                label: 'Nuevo suplidor',
                onTap: _quickCreateSupplier,
              ),
              const SizedBox(height: 6),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SelectorValueRow(
                        title: 'Sin suplidor',
                        leading: _buildStaticCircle(
                          icon: Icons.storefront_outlined,
                          color: const Color(0xFF64748B),
                        ),
                        isSelected: _selectedSupplierId == null,
                        onTap: () {
                          setState(() => _selectedSupplierId = null);
                          _supplierMenuController.close();
                        },
                      ),
                      ..._suppliers.map(
                        (supplier) => _SelectorValueRow(
                          title: supplier.name,
                          leading: _buildStaticCircle(
                            icon: Icons.local_shipping_outlined,
                            color: const Color(0xFF1A56DB),
                          ),
                          isSelected: _selectedSupplierId == supplier.id,
                          onTap: () {
                            setState(() => _selectedSupplierId = supplier.id);
                            _supplierMenuController.close();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
      builder: (context, controller, child) {
        return _buildSelectorField(
          context: context,
          label: 'Suplidor',
          value: selectedSupplier?.name ?? 'Sin suplidor',
          leading: _buildStaticCircle(
            icon: Icons.local_shipping_outlined,
            color: const Color(0xFF1A56DB),
          ),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
        );
      },
    );
  }

  Widget _buildStaticCircle({required IconData icon, required Color color}) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);

    final dialogWidth = (viewport.width - 96).clamp(560.0, 700.0).toDouble();
    final dialogMaxHeight = (viewport.height - 110)
        .clamp(560.0, 740.0)
        .toDouble();

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.pop(context),
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_isLoading) return null;
              _save();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Center(
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: dialogWidth,
                  maxHeight: dialogMaxHeight,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.13),
                        blurRadius: 32,
                        spreadRadius: -12,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ProductsSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              border: Border(
                                bottom: BorderSide(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF2FF),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFBFD1F7),
                                    ),
                                  ),
                                  child: Icon(
                                    _isEdit
                                        ? Icons.edit_note_rounded
                                        : Icons.add_box_outlined,
                                    color: const Color(0xFF1A56DB),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isEdit
                                            ? 'Editar producto'
                                            : 'Crear producto',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                              color: scheme.onSurface,
                                              fontWeight: FontWeight.w800,
                                              height: 1.05,
                                            ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Completa los datos del producto',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                              height: 1.1,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    backgroundColor: const Color(0xFFF1F5F9),
                                    foregroundColor: const Color(0xFF475569),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                16,
                                12,
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final fieldWidth =
                                      ((constraints.maxWidth - 10) / 2).clamp(
                                        240.0,
                                        constraints.maxWidth,
                                      );

                                  return Form(
                                    key: _formKey,
                                    child: SingleChildScrollView(
                                      physics: const ClampingScrollPhysics(),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildSectionLabel(
                                            context,
                                            'Datos',
                                            null,
                                          ),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              SizedBox(
                                                width: fieldWidth,
                                                child: TextFormField(
                                                  controller: _codeController,
                                                  decoration: _fieldDecoration(
                                                    'Código *',
                                                  ),
                                                  textCapitalization:
                                                      TextCapitalization
                                                          .characters,
                                                  validator: (value) {
                                                    if (value == null ||
                                                        value.trim().isEmpty) {
                                                      return 'Requerido';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ),
                                              SizedBox(
                                                width: fieldWidth,
                                                child: TextFormField(
                                                  controller: _nameController,
                                                  decoration: _fieldDecoration(
                                                    'Nombre *',
                                                  ),
                                                  textCapitalization:
                                                      TextCapitalization.words,
                                                  validator: (value) {
                                                    if (value == null ||
                                                        value.trim().isEmpty) {
                                                      return 'Requerido';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          _buildSectionLabel(
                                            context,
                                            'Clasificación',
                                            null,
                                          ),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              SizedBox(
                                                width: fieldWidth,
                                                child: _buildCategorySelector(
                                                  context,
                                                ),
                                              ),
                                              SizedBox(
                                                width: fieldWidth,
                                                child: _buildSupplierSelector(
                                                  context,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          _buildSectionLabel(
                                            context,
                                            'Imagen',
                                            null,
                                          ),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: scheme.outlineVariant,
                                              ),
                                              color: scheme.surface,
                                            ),
                                            child: Row(
                                              children: [
                                                ProductThumbnail(
                                                  name:
                                                      _nameController.text
                                                          .trim()
                                                          .isEmpty
                                                      ? 'Producto'
                                                      : _nameController.text
                                                            .trim(),
                                                  imagePath: _previewImagePath,
                                                  placeholderType: 'image',
                                                  categoryId:
                                                      _selectedCategoryId,
                                                  size: 68,
                                                  width: 68,
                                                  height: 68,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),

                                                const SizedBox(width: 12),

                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        _nameController.text
                                                                .trim()
                                                                .isEmpty
                                                            ? 'Sin nombre'
                                                            : _nameController
                                                                  .text
                                                                  .trim(),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        _previewImagePath ==
                                                                null
                                                            ? 'Sin imagen personalizada. Se usará el ícono por defecto.'
                                                            : 'Imagen personalizada seleccionada.',
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: theme
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: scheme
                                                                  .onSurfaceVariant,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                              height: 1.25,
                                                            ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: FilledButton.icon(
                                                              onPressed:
                                                                  _isLoading
                                                                  ? null
                                                                  : _pickImage,
                                                              icon: const Icon(
                                                                Icons
                                                                    .upload_file_rounded,
                                                                size: 18,
                                                              ),
                                                              label: Text(
                                                                _previewImagePath ==
                                                                        null
                                                                    ? 'Seleccionar imagen'
                                                                    : 'Cambiar imagen',
                                                              ),
                                                            ),
                                                          ),
                                                          if (_previewImagePath !=
                                                              null) ...[
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            SizedBox(
                                                              width: 42,
                                                              height: 42,
                                                              child: OutlinedButton(
                                                                onPressed:
                                                                    _isLoading
                                                                    ? null
                                                                    : _removeSelectedImage,
                                                                style: OutlinedButton.styleFrom(
                                                                  padding:
                                                                      EdgeInsets
                                                                          .zero,
                                                                ),
                                                                child: const Icon(
                                                                  Icons
                                                                      .delete_outline_rounded,
                                                                  size: 18,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          const SizedBox(height: 12),
                                          _buildSectionLabel(
                                            context,
                                            'Precios',
                                            null,
                                          ),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              SizedBox(
                                                width: fieldWidth,
                                                child: TextFormField(
                                                  controller:
                                                      _purchasePriceController,
                                                  decoration: _fieldDecoration(
                                                    'Precio compra',
                                                    prefixText: '\$ ',
                                                  ),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(
                                                      RegExp(r'^\d+\.?\d{0,2}'),
                                                    ),
                                                  ],
                                                  validator: (value) {
                                                    if (value == null ||
                                                        value.trim().isEmpty) {
                                                      return 'Requerido';
                                                    }
                                                    final price =
                                                        double.tryParse(
                                                          value.trim(),
                                                        );
                                                    if (price == null ||
                                                        price <= 0) {
                                                      return 'Debe ser mayor que 0';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ),
                                              SizedBox(
                                                width: fieldWidth,
                                                child: TextFormField(
                                                  controller:
                                                      _salePriceController,
                                                  decoration: _fieldDecoration(
                                                    'Precio venta',
                                                    prefixText: '\$ ',
                                                  ),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(
                                                      RegExp(r'^\d+\.?\d{0,2}'),
                                                    ),
                                                  ],
                                                  validator: (value) {
                                                    if (value == null ||
                                                        value.trim().isEmpty) {
                                                      return 'Requerido';
                                                    }
                                                    final price =
                                                        double.tryParse(
                                                          value.trim(),
                                                        );
                                                    if (price == null ||
                                                        price <= 0) {
                                                      return 'Debe ser mayor que 0';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          _buildSectionLabel(
                                            context,
                                            'Inventario',
                                            null,
                                          ),
                                          Wrap(
                                            spacing: 10,
                                            runSpacing: 10,
                                            children: [
                                              SizedBox(
                                                width: fieldWidth,
                                                child: TextFormField(
                                                  controller: _stockController,
                                                  enabled: !_isEdit,
                                                  decoration: _fieldDecoration(
                                                    _isEdit
                                                        ? 'Stock actual (bloqueado)'
                                                        : 'Stock actual',
                                                  ),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(
                                                      RegExp(r'^\d+\.?\d{0,2}'),
                                                    ),
                                                  ],
                                                  validator: (value) {
                                                    if (value == null ||
                                                        value.trim().isEmpty) {
                                                      return 'Requerido';
                                                    }
                                                    final stock =
                                                        double.tryParse(
                                                          value.trim(),
                                                        );
                                                    if (stock == null ||
                                                        stock < 0) {
                                                      return 'Inválido';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ),
                                              SizedBox(
                                                width: fieldWidth,
                                                child: TextFormField(
                                                  controller:
                                                      _stockMinController,
                                                  decoration: _fieldDecoration(
                                                    'Stock mínimo',
                                                  ),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        decimal: true,
                                                      ),
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter.allow(
                                                      RegExp(r'^\d+\.?\d{0,2}'),
                                                    ),
                                                  ],
                                                  validator: (value) {
                                                    if (value == null ||
                                                        value.trim().isEmpty) {
                                                      return 'Requerido';
                                                    }
                                                    final stock =
                                                        double.tryParse(
                                                          value.trim(),
                                                        );
                                                    if (stock == null ||
                                                        stock < 0) {
                                                      return 'Inválido';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              border: Border(
                                top: BorderSide(color: scheme.outlineVariant),
                              ),
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(16),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () => Navigator.pop(context),
                                  child: const Text('Cancelar'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  onPressed: _isLoading ? null : _save,
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(156, 46),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    backgroundColor: const Color(0xFF1A56DB),
                                    foregroundColor: Colors.white,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          _isEdit
                                              ? 'Guardar cambios'
                                              : 'Crear producto',
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
