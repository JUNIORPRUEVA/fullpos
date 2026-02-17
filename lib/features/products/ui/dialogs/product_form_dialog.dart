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
      _placeholderColorHex = p.placeholderColorHex ??
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

  String? get _previewImagePath =>
      _placeholderType == 'color' ? null : (_pendingImageSourcePath ?? _imagePath);

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

  void _setPlaceholderType(String type) {
    if (type == _placeholderType) return;
    setState(() {
      _placeholderType = type;
      if (type == 'color') {
        _pendingImageSourcePath = null;
        _imagePath = null;
        _removeImage = true;
        _placeholderColorHex = _resolvePlaceholderColor();
      } else {
        _removeImage = false;
      }
    });
  }

  void _generateColor() {
    setState(() {
      _placeholderType = 'color';
      _placeholderColorHex = _resolvePlaceholderColor();
      _pendingImageSourcePath = null;
      _imagePath = null;
      _removeImage = true;
    });
  }

  Future<void> _pickColorManually() async {
    const presets = [
      Colors.teal,
      Colors.blue,
      Colors.indigo,
      Colors.deepPurple,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.green,
      Colors.pink,
      Colors.amber,
      Colors.blueGrey,
    ];

    final selected = await showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elige un color'),
        content: SizedBox(
          width: 320,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: presets
                .map(
                  (c) => GestureDetector(
                    onTap: () => Navigator.pop(context, c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                  ),
                )
                .toList(),
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

    if (selected == null) return;
    if (!mounted) return;
    setState(() {
      _placeholderType = 'color';
      _placeholderColorHex = ColorUtils.colorToHex(selected);
      _pendingImageSourcePath = null;
      _imagePath = null;
      _removeImage = true;
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
      final salePrice = double.tryParse(_salePriceController.text.trim()) ?? 0.0;
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

  Future<void> _quickCreateCategory() async {
    final previousCategoryIds = _categories
        .map((c) => c.id)
        .whereType<int>()
        .toSet();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const CategoryFormDialog(),
    );

    if (!mounted) return;
    if (result == true) {
      // Recargar categorías
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

      if (!mounted) return;
      setState(() {
        _categories = categories;
        if (newCategoryId != null) {
          _selectedCategoryId = newCategoryId;
        } else if (_selectedCategoryId != null &&
            !categories.any((c) => c.id == _selectedCategoryId)) {
          _selectedCategoryId = null;
        }
      });
    }
  }

  Future<void> _quickCreateSupplier() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const SupplierFormDialog(),
    );

    if (!mounted) return;
    if (result == true) {
      // Recargar suplidores
      final suppliers = await _suppliersRepo.getAll();
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        if (suppliers.isNotEmpty) {
          _selectedSupplierId = suppliers.last.id;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
          child: Dialog(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, color: Colors.white),
                  const SizedBox(width: 12),
                  Text(
                    _isEdit ? 'Editar Producto' : 'Nuevo Producto',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Código y Nombre
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _codeController,
                              decoration: const InputDecoration(
                                labelText: 'Código *',
                                hintText: 'SKU o código del producto',
                                border: OutlineInputBorder(),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Requerido';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Nombre *',
                                hintText: 'Nombre del producto',
                                border: OutlineInputBorder(),
                              ),
                              textCapitalization: TextCapitalization.words,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Requerido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Categoría y Suplidor
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int?>(
                              value: _selectedCategoryId,
                              decoration: const InputDecoration(
                                labelText: 'Categoría',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Sin categoría'),
                                ),
                                ..._categories.map(
                                  (c) => DropdownMenuItem(
                                    value: c.id,
                                    child: Text(c.name),
                                  ),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _selectedCategoryId = value),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle),
                            onPressed: _quickCreateCategory,
                            tooltip: 'Crear categoría',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedSupplierId,
                              decoration: const InputDecoration(
                                labelText: 'Suplidor',
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('Sin suplidor'),
                                ),
                                ..._suppliers.map(
                                  (s) => DropdownMenuItem(
                                    value: s.id,
                                    child: Text(s.name),
                                  ),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _selectedSupplierId = value),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle),
                            onPressed: _quickCreateSupplier,
                            tooltip: 'Crear suplidor',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Imagen / Color
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Vista previa',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                              color: Colors.grey[50],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ProductThumbnail(
                                      name: _nameController.text.trim().isEmpty
                                          ? 'Producto'
                                          : _nameController.text.trim(),
                                      imagePath: _previewImagePath,
                                      placeholderColorHex: _resolvePlaceholderColor(),
                                      placeholderType: _placeholderType,
                                      categoryId: _selectedCategoryId,
                                      size: 92,
                                      width: 92,
                                      height: 92,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _nameController.text.trim().isEmpty
                                                ? 'Sin nombre'
                                                : _nameController.text.trim(),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              ChoiceChip(
                                                label: const Text('Usar imagen'),
                                                selected: _placeholderType == 'image',
                                                onSelected: (_) => _setPlaceholderType('image'),
                                              ),
                                              ChoiceChip(
                                                label:
                                                    const Text('Usar color (sin imagen)'),
                                                selected: _placeholderType == 'color',
                                                onSelected: (_) => _setPlaceholderType('color'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (_placeholderType == 'image') ...[
                                      ElevatedButton.icon(
                                        onPressed: _isLoading ? null : _pickImage,
                                        icon: const Icon(Icons.upload_file),
                                        label: const Text('Seleccionar imagen'),
                                      ),
                                      if (_previewImagePath != null)
                                        OutlinedButton.icon(
                                          onPressed: _isLoading
                                              ? null
                                              : _removeSelectedImage,
                                          icon: const Icon(Icons.delete_outline),
                                          label: const Text('Quitar'),
                                        ),
                                    ] else ...[
                                      ElevatedButton.icon(
                                        onPressed: _isLoading ? null : _generateColor,
                                        icon: const Icon(Icons.palette_outlined),
                                        label: const Text('Generar color'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed:
                                            _isLoading ? null : _pickColorManually,
                                        icon: const Icon(Icons.color_lens),
                                        label: const Text('Elegir color'),
                                      ),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 28,
                                            height: 28,
                                            decoration: BoxDecoration(
                                              color: ColorUtils.colorFromHex(
                                                _resolvePlaceholderColor(),
                                              ),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.grey.shade300,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(_resolvePlaceholderColor()),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _placeholderType == 'color'
                                      ? 'Se guardara sin imagen usando el color.'
                                      : 'Se prioriza la imagen; el color queda guardado como respaldo.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Precios
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _purchasePriceController,
                              decoration: const InputDecoration(
                                labelText: 'Precio Compra',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
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
                                if (value == null || value.trim().isEmpty) {
                                  return 'Requerido';
                                }
                                final price = double.tryParse(value.trim());
                                if (price == null || price <= 0) {
                                  return 'Debe ser mayor que 0';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _salePriceController,
                              decoration: const InputDecoration(
                                labelText: 'Precio Venta',
                                prefixText: '\$ ',
                                border: OutlineInputBorder(),
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
                                if (value == null || value.trim().isEmpty) {
                                  return 'Requerido';
                                }
                                final price = double.tryParse(value.trim());
                                if (price == null || price <= 0) {
                                  return 'Debe ser mayor que 0';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Stock
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFormField(
                                  controller: _stockController,
                                  enabled: !_isEdit,
                                  decoration: InputDecoration(
                                    labelText: 'Stock Actual',
                                    helperText: _isEdit
                                        ? 'Solo editable desde "Agregar Stock"'
                                        : null,
                                    border: const OutlineInputBorder(),
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
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Requerido';
                                    }
                                    final stock = double.tryParse(value.trim());
                                    if (stock == null || stock < 0) {
                                      return 'Inválido';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _stockMinController,
                              decoration: const InputDecoration(
                                labelText: 'Stock Mínimo',
                                border: OutlineInputBorder(),
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
                                if (value == null || value.trim().isEmpty) {
                                  return 'Requerido';
                                }
                                final stock = double.tryParse(value.trim());
                                if (stock == null || stock < 0) {
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
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_isEdit ? 'Actualizar' : 'Crear'),
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
    );
  }
}
