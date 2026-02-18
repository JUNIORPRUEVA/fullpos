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
      ref.read(purchaseCatalogFiltersProvider.notifier).state = filters
          .copyWith(query: _searchCtrl.text);
    }

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
          (category) => DropdownMenuItem(
            value: category.id,
            child: Text(category.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ];

      return SizedBox(
        height: 42,
        child: DropdownButtonFormField<int?>(
          value: filters.categoryId,
          items: items,
          decoration: InputDecoration(
            labelText: 'Categoría',
            isDense: true,
            filled: true,
            fillColor: AppColors.surfaceLightVariant,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withOpacity(0.85),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: scheme.outlineVariant.withOpacity(0.85),
              ),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              borderSide: BorderSide(color: AppColors.brandBlue, width: 1.2),
            ),
          ),
          onChanged: (value) {
            ref.read(purchaseCatalogFiltersProvider.notifier).state = filters
                .copyWith(categoryId: value);
          },
        ),
      );
    }

    final containerDecoration = BoxDecoration(
      color: Color.alphaBlend(scheme.surface.withOpacity(0.96), bg),
      borderRadius: BorderRadius.circular(AppSizes.radiusXL),
      border: Border.all(color: scheme.outlineVariant.withOpacity(0.55)),
      boxShadow: [
        BoxShadow(
          color: theme.shadowColor.withOpacity(0.10),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    );

    return Shortcuts(
      shortcuts: const {
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 860;

                final search = SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: widget.searchFocusNode,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => commitSearch(),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(
                        Icons.search,
                        size: 18,
                        color: onBg.withOpacity(0.68),
                      ),
                      hintText: 'Buscar producto (nombre o código)',
                      filled: true,
                      fillColor: AppColors.surfaceLightVariant,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: scheme.outlineVariant.withOpacity(0.85),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: scheme.outlineVariant.withOpacity(0.85),
                        ),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                        borderSide: BorderSide(
                          color: AppColors.brandBlue,
                          width: 1.2,
                        ),
                      ),
                    ),
                  ),
                );

                final onlySupplier = SizedBox(
                  height: 40,
                  child: FilterChip(
                    selected: filters.onlySupplierProducts,
                    label: const Text('Solo proveedor'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    side: BorderSide(
                      color: filters.onlySupplierProducts
                          ? AppColors.brandBlue
                          : scheme.outlineVariant.withOpacity(0.85),
                    ),
                    selectedColor: AppColors.brandBlue.withOpacity(0.14),
                    checkmarkColor: AppColors.brandBlue,
                    labelStyle: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: filters.onlySupplierProducts
                          ? AppColors.brandBlue
                          : AppColors.textDarkSecondary,
                    ),
                    onSelected: (value) {
                      ref.read(purchaseCatalogFiltersProvider.notifier).state =
                          filters.copyWith(onlySupplierProducts: value);
                    },
                  ),
                );

                final addSupplier = SizedBox(
                  height: 40,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await showDialog<void>(
                        context: context,
                        builder: (dialogContext) => const SupplierFormDialog(),
                      );
                      ref.invalidate(purchaseSuppliersProvider);
                    },
                    icon: const Icon(Icons.add_business, size: 17),
                    label: const Text('+ Proveedor'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );

                final category = categoriesAsync.when(
                  data: categoryDropdown,
                  loading: () => const SizedBox(
                    height: 42,
                    child: Center(child: LinearProgressIndicator(minHeight: 2)),
                  ),
                  error: (error, _) => Text(
                    'Error cargando categorías: $error',
                    style: const TextStyle(color: AppColors.error),
                  ),
                );

                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: 10),
                      category,
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [onlySupplier, addSupplier],
                      ),
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
