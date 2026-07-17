# 🚀 SUPER PROMPT - MÓDULO DE REPORTES PREMIUM (FULLPOS)

## 📋 INSTRUCCIONES

Usa este prompt en otra app (Cursor, Windsurf, Lovable, Bolt, etc.) para **replicar EXACTAMENTE** el módulo de reportes de FULLPOS con un diseño **fino, premium y profesional**. El resultado debe ser **idéntico pixel a pixel** en estilo, animaciones, comportamiento y organización.

---

## 🎯 OBJETIVO

Crear un **Módulo de Reportes Premium** con las siguientes características:

1. **Dashboard ejecutivo** con KPIs principales (Ventas totales, Utilidad, Margen, Órdenes)
2. **Gráfico de barras** de ventas por día/semana/mes
3. **Gráfico de pastel** de métodos de pago
4. **Gráfico de línea** de utilidad/ganancia
5. **Tabla de productos más vendidos** con ranking
6. **Tabla de clientes top** con gasto total
7. **Selector de período** (Hoy, Semana, 15 días, Mes, Año, Personalizado)
8. **Tarjetas ejecutivas** con métricas detalladas
9. **Estadísticas comparativas** (Hoy vs Ayer, Esta semana vs Semana pasada, Este mes vs Mes pasado)
10. **Ventas por cliente** con detalle de facturas
11. **Rendimiento por categoría** con ventas, devoluciones y ganancia
12. **Responsive**: se adapta a pantallas anchas y estrechas

---

## 🏗️ ARQUITECTURA

```
lib/features/reports/
├── data/
│   ├── reports_repository.dart       ← Modelos y consultas SQL
│   └── report_data_service.dart       ← Servicio de datos de reportes
├── ui/
│   ├── reports_page.dart             ← Página principal de reportes
│   ├── client_sales_report_page.dart ← Reporte de ventas por cliente
│   └── widgets/
│       ├── date_range_selector.dart  ← Selector de período
│       ├── sales_bar_chart.dart      ← Gráfico de barras de ventas
│       ├── sales_line_chart.dart     ← Gráfico de línea (doble serie)
│       ├── profit_line_chart.dart    ← Gráfico de línea de utilidad
│       ├── payment_method_pie_chart.dart ← Gráfico de pastel métodos pago
│       ├── kpi_cards_row.dart        ← Filas de tarjetas KPI
│       ├── advanced_kpi_cards.dart   ← Tarjetas KPI avanzadas
│       ├── top_products_table.dart   ← Tabla de productos top
│       ├── top_clients_table.dart    ← Tabla de clientes top
│       └── comparative_stats_card.dart ← Estadísticas comparativas
```

---

## 📦 MODELOS DE DATOS

### KpisData
```dart
class KpisData {
  final double totalSales;      // Ventas netas totales
  final double totalProfit;     // Ganancia bruta
  final double netProfit;       // Utilidad neta
  final double totalCost;       // Costo total vendido
  final int salesCount;         // Cantidad de ventas
  final int quotesCount;        // Cotizaciones
  final int quotesConverted;    // Cotizaciones convertidas
  final double avgTicket;       // Ticket promedio
  final double cashIncome;      // Ingresos de caja
  final double cashExpense;     // Gastos de caja
}
```

### PaymentMethodData
```dart
class PaymentMethodData {
  final String method;   // 'Efectivo', 'Tarjeta', 'Transferencia', 'Crédito', etc.
  final double amount;   // Monto total
  final int count;       // Cantidad de transacciones
}
```

### CategoryPerformanceData
```dart
class CategoryPerformanceData {
  final String category;
  final double sales;        // Ventas
  final double refunds;      // Devoluciones
  final double netSales;     // Ventas netas
  final double profit;       // Ganancia
  final double itemsSold;    // Unidades vendidas
  final double itemsRefunded; // Unidades devueltas
}
```

### SeriesDataPoint
```dart
class SeriesDataPoint {
  final String label;  // Fecha o período (ej: '2024-01-15')
  final double value;  // Valor
}
```

### TopProduct
```dart
class TopProduct {
  final int productId;
  final String productName;
  final double totalSales;   // Ventas totales
  final double totalQty;     // Cantidad vendida
  final double totalProfit;  // Ganancia
}
```

### TopClient
```dart
class TopClient {
  final int clientId;
  final String clientName;
  final double totalSpent;    // Total gastado
  final int purchaseCount;    // Cantidad de compras
}
```

### ClientSalesSummary
```dart
class ClientSalesSummary {
  final int clientId;
  final String clientName;
  final double totalSales;    // Ventas totales
  final double totalCredit;   // Crédito total
  final int salesCount;       // Cantidad de ventas
  final int lastPurchaseAtMs; // Última compra (timestamp)
}
```

### SaleRecord
```dart
class SaleRecord {
  final int id;
  final int? customerId;
  final String localCode;     // Código de factura
  final String kind;          // 'invoice', 'sale', 'return'
  final int createdAtMs;      // Fecha (timestamp)
  final String? customerName;
  final double total;
  final String? paymentMethod;
}
```

### SalesByUser
```dart
class SalesByUser {
  final int userId;
  final String username;
  final double totalSales;
  final int salesCount;
}
```

---

## 🎨 DISEÑO Y ESTILOS

### Paleta de colores
```dart
// Colores base
Color primaryBlue = const Color(0xFF2563EB);
Color teal = const Color(0xFF0D9488);
Color gold = const Color(0xFFD97706);
Color error = const Color(0xFFDC2626);
Color textPrimary = const Color(0xFF111827);
Color textSecondary = const Color(0xFF6B7280);
Color borderSoft = const Color(0xFFE5E7EB);

// Esquema de colores para gráficos
List<Color> chartColors = [
  scheme.primary,           // Azul
  scheme.tertiary,          // Verde/Teal
  scheme.secondary,         // Naranja/Dorado
  scheme.error,             // Rojo
  scheme.primaryContainer,  // Azul claro
  scheme.secondaryContainer, // Naranja claro
];
```

### Tipografía
```dart
// Títulos grandes (ventas del período)
fontSize: 42 (wide) / 34 (narrow), fontWeight: FontWeight.w700, letterSpacing: -0.5

// Títulos de tarjetas
fontSize: 15, fontWeight: FontWeight.w600

// Subtítulos
fontSize: 12-13, fontWeight: FontWeight.w500, color: onSurfaceVariant

// Valores de KPIs principales
fontSize: 26, fontWeight: FontWeight.bold

// Valores de KPIs secundarios
fontSize: 15, fontWeight: FontWeight.bold

// Labels de gráficos
fontSize: 10, fontWeight: FontWeight.w500

// Tablas (encabezados)
fontSize: 13, fontWeight: FontWeight.w600

// Tablas (datos)
fontSize: 13, fontWeight: FontWeight.w400
```

### Dimensiones y espaciados
```dart
// Padding general de página
EdgeInsets.fromLTRB(12, 12, 12, 12)

// Padding de tarjetas
EdgeInsets.all(12)  // tarjetas simples
EdgeInsets.all(16)  // tarjetas con título
EdgeInsets.all(18)  // tarjetas KPI principales
EdgeInsets.all(22)  // hero panel

// Border radius
BorderRadius.circular(10)  // tarjetas estándar
BorderRadius.circular(12)  // tarjetas premium
BorderRadius.circular(14)  // contenedores principales
BorderRadius.circular(18)  // tarjetas KPI avanzadas
BorderRadius.circular(999) // pills/badges

// Sombras
BoxShadow(
  color: scheme.shadow.withOpacity(0.04-0.06),
  blurRadius: 12-20,
  offset: Offset(0, 6-10),
)

// Bordes
Border.all(color: scheme.outlineVariant)  // estándar
Border.all(color: color.withOpacity(0.12-0.20))  // con acento
```

---

## 🧩 COMPONENTES

### 1. ReportsPage (Página Principal)

**Estado:**
```dart
class _ReportsPageState extends State<ReportsPage> {
  DateRangePeriod _selectedPeriod = DateRangePeriod.month;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _isLoading = true;
  
  // Datos
  KpisData? _kpis;
  List<SeriesDataPoint> _salesSeries = [];
  List<SeriesDataPoint> _profitSeries = [];
  List<PaymentMethodData> _paymentMethods = [];
  List<TopProduct> _topProducts = [];
  List<TopClient> _topClients = [];
  List<CategoryPerformanceData> _categoryPerformance = [];
  List<SaleRecord> _recentSales = [];
  Map<String, dynamic> _comparativeStats = {};
}
```

**Layout general:**
```dart
Scaffold(
  backgroundColor: scheme.surface,
  body: Padding(
    padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // TOP BAR: Título + Selector de período + Botón recargar
        _buildTopBar(),
        SizedBox(height: 12),
        
        if (_isLoading)
          Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: isWide
              ? _buildWideLayout()   // Row con paneles lado a lado
              : _buildNarrowLayout(), // Column con paneles apilados
          ),
      ],
    ),
  ),
)
```

**Top Bar:**
```dart
Container(
  padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: scheme.outlineVariant),
    boxShadow: [BoxShadow(color: scheme.shadow.withOpacity(0.05), blurRadius: 12, offset: Offset(0, 6))],
  ),
  child: LayoutBuilder(
    builder: (context, constraints) {
      final stacked = constraints.maxWidth < 980;
      return Column(
        children: [
          // Fila de título + recargar
          Row(
            children: [
              IconButton(arrow_back, onPressed: () => Navigator.maybePop(context)),
              SizedBox(width: 10),
              Container(
                padding: EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.primary.withOpacity(0.18)),
                ),
                child: Icon(Icons.bar_chart_rounded, color: scheme.primary, size: 18),
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text('Reportes', style: titleLarge.copyWith(fontWeight: FontWeight.w800)),
              ),
              OutlinedButton.icon(
                icon: Icon(Icons.refresh_rounded, size: 16),
                label: Text('Recargar'),
                onPressed: _loadData,
                style: OutlinedButton.styleFrom(minimumSize: Size(0, 36), padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ],
          ),
          SizedBox(height: 10),
          // Selector de período + badges
          DateRangeSelector(
            selectedPeriod: _selectedPeriod,
            customStart: _customStart,
            customEnd: _customEnd,
            onPeriodChanged: _onPeriodChanged,
            onCustomRangeChanged: _onCustomRangeChanged,
          ),
        ],
      );
    },
  ),
)
```

### 2. Hero Panel (Ventas del Período)

**Layout wide (pantalla ≥ 1120px):**
```dart
Container(
  padding: EdgeInsets.all(22),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    gradient: LinearGradient(
      colors: [Color(0xFFF8FBFF), Color(0xFFEDF4FF), Color(0xFFF6FBFF)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    border: Border.all(color: borderSoft),
    boxShadow: [BoxShadow(color: shadow.withOpacity(0.06), blurRadius: 20, offset: Offset(0, 10))],
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Columna izquierda (6/10): Título + Valor + Selector + Gráfico barras
      Expanded(
        flex: 6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ventas del periodo', style: TextStyle(color: onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500)),
            SizedBox(height: 6),
            Text(_formatCurrency(kpis.totalSales), style: TextStyle(fontSize: 42, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
            SizedBox(height: 18),
            Row(children: [periodBadge()]),
            SizedBox(height: 18),
            SizedBox(height: 290, child: SalesBarChart(data: _salesSeries, barColor: scheme.primary)),
          ],
        ),
      ),
      SizedBox(width: 26),
      // Columna derecha (4/10): Métricas + Gráfico pastel + Mini info
      Expanded(
        flex: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10, runSpacing: 10,
              children: [
                summaryTile(label: 'Margen', value: '${margin.toStringAsFixed(1)}%', accent: scheme.tertiary),
                summaryTile(label: 'Ordenes', value: salesCount, accent: scheme.primary),
                summaryTile(label: 'Utilidad', value: _formatCurrency(kpis.netProfit), accent: scheme.secondary),
              ],
            ),
            SizedBox(height: 14),
            SizedBox(height: 250, child: PaymentMethodPieChart(data: _paymentMethods)),
            SizedBox(height: 16),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: [
                heroMiniInfo(label: 'Ticket promedio', value: _formatCurrency(kpis.avgTicket)),
                heroMiniInfo(label: 'Cliente principal', value: topClient?.clientName ?? 'Sin datos'),
                heroMiniInfo(label: 'Metodo lider', value: topPayment?.method ?? 'Sin datos'),
              ],
            ),
          ],
        ),
      ),
    ],
  ),
)
```

**Layout narrow (pantalla < 1120px):**
```dart
// Mismo contenido pero en Column en lugar de Row
// El gráfico de barras ocupa 240px de alto
// Las métricas van debajo del gráfico
// El gráfico de pastel va después de las métricas
```

### 3. DateRangeSelector

```dart
enum DateRangePeriod { today, week, biweekly, month, year, custom }

class DateRangeSelector extends StatelessWidget {
  final DateRangePeriod selectedPeriod;
  final DateTime? customStart;
  final DateTime? customEnd;
  final Function(DateRangePeriod) onPeriodChanged;
  final Function(DateTime, DateTime)? onCustomRangeChanged;
}
```

**Layout:**
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: scheme.outlineVariant),
  ),
  child: Wrap(
    spacing: 6, runSpacing: 6,
    children: [
      _buildChip(context, 'Hoy', DateRangePeriod.today),
      _buildChip(context, 'Semana', DateRangePeriod.week),
      _buildChip(context, '15 dias', DateRangePeriod.biweekly),
      _buildChip(context, 'Mes', DateRangePeriod.month),
      _buildChip(context, 'Ano', DateRangePeriod.year),
      _buildChip(context, 'Personalizado', DateRangePeriod.custom),
    ],
  ),
)
```

**Chip:**
```dart
ChoiceChip(
  label: Text(label),
  selected: isSelected,
  onSelected: (selected) {
    if (selected) {
      if (period == DateRangePeriod.custom) {
        _showCustomDatePicker(context);
      } else {
        onPeriodChanged(period);
      }
    }
  },
  backgroundColor: scheme.surface,
  selectedColor: scheme.primary.withOpacity(0.14),
  side: BorderSide(color: isSelected ? scheme.primary.withOpacity(0.22) : scheme.outlineVariant),
  visualDensity: VisualDensity.compact,
  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
  labelPadding: EdgeInsets.symmetric(horizontal: 4),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
  labelStyle: TextStyle(
    color: isSelected ? scheme.primary : scheme.onSurface,
    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
    fontSize: 12,
  ),
)
```

**DateRangeHelper:**
```dart
class DateRangeHelper {
  static DateTimeRange getRangeForPeriod(DateRangePeriod period, {DateTime? customStart, DateTime? customEnd}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    
    switch (period) {
      case DateRangePeriod.today:     return DateTimeRange(start: today, end: endOfToday);
      case DateRangePeriod.week:      return DateTimeRange(start: today.subtract(Duration(days: 7)), end: endOfToday);
      case DateRangePeriod.biweekly:  return DateTimeRange(start: today.subtract(Duration(days: 15)), end: endOfToday);
      case DateRangePeriod.month:     return DateTimeRange(start: DateTime(now.year, now.month, 1), end: endOfToday);
      case DateRangePeriod.year:      return DateTimeRange(start: DateTime(now.year, 1, 1), end: endOfToday);
      case DateRangePeriod.custom:    // Usar customStart y customEnd
    }
  }
}
```

### 4. SalesBarChart (Gráfico de Barras)

```dart
class SalesBarChart extends StatefulWidget {
  final List<SeriesDataPoint> data;
  final Color? barColor;
  final String title;
}
```

**Características:**
- Usa `fl_chart` package (`BarChart`)
- Tooltip al tocar una barra (fecha + monto)
- Barras con borde redondeado (4px)
- Colores: primary para valores positivos, error para negativos
- Eje Y con formato de moneda
- Eje X con fechas (dd/MM) con espaciado automático
- Ancho de barra dinámico según cantidad de datos (28px ≤7, 18px ≤14, 12px ≤21, 8px >21)
- Grid horizontal con línea base resaltada
- Touch callback para resaltar barra seleccionada

```dart
BarChart(
  BarChartData(
    minY: minY,
    maxY: maxY,
    baselineY: 0,
    barTouchData: BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (group) => scheme.onSurface.withOpacity(0.9),
        tooltipPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          final item = widget.data[group.x.toInt()];
          return BarTooltipItem(
            '${_formatDate(item.label)}\n',
            TextStyle(color: scheme.surface, fontWeight: FontWeight.w500, fontSize: 12),
            children: [
              TextSpan(text: _formatCurrency(item.value), style: TextStyle(color: scheme.surface, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          );
        },
      ),
    ),
    titlesData: FlTitlesData(
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: ...)),
      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 60, getTitlesWidget: ...)),
      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
    ),
    borderData: FlBorderData(show: true, border: Border(left: ..., bottom: ...)),
    gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: ...),
    barGroups: _buildBarGroups(...),
  ),
)
```

### 5. PaymentMethodPieChart (Gráfico de Pastel)

```dart
class PaymentMethodPieChart extends StatefulWidget {
  final List<PaymentMethodData> data;
}
```

**Características:**
- Usa `fl_chart` package (`PieChart`)
- Donut chart con centro vacío (centerSpaceRadius: 50)
- Tooltip al tocar una sección (resalta + agranda)
- Leyenda lateral con color, nombre, porcentaje, cantidad de ventas y monto
- Colores: primary, tertiary, secondary, error, primaryContainer, secondaryContainer
- Formato: "45% • 120 ventas • RD$ 45,000.00"

```dart
Row(
  children: [
    Expanded(flex: 3, child: PieChart(...)),
    SizedBox(width: 16),
    Expanded(flex: 2, child: Container(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: data.asMap().entries.map((entry) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(width: 14, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.method, style: TextStyle(fontSize: 12, fontWeight: touchedIndex == index ? FontWeight.bold : FontWeight.w500)),
                      Text('${percentage.toStringAsFixed(1)}% • ${item.count} ventas • ${_formatCurrency(item.amount)}', style: TextStyle(fontSize: 10, color: onSurface.withOpacity(0.6))),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    )),
  ],
)
```

### 6. ProfitLineChart (Gráfico de Línea - Utilidad)

```dart
class ProfitLineChart extends StatelessWidget {
  final List<SeriesDataPoint> data;
}
```

**Características:**
- Usa `fl_chart` package (`LineChart`)
- Línea curva con color gold (#D97706)
- Área debajo de la línea con opacidad 0.2
- Puntos blancos con borde gold (cuando hay ≤15 datos)
- Eje Y con formato de moneda
- Eje X con fechas (día)

### 7. SalesLineChart (Gráfico de Línea - Doble Serie)

```dart
class SalesLineChart extends StatelessWidget {
  final List<SeriesDataPoint> data;           // Serie principal
  final List<SeriesDataPoint> secondaryData;  // Serie secundaria (opcional)
  final Color? primaryColor;
  final Color? secondaryColor;
  final String? primaryLabel;
  final String? secondaryLabel;
}
```

**Características:**
- Soporta dos series de datos (ej: ventas vs año anterior)
- Serie secundaria con línea punteada (dashArray: [6, 4])
- Leyenda superior con colores y labels
- Área debajo de la línea principal con opacidad 0.12

### 8. AdvancedKpiCards (Tarjetas KPI Avanzadas)

```dart
class AdvancedKpiCards extends StatelessWidget {
  final KpisData kpis;
}
```

**Layout:**
```dart
Column(
  children: [
    // Tarjetas principales (Total Ventas + Utilidad)
    if (compact)
      Column(children: [_buildMainKpiCard('Total Ventas', ...), SizedBox(height: 12), _buildMainKpiCard('Utilidad', ...)])
    else
      Row(children: [Expanded(child: _buildMainKpiCard('Total Ventas', ...)), SizedBox(width: 14), Expanded(child: _buildMainKpiCard('Utilidad', ...))]),
    
    SizedBox(height: 14),
    
    // Tarjetas secundarias (Ticket Promedio, Cotizaciones, Conversión, Ingresos Caja, Costo Vendido)
    Wrap(
      spacing: 12, runSpacing: 12,
      children: [
        _buildSecondaryKpiCard('Ticket Promedio', ...),
        _buildSecondaryKpiCard('Cotizaciones', ...),
        _buildSecondaryKpiCard('Conversion', ...),
        _buildSecondaryKpiCard('Ingresos Caja', ...),
        _buildSecondaryKpiCard('Costo vendido', ...),
      ],
    ),
  ],
)
```

**MainKpiCard:**
```dart
Container(
  padding: EdgeInsets.all(18),
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: color.withOpacity(0.2)),
    boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 18, offset: Offset(0, 10))],
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          Spacer(),
          if (isAlert) Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: scheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.warning, size: 12, color: scheme.error), SizedBox(width: 4), Text(alertText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: scheme.error))]),
          ),
        ],
      ),
      SizedBox(height: 16),
      Text(title, style: TextStyle(fontSize: 13, color: onSurface.withOpacity(0.7), fontWeight: FontWeight.w500)),
      SizedBox(height: 6),
      Text(currency.format(value), style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
      SizedBox(height: 6),
      Text(subtitle, style: TextStyle(fontSize: 12, color: onSurface.withOpacity(0.6))),
    ],
  ),
)
```

**SecondaryKpiCard:**
```dart
Container(
  width: width,
  padding: EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: scheme.outlineVariant),
  ),
  child: Row(
    children: [
      Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 18),
      ),
      SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 11, color: onSurface.withOpacity(0.7)), maxLines: 1, overflow: TextOverflow.ellipsis),
            SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ],
  ),
)
```

### 9. TopProductsTable (Tabla de Productos Más Vendidos)

```dart
class TopProductsTable extends StatelessWidget {
  final List<TopProduct> products;
}
```

**Layout:**
```dart
SingleChildScrollView(
  child: Column(
    children: [
      // Encabezado
      Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primary.withOpacity(0.06),
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            SizedBox(width: 40, child: Text('#', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            Expanded(flex: 3, child: Text('Producto', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            Expanded(flex: 2, child: Text('Ventas', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 16),
            Expanded(flex: 1, child: Text('Cantidad', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.right)),
            SizedBox(width: 16),
            Expanded(flex: 2, child: Text('Margen Bruto', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.right)),
          ],
        ),
      ),
      // Filas de datos
      ...products.asMap().entries.map((entry) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: index % 2 == 0 ? scheme.surface : scheme.surface.withOpacity(0.72),
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              SizedBox(width: 40, child: Text('${index + 1}', style: TextStyle(color: rankColor, fontWeight: index < 3 ? FontWeight.bold : FontWeight.w600))),
              Expanded(flex: 3, child: Text(product.productName, style: TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Expanded(flex: 2, child: Text(money.format(product.totalSales), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
              SizedBox(width: 16),
              Expanded(flex: 1, child: Text(product.totalQty.toStringAsFixed(0), style: TextStyle(fontSize: 13), textAlign: TextAlign.right)),
              SizedBox(width: 16),
              Expanded(flex: 2, child: Text(money.format(product.totalProfit), style: TextStyle(fontSize: 13, color: scheme.tertiary, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
            ],
          ),
        );
      }),
    ],
  ),
)
```

### 10. TopClientsTable (Tabla de Clientes Top)

```dart
class TopClientsTable extends StatelessWidget {
  final List<TopClient> clients;
}
```

**Layout:** Similar a TopProductsTable pero con columnas: #, Cliente, Total Gastado, Compras

### 11. ComparativeStatsCard (Estadísticas Comparativas)

```dart
class ComparativeStatsCard extends StatelessWidget {
  final Map<String, dynamic> stats;
  // stats['today'], stats['yesterday'], stats['thisWeek'], stats['lastWeek'], stats['thisMonth'], stats['lastMonth']
  // Cada uno: {'sales': double, 'count': int}
}
```

**Layout:**
```dart
Column(
  children: [
    _buildComparisonRow('Hoy', todaySales, todayCount, 'Ayer', yesterdaySales, yesterdayCount, Icons.today),
    SizedBox(height: 10),
    _buildComparisonRow('Esta semana', thisWeekSales, thisWeekCount, 'Semana pasada', lastWeekSales, lastWeekCount, Icons.date_range),
    SizedBox(height: 10),
    _buildComparisonRow('Este mes', thisMonthSales, thisMonthCount, 'Mes pasado', lastMonthSales, lastMonthCount, Icons.calendar_month),
  ],
)
```

**ComparisonRow:**
```dart
Container(
  padding: EdgeInsets.all(14),
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: scheme.outlineVariant),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(color: scheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: scheme.primary, size: 22),
      ),
      SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(currentLabel, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: changeColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(isPositive ? Icons.trending_up : Icons.trending_down, size: 14, color: changeColor),
                      SizedBox(width: 4),
                      Text('${isPositive ? '+' : ''}${change.toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: changeColor)),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(currency.format(currentValue), style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: scheme.primary)),
            SizedBox(height: 4),
            Text('$currentCount ventas | $previousLabel: ${currency.format(previousValue)} ($previousCount ventas)',
              style: TextStyle(fontSize: 11, color: onSurface.withOpacity(0.62), fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    ],
  ),
)
```

### 12. ClientSalesReportPage (Ventas por Cliente)

```dart
class ClientSalesReportPage extends StatefulWidget {
  const ClientSalesReportPage({super.key});
}
```

**Estado:**
```dart
DateRangePeriod _selectedPeriod = DateRangePeriod.month;
DateTime? _customStart;
DateTime? _customEnd;
bool _isLoading = true;
List<ClientSalesSummary> _clientSummaries = [];
List<TopProduct> _topProducts = [];
TopClient? _topClient;
List<SaleRecord> _selectedClientSales = [];
ClientSalesSummary? _selectedClient;
```

**Layout general:**
```dart
Scaffold(
  backgroundColor: scheme.surface,
  body: Padding(
    padding: EdgeInsets.fromLTRB(12, 12, 12, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top bar con título + selector de período + badges
        _buildTopBar(),
        SizedBox(height: 12),
        
        if (_isLoading)
          Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: isWide
              ? Row(
                  children: [
                    Expanded(flex: 2, child: _buildGeneralPanel(context)),
                    SizedBox(width: 12),
                    Expanded(flex: 3, child: _buildClientDetailPanel(context)),
                  ],
                )
              : Column(
                  children: [
                    Expanded(child: _buildGeneralPanel(context)),
                    SizedBox(height: 12),
                    Expanded(child: _buildClientDetailPanel(context)),
                  ],
                ),
          ),
      ],
    ),
  ),
)
```

**GeneralPanel (Resumen general):**
```dart
Container(
  padding: EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: scheme.outlineVariant),
    boxShadow: [BoxShadow(color: scheme.shadow.withOpacity(0.05), blurRadius: 12, offset: Offset(0, 6))],
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Resumen general', style: titleMedium.copyWith(fontWeight: FontWeight.w800)),
      SizedBox(height: 10),
      // Stats tiles: Ventas totales, Créditos totales, Clientes con compras, Cliente top
      Wrap(
        spacing: 8, runSpacing: 8,
        children: [
          SizedBox(width: tileWidth, child: _statTile('Ventas totales', money.format(totalSales), Icons.payments)),
          SizedBox(width: tileWidth, child: _statTile('Créditos totales', money.format(totalCredits), Icons.credit_card)),
          SizedBox(width: tileWidth, child: _statTile('Clientes con compras', _clientSummaries.length.toString(), Icons.people)),
          SizedBox(width: tileWidth, child: _statTile('Cliente top', topClient?.clientName ?? '-', Icons.workspace_premium)),
        ],
      ),
      SizedBox(height: 12),
      Text('Productos más vendidos', style: titleSmall.copyWith(fontWeight: FontWeight.w800)),
      SizedBox(height: 8),
      Expanded(
        child: ListView.separated(
          itemCount: _topProducts.length,
          separatorBuilder: (_, _) => Divider(color: scheme.outlineVariant.withOpacity(0.6), height: 10),
          itemBuilder: (context, index) {
            return Row(
              children: [
                SizedBox(width: 22, child: Text('${index + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary))),
                Expanded(child: Text(item.productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700))),
                SizedBox(width: 8),
                Text('${item.totalQty.toStringAsFixed(0)} u', style: TextStyle(fontSize: 12)),
              ],
            );
          },
        ),
      ),
    ],
  ),
)
```

**ClientDetailPanel (Detalle del cliente):**
```dart
Container(
  padding: EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: scheme.surface,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: scheme.outlineVariant),
    boxShadow: [BoxShadow(color: scheme.shadow.withOpacity(0.05), blurRadius: 12, offset: Offset(0, 6))],
  ),
  child: LayoutBuilder(
    builder: (context, constraints) {
      final stacked = constraints.maxWidth < 760;
      
      return Row(
        children: [
          // Lista de clientes (2/5)
          Expanded(flex: 2, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Clientes', style: titleMedium.copyWith(fontWeight: FontWeight.w800)),
              SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: _clientSummaries.length,
                  itemBuilder: (context, index) {
                    final item = _clientSummaries[index];
                    final selected = item.clientId == _selectedClient?.clientId;
                    return InkWell(
                      onTap: () => _selectClient(item),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        margin: EdgeInsets.only(bottom: 8),
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: selected ? scheme.primary.withOpacity(0.10) : scheme.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: selected ? scheme.primary.withOpacity(0.60) : scheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.clientName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800)),
                            SizedBox(height: 3),
                            Text('${money.format(item.totalSales)} · ${item.salesCount} ventas', style: TextStyle(fontSize: 11, color: onSurfaceVariant, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          )),
          SizedBox(width: 12),
          // Detalle de facturas del cliente (3/5)
          Expanded(flex: 3, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_selectedClient?.clientName ?? 'Detalle del cliente', style: titleMedium.copyWith(fontWeight: FontWeight.w800)),
              SizedBox(height: 10),
              if (_selectedClient != null) ...[
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: [
                    _pill(context, 'Ventas: ${_selectedClient!.salesCount}'),
                    _pill(context, 'Total: ${money.format(_selectedClient!.totalSales)}'),
                    _pill(context, 'Crédito: ${money.format(_selectedClient!.totalCredit)}'),
                  ],
                ),
                SizedBox(height: 10),
              ],
              Expanded(
                child: ListView.separated(
                  itemCount: _selectedClientSales.length,
                  separatorBuilder: (_, _) => Divider(color: scheme.outlineVariant.withOpacity(0.6), height: 10),
                  itemBuilder: (context, index) {
                    final sale = _selectedClientSales[index];
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(sale.localCode, style: TextStyle(fontWeight: FontWeight.w700)),
                              SizedBox(height: 2),
                              Text('${sale.kind == 'return' ? 'Devolución' : 'Factura'} • ${date.format(DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs))}',
                                style: TextStyle(fontSize: 11, color: onSurfaceVariant)),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(money.format(sale.total), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800)),
                      ],
                    );
                  },
                ),
              ),
            ],
          )),
        ],
      );
    },
  ),
)
```

**StatTile:**
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
  decoration: BoxDecoration(
    color: scheme.primary.withOpacity(0.04),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: scheme.outlineVariant),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(color: scheme.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: scheme.primary),
          ),
          SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: onSurfaceVariant, fontWeight: FontWeight.w700))),
        ],
      ),
      SizedBox(height: 8),
      Text(value, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800)),
    ],
  ),
)
```

**Pill:**
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: scheme.primary.withOpacity(0.10),
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: scheme.primary.withOpacity(0.35)),
  ),
  child: Text(text, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
)
```

---

## 📊 CONSULTAS SQL PRINCIPALES

### KPIs (getKpis)
```sql
-- Ventas netas totales
SELECT COALESCE(SUM(
  CASE WHEN kind = 'return' THEN -ABS(COALESCE(total, 0))
  ELSE COALESCE(total, 0) END
), 0) as total
FROM sales
WHERE status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
  AND kind IN ('invoice', 'sale', 'return')
  AND deleted_at_ms IS NULL
  AND created_at_ms >= ? AND created_at_ms <= ?

-- Costo vendido (productos vendidos)
SELECT COALESCE(SUM(
  COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)
), 0) as total
FROM sale_items si
INNER JOIN sales s ON si.sale_id = s.id
LEFT JOIN products p ON (si.product_id = p.id)
WHERE s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
  AND s.kind IN ('invoice', 'sale')
  AND s.deleted_at_ms IS NULL
  AND s.created_at_ms >= ? AND s.created_at_ms <= ?

-- Costo devuelto (productos devueltos)
SELECT COALESCE(SUM(
  COALESCE(ri.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)
), 0) as total
FROM return_items ri
INNER JOIN returns r ON ri.return_id = r.id
INNER JOIN sales rs ON r.return_sale_id = rs.id
LEFT JOIN sale_items si ON ri.sale_item_id = si.id
LEFT JOIN products p ON COALESCE(ri.product_id, si.product_id) = p.id
WHERE rs.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
  AND rs.kind = 'return'
  AND rs.deleted_at_ms IS NULL
  AND rs.created_at_ms >= ? AND rs.created_at_ms <= ?
```

### Serie de ventas (getSalesSeries)
```sql
SELECT 
  DATE(datetime(created_at_ms/1000, 'unixepoch', 'localtime')) as date_label,
  COALESCE(SUM(
    CASE WHEN kind = 'return' THEN -ABS(COALESCE(total, 0))
    ELSE COALESCE(total, 0) END
  ), 0) as daily_total
FROM sales
WHERE kind IN ('invoice', 'sale', 'return')
  AND status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
  AND deleted_at_ms IS NULL
  AND created_at_ms >= ? AND created_at_ms <= ?
GROUP BY date_label
ORDER BY date_label ASC
```

### Top productos (getTopProducts)
```sql
WITH sale_item_totals AS (
  SELECT si.sale_id, COALESCE(SUM(COALESCE(si.total_line, 0)), 0) as items_total
  FROM sale_items si GROUP BY si.sale_id
),
return_item_totals AS (
  SELECT ri.return_id, COALESCE(SUM(COALESCE(ri.total, 0)), 0) as items_total
  FROM return_items ri GROUP BY ri.return_id
)
SELECT
  product_id,
  COALESCE(NULLIF(TRIM(master_name), ''), NULLIF(TRIM(MAX(snapshot_name)), ''), 'Producto sin nombre') as product_name,
  COALESCE(SUM(total_sales), 0) as total_sales,
  COALESCE(SUM(total_qty), 0) as total_qty,
  COALESCE(SUM(profit_before_expenses), 0) as profit_before_expenses
FROM (
  -- Ventas
  SELECT ... FROM sale_items si ... WHERE s.kind IN ('invoice', 'sale')
  UNION ALL
  -- Devoluciones
  SELECT ... FROM return_items ri ... WHERE s.kind = 'return'
) t
GROUP BY product_id, master_name
ORDER BY total_sales DESC
LIMIT ?
```

### Top clientes (getTopClients)
```sql
SELECT
  t.client_id,
  COALESCE(NULLIF(TRIM(c.nombre), ''), NULLIF(TRIM(t.snapshot_name), ''), 'Cliente General') AS client_name,
  t.total_spent, t.purchase_count
FROM (
  SELECT
    s.customer_id AS client_id,
    MAX(COALESCE(s.customer_name_snapshot, '')) AS snapshot_name,
    COALESCE(SUM(CASE WHEN s.kind = 'return' THEN -ABS(COALESCE(s.total, 0)) ELSE COALESCE(s.total, 0) END), 0) AS total_spent,
    COALESCE(SUM(CASE WHEN s.kind IN ('invoice', 'sale') THEN 1 ELSE 0 END), 0) AS purchase_count
  FROM sales s
  WHERE s.kind IN ('invoice', 'sale', 'return')
    AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND','REFUNDED')
    AND s.deleted_at_ms IS NULL
    AND s.customer_id IS NOT NULL
    AND s.created_at_ms >= ? AND s.created_at_ms <= ?
  GROUP BY s.customer_id
) t
LEFT JOIN clients c ON c.id = t.client_id
ORDER BY total_spent DESC
LIMIT ?
```

---

## 🛠️ DEPENDENCIAS

```yaml
dependencies:
  flutter_riverpod: ^2.4.0
  go_router: ^14.0.0
  fl_chart: ^0.68.0          # Gráficos (barras, pastel, línea)
  intl: ^0.19.0              # Formato de moneda y fechas
  sqflite: ^2.3.0            # Base de datos SQLite
```

---

## ✅ LISTA DE VERIFICACIÓN FINAL

- [ ] **Hero Panel**: Ventas del período con gradiente azul, valor grande (42px), gráfico de barras
- [ ] **Selector de período**: ChoiceChips con Hoy, Semana, 15 días, Mes, Año, Personalizado
- [ ] **DatePicker personalizado**: showDateRangePicker para rango custom
- [ ] **Gráfico de barras (SalesBarChart)**: fl_chart, tooltip, ancho dinámico, colores por signo
- [ ] **Gráfico de pastel (PaymentMethodPieChart)**: donut chart, leyenda lateral con detalles
- [ ] **Gráfico de línea utilidad (ProfitLineChart)**: línea curva gold, área sombreada
- [ ] **Gráfico de línea doble (SalesLineChart)**: dos series, línea punteada secundaria, leyenda
- [ ] **Tarjetas KPI avanzadas (AdvancedKpiCards)**: main + secondary cards con iconos y colores
- [ ] **Tabla productos top (TopProductsTable)**: ranking #, producto, ventas, cantidad, margen
- [ ] **Tabla clientes top (TopClientsTable)**: ranking #, cliente, total gastado, compras
- [ ] **Estadísticas comparativas (ComparativeStatsCard)**: Hoy vs Ayer, Semana, Mes con % cambio
- [ ] **Ventas por cliente (ClientSalesReportPage)**: resumen general + detalle por cliente
- [ ] **Responsive**: wide (Row) y narrow (Column) para todos los paneles
- [ ] **Loading state**: CircularProgressIndicator mientras carga
- [ ] **Empty state**: mensajes "Sin datos en el rango seleccionado"
- [ ] **Formato moneda**: NumberFormat.currency con símbolo RD$ y 2 decimales
- [ ] **Formato números grandes**: abreviación con K, M para counts
- [ ] **Sombras y bordes**: boxShadow suave, border outlineVariant en todas las tarjetas
- [ ] **Iconos Material**: Icons de Material Design para todas las métricas

---

## 🎯 NOTAS IMPORTANTES

1. **Usar `fl_chart`** para todos los gráficos (BarChart, PieChart, LineChart)
2. **Usar `LayoutBuilder`** para detectar el ancho disponible y adaptar layout (wide vs narrow)
3. **Usar `Wrap`** para las tarjetas y chips (responsive automático)
4. **Los datos vienen de SQLite** con consultas SQL directas (no API)
5. **El formato de moneda** usa `NumberFormat.currency(locale: 'en_US', symbol: 'RD\$ ', decimalDigits: 2)`
6. **Los timestamps** están en milisegundos (created_at_ms)
7. **Las devoluciones (returns)** tienen signo negativo en los cálculos
8. **El costo de productos** usa `purchase_price_snapshot` primero, luego `purchase_price` de la tabla products
9. **Los productos sin categoría** se agrupan como "Sin categoria"
10. **Los clientes sin nombre** se muestran como "Cliente General"
11. **El margen** se calcula como `(netProfit / totalSales) * 100`
12. **El ticket promedio** se calcula como `totalSales / salesCount`
13. **La conversión de cotizaciones** se calcula como `(quotesConverted / quotesCount) * 100`
14. **Los gráficos deben tener touch interaction** para mostrar tooltips
15. **El ancho de las barras** debe ser dinámico según la cantidad de datos
