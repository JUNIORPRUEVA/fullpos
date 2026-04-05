import 'package:flutter/material.dart';

import '../../data/categories_repository.dart';
import '../../data/suppliers_repository.dart';
import '../../models/category_model.dart';
import '../../models/supplier_model.dart';
import '../dialogs/product_form_dialog.dart';
import '../widgets/products_surface.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({
    super.key,
    required this.onBack,
    this.onCreated,
    this.onOpenCategories,
  });

  final VoidCallback onBack;
  final VoidCallback? onCreated;
  final VoidCallback? onOpenCategories;

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final CategoriesRepository _categoriesRepo = CategoriesRepository();
  final SuppliersRepository _suppliersRepo = SuppliersRepository();

  bool _isLoading = true;
  bool _didAutoOpen = false;
  List<CategoryModel> _categories = [];
  List<SupplierModel> _suppliers = [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadData);
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _categoriesRepo.getAll(includeInactive: true),
        _suppliersRepo.getAll(includeInactive: true),
      ]);

      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<CategoryModel>;
        _suppliers = results[1] as List<SupplierModel>;
      });

      if (!_didAutoOpen) {
        _didAutoOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openForm();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al preparar formulario: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openForm() async {
    if (_isLoading || !mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) =>
          ProductFormDialog(categories: _categories, suppliers: _suppliers),
    );

    if (!mounted) return;
    if (result == true) {
      widget.onCreated?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        Expanded(
          child: ProductsSurface(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.add_business_outlined,
                              size: 40,
                              color: scheme.primary,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Crear nuevo producto',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Abre el formulario y registra el producto sin elementos visuales innecesarios.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              onPressed: _openForm,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Abrir formulario'),
                            ),
                            if (widget.onOpenCategories != null) ...[
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: widget.onOpenCategories,
                                icon: const Icon(Icons.category_outlined),
                                label: const Text('Gestionar categorías'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
