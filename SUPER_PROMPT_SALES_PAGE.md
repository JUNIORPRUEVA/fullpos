# 🚀 SUPER PROMPT - PANTALLA PRINCIPAL DE VENTAS (POS) CON LISTA DE VENTAS RECIENTES (FULLPOS)

## 📋 INSTRUCCIONES

Usa este prompt en otra app (Cursor, Windsurf, Lovable, Bolt, etc.) para **replicar EXACTAMENTE** la pantalla principal de ventas (POS) de FULLPOS con su **panel de ventas recientes integrado**. El resultado debe ser **idéntico pixel a pixel** en estilo, animaciones, comportamiento y organización.

---

## 🎯 OBJETIVO

Crear la **pantalla principal de ventas (SalesPage)** que es el corazón del POS. Es una pantalla compleja con:

1. **Layout principal:** Sidebar de categorías + Grid de productos + Panel de ticket (carrito) + Panel de ventas recientes (toggleable)
2. **Panel de Ventas Recientes:** Panel lateral que se abre/cierra mostrando las últimas 8 ventas con acciones (imprimir, ver PDF, reembolsar)
3. **Carrito de compras (_Cart):** Modelo de datos con items, cliente, descuentos, ITBIS, tipo de documento fiscal
4. **Atajos de teclado:** F1-F9 para búsqueda, cliente, pago, descuento, etc.
5. **Responsive:** Se adapta a diferentes tamaños de pantalla (tight desktop, compact desktop)

---

## 📁 ESTRUCTURA DE ARCHIVOS

```
lib/
├── core/
│   ├── constants/
│   │   └── app_colors.dart          # Paleta de colores corporativa
│   ├── utils/
│   │   └── currency_display.dart    # Formateo de moneda
│   ├── session/
│   │   └── session_manager.dart     # Gestión de sesión de usuario
│   └── widgets/
│       └── branded_loading_view.dart # Loading con marca
├── features/
│   └── sales/
│       ├── data/
│       │   ├── sale_model.dart          # Modelo SaleModel
│       │   ├── sale_item_model.dart     # Modelo SaleItemModel
│       │   ├── sales_repository.dart    # Repositorio de ventas
│       │   └── returns_repository.dart  # Repositorio de devoluciones
│       └── ui/
│           ├── sales_page.dart          # Pantalla principal de ventas (POS)
│           ├── factura_page.dart        # Pantalla de historial de ventas
│           └── dialogs/
│               └── refund_reason_dialog.dart # Diálogo de motivo de devolución
```

---

## 🎨 DISEÑO Y ESTILOS (Allegra-Style)

### Colores Principales

```dart
// app_colors.dart
class AppColors {
  static const Color brandBlue = Color(0xFF2563EB);
  static const Color brandBlueDark = Color(0xFF1E3A8A);
  static const Color brandBlueLight = Color(0xFFDBEAFE);
  static const Color surfaceLightVariant = Color(0xFFF2F6F9);
  static const Color surfaceLightBorder = Color(0xFFD7E1EC);
  static const Color textDark = Color(0xFF172033);
  static const Color textDarkSecondary = Color(0xFF475569);
  static const Color textDarkMuted = Color(0xFF64748B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color success = Color(0xFF16A34A);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color error = Color(0xFFDC2626);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFD97706);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color infoLight = Color(0xFFDBEAFE);
  static const Color borderSoft = Color(0xFFE2E8F0);
  static const Color lightBlueHover = Color(0xFFEFF6FF);
}
```

### Colores Específicos de la Pantalla de Ventas

```dart
// Colores usados en SalesPage
const Color recentSaleHover = Color(0xFFEAF7FB);
const Color recentSaleHighlight = Color(0xFFF1FBFC);
const Color tableHeaderBg = Color(0xFFF8FAFC);
const Color tableBorder = Color(0xFFE2E8F0);
const Color circleIconBg = Color(0xFFDBE5FF);
const Color circleIconColor = Color(0xFF1A56DB);
const Color textDark = Color(0xFF0F172A);
const Color textMuted = Color(0xFF64748B);
const Color textGray = Color(0xFF475569);
const Color iconGray = Color(0xFF475569);
const Color pdfRed = Color(0xFFDC2626);
const Color refundOrange = Color(0xFFB45309);
const Color emptyIconGray = Color(0xFFB8C4D1);
```

### Tipografía

- **Familia principal:** 'Inter' (descargar de Google Fonts)
- **Tamaños:** 13px, 13.2px, 13.5px, 13.8px, 14.2px, 17.5px
- **Pesos:** w400 (regular), w500 (medium), w700 (bold), w800 (extrabold)
- **Altura de línea (height):** 1.1, 1.15, 1.25, 1.35

### Sombras

```dart
BoxShadow(
  color: Colors.black.withOpacity(0.06),
  blurRadius: 20,
  offset: const Offset(0, 6),
)
```

### Bordes

- Color: `Color(0xFFCBD5E1)`, `Color(0xFFE2E8F0)`
- Radio: 8px, 10px, 12px, 14px, 16px, 18px, 20px, 24px, 999 (pill)
- Ancho: 1.0

---

## 📄 PANTALLA PRINCIPAL: SalesPage

### Comportamiento General

- **Ruta:** `/` (raíz del POS)
- **ConsumerStatefulWidget** `SalesPage` con `_SalesPageState` que usa `WidgetsBindingObserver`
- **Scaffold** con `Shortcuts` y `Actions` para atajos de teclado
- **Layout responsive** con `LayoutBuilder` y `_SalesResponsiveMetrics`
- **Carga inicial:** `_loadInitialData()` que carga productos, categorías, clientes, tickets pendientes
- **Atajos de teclado:** F1 (buscar producto), F2 (buscar cliente), F3 (nuevo cliente), F4 (selector de tickets), F5 (venta manual), F6 (abrir pago), F7 (descuento), F8 (finalizar venta), Ctrl+Backspace (eliminar item), + (aumentar cantidad), - (disminuir cantidad)

### Layout Principal (build method)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ┌──────────┐ ┌────────────────────────────────────┐ ┌──────────────────┐   │
│ │          │ │                                    │ │                  │   │
│ │ Categoría│ │      Grid de Productos             │ │  Panel Ticket    │   │
│ │ Sidebar  │ │                                    │ │  (Carrito)       │   │
│ │          │ │                                    │ │                  │   │
│ │          │ │                                    │ │                  │   │
│ │          │ │                                    │ │                  │   │
│ │          │ │                                    │ │                  │   │
│ │          │ │                                    │ │                  │   │
│ └──────────┘ └────────────────────────────────────┘ └──────────────────┘   │
│                                                                             │
│ ┌─────────────────────────────────────────────────────────────────────────┐ │
│ │ Footer con tabs de tickets (múltiples carritos)                         │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

- **Sidebar de categorías:** Colapsable/expandible, con iconos circulares y nombres
- **Grid de productos:** `GridView.builder` con tarjetas de producto modernas
- **Panel de ticket:** Header con cliente, tipo documento, items del carrito, totales y botón de pago
- **Panel de ventas recientes:** Se superpone como `Positioned.fill` cuando `_showRecentSalesPanel = true`
- **Footer:** Tabs para múltiples carritos/tickets

### Variables de Estado Clave

```dart
final List<_Cart> _carts = [_Cart(name: 'Venta principal')];
int _currentCartIndex = 0;
bool _showRecentSalesPanel = false;
bool _isLoadingRecentSales = false;
final List<legacy_sales.SaleModel> _recentSales = [];
final Set<int> _hoveredRecentSaleIds = {};
int? _selectedCartItemIndex;
int? _inlineEditCartItemIndex;
bool _isLoading = true;
List<ProductModel> _allProducts = [];
List<CategoryModel> _categories = [];
List<ClientModel> _clients = [];
String _searchQuery = '';
final FocusNode _searchFocusNode = FocusNode();
final FocusNode _clientSearchFocusNode = FocusNode();
final TextEditingController _searchController = TextEditingController();
final TextEditingController _clientSearchController = TextEditingController();
```

### _SalesResponsiveMetrics

```dart
class _SalesResponsiveMetrics {
  final bool isCompactDesktop;
  final bool isTightDesktop;
  final bool isShortDesktop;
  final bool isVeryShortDesktop;
  final double ticketPanelWidth;
  final double productCardWidth;
  final double productCardHeight;
  final double productHorizontalMargin;
}
```

### _toggleRecentSalesPanel / _loadRecentSales

```dart
Future<void> _toggleRecentSalesPanel() async {
  final shouldOpen = !_showRecentSalesPanel;
  if (!mounted) return;
  setState(() => _showRecentSalesPanel = shouldOpen);
  if (shouldOpen) {
    await _loadRecentSales();
  }
}

void _closeRecentSalesPanel() {
  if (!mounted || !_showRecentSalesPanel) return;
  setState(() => _showRecentSalesPanel = false);
}

Future<void> _loadRecentSales() async {
  if (_isLoadingRecentSales) return;
  if (!mounted) return;
  setState(() => _isLoadingRecentSales = true);
  try {
    final sales = await SalesRepository.listCompletedSales();
    if (!mounted) return;
    setState(() {
      _recentSales
        ..clear()
        ..addAll(sales.take(8));
    });
  } catch (_) {
    if (!mounted) return;
  } finally {
    if (mounted) {
      setState(() => _isLoadingRecentSales = false);
    }
  }
}
```

---

## 📄 PANEL DE VENTAS RECIENTES (_buildRecentSalesPanel)

### Comportamiento

- Se muestra como un panel superpuesto (`Positioned.fill`) dentro del layout
- Se activa/desactiva con `_toggleRecentSalesPanel()`
- Carga las últimas 8 ventas completadas
- Tiene header, tabla con columnas, y botón "Ir al historial de ventas"
- Ancho: mismo que el panel de ticket (`ticketPanelConstraints.maxWidth`)
- Responsive: `isCompact` cuando `screenWidth <= 1366`

### Estructura Visual

```
┌──────────────────────────────────────────────────────┐
│ [📋] Ventas recientes                          [✕]  │
├──────────────────────────────────────────────────────┤
│ ──────────────────────────────────────────────────── │
│ Venta              Total        Estado               │
│ ──────────────────────────────────────────────────── │
│ FAC-001234    RD$ 1,250.00    Activa     [🖨][📄][↩] │
│ FAC-001235    RD$ 3,400.00    Activa     [🖨][📄][↩] │
│ FAC-001236    RD$ 2,100.00    Parcial    [🖨][📄]    │
│ FAC-001237    RD$ 500.00      Devuelta   [🖨][📄]    │
│ ...                                                  │
├──────────────────────────────────────────────────────┤
│ [Ir al historial de ventas →]                        │
└──────────────────────────────────────────────────────┘
```

### _buildRecentSalesPanel

```dart
Widget _buildRecentSalesPanel() {
  const dividerColor = Color(0xFFE2E8F0);
  final screenWidth = MediaQuery.sizeOf(context).width;
  final isCompact = screenWidth <= 1366;
  final hp = isCompact ? 12.0 : 18.0;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _buildRecentSalesPanelHeader(isCompact: isCompact, hp: hp),
      const SizedBox(height: 10),
      const Divider(height: 1, color: dividerColor),
      _buildRecentSalesTableHeader(),
      Expanded(child: _buildRecentSalesTable()),
      const Divider(height: 1, color: dividerColor),
      Padding(
        padding: EdgeInsets.fromLTRB(hp, isCompact ? 10 : 14, hp, isCompact ? 12 : 18),
        child: SizedBox(
          height: isCompact ? 40 : 46,
          child: OutlinedButton(
            onPressed: _openFacturaPage,
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F172A),
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 18),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Ir al historial de ventas', style: TextStyle(fontSize: 14.2, fontWeight: FontWeight.w500, height: 1.1)),
                SizedBox(width: 10),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
```

### _buildRecentSalesPanelHeader

```dart
Widget _buildRecentSalesPanelHeader({bool isCompact = false, double hp = 18}) {
  return Padding(
    padding: EdgeInsets.fromLTRB(hp, isCompact ? 12 : 18, hp, 0),
    child: Row(
      children: [
        // Icono circular azul claro con icono de recibo
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFDBE5FF),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.receipt_long_outlined, size: 18, color: Color(0xFF1A56DB)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Ventas recientes',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 17.5, fontWeight: FontWeight.w700, height: 1.15),
          ),
        ),
        // Botón cerrar
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _closeRecentSalesPanel,
            borderRadius: BorderRadius.circular(10),
            child: const SizedBox(width: 34, height: 34, child: Icon(Icons.close_rounded, size: 20, color: Color(0xFF475569))),
          ),
        ),
      ],
    ),
  );
}
```

### _buildRecentSalesTableHeader

```dart
Widget _buildRecentSalesTableHeader() {
  const textStyle = TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w500, height: 1.1);

  Widget cell(String label, {required int flex, Alignment alignment = Alignment.centerLeft, bool showRightDivider = true}) {
    return Expanded(
      flex: flex,
      child: Container(
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          border: showRightDivider ? const Border(right: BorderSide(color: Color(0xFFE2E8F0), width: 1)) : null,
        ),
        child: Text(label, style: textStyle),
      ),
    );
  }

  return Container(
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
    decoration: BoxDecoration(
      color: const Color(0xFFF8FAFC),
      border: Border.all(color: const Color(0xFFE2E8F0)),
    ),
    child: const Row(
      children: [
        cell('Venta', flex: 34),
        cell('Total', flex: 30),
        cell('Estado', flex: 24),
        cell('', flex: 20, alignment: Alignment.center, showRightDivider: false),
      ],
    ),
  );
}
```

### _buildRecentSalesTable

```dart
Widget _buildRecentSalesTable() {
  if (_isLoadingRecentSales) {
    return const Center(
      child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.4)),
    );
  }

  if (_recentSales.isEmpty) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.receipt_long_outlined, size: 40, color: Color(0xFFB8C4D1)),
            SizedBox(height: 10),
            Text('No hay ventas recientes', style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  return ListView.separated(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
    itemCount: _recentSales.length,
    separatorBuilder: (_, index) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
    itemBuilder: (context, index) => _buildRecentSaleRow(_recentSales[index], index),
  );
}
```

### _buildRecentSaleRow

```dart
Widget _buildRecentSaleRow(legacy_sales.SaleModel sale, int index) {
  final saleId = sale.id ?? -1;
  final isHovered = _hoveredRecentSaleIds.contains(saleId);
  final isHighlighted = index == 0;
  final backgroundColor = isHovered
      ? const Color(0xFFEAF7FB)
      : (isHighlighted ? const Color(0xFFF1FBFC) : Colors.white);

  return MouseRegion(
    onEnter: (_) => _setHoverStateDeferred(_hoveredRecentSaleIds, saleId, true),
    onExit: (_) => _setHoverStateDeferred(_hoveredRecentSaleIds, saleId, false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          // Columna Venta (flex: 34)
          Expanded(
            flex: 34,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _recentSaleTitle(sale),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.8, fontWeight: FontWeight.w500, height: 1.15),
              ),
            ),
          ),
          // Columna Total (flex: 30)
          Expanded(
            flex: 30,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  CurrencyDisplay.format(sale.total),
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13.2, fontWeight: FontWeight.w700, height: 1.15),
                ),
              ),
            ),
          ),
          // Columna Estado (flex: 24)
          Expanded(
            flex: 24,
            child: Text(
              _recentSaleStatusLabel(sale),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontStyle: FontStyle.italic, fontWeight: FontWeight.w400, height: 1.15),
            ),
          ),
          // Columna Acciones (flex: 20)
          Expanded(
            flex: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Imprimir
                Tooltip(
                  message: 'Imprimir factura',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: sale.id == null ? null : () => unawaited(_printRecentSale(sale)),
                      borderRadius: BorderRadius.circular(10),
                      child: const SizedBox(width: 26, height: 30, child: Icon(Icons.print_outlined, size: 17, color: Color(0xFF475569))),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Ver PDF
                Tooltip(
                  message: 'Ver PDF carta',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: sale.id == null ? null : () => unawaited(_openSalePdfPreview(sale)),
                      borderRadius: BorderRadius.circular(10),
                      child: const SizedBox(width: 26, height: 30, child: Icon(Icons.picture_as_pdf_rounded, size: 17, color: Color(0xFFDC2626))),
                    ),
                  ),
                ),
                // Reembolsar (solo si no está devuelta)
                if (sale.id != null && sale.status.toUpperCase() != 'REFUNDED') ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Reembolsar factura',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => unawaited(_showRecentSaleRefundDialog(sale)),
                        borderRadius: BorderRadius.circular(10),
                        child: const SizedBox(width: 26, height: 30, child: Icon(Icons.assignment_return_outlined, size: 17, color: Color(0xFFB45309))),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
```

### _recentSaleTitle / _recentSaleStatusLabel

```dart
String _recentSaleTitle(legacy_sales.SaleModel sale) {
  final code = sale.localCode.trim();
  // Retorna el código de factura formateado
  return code;
}

String _recentSaleStatusLabel(legacy_sales.SaleModel sale) {
  final statusLabel = switch (sale.status.toUpperCase()) {
    'ACTIVE' => 'Activa',
    'REFUNDED' => 'Devuelta',
    'PARTIAL_REFUND' => 'Parcial',
    _ => sale.status,
  };
  return statusLabel;
}
```

### _openFacturaPage

```dart
void _openFacturaPage({int? saleId, bool openRefund = false}) {
  _closeClientSearchOverlay();
  // Navega a la página de facturas con parámetros opcionales
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => FacturaPage(initialSaleId: saleId, openRefund: openRefund),
    ),
  );
}
```

### _printRecentSale

```dart
Future<void> _printRecentSale(legacy_sales.SaleModel sale) async {
  final saleId = sale.id;
  if (saleId == null) return;
  try {
    final items = await SalesRepository.getItemsBySaleId(saleId);
    if (!mounted) return;
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
  } catch (e, st) {
    await ErrorHandler.instance.handle(e, stackTrace: st, context: context,
      onRetry: () => _printRecentSale(sale), module: 'sales/recent_sales/print');
  }
}
```

### _openSalePdfPreview

```dart
Future<void> _openSalePdfPreview(legacy_sales.SaleModel sale) async {
  final saleId = sale.id;
  if (saleId == null) return;
  try {
    // Abre vista previa del PDF de la factura
    // ...
  } catch (e, st) {
    await ErrorHandler.instance.handle(e, stackTrace: st, context: context,
      onRetry: () => _openSalePdfPreview(sale), module: 'sales/recent_sales/pdf_preview');
  }
}
```

### _showRecentSaleRefundDialog

```dart
Future<void> _showRecentSaleRefundDialog(legacy_sales.SaleModel sale) async {
  try {
    final result = await showSaleRefundDialog(context, sale);
    if (!mounted) return;
    if (result == SaleRefundOutcome.refunded || result == SaleRefundOutcome.cancelled) {
      _showSuccess(result == SaleRefundOutcome.refunded ? '¡Devolución procesada!' : '✅ Ticket cancelado y stock restaurado');
      await _loadRecentSales();
    }
  } catch (e, st) {
    await ErrorHandler.instance.handle(e, stackTrace: st, context: context,
      actionLabel: 'Reintentar', onAction: () => _showRecentSaleRefundDialog(sale));
  }
}
```

---

## 🧩 MODELO _Cart (Carrito de Compras)

```dart
class _Cart {
  String name;
  int? ticketId;           // ID del ticket en BD (si es persistido)
  int? tempCartId;         // ID del carrito temporal en BD
  ClientModel? selectedClient;
  List<SaleItemModel> items = [];
  double discountTotal = 0;
  String discountTotalType = 'amount';  // 'amount' | 'percent'
  double itbisRate = 0.18;
  bool electronicInvoiceEnabled = false;
  _SalesDocumentType documentType = _SalesDocumentType.consumidorFinal;
  bool hasCopia = false;

  _Cart({required this.name});

  String get displayName {
    if (selectedClient != null) {
      // Muestra nombre del cliente o "Ticket N"
    }
    // Muestra nombre del ticket
  }

  void addProduct(ProductModel product) {
    // Si ya existe, incrementa cantidad; si no, agrega nuevo item
  }

  double getQuantityForProduct(int productId) { /* ... */ }
  void updateQuantity(int index, double newQty) { /* ... */ }
  void removeItem(int index) { /* ... */ }
  void clear() { /* ... */ }

  double calculateGrossSubtotal() { /* suma totalLine de items */ }
  double calculateLineDiscounts() { /* suma discountLine de items */ }
  double calculateSubtotal() { /* grossSubtotal - lineDiscounts */ }
  double calculateTotalDiscountInputLimit() { /* subtotal * 0.5 */ }
  double calculateTotalDiscount() { /* si es percent: subtotal * discountTotal / 100 */ }
  double calculateSubtotalAfterDiscount() { /* subtotal - totalDiscount */ }
  double calculateTotalDiscountsCombined() { /* lineDiscounts + totalDiscount */ }
  double calculateItbis() { /* subtotalAfterDiscount * itbisRate si electronicInvoiceEnabled */ }
  double calculateTotal() { /* subtotalAfterDiscount + itbis */ }
}
```

### _SalesDocumentType

```dart
enum _SalesDocumentType { consumidorFinal, creditoFiscal }
```

### _CartItemBadge

```dart
class _CartItemBadge {
  final String label;
  final Color color;
  final Color background;
  const _CartItemBadge({required this.label, required this.color, required this.background});
}
```

---

## 🧩 WIDGETS DEL LAYOUT PRINCIPAL

### _build3DControlBar

Barra de control superior con:
- Botón de menú lateral (hamburguesa)
- Campo de búsqueda de productos con icono de lupa
- Botón de búsqueda por código de barras
- Botón de toggle del panel de ventas recientes (con badge de conteo)
- Botón de movimientos de caja
- Botón de turno actual

### _buildCategorySidebar

Sidebar vertical con categorías:
- Estado colapsado: solo iconos circulares (64px de ancho)
- Estado expandido: icono + nombre (200px de ancho)
- Cada item: `_CategorySidebarItem` con hover elegante
- Botón "Todas" al inicio
- Botón de limpiar filtro de categoría

### _buildModernProductCard

Tarjeta de producto en el grid:
- Imagen del producto (si tiene)
- Nombre del producto (max 2 líneas)
- Precio formateado
- Stock badge si es bajo
- Efecto hover con elevación
- Al hacer tap: agrega al carrito

### _buildTicketPanel

Panel lateral del carrito:
- Header con cliente, tipo de documento, botones de acción
- Lista de items del carrito con cantidad, precio, descuento
- Total y acciones (pago, descuento, etc.)
- Botón de pago grande y llamativo

### _buildInvoicePanelHeader

Header del panel de ticket:
- Selector de tipo de documento (Consumidor Final / Crédito Fiscal / NCF)
- Selector de cliente con búsqueda
- Botón de nuevo cliente
- Botón de descuento rápido
- Botón de cotización

### _buildItemsListCard

Lista de items en el carrito:
- Cada item: nombre, precio unitario, cantidad (stepper), total, badges (descuento, stock bajo)
- Botones de acción por item (editar cantidad, aplicar descuento, eliminar)
- Animación de entrada para nuevos items (`_AnimatedNewItemHighlight`)
- Efecto "shine sweep" en items nuevos (`_ShineSweepPainter`)

### _buildTotalAndActionsCard

Card de totales y acciones:
- Subtotal, descuento, ITBIS, total
- Botón de pago (FilledButton azul grande)
- Botón de descuento global
- Botón de cotización

### Footer con Tabs de Tickets

```dart
List<FooterTicketTabData> _buildFooterTabs() {
  return List.generate(_carts.length, (index) {
    final cart = _carts[index];
    return FooterTicketTabData(
      label: _footerTicketLabel(cart, index),
      onTap: () => _selectFooterTicket(index),
      onClose: _carts.length > 1 ? () => _deleteFooterTicket(index) : null,
      isActive: index == _currentCartIndex,
    );
  });
}
```

---

## 🧩 WIDGETS REUTILIZABLES

### _setHoverStateDeferred

```dart
void _setHoverStateDeferred<T>(Set<T> target, T value, bool isHovered) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    setState(() {
      if (isHovered) {
        target.add(value);
      } else {
        target.remove(value);
      }
    });
  });
}
```

### _recentSaleTitle

```dart
String _recentSaleTitle(legacy_sales.SaleModel sale) {
  final code = sale.localCode.trim();
  return code;
}
```

### _recentSaleStatusLabel

```dart
String _recentSaleStatusLabel(legacy_sales.SaleModel sale) {
  return switch (sale.status.toUpperCase()) {
    'ACTIVE' => 'Activa',
    'REFUNDED' => 'Devuelta',
    'PARTIAL_REFUND' => 'Parcial',
    _ => sale.status,
  };
}
```

---

## ✅ CHECKLIST DE VERIFICACIÓN

Antes de dar por terminado, verifica:

- [ ] **SalesPage** tiene layout con sidebar de categorías + grid de productos + panel de ticket
- [ ] **SalesPage** tiene atajos de teclado (F1-F9, Ctrl+Backspace, +, -)
- [ ] **SalesPage** tiene footer con tabs de múltiples carritos
- [ ] **SalesPage** tiene panel de ventas recientes toggleable
- [ ] **Panel de ventas recientes** se abre/cierra con animación
- [ ] **Panel de ventas recientes** carga últimas 8 ventas
- [ ] **Panel de ventas recientes** tiene header con icono circular azul y botón cerrar
- [ ] **Panel de ventas recientes** tiene tabla con columnas Venta/Total/Estado/Acciones
- [ ] **Panel de ventas recientes** tiene filas con hover color `Color(0xFFEAF7FB)`
- [ ] **Panel de ventas recientes** tiene primera fila destacada `Color(0xFFF1FBFC)`
- [ ] **Panel de ventas recientes** tiene acciones: Imprimir (🖨), PDF (📄), Reembolsar (↩)
- [ ] **Panel de ventas recientes** tiene botón "Ir al historial de ventas" al final
- [ ] **Panel de ventas recientes** tiene estado vacío con icono y mensaje
- [ ] **Panel de ventas recientes** tiene loading indicator
- [ ] **Modelo _Cart** tiene métodos: addProduct, updateQuantity, removeItem, clear, calculateTotal, etc.
- [ ] **Modelo _Cart** soporta descuentos por línea y globales (amount/percent)
- [ ] **Modelo _Cart** soporta ITBIS y tipo de documento fiscal
- [ ] **Responsive:** `isCompact` cuando `screenWidth <= 1366`
- [ ] **Responsive:** `_SalesResponsiveMetrics` con tight/compact/short desktop
- [ ] Todos los colores usan valores consistentes
- [ ] Tipografía usa 'Inter' con pesos w400-w700
- [ ] Animaciones con `AnimatedContainer` duración 140ms
- [ ] Formato moneda con `CurrencyDisplay.format()`

---

## 📦 DEPENDENCIAS