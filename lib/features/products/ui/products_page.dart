import 'package:flutter/material.dart';
import 'package:fullpos/features/products/ui/tabs/catalog_tab.dart';
import 'package:fullpos/features/products/ui/tabs/categories_tab.dart';
import 'package:fullpos/features/products/ui/tabs/inventory_tab.dart';

/// Página principal del módulo de Productos
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  void _goToCatalog() => _tabController.animateTo(0);

  void _goToInventory() => _tabController.animateTo(1);

  void _goToCategories() => _tabController.animateTo(2);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          const maxContentWidth = 1280.0;
          final contentWidth = constraints.maxWidth > maxContentWidth
              ? maxContentWidth
              : constraints.maxWidth;
          final side = ((constraints.maxWidth - contentWidth) / 2).clamp(
            12.0,
            40.0,
          );

          return Padding(
            padding: EdgeInsets.fromLTRB(side, 4, side, 10),
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                CatalogTab(
                  onGoToInventory: _goToInventory,
                  onGoToCategories: _goToCategories,
                ),
                InventoryTab(onBackToCatalog: _goToCatalog),
                CategoriesTab(onBackToCatalog: _goToCatalog),
              ],
            ),
          );
        },
      ),
    );
  }
}
