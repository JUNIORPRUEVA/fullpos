import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_gradient_theme.dart';
import '../../../../core/theme/color_utils.dart';
import '../../../products/models/category_model.dart';
import '../../../products/ui/dialogs/supplier_form_dialog.dart';
import '../../providers/purchase_catalog_provider.dart';

class PurchaseHeaderRow extends ConsumerStatefulWidget {
  final FocusNode? searchFocusNode;

  const PurchaseHeaderRow({super.key, this.searchFocusNode});

  @override
  ConsumerState<PurchaseHeaderRow> createState() => _PurchaseHeaderRowState();
}

class _PurchaseHeaderRowState extends ConsumerState<PurchaseHeaderRow> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradientTheme = theme.extension<AppGradientTheme>();
    final bg = gradientTheme?.mid ?? scheme.surface;
    final onBg = ColorUtils.ensureReadableColor(scheme.onSurface, bg);

    final filters = ref.watch(purchaseCatalogFiltersProvider);
    final categoriesAsync = ref.watch(purchaseCategoriesProvider);

    void commitSearch() {
      ref.read(purchaseCatalogFiltersProvider.notifier).state =
          filters.copyWith(query: _searchCtrl.text);
    }

    // Mantener controller en sync sin romper cursor: solo si difiere.
    if (_searchCtrl.text != filters.query) {
      _searchCtrl.value = TextEditingValue(
        text: filters.query,
        selection: TextSelection.collapsed(offset: filters.query.length),
      );
    }

    Widget categoryDropdown(List<CategoryModel> categories) {
      final items = <DropdownMenuItem<int?>>[
        const DropdownMenuItem(value: null, child: Text('Todas')),
        ...categories.map(
          (c) => DropdownMenuItem(
            value: c.id,
            child: Text(c.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ];

      return DropdownButtonFormField<int?>(
        value: filters.categoryId,
        items: items,
        decoration: const InputDecoration(
          labelText: 'Categoría',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onChanged: (value) {
          ref.read(purchaseCatalogFiltersProvider.notifier).state =
              filters.copyWith(categoryId: value);
        },
      );
    }

    final containerDecoration = BoxDecoration(
      color: Color.alphaBlend(scheme.surface.withOpacity(0.92), bg),
      borderRadius: BorderRadius.circular(AppSizes.radiusXL),
      border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withOpacity(0.12),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );

    return Shortcuts(
      shortcuts: const {
        // F2 para focus buscador
        SingleActivator(LogicalKeyboardKey.f2): _FocusSearchIntent(),
      },
      child: Actions(
        actions: {
          _FocusSearchIntent: CallbackAction<_FocusSearchIntent>(
            onInvoke: (_) {
              widget.searchFocusNode?.requestFocus();
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          child: Container(
            decoration: containerDecoration,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.paddingM,
              vertical: 12,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 860;

                final search = TextField(
                  controller: _searchCtrl,
                  focusNode: widget.searchFocusNode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => commitSearch(),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, color: onBg.withOpacity(0.7)),
                    hintText: 'Buscar producto (nombre o código)',
                    border: const OutlineInputBorder(),
                  ),
                );

                final onlySupplier = FilterChip(
                  selected: filters.onlySupplierProducts,
                  label: const Text('Solo proveedor'),
                  onSelected: (v) {
                    ref.read(purchaseCatalogFiltersProvider.notifier).state =
                        filters.copyWith(onlySupplierProducts: v);
                  },
                );

                final addSupplier = FilledButton.icon(
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (c) => const SupplierFormDialog(),
                    );
                    ref.invalidate(purchaseSuppliersProvider);
                  },
                  icon: const Icon(Icons.add_business),
                  label: const Text('+ Proveedor'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                );

                final category = categoriesAsync.when(
                  data: categoryDropdown,
                  loading: () => const SizedBox(
                    height: 48,
                    child: Center(child: LinearProgressIndicator(minHeight: 2)),
                  ),
                  error: (e, _) => Text(
                    'Error cargando categorías: $e',
                    style: TextStyle(color: AppColors.error),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: category),
                          const SizedBox(width: 10),
                          onlySupplier,
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: addSupplier),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 6, child: search),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: category),
                    const SizedBox(width: 10),
                    onlySupplier,
                    const SizedBox(width: 10),
                    addSupplier,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusSearchIntent extends Intent {
  const _FocusSearchIntent();
}
