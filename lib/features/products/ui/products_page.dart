import 'package:flutter/material.dart';
import 'package:fullpos/features/products/ui/stock_history_page.dart';
import 'package:fullpos/features/products/ui/tabs/add_product_page.dart';
import 'package:fullpos/features/products/ui/tabs/catalog_tab.dart';
import 'package:fullpos/features/products/ui/tabs/categories_tab.dart';
import 'package:fullpos/features/products/ui/tabs/inventory_tab.dart';
import 'package:fullpos/features/products/ui/tabs/stock_adjustments_page.dart';

enum _ProductsModuleSection {
  catalog,
  stockAdjustments,
  addProduct,
  inventory,
  categories,
  movements,
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  _ProductsModuleSection _activeSection = _ProductsModuleSection.catalog;
  final List<_ProductsModuleSection> _sectionHistory = [];
  int _catalogVersion = 0;

  void _selectSection(
    _ProductsModuleSection section, {
    bool trackHistory = true,
  }) {
    if (_activeSection == section) return;
    setState(() {
      if (trackHistory) {
        _sectionHistory.add(_activeSection);
      }
      _activeSection = section;
    });
  }

  void _goBack() {
    if (_sectionHistory.isEmpty) {
      if (_activeSection != _ProductsModuleSection.catalog) {
        setState(() => _activeSection = _ProductsModuleSection.catalog);
      }
      return;
    }

    setState(() {
      _activeSection = _sectionHistory.removeLast();
    });
  }

  void _refreshCatalog() {
    setState(() => _catalogVersion++);
  }

  Widget _buildContent() {
    switch (_activeSection) {
      case _ProductsModuleSection.catalog:
        return CatalogTab(key: ValueKey('catalog-$_catalogVersion'));
      case _ProductsModuleSection.inventory:
        return InventoryTab(embedded: true, onBackToCatalog: _goBack);
      case _ProductsModuleSection.movements:
        return StockHistoryPage(embedded: true, onBack: _goBack);
      case _ProductsModuleSection.stockAdjustments:
        return StockAdjustmentsPage(
          onOpenInventory: () =>
              _selectSection(_ProductsModuleSection.inventory),
        );
      case _ProductsModuleSection.addProduct:
        return AddProductPage(
          onBack: _goBack,
          onCreated: () {
            _refreshCatalog();
            _goBack();
          },
          onOpenCategories: () =>
              _selectSection(_ProductsModuleSection.categories),
        );
      case _ProductsModuleSection.categories:
        return CategoriesTab(onBackToCatalog: _goBack);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 980;

          return Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface.withOpacity(0.6),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: compact
                  ? Column(
                      children: [
                        _ProductsModuleSidebar(
                          activeSection: _activeSection,
                          compact: true,
                          onSelectSection: _selectSection,
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1200),
                              child: _buildContent(),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        _ProductsModuleSidebar(
                          activeSection: _activeSection,
                          onSelectSection: _selectSection,
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: scheme.outlineVariant,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1200,
                                ),
                                child: _buildContent(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductsModuleSidebar extends StatelessWidget {
  const _ProductsModuleSidebar({
    required this.activeSection,
    required this.onSelectSection,
    this.compact = false,
  });

  final _ProductsModuleSection activeSection;
  final ValueChanged<_ProductsModuleSection> onSelectSection;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final primaryItems = [
      (
        section: _ProductsModuleSection.catalog,
        label: 'Catálogo',
        icon: Icons.inventory_2_outlined,
      ),
      (
        section: _ProductsModuleSection.stockAdjustments,
        label: 'Ajuste de stock',
        icon: Icons.tune_rounded,
      ),
      (
        section: _ProductsModuleSection.addProduct,
        label: 'Agregar producto',
        icon: Icons.add_box_outlined,
      ),
    ];

    final secondaryItems = [
      (
        section: _ProductsModuleSection.inventory,
        label: 'Inventario',
        icon: Icons.analytics_outlined,
      ),
      (
        section: _ProductsModuleSection.categories,
        label: 'Categorías',
        icon: Icons.category_outlined,
      ),
      (
        section: _ProductsModuleSection.movements,
        label: 'Movimientos',
        icon: Icons.swap_horiz_rounded,
      ),
    ];

    final content = compact
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ProductsModuleSectionLabel(title: 'Principal'),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: primaryItems
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _ProductsModuleSidebarItem(
                              label: item.label,
                              icon: item.icon,
                              selected: activeSection == item.section,
                              compact: true,
                              onTap: () => onSelectSection(item.section),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: 12),
                const _ProductsModuleSectionLabel(title: 'Gestión'),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: secondaryItems
                        .map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _ProductsModuleSidebarItem(
                              label: item.label,
                              icon: item.icon,
                              selected: activeSection == item.section,
                              compact: true,
                              onTap: () => onSelectSection(item.section),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          )
        : SizedBox(
            width: 236,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Productos',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Navegación del módulo',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _ProductsModuleSectionLabel(title: 'Principal'),
                  const SizedBox(height: 8),
                  for (final item in primaryItems) ...[
                    _ProductsModuleSidebarItem(
                      label: item.label,
                      icon: item.icon,
                      selected: activeSection == item.section,
                      onTap: () => onSelectSection(item.section),
                    ),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 10),
                  Divider(height: 1, color: scheme.outlineVariant),
                  const SizedBox(height: 14),
                  const _ProductsModuleSectionLabel(title: 'Gestión'),
                  const SizedBox(height: 8),
                  for (final item in secondaryItems) ...[
                    _ProductsModuleSidebarItem(
                      label: item.label,
                      icon: item.icon,
                      selected: activeSection == item.section,
                      onTap: () => onSelectSection(item.section),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: compact ? scheme.surface : scheme.surface.withOpacity(0.9),
        borderRadius: compact
            ? const BorderRadius.vertical(top: Radius.circular(24))
            : const BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: content,
    );
  }
}

class _ProductsModuleSidebarItem extends StatefulWidget {
  const _ProductsModuleSidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_ProductsModuleSidebarItem> createState() =>
      _ProductsModuleSidebarItemState();
}

class _ProductsModuleSidebarItemState
    extends State<_ProductsModuleSidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = widget.selected
        ? scheme.primary.withOpacity(0.10)
        : (_hovered ? scheme.surfaceContainerHighest.withOpacity(0.65) : null);
    final foreground = widget.selected ? scheme.primary : scheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 12 : 14,
              vertical: widget.compact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: widget.selected
                    ? scheme.primary.withOpacity(0.26)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisSize: widget.compact
                  ? MainAxisSize.min
                  : MainAxisSize.max,
              children: [
                Icon(widget.icon, size: 18, color: foreground),
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: widget.selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductsModuleSectionLabel extends StatelessWidget {
  const _ProductsModuleSectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      ),
    );
  }
}
