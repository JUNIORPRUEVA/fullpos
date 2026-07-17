# 🚀 SUPER PROMPT - MÓDULO DE VENTAS, FACTURAS, DEVOLUCIONES Y GASTOS (FULLPOS)

## 📋 INSTRUCCIONES

Usa este prompt en otra app (Cursor, Windsurf, Lovable, Bolt, etc.) para **replicar EXACTAMENTE** el módulo de Ventas, Facturas con Devoluciones y Gastos de FULLPOS con un diseño **fino, premium y profesional**. El resultado debe ser **idéntico pixel a pixel** en estilo, animaciones, comportamiento y organización.

---

## 🎯 OBJETIVO

Crear 3 pantallas principales con diseño **Allegra-style** (moderno, limpio, profesional):

1. **FacturaPage** (`/factura`) - Listado maestro-detalle de facturas con filtros avanzados, panel lateral de filtros, devolución integrada y panel de detalle con productos, totales y acciones.
2. **ReturnsListPage** (`/returns`) - Listado de devoluciones con detalle, búsqueda y filtros por fecha/cajero.
3. **ExpensesOverviewPage** (`/expenses`) - Visor de movimientos de caja (entradas/salidas) con filtros por rango y tipo, búsqueda y resumen de totales.

---

## 📁 ESTRUCTURA DE ARCHIVOS

```
lib/
├── core/
│   ├── constants/
│   │   └── app_colors.dart          # Paleta de colores corporativa
│   │   └── app_sizes.dart           # Espaciados y radios consistentes
│   ├── db/
│   │   └── database_manager.dart    # Gestor de BD con reopen automático
│   ├── errors/
│   │   └── error_handler.dart       # Manejador global de errores con retry
│   ├── notifications/
│   │   └── fullpos_notifications.dart # Sistema de notificaciones toast
│   ├── printing/
│   │   └── unified_ticket_printer.dart # Impresión de tickets
│   ├── security/
│   │   └── authorization_guard.dart # Guard de autorización
│   ├── session/
│   │   └── session_manager.dart     # Gestión de sesión de usuario
│   ├── theme/
│   │   └── app_status_theme.dart    # Tema de estados (success, warning, error)
│   │   └── color_utils.dart         # Utilidades de color
│   ├── utils/
│   │   └── currency_display.dart    # Formateo de moneda
│   └── widgets/
│       └── branded_loading_view.dart # Loading con marca
├── features/
│   ├── sales/
│   │   ├── data/
│   │   │   ├── sale_model.dart          # Modelo SaleModel
│   │   │   ├── sale_item_model.dart     # Modelo SaleItemModel
│   │   │   ├── sales_repository.dart    # Repositorio de ventas
│   │   │   ├── returns_repository.dart  # Repositorio de devoluciones
│   │   │   ├── refund_calculator.dart   # Calculadora de reembolsos
│   │   │   └── sale_totals_calculator.dart # Calculadora de totales
│   │   └── ui/
│   │       ├── factura_page.dart        # Pantalla principal de facturas
│   │       ├── returns_list_page.dart   # Pantalla de devoluciones
│   │       └── dialogs/
│   │           └── refund_reason_dialog.dart # Diálogo de motivo de devolución
│   └── cash/
│       ├── data/
│       │   ├── cash_movement_model.dart  # Modelo CashMovementModel
│       │   └── cash_repository.dart      # Repositorio de movimientos de caja
│       └── ui/
│           ├── expenses_overview_page.dart # Pantalla de gastos/movimientos
│           └── cash_movement_dialog.dart   # Diálogo para registrar movimiento
```

---

## 🎨 DISEÑO Y ESTILOS (Allegra-Style)

### Colores Principales

```dart
// app_colors.dart
class AppColors {
  // Brand
  static const Color brandBlue = Color(0xFF2563EB);
  static const Color brandBlueDark = Color(0xFF1E3A8A);
  static const Color brandBlueLight = Color(0xFFDBEAFE);

  // Surface
  static const Color surfaceLightVariant = Color(0xFFF2F6F9);
  static const Color surfaceLightBorder = Color(0xFFD7E1EC);

  // Text
  static const Color textDark = Color(0xFF172033);
  static const Color textDarkSecondary = Color(0xFF475569);
  static const Color textDarkMuted = Color(0xFF64748B);
  static const Color textSecondary = Color(0xFF64748B);

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color infoLight = Color(0xFFDBEAFE);

  // Borders
  static const Color borderSoft = Color(0xFFE2E8F0);

  // Hover
  static const Color lightBlueHover = Color(0xFFEFF6FF);
}
```

### Espaciados (app_sizes.dart)

```dart
class AppSizes {
  static const double paddingXS = 4.0;
  static const double paddingS = 8.0;
  static const double paddingM = 16.0;
  static const double paddingL = 24.0;
  static const double paddingXL = 32.0;
  static const double spaceXS = 4.0;
  static const double spaceS = 8.0;
  static const double spaceM = 16.0;
  static const double spaceL = 24.0;
  static const double spaceXL = 32.0;
  static const double radiusS = 8.0;
  static const double radiusM = 12.0;
  static const double radiusL = 16.0;
  static const double radiusXL = 20.0;
}
```

### Tipografía

- **Familia principal:** 'Inter' (descargar de Google Fonts)
- **Tamaños:** 9.5px (labelSmall), 11px (labelSmall), 12px (bodySmall), 13px, 14px (bodyMedium), 15px, 18px (titleMedium), 22px (titleLarge)
- **Pesos:** w400 (regular), w500 (medium), w600 (semibold), w700 (bold), w800 (extrabold), w900 (black)
- **Altura de línea (height):** 1.25, 1.3, 1.35

### Sombras

```dart
BoxShadow(
  color: AppColors.brandBlueDark.withOpacity(0.06),
  blurRadius: 20,
  offset: const Offset(0, 6),
)
```

### Bordes

- Color: `Color(0xFFCBD5E1)` o `Color(0xFFDCE5EF)` o `Color(0xFFE2E8F0)`
- Radio: 8px, 10px, 12px, 14px, 16px, 18px, 20px, 24px, 999 (pill)
- Ancho: 1.0, 1.1

---

## 📄 PANTALLA 1: FACTURAS (FacturaPage)

### Comportamiento General

- **Ruta:** `/factura`
- **StatefulWidget** con `_FacturaPageState`
- **Scaffold** con `endDrawer` para panel de filtros
- **Layout responsive:** 
  - `constraints.maxWidth >= 1100` → modo maestro-detalle (Row con flex 3:2)
  - `constraints.maxWidth < 1100` → modo lista simple con navegación a detalle
- **Header** con back button, search field, filter button y summary
- **Carga inicial:** `Future.delayed(50ms)` luego `_loadData()`

### Estados

```dart
enum DateFilter { all, today, yesterday, thisWeek, thisMonth, custom }
enum _InvoiceStatusFilter { all, active, withRefund, partialRefund, refunded }
```

### Variables de Estado Clave

```dart
SaleModel? _selectedSale;
int? _selectedSaleId;
List<SaleModel> _completedSales = [];
List<Map<String, dynamic>> _returns = [];
Map<int, String> _cashierNameBySessionId = {};
final Map<int, Future<List<SaleItemModel>>> _saleItemsFutureCache = {};
bool _isLoading = false;
String _searchQuery = '';
int _loadSeq = 0;

DateFilter _selectedFilter = DateFilter.thisMonth;
DateTime? _customDateFrom;
DateTime? _customDateTo;
int? _selectedSessionId;
_InvoiceStatusFilter _statusFilter = _InvoiceStatusFilter.active;
```

### Header (Widget _buildHeader)

```
┌─────────────────────────────────────────────────────────────┐
│ [←]  [🔍 Buscar por código, cliente o total...]  [Filtro]  │  [📊 FACTURAS: 42 | TOTAL VENDIDO: RD$ 125,430.00]
└─────────────────────────────────────────────────────────────┘
```

- **Back button:** `Material` blanco con borde `Color(0xFFCBD5E1)`, radio 8px, icono `arrow_back_rounded` 21px
- **Search field:** `TextField` con `filled: true`, `fillColor: Colors.white`, sombra suave, radio 8px, icono `search_rounded` color `Color(0xFF2563EB)`, hint text "Buscar por código, cliente o total..."
- **Filter button:** `FilledButton.icon` con fondo `Color(0xFF2563EB)`, icono `tune_rounded` o `filter_alt_outlined`, label "Filtro" o "Filtro (N)" si hay filtros activos
- **Summary:** Container blanco con borde, muestra "FACTURAS: N" y "TOTAL VENDIDO: RD$ X" con iconos en caja azul claro
- **Responsive:** Si `constraints.maxWidth < 850` se apila en columna

### Panel de Filtros Lateral (endDrawer)

```
┌─────────────────────┐
│ Filtrar facturas     │
│ Ajusta estado, fechas│
│ y cajero             │
├─────────────────────┤
│ Estado               │
│ ○ Activas            │
│ ○ Con devolución     │
│ ○ Parcial            │
│ ○ Devueltas          │
│ ○ Todas incl. devuelt│
│                      │
│ Periodo              │
│ ○ Hoy                │
│ ○ Ayer               │
│ ○ Esta semana        │
│ ○ Último mes         │
│ ○ Todas              │
│ ○ Personalizado      │
│                      │
│ Cajero               │
│ [Todos los cajeros ▼]│
├─────────────────────┤
│ [Limpiar]  [Cerrar]  │
└─────────────────────┘
```

- **Drawer** de 324px de ancho
- **Header** con título "Filtrar facturas", subtítulo explicativo y botón cerrar
- **Secciones:** Estado (RadioListTile), Periodo (RadioListTile), Cajero (DropdownButtonFormField)
- **Footer** con botones "Limpiar" y "Cerrar"
- **Filtro personalizado:** Muestra botón "Seleccionar rango" que abre `showDateRangePicker`

### Lista de Facturas (Widget _buildSalesTab)

```
┌──────────────────────────────────────────────────────────────────────┐
│ Listado de facturas                                      Filtro: ... │
│ Selecciona una factura para ver el resumen completo                 │
├──────────────────────────────────────────────────────────────────────┤
│ FAC-001234    Juan Pérez         14/07/26 15:30    [ACTIVA]  RD$ 1,250.00  [👁][↩] │
│ FAC-001235    María García       14/07/26 14:15    [ACTIVA]  RD$ 3,400.00  [👁][↩] │
│ FAC-001236    Carlos López       14/07/26 12:00    [PARCIAL] RD$ 2,100.00  [👁]    │
│ FAC-001237    Ana Martínez       13/07/26 18:45    [DEVUELTA] RD$ 500.00   [👁]    │
└──────────────────────────────────────────────────────────────────────┘
```

- **Contenedor:** Card blanca con borde `Color(0xFFCBD5E1)`, radio 14px, sombra suave
- **Header de tabla:** Título "Listado de facturas" + subtítulo + indicador de filtro activo
- **Filas:** `ListView.separated` con `Divider` entre filas
- **Cada fila:** `Material` + `InkWell` con hover color `AppColors.lightBlueHover`
- **Selección:** Fondo `AppColors.lightBlueHover.withOpacity(0.30)`
- **Facturas fiscales:** Borde izquierdo de 4px color naranja, fondo `Color(0xFFFFFBF2)`, chip "FISCAL E31/E32"
- **Compacto:** Si `rowConstraints.maxWidth < 760` se muestra en columna
- **Columnas:** Código (flex 3), Cajero (flex 3), Cliente (flex 5), Fecha (flex 3), Status chip, Monto (flex 2), Acciones
- **Status chip:** 
  - ACTIVA: fondo `Color(0xFFDCFCE7)`, texto `Color(0xFF166534)`
  - PARCIAL: fondo `Color(0xFFFEF3C7)`, texto `Color(0xFF92400E)`
  - DEVUELTA: fondo `Color(0xFFFEE2E2)`, texto `Color(0xFF991B1B)`
- **Acciones:** IconButton "👁" (ver factura), IconButton "↩" color `Color(0xFFB45309)` (devolver, solo si no está devuelta)
- **Formato moneda:** `RichText` con "RD$ " en smallStyle y monto en bigStyle

### Panel de Detalle (Widget _buildDetailsPanel)

```
┌──────────────────────────────────────┐
│ Juan Pérez                   [ACTIVA]│
│ FAC-001234                          │
│                                      │
│ Fecha     14/07/26 15:30             │
│ Cajero    Pedro Sánchez              │
│ Pago      EFECTIVO                   │
│                                      │
│ ─────────────────────────────────── │
│ DETALLE                              │
│                                      │
│ Producto A       2 x RD$ 250  RD$ 500│
│ Producto B       1 x RD$ 750  RD$ 750│
│                                      │
│ ─────────────────────────────────── │
│ Subtotal                  RD$ 1,250  │
│ ITBIS                     RD$ 225    │
│ Total factura             RD$ 1,475  │
│                                      │
│ [↩ Devolver]  [🖨 Imprimir]          │
└──────────────────────────────────────┘
```

- **Contenedor:** Card blanca con borde `AppColors.borderSoft`, radio 14px
- **Header:** Nombre del cliente (o código si es "Cliente General"), código de factura, status chip, botón cerrar
- **Metadatos:** Filas con label (62px) y valor usando `_buildTicketMetaRow`
- **Sección DETALLE:** Label con letter-spacing 1.0
- **Items:** `FutureBuilder` que carga `_loadSaleItemsForSale(sale)`, cada item muestra nombre, cantidad x precio unitario, y total
- **Totales:** Subtotal, Descuento (si aplica), Base imponible, ITBIS (si aplica), Total factura, Devuelto (si aplica), Neto vigente (si aplica), Recibido/Cambio (si aplica)
- **Devoluciones relacionadas:** Muestra hasta 3 devoluciones con código, fecha, estado de nota de crédito electrónica y monto
- **Acciones:** Botón "Devolver" (FilledButton) y "Imprimir" (OutlinedButton)

### Diálogo de Devolución (showSaleRefundDialog)

- Función standalone `showSaleRefundDialog(BuildContext context, SaleModel sale)`
- Retorna `SaleRefundOutcome?` (refunded, cancelled, null)
- Validaciones: sale.id != null, sale no cancelada ni devuelta, items con id
- Abre `_RefundDialog` como `showDialog` con `barrierDismissible: false`
- `_RefundDialog` permite seleccionar items a devolver con cantidades, motivo y opción de cancelar ticket completo

### Impresión de Ticket

```dart
Future<void> _printTicket(SaleModel sale, List<SaleItemModel> items) async {
  final settings = await PrinterSettingsRepository.getOrCreate();
  if (settings.selectedPrinterName == null || settings.selectedPrinterName!.isEmpty) {
    _showError('No hay impresora configurada');
    return;
  }
  final cashierName = await SessionManager.displayName() ?? 'Cajero';
  final result = await UnifiedTicketPrinter.printSaleTicket(
    sale: sale, items: items, cashierName: cashierName, overrideCopies: 1,
  );
  if (result.success) _showSuccess('Ticket impreso correctamente');
  else _showError('No se pudo imprimir. Verifique la impresora y reintente.');
}
```

### Consultas SQL Principales

```sql
-- Listar ventas completadas
SELECT * FROM sales 
WHERE kind IN ('invoice', 'sale') 
  AND status NOT IN ('cancelled', 'canceled')
  AND created_at_ms BETWEEN ? AND ?
ORDER BY created_at_ms DESC;

-- Listar devoluciones
SELECT * FROM returns 
WHERE created_at_ms BETWEEN ? AND ?
ORDER BY created_at_ms DESC;

-- Obtener items de una venta
SELECT * FROM sale_items WHERE sale_id = ?;

-- Obtener cantidades devueltas por venta
SELECT item_id, SUM(qty) as returned_qty 
FROM return_items WHERE original_sale_id = ?
GROUP BY item_id;
```

---

## 📄 PANTALLA 2: DEVOLUCIONES (ReturnsListPage)

### Comportamiento General

- **StatefulWidget** con `_FacturaPageState` (misma clase que facturas pero con tabs)
- **Tabs:** "Facturas" (índice 0) y "Devoluciones" (índice 1) usando `ToggleButtons`
- **Layout responsive:** `constraints.maxWidth >= 1200` → modo maestro-detalle
- **Mismos filtros** de fecha y cajero que FacturaPage

### Header

```
┌─────────────────────────────────────────────────────────────┐
│ [←] Factura  [🔍 Buscar...]  [Facturas|Devoluciones] [Hoy▼] [Rango] [Cajero▼] [🧹] [🔄] [📊 Facturas: 42 | Total: RD$ 125K]
└─────────────────────────────────────────────────────────────┘
```

- **Back button** con `IconButton(Icons.arrow_back)`
- **Search field** con debounce de 300ms
- **ToggleButtons** con borderRadius 10, dos opciones: "Facturas" y "Devoluciones"
- **DateDropdown** con `DropdownButton<DateFilter>` (Hoy, Ayer, Esta semana, Este mes, Todas, Personalizado)
- **Range button** `OutlinedButton.icon` con icono `date_range`
- **Cashier dropdown** con `DropdownButton<int?>` (Todos los cajeros, o nombres)
- **Clear button** si hay filtros activos
- **Refresh button** `IconButton(Icons.refresh)`
- **Summary** con conteo y total

### Tabla de Devoluciones

```
┌──────────────────────────────────────────────────────────────┐
│ DEV-001    Juan Pérez         14/07/26 15:30    RD$ 1,250.00 💬│
│ DEV-002    María García       14/07/26 14:15    RD$ 3,400.00   │
└──────────────────────────────────────────────────────────────┘
```

- Misma estructura visual que facturas
- Columnas: Código (flex 2), Cliente (flex 5), Fecha (flex 3), Monto (flex 2)
- Icono `comment_outlined` si tiene nota
- Al seleccionar, muestra panel de detalle con código, cliente, cajero, fecha, total, nota (si aplica) y botón "Ver detalles"

### Panel de Detalle de Devolución

```
┌──────────────────────────────────────┐
│ DEV-001                               │
│ Juan Pérez                            │
│ Cajero: Pedro Sánchez                 │
│ 🕐 14/07/26 15:30                     │
│ ───────────────────────────────────  │
│ Total                    RD$ 1,250.00 │
│                                      │
│ Nota                                  │
│ ┌──────────────────────────────────┐ │
│ │ Devolución por defecto de fábrica│ │
│ └──────────────────────────────────┘ │
│                                      │
│ [👁 Ver detalles]                    │
└──────────────────────────────────────┘
```

---

## 📄 PANTALLA 3: GASTOS / MOVIMIENTOS DE CAJA (ExpensesOverviewPage)

### Comportamiento General

- **StatefulWidget** con `_ExpensesOverviewPageState`
- **Ruta:** `/expenses`
- **Layout:** Scaffold con fondo `AppColors.surfaceLightVariant`
- **Contenido centrado** con ancho máximo 1280px
- **Carga inicial:** Rango por defecto de 30 días hacia atrás
- **Filtros:** Por rango de fecha y tipo de movimiento (Todos, Entradas, Salidas)

### Variables de Estado

```dart
late DateTimeRange _range;  // Por defecto: últimos 30 días
final _searchController = TextEditingController();
String _searchQuery = '';
MovementFilter _filter = MovementFilter.all;
bool _loading = true;
String? _error;
List<CashMovementModel> _movements = [];
int? _selectedMovementId;
```

### Header Compacto (Widget _buildTopCompactBar)

```
┌──────────────────────────────────────────────────────────────────────┐
│ [🔍]  [📈 Entradas: RD$ 50K] [📉 Salidas: RD$ 30K] [💰 Neto: RD$ 20K] [🧾 Registros: 150]  [🎛 Filtros] │
└──────────────────────────────────────────────────────────────────────┘
```

- **Search button:** `_HeaderActionIconButton` con icono `search_rounded`, tooltip "Buscar movimientos", indicador activo si hay búsqueda
- **Summary panel:** `_ExpensesHeaderSummary` con 4 badges compactos:
  - Entradas (icono `south_west_rounded`, color `AppColors.success`, fondo `AppColors.successLight`)
  - Salidas (icono `north_east_rounded`, color `AppColors.error`, fondo `AppColors.errorLight`)
  - Neto (icono `account_balance_wallet_outlined`, color `AppColors.brandBlue`, fondo `AppColors.infoLight`)
  - Registros (icono `receipt_long_outlined`, color `AppColors.textDark`, fondo `AppColors.surfaceLightVariant`)
- **Filter button:** Botón con icono `tune_rounded` en caja azul, label "Filtros"
- **Contenedor:** Card blanca con radio 18px, sombra suave, borde `AppColors.surfaceLightBorder`

### Tabla de Movimientos

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ TIPO     MOTIVO                    FECHA           SESIÓN  USUARIO  MONTO    │
├──────────────────────────────────────────────────────────────────────────────┤
│ [ENT]    Pago de proveedor        14/07/26 15:30   #42     #5       -RD$ 5,000│
│ [SAL]    Cambio para cliente      14/07/26 14:15   #42     #5       -RD$ 500  │
│ [ENT]    Depósito bancario        14/07/26 12:00   #41     #3       +RD$ 10K  │
└──────────────────────────────────────────────────────────────────────────────┘
```

- **Header row:** `_MovementsHeaderRow` con labels: Tipo (flex 2), Motivo (flex 6), Fecha (flex 3), Sesión (flex 2), Usuario (flex 2), Monto (flex 3, alineado derecha)
- **Filas:** `_CompactMovementRow` con:
  - Badge tipo: "ENT" (fondo `AppColors.successLight`, texto `AppColors.success`) o "SAL" (fondo `AppColors.errorLight`, texto `AppColors.error`)
  - Motivo en bold
  - Fecha formato `dd/MM/yy HH:mm`
  - Sesión "#N"
  - Usuario "#N" o "General"
  - Monto con signo (+ verde / - rojo)
- **Selección:** Fondo `AppColors.brandBlue.withOpacity(0.055)`, hover `AppColors.brandBlue.withOpacity(0.03)`
- **Animación:** `AnimatedContainer` con duración 160ms

### Panel de Búsqueda (_ExpensesSearchSheet)

```
┌──────────────────────────────────────┐
│ Buscar movimientos                   │
│ Busca por motivo o número de sesión  │
│                                      │
│ [🔍 Buscar motivo o sesión (#)...   ]│
│                                      │
│ [Limpiar]  [✓ Listo]                 │
└──────────────────────────────────────┘
```

- `showGeneralDialog` con animación fade + slide
- Ancho máximo 620px
- Card blanca con radio 24px, sombra pronunciada
- `TextField` con auto-focus, icono `search_rounded`, hint "Buscar motivo o sesión (#)"
- Botones "Limpiar" (OutlinedButton) y "Listo" (ElevatedButton azul)

### Panel de Filtros (_ExpensesFiltersSheet)

```
┌──────────────────────────────────────┐
│ Filtros de gastos                    │
│ Controla el rango y el tipo          │
├──────────────────────────────────────┤
│ ┌──────────────────────────────────┐ │
│ │ 📅 14 jun 2026 - 14 jul 2026    │ │
│ └──────────────────────────────────┘ │
│ [Elegir rango personalizado]         │
│ [Hoy] [7 días] [30 días] [90 días]   │
│                                      │
│ Tipo de movimiento                   │
│ [Todos] [Entradas] [Salidas]         │
│                                      │
│ Resumen de la vista                  │
│ Rango: 14 jun - 14 jul               │
│ Movimiento: Todos                    │
├──────────────────────────────────────┤
│ [Restablecer]  [✓ Aplicar filtros]   │
└──────────────────────────────────────┘
```

- `showGeneralDialog` con animación fade + slide desde la derecha
- Ancho: `min(max(390px, 34% del ancho), 480px)`
- Header con gradiente azul (`Color(0xFF0D5EC3)` a `Color(0xFF1A7FFF)`)
- Secciones en cards (`_FilterSectionCard`) con título, subtítulo y contenido
- **Periodo:** Muestra rango actual, botón "Elegir rango personalizado", chips rápidos (Hoy, 7 días, 30 días, 90 días)
- **Tipo:** `ChoiceChip` para Todos/Entradas/Salidas con color azul cuando seleccionado
- **Resumen:** Preview de filtros aplicados
- Footer con "Restablecer" (OutlinedButton) y "Aplicar filtros" (ElevatedButton azul)

### Bottom Sheet de Detalle (_showMovementDetails)

```
┌──────────────────────────────────────┐
│ Detalle                              │
│                                      │
│ [💰] Pago de proveedor    -RD$ 5,000│
│                                      │
│ [Tipo: Salida] [Sesión: #42]         │
│ [Usuario: #5] [Fecha: 14/07/26 15:30]│
└──────────────────────────────────────┘
```

- `showModalBottomSheet` con radio 16px
- Header con badge de color (verde para entrada, rojo para salida)
- Wrap con pills informativas

### Consultas SQL

```sql
-- Listar movimientos por rango
SELECT * FROM cash_movements 
WHERE created_at BETWEEN ? AND ?
ORDER BY created_at DESC
LIMIT 800;

-- Filtrar por tipo
-- Entradas: type = 'IN'
-- Salidas: type = 'OUT'
-- movement_type: 'expense' | 'owner_draw' | 'transfer'
-- affects_profit: 1 | 0
```

---

## 🧩 MODELOS DE DATOS

### SaleModel

```dart
class SaleModel {
  final int? id;
  final String localCode;
  final String kind;           // 'invoice', 'sale'
  final String status;         // 'active', 'PARTIAL_REFUND', 'REFUNDED', 'cancelled'
  final double total;
  final double subtotal;
  final double discountTotal;
  final double itbisAmount;
  final double itbisRate;
  final int itbisEnabled;      // 0 o 1
  final double paidAmount;
  final double changeAmount;
  final int createdAtMs;
  final int? sessionId;
  final String? customerNameSnapshot;
  final String? customerPhoneSnapshot;
  final String? customerRncSnapshot;
  final String? paymentMethod;
  final String? paymentMethodDisplayLabel;
  final int electronicInvoiceEnabled;  // 0 o 1
  final String? electronicInvoiceCode;
  final String? electronicDocumentType;
}
```

### SaleItemModel

```dart
class SaleItemModel {
  final int? id;
  final int? productId;
  final String productNameSnapshot;
  final double qty;
  final double unitPrice;
  final double totalLine;
  final double discountLine;
  final double? purchasePriceSnapshot;
}
```

### CashMovementModel

```dart
class CashMovementModel {
  final int? id;
  final int sessionId;
  final int userId;
  final String type;           // 'IN' | 'OUT'
  final double amount;
  final String reason;
  final String movementType;   // 'expense' | 'owner_draw' | 'transfer'
  final bool affectsProfit;
  final DateTime createdAt;
  final int createdAtMs;

  bool get isIn => type == 'IN';
  bool get isOut => type == 'OUT';
  bool get isExpense => type == 'OUT';
}
```

### CashMovementType / CashMovementAccountingType

```dart
class CashMovementType {
  static const String income = 'IN';
  static const String expense = 'OUT';
  static const List<String> all = ['IN', 'OUT'];
}

class CashMovementAccountingType {
  static const String expense = 'expense';
  static const String ownerDraw = 'owner_draw';
  static const String transfer = 'transfer';
}
```

---

## 🧩 WIDGETS REUTILIZABLES

### _buildMoneyText

```dart
Widget _buildMoneyText({
  required double amount,
  required TextStyle? bigStyle,
  required TextStyle? smallStyle,
}) {
  final formatter = CurrencyDisplay.currency(symbol: '');
  return RichText(
    text: TextSpan(
      children: [
        TextSpan(text: 'RD\$ ', style: smallStyle),
        TextSpan(text: formatter.format(amount).trim(), style: bigStyle),
      ],
    ),
  );
}
```

### _buildStatusChip

```dart
Widget _buildStatusChip(({String label, Color background, Color foreground}) style) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: style.background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      style.label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: style.foreground,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
  );
}
```

### _buildTicketMetaRow

```dart
Widget _buildTicketMetaRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(label, style: /* small, muted */),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(value, style: /* small, regular */),
        ),
      ],
    ),
  );
}
```

### _buildTicketAmountRow

```dart
Widget _buildTicketAmountRow(String label, double amount, {bool emphasized = false}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(child: Text(label, style: /* según emphasized */)),
        Text(CurrencyDisplay.format(amount, symbol: 'RD\$'), style: /* según emphasized */),
      ],
    ),
  );
}
```

### _HeaderActionIconButton

```dart
class _HeaderActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isActive;
  // Construye un botón cuadrado de 50x50 con fondo azul claro, borde, y punto indicador si isActive
}
```

### _CompactSummaryBadge

```dart
class _CompactSummaryBadge extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color background;
  // Badge compacto con icono en caja blanca, label y value
}
```

### _FilterSectionCard

```dart
class _FilterSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  // Card blanca con borde, sombra suave, título, subtítulo y contenido
}
```

### _QuickRangeChip

```dart
class _QuickRangeChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  // Chip rápido con fondo azul claro, borde, texto azul, borderRadius 999
}
```

### _CompactMovementRow

```dart
class _CompactMovementRow extends StatelessWidget {
  final CashMovementModel movement;
  final bool isSelected;
  final VoidCallback onTap;
  // Fila con badge ENT/SAL, motivo bold, fecha, sesión, usuario, monto con signo (+ verde / - rojo)
  // AnimatedContainer con duración 160ms para cambio de selección
}
```

### _MovementsHeaderRow

```dart
class _MovementsHeaderRow extends StatelessWidget {
  // Fila de encabezado con labels: Tipo (flex 2), Motivo (flex 6), Fecha (flex 3), Sesión (flex 2), Usuario (flex 2), Monto (flex 3)
  // Texto en gris, fontWeight w800, fontSize 11px
}
```

### _ExpensesHeaderSummary

```dart
class _ExpensesHeaderSummary extends StatelessWidget {
  final double totalIn;
  final double totalOut;
  final int count;
  // Muestra 4 badges: Entradas (verde), Salidas (rojo), Neto (azul), Registros (gris)
  // Wrap con spacing 8, cada badge es _CompactSummaryBadge
}
```

---

## ✅ CHECKLIST DE VERIFICACIÓN

Antes de dar por terminado, verifica:

- [ ] **FacturaPage** tiene header con search, filter button y summary
- [ ] **FacturaPage** tiene endDrawer con filtros de estado, periodo y cajero
- [ ] **FacturaPage** tiene lista de facturas con status chips (ACTIVA/PARCIAL/DEVUELTA)
- [ ] **FacturaPage** tiene modo maestro-detalle responsive (>=1100px)
- [ ] **FacturaPage** tiene panel de detalle con productos, totales y acciones
- [ ] **FacturaPage** tiene diálogo de devolución con selección de items
- [ ] **FacturaPage** tiene impresión de ticket
- [ ] **ReturnsListPage** tiene tabs Facturas/Devoluciones con ToggleButtons
- [ ] **ReturnsListPage** tiene tabla de devoluciones con detalle
- [ ] **ExpensesOverviewPage** tiene header compacto con badges de resumen
- [ ] **ExpensesOverviewPage** tiene tabla de movimientos con ENT/SAL badges
- [ ] **ExpensesOverviewPage** tiene panel de búsqueda (_ExpensesSearchSheet)
- [ ] **ExpensesOverviewPage** tiene panel de filtros (_ExpensesFiltersSheet)
- [ ] **ExpensesOverviewPage** tiene bottom sheet de detalle de movimiento
- [ ] Todos los colores usan `AppColors` consistentemente
- [ ] Todos los espaciados usan valores consistentes (4, 6, 8, 10, 12, 14, 16, 18, 20, 24, 28, 32)
- [ ] Tipografía usa 'Inter' con pesos w400-w900
- [ ] Sombras suaves con `AppColors.brandBlueDark.withOpacity(0.06)`
- [ ] Bordes con colores `Color(0xFFCBD5E1)`, `Color(0xFFDCE5EF)`, `Color(0xFFE2E8F0)`
- [ ] Formato moneda con `CurrencyDisplay.format(amount, symbol: 'RD\$')`
- [ ] Responsive design en todas las pantallas
- [ ] Animaciones suaves (fade, slide, AnimatedContainer)

---

## 📦 DEPENDENCIAS (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  google_fonts: ^6.1.0
  sqflite: ^2.3.0
  intl: ^0.19.0
  provider: ^6.1.1
  printing: ^5.12.0
  esc_pos_bluetooth: ^0.2.10
  flutter_blue_plus: ^1.30.0
  share_plus: ^7.2.1
  path_provider: ^2.1.1
  path: ^1.8.3
  uuid: ^4.2.1
  logger: ^2.0.2
  connectivity_plus: ^5.0.2
  http: ^1.1.2
  crypto: ^3.0.3
  archive: ^3.4.9
  synchronized: ^3.1.0
```

---

## 🎯 RESUMEN FINAL

Este prompt cubre **3 pantallas completas** del módulo de Ventas/Devoluciones/Gastos de FULLPOS:

| Pantalla | Archivo | Funcionalidades Clave |
|----------|---------|----------------------|
| **FacturaPage** | `factura_page.dart` | Listado maestro-detalle, filtros avanzados, devolución, impresión, responsive |
| **ReturnsListPage** | `returns_list_page.dart` | Tabs con facturas, tabla de devoluciones, detalle con nota |
| **ExpensesOverviewPage** | `expenses_overview_page.dart` | Movimientos IN/OUT, búsqueda, filtros por rango y tipo, resumen |

Cada pantalla sigue el mismo **Allegra-style** con colores corporativos, tipografía 'Inter', bordes suaves, sombras elegantes y comportamiento responsive. El diseño es **idéntico pixel a pixel** al original de FULLPOS.

¡A replicar! 🚀
