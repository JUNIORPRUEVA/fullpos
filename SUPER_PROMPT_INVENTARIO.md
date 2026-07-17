# 🚀 SUPER PROMPT - MÓDULO DE INVENTARIO COMPLETO (FULLPOS)

## 📋 INSTRUCCIONES

Usa este prompt en otra app (Cursor, Windsurf, Lovable, Bolt, etc.) para **replicar EXACTAMENTE** el módulo de inventario de FULLPOS. El resultado debe ser **idéntico pixel a pixel** en UI, funcionalidad, flujos y comportamiento.

---

## 🎯 OBJETIVO GENERAL

Crear un **módulo de inventario completo** con las siguientes pantallas y funcionalidades:

1. **Catálogo de Productos** (CatalogTab) - Tabla con búsqueda, filtros, selección múltiple, edición masiva, import/export Excel, PDF
2. **Dashboard de Inventario** (InventoryTab) - KPIs, alertas de stock bajo/agotados, desglose por categoría/suplidor, movimientos recientes
3. **Ajuste de Stock** (StockAdjustmentsPage / StockAdjustmentWorkspacePage) - Panel rápido para incrementar/disminuir/fijar stock con trazabilidad
4. **Categorías** (CategoriesTab) - CRUD completo con activar/desactivar/eliminar/restaurar
5. **Suplidores** (SuppliersTab) - CRUD completo con búsqueda
6. **Crear Producto** (AddProductPage) - Formulario con selector de categoría/suplidor, imagen
7. **Diálogos**: Formulario producto, Ajuste stock, Detalles producto, Filtros, Edición masiva, Formulario categoría, Formulario suplidor

---

## 🏗️ ARQUITECTURA DEL MÓDULO

```
lib/features/products/
├── data/
│   ├── categories_repository.dart
│   ├── products_repository.dart
│   ├── stock_repository.dart
│   └── suppliers_repository.dart
├── models/
│   ├── category_model.dart
│   ├── product_model.dart
│   ├── stock_movement_model.dart
│   └── supplier_model.dart
├── ui/
│   ├── inventory_module_pages.dart          ← Página principal con tabs
│   ├── tabs/
│   │   ├── catalog_tab.dart                 ← Catálogo de productos
│   │   ├── inventory_tab.dart               ← Dashboard inventario
│   │   ├── stock_adjustments_page.dart       ← Ajuste de stock (v2)
│   │   ├── categories_tab.dart              ← CRUD categorías
│   │   ├── suppliers_tab.dart               ← CRUD suplidores
│   │   └── add_product_page.dart            ← Crear producto rápido
│   ├── dialogs/
│   │   ├── product_form_dialog.dart         ← Formulario crear/editar producto
│   │   ├── stock_adjust_dialog.dart         ← Diálogo ajuste stock
│   │   ├── product_details_dialog.dart      ← Detalles del producto
│   │   ├── product_filters_dialog.dart      ← Filtros avanzados
│   │   ├── bulk_edit_dialog.dart            ← Edición masiva
│   │   ├── category_form_dialog.dart        ← Formulario categoría
│   │   └── supplier_form_dialog.dart        ← Formulario suplidor
│   └── widgets/
│       ├── products_surface.dart            ← Contenedor con sombra/borde
│       ├── compact_product_card.dart        ← Tarjeta compacta producto
│       ├── kpi_card.dart                    ← Tarjeta KPI
│       ├── product_thumbnail.dart           ← Miniatura producto
│       └── product_card.dart                ← Tarjeta producto (si existe)
```

---

## 🎨 DISEÑO Y ESTILOS

### Colores principales
```dart
// Usar estos colores EXACTOS:
Color primaryBlue = const Color(0xFF1A56DB);
Color lightBlueHover = const Color(0xFFEFF6FF);
Color textPrimary = const Color(0xFF0F172A);
Color textSecondary = const Color(0xFF64748B);
Color borderSoft = const Color(0xFFE2E8F0);
Color pageBackground = const Color(0xFFEFF4FA);
```

### Tipografía
- **Font Family**: 'Inter' (usar Google Fonts o incluirla)
- **Font Weights**: w500 (regular), w600 (semibold), w700 (bold), w800 (extrabold), w900 (black)
- **Tamaños**: headlineSmall (24px), titleLarge (20px), titleMedium (16px), titleSmall (14px), bodyMedium (14px), bodySmall (12px), labelLarge (13px), labelMedium (11px), labelSmall (10px)

### Componentes compartidos

#### ProductsSurface
```dart
// Contenedor con borde, sombra suave y border-radius
DecoratedBox(
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(radius), // default 22
    border: Border.all(color: scheme.outlineVariant.withOpacity(0.65), width: 0.8),
    boxShadow: [
      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: Offset(0, 8)),
      BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: Offset(0, 2)),
    ],
  ),
  child: Padding(padding: padding, child: child),
)
```

#### productsResponsivePagePadding
```dart
EdgeInsets productsResponsivePagePadding(BoxConstraints constraints, {double top = 14, double bottom = 18}) {
  final width = constraints.maxWidth;
  final fraction = width >= 1200 ? 0.80 : (width >= 760 ? 0.90 : 0.95);
  final contentWidth = (width * fraction).clamp(0.0, 1180.0);
  final horizontal = ((width - contentWidth) / 2).clamp(10.0, 96.0);
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
}
```

#### ProductThumbnail
- Muestra imagen local (File) o remota (NetworkImage)
- Si no hay imagen, muestra placeholder con icono `Icons.sell_outlined` color `Color(0xFFCBD5E1)` sobre fondo blanco
- Tamaño configurable, con borde opcional `Color(0xFFDDE6F0)`
- Sombra suave opcional

#### KpiCard
- Icono en contenedor circular con color de fondo `color.withOpacity(0.11)`
- Título en `textSecondary`, valor en `color` (el color del KPI)
- Barra decorativa inferior con `FractionallySizedBox(widthFactor: 0.42)`
- Altura adaptable, con FittedBox para evitar overflow
- Si tiene `onTap`, muestra flecha `arrow_forward_ios`

#### CompactProductCard
- Barra lateral izquierda de 3px de ancho indicando estado
- Thumbnail del producto
- Código en contenedor con `surfaceContainerHighest`
- Nombre del producto
- Stock, Valor, Margen en columnas compactas
- Botón "Stock" para ajustar (opcional)

---

## 📄 PANTALLA PRINCIPAL: InventoryModulePages

### Layout
- **Tabs**: Catálogo | Inventario | Ajuste Stock | Categorías | Suplidores
- Usar `TabBar` con `Tab` widgets
- Cada tab es un `StatefulWidget` independiente
- Responsive: se adapta a cualquier tamaño de pantalla

---

## 📄 TAB 1: CATÁLOGO DE PRODUCTOS (CatalogTab)

### Características
- **Barra de búsqueda** con debounce de 500ms
- **Botón de filtros** → abre `ProductFiltersDialog` (panel lateral derecho)
- **Botón de acciones** → menú con "Eliminar todos los productos" y "Eliminar todas las categorías"
- **Botón Importar Excel** → solo admin o `canViewPurchasePrice`
- **Botón Exportar Excel** → exporta todos los productos
- **Selección múltiple** con checkbox en cada fila + checkbox "Seleccionar todo"
- **Acciones de selección**: Editar (1 solo), Edición masiva, Eliminar, Exportar PDF
- **Tabla de productos** con columnas:
  - Checkbox
  - Código
  - Nombre (con thumbnail)
  - Categoría
  - Precio Compra (si tiene permiso)
  - Precio Venta
  - Stock (con color: rojo si agotado, naranja si bajo, verde si ok)
  - Stock Mínimo
  - Ganancia (si tiene permiso)
  - Acciones: Editar, Ajustar Stock, Eliminar
- **Click en código** → abre `StockAdjustDialog`
- **Responsive**: en pantallas pequeñas oculta columnas y muestra vista compacta

### Filtros (ProductFiltersDialog)
- Panel lateral derecho
- Secciones: Categoría (radio buttons), Suplidor (radio buttons), Stock (toggles: Stock bajo, Agotados)
- Botones: Limpiar, Aplicar
- Keyboard shortcuts: Escape para cerrar, Enter para aplicar

### Edición Masiva (BulkEditDialog)
- Diálogo modal
- Secciones: Categoría, Suplidor, Stock mínimo
- Cada sección tiene toggle para activar el cambio
- Selector visual con checkmark en la opción seleccionada

---

## 📄 TAB 2: DASHBOARD DE INVENTARIO (InventoryTab)

### KPIs (7 tarjetas en grid responsivo)
1. **Inversión Total** - azul - `stock * purchasePrice` (oculto si no tiene permiso)
2. **Valor de Venta** - verde - `stock * salePrice`
3. **Ganancia Potencial** - púrpura - `stock * profit` (oculto si no tiene permiso)
4. **Margen Promedio** - teal - porcentaje (oculto si no tiene permisos)
5. **Unidades en Stock** - índigo - suma de stocks
6. **Productos Activos** - cyan - conteo
7. **Alertas activas** - naranja/verde - conteo de stock bajo + agotados

### Filtro por categoría
- Dropdown para filtrar todos los KPIs por categoría
- Muestra "X visibles"

### Sección expandible "Ver más / Ver menos"
- **Inventario por categoría** y **por suplidor**: tablas con nombre, valor, unidades, %
- **Alertas de inventario**: Stock Bajo y Agotados (tarjetas cliqueables)
- **Movimientos recientes**: lista con icono, nombre, código, tipo, fecha, usuario, cantidad

### Alertas
- Click en "Stock Bajo" → BottomSheet con lista de productos con stock bajo
- Click en "Agotados" → BottomSheet con lista de productos agotados
- Cada item tiene: barra de estado, thumbnail, código, nombre, stock, valor, margen, botón "Stock"
- DraggableScrollableSheet

---

## 📄 TAB 3: AJUSTE DE STOCK (StockAdjustmentsPage)

### Panel superior fijo
- **Título**: "INVENTARIO" (eyebrow) + "Ajuste de stock" + descripción
- **Contador**: "X productos"
- **Botón**: "Ver productos" / "Ocultar productos"

### Búsqueda y filtros
- Campo de búsqueda por nombre o código
- Dropdown de categoría
- **Filtros de disponibilidad**: Todos, Disponible, Stock bajo, Agotados, Stock alto, Prioridad (ChoiceChips)

### Formulario rápido de ajuste
- **Código**: campo con autoselección por código
- **Producto**: dropdown con todos los productos activos
- **Tipo**: Incrementar | Disminuir | Fijar exacto
- **Cantidad**: campo numérico
- **Nota**: campo opcional
- **Preview**: muestra el nuevo stock calculado
- **Botón Guardar**: con autorización y validación

### Tabla de productos (toggleable)
- Muestra productos filtrados con: thumbnail, código, nombre, categoría, stock, badge de estado
- Click en fila → selecciona producto para ajuste
- Botón de ajuste rápido en cada fila

### Movimientos recientes (toggleable)
- Lista de últimos ajustes con: icono, nombre producto, código, tipo, fecha, usuario, cantidad

---

## 📄 TAB 4: CATEGORÍAS (CategoriesTab)

### Características
- Lista con avatar (inicial o imagen), nombre, badge de estado (Activa/Inactiva/Eliminada)
- Switch para activar/desactivar
- Botones: Editar, Eliminar/Restaurar
- Botón "Nueva categoría" en header
- Vista responsiva: en compacto muestra layout vertical con más detalles
- Empty state con acción para crear primera categoría

---

## 📄 TAB 5: SUPLIDORES (SuppliersTab)

### Características
- Barra de búsqueda por nombre o teléfono
- Lista con: avatar (icono business), nombre, teléfono, nota, badge de estado
- Botones: Activar/Desactivar, Editar, Eliminar/Restaurar
- Botón "Nuevo" en header
- Empty state

---

## 📄 CREAR PRODUCTO (AddProductPage)

### Características
- Auto-abre el `ProductFormDialog` al cargar
- Muestra pantalla de bienvenida con icono y botón "Abrir formulario"
- Botón opcional "Gestionar categorías"

---

## 📄 DIÁLOGOS

### ProductFormDialog
- **Ancho**: 33% del viewport (clamp 560-700px)
- **Secciones**: Información general, Precios, Inventario, Imagen
- **Campos**: Código, Nombre, Categoría (selector con menú desplegable), Suplidor (selector), Precio Compra, Precio Venta, Stock, Stock Mínimo
- **Selector de Categoría**: MenuAnchor con búsqueda, crear nueva, editar, eliminar
- **Selector de Suplidor**: MenuAnchor con crear nuevo
- **Imagen**: picker de archivos, preview, opción de quitar
- **Placeholder**: color generado deterministicamente basado en nombre + categoría
- **Validaciones**: campos requeridos, precios > 0
- **Autorizaciones**: separadas para editar costo, precio venta, stock, datos generales
- **Keyboard shortcuts**: Enter para guardar, Escape para cerrar

### StockAdjustDialog
- **Ancho**: 33% del viewport (clamp 420-520px)
- **Alineación**: derecha (Alignment.centerRight)
- **Animación**: FadeTransition + ScaleTransition
- **Info producto**: nombre, código, stock actual, stock mínimo
- **Selector**: SegmentedButton (Agregar / Restar)
- **Campos**: Cantidad (con validación), Nota (opcional)
- **Preview**: nuevo stock con advertencia si está por debajo del mínimo
- **Botones**: Cancelar, Guardar (con icono dinámico según tipo)
- **Keyboard shortcuts**: Enter para guardar, Escape para cerrar

### ProductDetailsDialog
- **Ancho**: 42% del viewport (clamp 520-680px)
- **Alineación**: derecha
- **Secciones**: General (categoría, suplidor), Precios (compra, venta, ganancia, margen), Inventario (stock, mínimo, valor, ganancia potencial, venta potencial), Registro (creado, actualizado, eliminado)
- **Badges**: código, ELIMINADO, INACTIVO, AGOTADO, STOCK BAJO
- **Thumbnail**: grande (160px height)
- **Keyboard shortcuts**: Escape/Enter para cerrar

### CategoryFormDialog
- **Ancho**: 28% del viewport (clamp 360-460px)
- **Alineación**: derecha
- **Campos**: Nombre (requerido, mínimo 2 caracteres)
- **Imagen**: preview 74x74, picker, opción de quitar
- **Validación**: nombre único (excluyendo la categoría actual si es edición)
- **Keyboard shortcuts**: Enter para guardar, Escape para cerrar

### SupplierFormDialog
- Similar a CategoryFormDialog pero para suplidores
- Campos: Nombre, Teléfono, Nota

---

## 📊 MODELOS DE DATOS

### ProductModel
```dart
class ProductModel {
  final int? id;
  final String? businessId;
  final int? serverId;
  final String code;
  final String name;
  final String? imagePath;
  final String? imageUrl;
  final String? placeholderColorHex;
  final String placeholderType; // 'image' | 'color'
  final int? categoryId;
  final int? supplierId;
  final bool isFeatured;
  final double purchasePrice;
  final double salePrice;
  final double stock;
  final double reservedStock;
  final double stockMin;
  final bool isActive;
  final String syncStatus;
  final int localUpdatedAtMs;
  final int? serverUpdatedAtMs;
  final int version;
  final String? lastModifiedBy;
  final String? lastSyncError;
  final bool needsSync;
  final int? lastSyncedAtMs;
  final int? deletedAtMs;
  final int createdAtMs;
  final int updatedAtMs;

  // Getters computados:
  bool get isDeleted => deletedAtMs != null;
  bool get hasLowStock => stock <= stockMin && stock > 0;
  bool get isOutOfStock => stock <= 0;
  double get availableStock => stock - reservedStock;
  double get profit => salePrice - purchasePrice;
  double get profitPercentage => purchasePrice > 0 ? (profit / purchasePrice) * 100 : 0;
  double get inventoryValue => stock * purchasePrice;
  double get potentialRevenue => stock * salePrice;
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  DateTime? get deletedAt => deletedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(deletedAtMs!) : null;
}
```

### StockMovementModel
```dart
enum StockMovementType { input('in', 'Entrada'), output('out', 'Salida'), adjust('adjust', 'Ajuste'); }

class StockMovementModel {
  final int? id;
  final int productId;
  final StockMovementType type;
  final double quantity;
  final String? note;
  final int? userId;
  final int createdAtMs;
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  bool get isInput => type == StockMovementType.input;
  bool get isOutput => type == StockMovementType.output;
  bool get isAdjust => type == StockMovementType.adjust;
}

class StockMovementDetail {
  final StockMovementModel movement;
  final String? productName;
  final String? productCode;
  final double? currentStock;
  final String? userDisplayName;
  final String? userUsername;
  String get userLabel => userDisplayName ?? userUsername ?? 'Sistema';
  String get productLabel => productName ?? 'Producto #${movement.productId}';
}

class StockSummary {
  final double totalInputs;
  final double totalOutputs;
  final double totalAdjustments;
  final int movementsCount;
  double get netChange => totalInputs - totalOutputs + totalAdjustments;
}
```

### CategoryModel
```dart
class CategoryModel {
  final int? id;
  final String name;
  final String? imagePath;
  final bool isActive;
  final bool isDeleted;
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
}
```

### SupplierModel
```dart
class SupplierModel {
  final int? id;
  final String name;
  final String? phone;
  final String? note;
  final bool isActive;
  final bool isDeleted;
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;
}
```

---

## 🔐 SEGURIDAD Y AUTORIZACIONES

Usar un sistema de permisos con `UserPermissions` y `AppActions`:

```dart
// Acciones disponibles
AppActions.createProduct
AppActions.updateProduct
AppActions.deleteProduct
AppActions.addStock
AppActions.removeStock
AppActions.adjustInventory
AppActions.editCost
AppActions.editSalePrice
AppActions.deleteCategory

// Verificar autorización
final authorized = await requireAuthorizationIfNeeded(
  context: context,
  action: AppActions.adjustStock,
  resourceType: 'product',
  resourceId: product.id?.toString(),
  reason: 'Ajustar stock',
);
if (!authorized) return;
```

---

## 🔄 SINCRONIZACIÓN EN TIEMPO REAL

Usar un `ProductSyncEventBus` (Stream) para refrescar datos cuando ocurren cambios:

```dart
StreamSubscription<ProductSyncChange>? _syncSubscription;

@override
void initState() {
  super.initState();
  _syncSubscription = ProductSyncEventBus.instance.stream.listen((_) {
    _syncRefreshDebounce?.cancel();
    _syncRefreshDebounce = Timer(const Duration(milliseconds: 250), _loadData);
  });
}

@override
void dispose() {
  _syncRefreshDebounce?.cancel();
  _syncSubscription?.cancel();
  super.dispose();
}
```

---

## 📱 RESPONSIVE DESIGN

- **Pantallas grandes (>1200px)**: contenido al 80% centrado, tablas completas, layout horizontal
- **Pantallas medianas (760-1200px)**: contenido al 90%, algunas columnas ocultas
- **Pantallas pequeñas (<760px)**: contenido al 95%, vista compacta, layout vertical
- Usar `LayoutBuilder` + `BoxConstraints` para detectar tamaño disponible
- Usar `Wrap` en lugar de `Row` cuando los elementos puedan desbordarse
- `ConstrainedBox` con `maxWidth` para limitar el ancho máximo del contenido

---

## 🎬 ANIMACIONES

- **StockAdjustDialog**: FadeTransition + ScaleTransition con CurvedAnimation (easeOutCubic, 180ms)
- **StockAdjustmentsPage**: TweenAnimationBuilder con fade + translate (260ms, easeOutCubic)
- **AnimatedSwitcher** para cambiar entre vistas (220ms)
- **AnimatedContainer** para hover effects (120ms)

---

## ⚡ KEYBOARD SHORTCUTS

Todos los diálogos deben soportar:
- **Enter** → Confirmar/Guardar
- **Escape** → Cancelar/Cerrar

Usar `Shortcuts` + `Actions` + `Focus` widgets:

```dart
Shortcuts(
  shortcuts: {
    LogicalKeySet(LogicalKeyboardKey.escape): DismissIntent(),
    LogicalKeySet(LogicalKeyboardKey.enter): ActivateIntent(),
  },
  child: Actions(
    actions: {
      DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => Navigator.pop(context)),
      ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) { _save(); return null; }),
    },
    child: Focus(autofocus: true, child: child),
  ),
);
```

---

## 📦 REPOSITORIOS (DATA LAYER)

Cada repositorio debe tener estos métodos mínimos:

### ProductsRepository
```dart
Future<List<ProductModel>> getAll({ProductFilters? filters});
Future<List<ProductModel>> search(String query, {ProductFilters? filters});
Future<ProductModel?> getById(int id);
Future<ProductModel?> getByCode(String code);
Future<List<ProductModel>> getLowStock();
Future<List<ProductModel>> getOutOfStock();
Future<int> create(ProductModel product);
Future<void> update(ProductModel product);
Future<void> softDelete(int id);
Future<void> softDeleteAll();
Future<int> count({bool includeDeleted = false});
Future<int> batchUpdate({required List<int> ids, bool updateCategory, int? categoryId, bool updateSupplier, int? supplierId, bool updateStockMin, double? stockMin});
Future<List<Map<String, dynamic>>> getInventoryByCategory();
Future<List<Map<String, dynamic>>> getInventoryBySupplier();
```

### StockRepository
```dart
Future<int> adjustStock({required int productId, required StockMovementType type, required double quantity, String? note, required int userId});
Future<StockSummary> summarize();
Future<List<StockMovementDetail>> getDetailedHistory({StockMovementType? type, int limit = 50});
Future<List<StockMovementDetail>> getByProductId(int productId, {int limit = 10});
```

### CategoriesRepository
```dart
Future<List<CategoryModel>> getAll({bool includeInactive = false});
Future<int> create(CategoryModel category);
Future<void> update(CategoryModel category);
Future<void> softDelete(int id);
Future<void> softDeleteAll();
Future<void> restore(int id);
Future<void> toggleActive(int id, bool isActive);
Future<bool> existsByName(String name, {int? excludeId});
Future<int> count({bool includeInactive = false, bool includeDeleted = false});
```

### SuppliersRepository
```dart
Future<List<SupplierModel>> getAll({bool includeInactive = false});
Future<int> create(SupplierModel supplier);
Future<void> update(SupplierModel supplier);
Future<void> softDelete(int id);
Future<void> restore(int id);
Future<void> toggleActive(int id, bool isActive);
```

---

## ✅ LISTA DE VERIFICACIÓN FINAL

- [ ] **Pantalla Catálogo**: búsqueda, filtros, selección múltiple, import/export Excel, PDF, edición masiva
- [ ] **Pantalla Inventario**: 7 KPIs, filtro por categoría, alertas cliqueables, desglose, movimientos recientes
- [ ] **Pantalla Ajuste Stock**: formulario rápido, búsqueda, filtros, tabla de productos, movimientos recientes
- [ ] **Pantalla Categorías**: CRUD completo, activar/desactivar, eliminar/restaurar
- [ ] **Pantalla Suplidores**: CRUD completo, búsqueda, activar/desactivar, eliminar/restaurar
- [ ] **Diálogo Producto**: formulario completo con selectores, imagen, validaciones, autorizaciones
- [ ] **Diálogo Ajuste Stock**: animación, preview, validación, autorización
- [ ] **Diálogo Detalles**: información completa del producto
- [ ] **Diálogo Filtros**: panel lateral con categoría, suplidor, stock
- [ ] **Diálogo Edición Masiva**: categoría, suplidor, stock mínimo
- [ ] **Diálogo Categoría**: formulario con nombre e imagen
- [ ] **Diálogo Suplidor**: formulario con nombre, teléfono, nota
- [ ] **Responsive**: funciona en todos los tamaños de pantalla
- [ ] **Keyboard shortcuts**: todos los diálogos soportan Enter/Escape
- [ ] **Animaciones**: transiciones suaves en diálogos y cambios de vista
- [ ] **Seguridad**: autorizaciones en cada acción crítica
- [ ] **Sincronización**: refresco automático cuando hay cambios externos

---

## 🎯 NOTAS IMPORTANTES

1. **TODOS los diálogos deben alinearse a la derecha** (`Alignment.centerRight`) excepto BulkEditDialog y ProductFiltersDialog
2. **Usar siempre `LayoutBuilder`** para detectar el tamaño disponible y adaptar la UI
3. **Los colores y estilos deben ser EXACTAMENTE** los especificados arriba
4. **La tipografía Inter debe estar disponible** (Google Fonts o asset)
5. **Los repositorios deben ser inyectables o instanciables** - en FULLPOS se instancian directamente
6. **Los modelos deben tener `fromMap`, `toMap` y `copyWith`**
7. **Todas las listas deben ser `RefreshIndicator`** para pull-to-refresh
8. **Los estados vacíos deben usar `ProductsEmptyState`** con icono, título, mensaje y acción opcional
