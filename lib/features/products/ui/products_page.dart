import 'package:flutter/material.dart';

import 'package:fullpos/features/products/ui/tabs/catalog_tab.dart';
import 'package:fullpos/features/products/ui/tabs/categories_tab.dart';
import 'package:fullpos/features/products/ui/tabs/inventory_tab.dart';
import 'package:fullpos/features/products/ui/tabs/suppliers_tab.dart';

/// Página principal del módulo de Productos
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        toolbarHeight: 8,
        backgroundColor: scheme.surface,
        elevation: 0,
        surfaceTintColor: scheme.surface,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: scheme.primary,
              indicatorWeight: 3,
              labelColor: scheme.primary,
              unselectedLabelColor: scheme.onSurface.withOpacity(0.6),
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              tabs: const [
                Tab(
                  height: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('Catálogo'),
                    ],
                  ),
                ),
                Tab(
                  height: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.dashboard_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('Inventario'),
                    ],
                  ),
                ),
                Tab(
                  height: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.category_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('Categorías'),
                    ],
                  ),
                ),
                Tab(
                  height: 40,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_shipping_outlined, size: 18),
                      SizedBox(width: 6),
                      Text('Suplidores'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          CatalogTab(),
          InventoryTab(),
          CategoriesTab(),
          SuppliersTab(),
        ],
      ),
    );
  }
}
