# 🖨️ SUPER PROMPT - MÓDULO DE IMPRESIÓN FULLPOS

## 📋 AUDITORÍA COMPLETA DEL SISTEMA DE IMPRESIÓN

---

## 1. ARQUITECTURA GENERAL DEL MÓDULO DE IMPRESIÓN

### 1.1 Estructura de Directorios

```
lib/core/printing/                          ← NÚCLEO DE IMPRESIÓN
├── unified_ticket_printer.dart             ← 🎯 PUNTO DE ENTRADA ÚNICO (SINGLE ENTRY POINT)
├── thermal_printer_service.dart            ← 🔌 SERVICIO DE IMPRESIÓN TÉRMICA (HARDWARE)
├── invoice_letter_pdf.dart                 ← 📄 FACTURA EN PDF CARTA (LETTER SIZE)
├── quote_printer.dart                      ← 📋 COTIZACIONES EN PDF
├── receipt_printer_service.dart            ← ⚠️ LEGACY: Impresión ESC/POS directa (OBSOLETO)
├── ticket_printer.dart                     ← ⚠️ LEGACY: Impresor antiguo (@Deprecated)
├── ticket_template.dart                    ← ⚠️ LEGACY: Template antiguo
├── product_catalog_printer.dart            ← 📦 Catálogo de productos
├── purchase_order_printer.dart             ← 📦 Órdenes de compra
├── reports_printer.dart                    ← 📊 Reportes
├── sale_invoice_pdf_service.dart           ← ⚠️ LEGACY: Servicio PDF antiguo
│
├── unified_ticket_preview_widget.dart      ← 👁️ VISTA PREVIA UNIFICADA (NUEVA)
├── simplified_ticket_preview_widget.dart   ← 👁️ VISTA PREVIA SIMPLIFICADA (NUEVA)
├── ticket_preview_widget.dart              ← ⚠️ LEGACY: Vista previa antigua
│
├── models/                                 ← 📦 MODELOS COMPARTIDOS
│   ├── models.dart                         ← Barrel export
│   ├── company_info.dart                   ← 🏢 Información de empresa (FUENTE ÚNICA)
│   ├── ticket_data.dart                    ← 🎫 Datos del ticket
│   ├── ticket_layout_config.dart           ← ⚙️ Configuración de layout
│   ├── ticket_builder.dart                 ← 🏗️ Constructor de PDF de tickets
│   ├── ticket_renderer.dart                ← 🎨 Renderer de líneas de ticket
│   └── receipt_text_utils.dart             ← 🔧 Utilidades de texto
│
└── repositories/                           ← 📦 REPOSITORIOS
    └── ticket_config_repository.dart       ← ⚙️ Configuración de ticket
```

### 1.2 Archivos de Configuración (Settings)

```
lib/features/settings/
├── data/
│   ├── printer_settings_model.dart         ← 🎯 MODELO DE CONFIGURACIÓN DE IMPRESORA
│   └── printer_settings_repository.dart    ← 🎯 REPOSITORIO DE CONFIGURACIÓN
└── ui/
    └── printer_settings_page.dart          ← 🎯 PÁGINA DE CONFIGURACIÓN DE IMPRESORA
```

### 1.3 Archivos de Cierre de Caja (Cash Close)

```
lib/features/cash/
└── data/
    └── daily_cash_close_ticket_printer.dart ← 🎯 IMPRESIÓN DE CIERRE DE CAJA DIARIO
```

### 1.4 Archivos de Tracking de Actividad de Impresión

```
lib/core/update/
└── print_activity_tracker.dart             ← 🎯 TRACKER DE ACTIVIDAD DE IMPRESIÓN
```

---

## 2. DIAGRAMA DE FLUJO DE IMPRESIÓN

```
┌─────────────────────────────────────────────────────────────────┐
│                    PUNTO DE ENTRADA ÚNICO                       │
│              UnifiedTicketPrinter (unified_ticket_printer.dart) │
└──────────────────────────┬──────────────────────────────────────┘
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
    ┌──────────────┐ ┌──────────┐ ┌──────────────┐
    │ printTicket  │ │printCustom│ │printSaleTicket│
    │  (genérico)  │ │  Lines   │ │  (desde Sale) │
    └──────┬───────┘ └────┬─────┘ └──────┬───────┘
           │              │              │
           └──────────────┼──────────────┘
                          ▼
           ┌──────────────────────────────┐
           │     TicketBuilder.buildPdf() │
           │   (genera PDF desde datos)   │
           └──────────────┬───────────────┘
                          ▼
           ┌──────────────────────────────┐
           │  ThermalPrinterService       │
           │  .printDocument()            │
           │  (envía PDF a impresora)     │
           └──────────────┬───────────────┘
                          ▼
           ┌──────────────────────────────┐
           │  Printing.directPrintPdf()   │
           │  (paquete printing)          │
           └──────────────────────────────┘
```

---

## 3. AUDITORÍA DETALLADA DE CADA ARCHIVO

### 3.1 🎯 `unified_ticket_printer.dart` - PUNTO DE ENTRADA ÚNICO

**Propósito:** Servicio unificado de impresión de tickets. Es el punto único para imprimir cualquier tipo de ticket.

**Métodos Públicos:**

| Método | Descripción | Parámetros Clave |
|--------|-------------|-------------------|
| `printTicket()` | Método principal genérico | `TicketData data`, `int? overrideCopies` |
| `printCustomLines()` | Imprime líneas personalizadas | `List<String> lines`, `String ticketNumber` |
| `printSaleTicket()` | Imprime ticket desde SaleModel | `SaleModel sale`, `List<SaleItemModel> items` |
| `autoPrintSale()` | Auto-impresión al cobrar | `SaleModel sale`, `List<SaleItemModel> items` |
| `reprintSale()` | Reimpresión (ignora auto-print) | `SaleModel sale`, `List<SaleItemModel> items` |
| `printTestTicket()` | Ticket de prueba | Ninguno |
| `openCashDrawerPulse()` | Abre cajón de dinero | Ninguno |
| `printWidthRulerTest()` | Regla de ancho para debug | Ninguno |
| `generatePreviewText()` | Vista previa en texto plano | `TicketData? data` |
| `getPreviewConfig()` | Config para vista previa | Ninguno |
| `getAvailablePrinters()` | Lista impresoras disponibles | Ninguno |
| `checkPrinterStatus()` | Estado de impresora | Ninguno |

**Flujo interno de `printTicket()`:**
1. Marca inicio de impresión en `PrintActivityTracker`
2. Obtiene datos de empresa desde `CompanyInfoRepository.getCurrentCompanyInfo()` (FUENTE ÚNICA)
3. Obtiene configuración de impresora desde `PrinterSettingsRepository.getOrCreate()`
4. Crea `TicketLayoutConfig` desde settings
5. Crea `TicketBuilder` con layout y company
6. Genera PDF con `builder.buildPdf(data)`
7. Envía a imprimir con `ThermalPrinterService.printDocument()`
8. Marca fin de impresión en `PrintActivityTracker`

**Clases adicionales en este archivo:**
- `PrintTicketResult` - Resultado de impresión (success, message, ticketNumber, skipped)
- `TicketPreviewConfig` - Configuración para vista previa

---

### 3.2 🔌 `thermal_printer_service.dart` - SERVICIO DE IMPRESIÓN TÉRMICA

**Propósito:** Servicio centralizado para impresión térmica USB de 80mm/58mm. Maneja detección de impresoras e impresión directa.

**Métodos:**

| Método | Descripción |
|--------|-------------|
| `getAvailablePrinters()` | Lista todas las impresoras del sistema vía `Printing.listPrinters()` |
| `findPrinter(String? name)` | Busca impresora por nombre (con caché) |
| `checkPrinterStatus()` | Verifica si hay impresora configurada y disponible |
| `printDocument()` | Imprime documento PDF a impresora térmica (con soporte multi-copia) |
| `getPageFormat()` | Genera formato de página para impresora térmica |
| `clearCache()` | Limpia caché de impresora |

**Clases adicionales:**
- `PrinterStatus` - Estado de la impresora (isConfigured, isAvailable, printerName, message, printer)
- `PrintResult` - Resultado de impresión (success, message)

**Detalles técnicos:**
- Usa el paquete `printing` para listar impresoras e imprimir PDFs
- El formato de página se calcula: 80mm → 72mm imprimibles, 58mm → 48mm imprimibles
- Alto del rollo: 2000mm (valor finito para evitar problemas con drivers Windows)
- Soporta múltiples copias iterando sobre `directPrintPdf()`

---

### 3.3 📄 `invoice_letter_pdf.dart` - FACTURA EN PDF CARTA

**Propósito:** Genera facturas en formato PDF tamaño carta (Letter) con diseño profesional.

**Método principal:**
```dart
static Future<Uint8List> generate({
  required SaleModel sale,
  required List<SaleItemModel> items,
  required BusinessSettings business,
  required int brandColorArgb,
  String? cashierName,
  String? warrantyPolicy,
  String? footerMessage,
})
```

**Características:**
- Formato carta (Letter) con márgenes de 40pt
- Logo de empresa (desde archivo local)
- Encabezado con nombre, RNC, teléfono, dirección, email
- Título dinámico: "FACTURA ELECTRÓNICA", "FACTURA FISCAL" o "FACTURA"
- Datos del cliente (nombre, teléfono, RNC/Cédula)
- Datos fiscales (NCF, e-CF, tipo, vencimiento)
- Tabla de items con soporte para descuentos por línea
- Bloque de totales (subtotal, descuento, ITBIS, total)
- Política de garantía
- Mensaje de pie de página
- Redes sociales (web, Instagram, Facebook)

---

### 3.4 📋 `quote_printer.dart` - COTIZACIONES EN PDF

**Propósito:** Servicio para imprimir, compartir y generar PDF de cotizaciones con diseño profesional.

**Métodos principales:**
- `generatePdf()` - Genera PDF de cotización (soporta isolate para no bloquear UI)
- `printQuote()` - Imprime cotización directamente
- `showPreview()` - Muestra vista previa en página aparte

**Características:**
- Formato A4
- Logo de empresa o iniciales como fallback
- Información del cliente
- Tabla de productos con ITBIS opcional
- Resumen de totales
- Notas y condiciones
- Footer con número de página
- Estados: APROBADA, CANCELADA, CONVERTIDA, VENCIDA, BORRADOR, PENDIENTE
- Colores dinámicos según estado
- Fuentes del sistema (Segoe UI, Arial) con fallback a Helvetica

---

### 3.5 ⚙️ `printer_settings_model.dart` - MODELO DE CONFIGURACIÓN

**Propósito:** Modelo de datos para la configuración de la impresora.

**Campos principales:**

| Campo | Tipo | Default | Descripción |
|-------|------|---------|-------------|
| `selectedPrinterName` | `String?` | null | Nombre de la impresora seleccionada |
| `paperWidthMm` | `int` | 80 | Ancho del papel (58 o 80 mm) |
| `charsPerLine` | `int` | 48 | Caracteres por línea |
| `autoPrintOnPayment` | `int` | 0 | Auto-imprimir al cobrar (0/1) |
| `autoOpenDrawerOnChargeWithoutTicket` | `int` | 0 | Abrir cajón sin ticket |
| `copies` | `int` | 1 | Número de copias |
| `showItbis` | `int` | 1 | Mostrar ITBIS |
| `showElectronicInvoiceReference` | `int` | 1 | Mostrar referencia e-CF |
| `showCashier` | `int` | 1 | Mostrar cajero |
| `showClient` | `int` | 1 | Mostrar cliente |
| `showPaymentMethod` | `int` | 1 | Mostrar método de pago |
| `showDiscounts` | `int` | 1 | Mostrar descuentos |
| `showCode` | `int` | 1 | Mostrar código de ticket |
| `showDatetime` | `int` | 1 | Mostrar fecha/hora |
| `headerBusinessName` | `String` | 'FULLPOS' | Nombre del negocio |
| `headerRnc` | `String?` | '' | RNC |
| `headerAddress` | `String?` | '' | Dirección |
| `headerPhone` | `String?` | '' | Teléfono |
| `headerExtra` | `String?` | '' | Encabezado adicional |
| `footerMessage` | `String` | 'Gracias por su compra' | Mensaje final |
| `warrantyPolicy` | `String` | '' | Política de garantía |
| `leftMargin` | `int` | 0 | Margen izquierdo |
| `rightMargin` | `int` | 0 | Margen derecho |
| `autoCut` | `int` | 1 | Corte automático |
| `itbisRate` | `double` | 0.18 | Tasa de ITBIS |
| `fontFamily` | `String` | 'arial' | Familia de fuente |
| `fontSize` | `String` | 'normal' | Tamaño de fuente |
| `showLogo` | `int` | 1 | Mostrar logo |
| `logoSize` | `int` | 70 | Tamaño del logo |
| `showBusinessData` | `int` | 1 | Mostrar datos del negocio |
| `showSubtotalItbisTotal` | `int` | 1 | Mostrar subtotal/ITBIS/total |
| `autoHeight` | `int` | 1 | Altura automática |
| `topMargin` | `int` | 8 | Margen superior |
| `bottomMargin` | `int` | 8 | Margen inferior |
| `fontSizeLevel` | `int` | 6 | Nivel de tamaño de fuente |
| `lineSpacingLevel` | `int` | 6 | Nivel de espaciado entre líneas |
| `sectionSpacingLevel` | `int` | 6 | Nivel de espaciado entre secciones |
| `sectionSeparatorStyle` | `String` | 'single' | Estilo de separador |
| `headerAlignment` | `String` | 'center' | Alineación del encabezado |
| `detailsAlignment` | `String` | 'left' | Alineación de detalles |
| `totalsAlignment` | `String` | 'right' | Alineación de totales |

---

### 3.6 🗄️ `printer_settings_repository.dart` - REPOSITORIO DE CONFIGURACIÓN

**Propósito:** Repositorio para gestionar la configuración de la impresora en SQLite.

**Métodos:**

| Método | Descripción |
|--------|-------------|
| `getSettings()` | Obtiene configuración actual (puede retornar null) |
| `getOrCreate()` | Obtiene configuración o crea una por defecto |
| `updateSettings()` | Actualiza configuración |
| `resetToDefaults()` | Restablece a valores por defecto (mantiene impresora) |
| `resetToProfessional()` | Restaura plantilla profesional ejecutiva |

**Características:**
- Auto-migración de esquema: verifica columnas faltantes y las agrega
- 50 columnas en total en la tabla `printer_settings`
- Valores por defecto profesionales

---

### 3.7 🖥️ `printer_settings_page.dart` - PÁGINA DE CONFIGURACIÓN

**Propósito:** Interfaz de usuario para configuración de impresora y ticket.

**Secciones de la UI:**
1. **Impresora** - Selección de impresora, ancho de papel (58/80mm), botón de prueba
2. **Logo y negocio** - Mostrar logo, tamaño del logo, mostrar datos del negocio
3. **Tamaño del texto** - Pequeña/Normal/Grande
4. **Formato del ticket** - Compacto/Detallado
5. **Mensaje y garantía** - Encabezado adicional, mensaje final, política de garantía

**Características:**
- Auto-guardado con debounce de 250ms
- Cola de persistencia para evitar condiciones de carrera
- Botón "Guardar ahora" en bottom bar
- Vista responsive (se adapta a pantallas pequeñas)
- Formato compacto vs detallado controla visibilidad de secciones

---

### 3.8 👁️ VISTAS PREVIAS (3 implementaciones)

#### 3.8.1 `unified_ticket_preview_widget.dart` - VISTA PREVIA UNIFICADA (NUEVA)
- Usa `TicketLayoutConfig` para configuración
- Muestra: logo, nombre, RNC, teléfono, dirección, tipo documento, fecha, ticket#, datos cliente, items, totales, pago, footer
- Soporta: factura electrónica, copia, datos fiscales
- Formato profesional estilo factura

#### 3.8.2 `simplified_ticket_preview_widget.dart` - VISTA PREVIA SIMPLIFICADA (NUEVA)
- Usa `TicketRenderer.buildLines()` como FUENTE ÚNICA DE VERDAD
- Muestra exactamente las mismas líneas que la impresión
- Usa fuente monospace (Courier New) para alineación precisa
- Mide el ancho de caracteres dinámicamente

#### 3.8.3 `ticket_preview_widget.dart` - VISTA PREVIA ANTIGUA (LEGACY)
- Usa `PrinterSettingsModel` directamente
- No usa `TicketLayoutConfig` ni `TicketRenderer`
- ⚠️ Puede mostrar diferencias con la impresión real

---

### 3.9 🏗️ MODELOS COMPARTIDOS

#### `ticket_data.dart` - Datos del ticket
- `TicketData` - Modelo principal con todos los campos
- `TicketItemData` - Item individual del ticket
- `ClientInfo` - Información del cliente
- `TicketType` - Enum: sale, quote, refund, credit, copy
- Método `TicketData.fromSale()` - Crea desde SaleModel
- Método `TicketData.demo()` - Datos de demostración

#### `ticket_layout_config.dart` - Configuración de layout
- `TicketLayoutConfig` - Configuración de diseño
- `TicketFontSize` - Enum: small, normal, large
- `TicketFontFamily` - Enum: arial, courier, times
- Método `fromPrinterSettings()` - Crea desde PrinterSettingsModel
- Propiedades calculadas: `adjustedFontSize`, `fontFamilyName`, `lineSpacingFactor`, `sectionSpacingFactor`, `logoSizePx`

#### `ticket_builder.dart` - Constructor de PDF
- `TicketBuilder` - Genera PDF y texto plano para tickets
- Método `buildPdf()` - Genera documento PDF completo
- Método `buildPdfFromLines()` - Genera PDF desde líneas pre-renderizadas
- Método `buildPlainText()` - Genera texto plano para vista previa
- Método `buildDebugRuler()` - Regla de depuración
- Más de 1500 líneas de código

#### `ticket_renderer.dart` - Renderer de líneas
- `TicketRenderer` - FUENTE ÚNICA DE VERDAD para layout
- Método `buildLines()` - Genera lista de líneas de texto
- Usado por: vista previa simplificada, impresión térmica, generación PDF
- Maneja: encabezado, items, totales, pagos, factura electrónica, crédito, apartados

#### `company_info.dart` - Información de empresa
- `CompanyInfo` - FUENTE ÚNICA de datos de empresa
- `CompanyInfoRepository` - Repositorio que unifica BusinessSettings y EmpresaConfig
- Método `getCurrentCompanyInfo()` - Obtiene datos actuales
- Soporta carga de logo desde archivo

---

### 3.10 🧾 `daily_cash_close_ticket_printer.dart` - CIERRE DE CAJA

**Propósito:** Imprime el ticket de cierre de caja diario con resumen de operaciones.

**Método principal:**
```dart
static Future<PrintTicketResult> printDailyCloseTicket({
  required int cashboxDailyId,
  required String businessDate,
  String? note,
})
```

**Contenido del ticket de cierre:**
- Nombre de empresa, RNC, teléfono
- "CORTE DE TURNO"
- Número de caja, cajero, fecha
- Hora de apertura y cierre
- Fondo inicial, total vendido, salidas de caja
- Efectivo esperado, efectivo final, diferencia
- Número de tickets
- Desglose: efectivo, tarjeta, transferencia, crédito
- Abonos a crédito y apartados
- Entradas y salidas manuales
- Nota opcional
- Últimos 8 movimientos

---

### 3.11 📊 `print_activity_tracker.dart` - TRACKER DE ACTIVIDAD

**Propósito:** Rastrea trabajos de impresión activos para seguridad del sistema de actualizaciones.

**Métodos:**
- `markPrintStarted()` - Marca inicio de impresión
- `markPrintCompleted()` - Marca fin de impresión
- `waitUntilIdle(Duration timeout)` - Espera hasta que todas las impresiones terminen
- Propiedades: `isPrinting`, `hasPendingPrintJobs`

---

### 3.12 ⚠️ ARCHIVOS LEGACY (OBSOLETOS)

| Archivo | Estado | Reemplazo |
|---------|--------|-----------|
| `ticket_printer.dart` | `@Deprecated` | `UnifiedTicketPrinter` |
| `ticket_template.dart` | No usado | `TicketBuilder` |
| `receipt_printer_service.dart` | No usado activamente | `ThermalPrinterService` |
| `sale_invoice_pdf_service.dart` | No usado | `InvoiceLetterPdf` |
| `ticket_preview_widget.dart` | Legacy | `UnifiedTicketPreviewWidget` |

---

## 4. FLUJOS DE IMPRESIÓN COMPLETOS

### 4.1 Flujo de Venta → Impresión de Ticket

```
SalesPage / PaymentDialog
    │
    ├── paymentResult['printTicket'] == true
    │
    ▼
UnifiedTicketPrinter.autoPrintSale()
    │
    ├── Verifica autoPrintOnPayment == 1
    │   └── Si no: retorna skipped=true
    │
    ▼
UnifiedTicketPrinter.printSaleTicket()
    │
    ├── Carga FacturaElectrónica (si existe)
    ├── Convierte SaleModel + items → TicketData
    │
    ▼
UnifiedTicketPrinter.printTicket(data)
    │
    ├── PrintActivityTracker.markPrintStarted()
    ├── CompanyInfoRepository.getCurrentCompanyInfo()
    ├── PrinterSettingsRepository.getOrCreate()
    ├── TicketLayoutConfig.fromPrinterSettings()
    ├── TicketBuilder(layout, company).buildPdf(data)
    ├── ThermalPrinterService.printDocument(pdf, settings, copies)
    │   ├── findPrinter(selectedPrinterName)
    │   ├── Printing.directPrintPdf() × copies
    │   └── Retorna PrintResult
    ├── PrintActivityTracker.markPrintCompleted()
    └── Retorna PrintTicketResult
```

### 4.2 Flujo de Reimpresión

```
FacturaPage / ReturnsListPage
    │
    ▼
UnifiedTicketPrinter.reprintSale()
    │
    ├── Carga FacturaElectrónica
    ├── Convierte a TicketData con isCopy=true
    │
    ▼
UnifiedTicketPrinter.printTicket(data, copies)
    │
    └── (mismo flujo que arriba)
```

### 4.3 Flujo de Cierre de Caja

```
CashCloseDialog
    │
    ▼
DailyCashCloseTicketPrinter.printDailyCloseTicket()
    │
    ├── OperationFlowService.getDailyCashbox()
    ├── CashRepository.buildDailySummary()
    ├── CashRepository.listMovementsForDailyCashbox()
    ├── PrinterSettingsRepository.getOrCreate()
    ├── TicketLayoutConfig.fromPrinterSettings()
    ├── CompanyInfoRepository.getCurrentCompanyInfo()
    ├── _buildDailyCloseLines() → genera líneas de texto
    │
    ▼
UnifiedTicketPrinter.printCustomLines(lines)
    │
    └── (mismo flujo de impresión)
```

### 4.4 Flujo de Factura PDF (Carta)

```
FacturaPage → Botón "Descargar PDF"
    │
    ▼
InvoiceLetterPdf.generate()
    │
    ├── PrinterSettingsRepository.getOrCreate() (para warranty/footer)
    ├── FacturaElectronicaRepository.getBySaleId()
    ├── Carga logo desde archivo
    ├── Construye documento PDF con pw.Document
    │   ├── MultiPage (Letter, márgenes 40pt)
    │   ├── Header (logo, empresa, título, fecha, cajero)
    │   ├── Info cards (cliente, datos fiscales)
    │   ├── Items table
    │   ├── Totals block
    │   ├── Warranty policy
    │   └── Footer message
    │
    ▼
    Retorna Uint8List (PDF bytes)
```

### 4.5 Flujo de Cotización PDF

```
QuotePrinter.generatePdf()
    │
    ├── _resolveBusinessData() (EmpresaConfig + BusinessSettings)
    ├── _loadBrandPalette() (colores del tema)
    ├── Carga fuentes del sistema (Segoe UI, Arial, Helvetica)
    ├── Carga logo
    │
    ▼
    Construye PDF con pw.Document
    │
    ├── MultiPage (A4, márgenes 44pt)
    ├── Header (logo, empresa, #cotización, estado, fechas)
    ├── Client section
    ├── Products table (con ITBIS opcional)
    ├── Summary section (subtotal, ITBIS, total)
    ├── Notes section
    └── Footer (página X de Y)
```

---

## 5. DEPENDENCIAS (PAQUETES)

| Paquete | Uso |
|---------|-----|
| `printing` | Listar impresoras, imprimir PDFs |
| `pdf` | Generar documentos PDF |
| `intl` | Formateo de fechas y números |
| `flutter_esc_pos_utils` | ⚠️ Legacy: comandos ESC/POS |
| `flutter_esc_pos_network` | ⚠️ Legacy: impresión por red |
| `usb_esc_printer_windows` | ⚠️ Legacy: impresión USB directa |

---

## 6. PUNTOS CRÍTICOS Y POSIBLES MEJORAS

### 6.1 Problemas Identificados

1. **⚠️ Múltiples vistas previas**: Hay 3 widgets de vista previa diferentes. El `ticket_preview_widget.dart` (legacy) puede mostrar resultados diferentes a la impresión real.

2. **⚠️ Legacy sin limpiar**: `ticket_printer.dart`, `ticket_template.dart`, `receipt_printer_service.dart`, `sale_invoice_pdf_service.dart` están marcados como deprecados pero aún existen en el código.

3. **⚠️ Duplicación de lógica**: `TicketBuilder.buildPdf()` y `TicketRenderer.buildLines()` tienen lógica similar para construir el contenido del ticket.

4. **⚠️ Manejo de errores**: En algunos lugares los errores de impresión se tragan silenciosamente con `catch (_)`.

5. **⚠️ Sin cola de impresión**: No hay un sistema de cola para múltiples trabajos de impresión simultáneos.

### 6.2 Mejoras Recomendadas

1. **✅ Unificar vistas previas**: Eliminar `ticket_preview_widget.dart` legacy y usar solo `UnifiedTicketPreviewWidget` o `SimplifiedTicketPreviewWidget`.

2. **✅ Limpiar código legacy**: Eliminar archivos deprecados después de verificar que no hay referencias.

3. **✅ Centralizar aún más**: Hacer que `TicketRenderer.buildLines()` sea la ÚNICA fuente de verdad, y que `TicketBuilder.buildPdf()` use `TicketRenderer` internamente.

4. **✅ Mejorar feedback al usuario**: Mostrar errores específicos (impresora no encontrada, sin papel, sin conexión).

5. **✅ Agregar cola de impresión**: Para evitar conflictos cuando múltiples impresiones se disparan casi simultáneamente.

---

## 7. COMANDOS PARA REPLICAR EL MÓDULO COMPLETO

### 7.1 Archivos EsencialES (NUEVOS - deben crearse)

```
lib/core/printing/
├── unified_ticket_printer.dart
├── thermal_printer_service.dart
├── invoice_letter_pdf.dart
├── quote_printer.dart
├── unified_ticket_preview_widget.dart
├── simplified_ticket_preview_widget.dart
├── models/
│   ├── models.dart
│   ├── company_info.dart
│   ├── ticket_data.dart
│   ├── ticket_layout_config.dart
│   ├── ticket_builder.dart
│   ├── ticket_renderer.dart
│   └── receipt_text_utils.dart
└── repositories/
    └── ticket_config_repository.dart
```

### 7.2 Archivos de Configuración

```
lib/features/settings/
├── data/
│   ├── printer_settings_model.dart
│   └── printer_settings_repository.dart
└── ui/
    └── printer_settings_page.dart
```

### 7.3 Archivos de Cierre de Caja

```
lib/features/cash/
└── data/
    └── daily_cash_close_ticket_printer.dart
```

### 7.4 Archivo de Tracking

```
lib/core/update/
└── print_activity_tracker.dart
```

### 7.5 Archivos Legacy (OBSOLETOS - no replicar)

```
✗ lib/core/printing/ticket_printer.dart          ← @Deprecated
✗ lib/core/printing/ticket_template.dart         ← No usado
✗ lib/core/printing/receipt_printer_service.dart  ← No usado activamente
✗ lib/core/printing/sale_invoice_pdf_service.dart ← No usado
✗ lib/core/printing/ticket_preview_widget.dart    ← Legacy
```

---

## 8. RESUMEN DE LÍNEAS DE CÓDIGO

| Archivo | Líneas | Estado |
|---------|--------|--------|
| `unified_ticket_printer.dart` | 545 | ✅ Activo |
| `thermal_printer_service.dart` | 223 | ✅ Activo |
| `invoice_letter_pdf.dart` | 807 | ✅ Activo |
| `quote_printer.dart` | 1755 | ✅ Activo |
| `unified_ticket_preview_widget.dart` | 727 | ✅ Activo |
| `simplified_ticket_preview_widget.dart` | 123 | ✅ Activo |
| `ticket_preview_widget.dart` | 597 | ⚠️ Legacy |
| `ticket_printer.dart` | 609 | ⚠️ Deprecated |
| `receipt_printer_service.dart` | 490 | ⚠️ Legacy |
| `printer_settings_model.dart` | ~200 | ✅ Activo |
| `printer_settings_repository.dart` | 317 | ✅ Activo |
| `printer_settings_page.dart` | 862 | ✅ Activo |
| `daily_cash_close_ticket_printer.dart` | 248 | ✅ Activo |
| `print_activity_tracker.dart` | 40 | ✅ Activo |
| `ticket_data.dart` | 443 | ✅ Activo |
| `ticket_layout_config.dart` | 448 | ✅ Activo |
| `ticket_builder.dart` | 1597 | ✅ Activo |
| `ticket_renderer.dart` | 494 | ✅ Activo |
| `company_info.dart` | 194 | ✅ Activo |
| **TOTAL** | **~11,319** | |

---

## 9. DIAGRAMA DE DEPENDENCIAS

```
printer_settings_page.dart
    ├── PrinterSettingsRepository
    ├── UnifiedTicketPrinter
    └── TicketLayoutConfig

unified_ticket_printer.dart
    ├── CompanyInfoRepository
    ├── PrinterSettingsRepository
    ├── TicketLayoutConfig
    ├── TicketBuilder
    ├── ThermalPrinterService
    └── PrintActivityTracker

thermal_printer_service.dart
    ├── Printing (paquete)
    └── PrinterSettingsRepository

ticket_builder.dart
    ├── TicketLayoutConfig
    ├── CompanyInfo
    ├── TicketRenderer
    └── ReceiptTextUtils

ticket_renderer.dart
    ├── TicketLayoutConfig
    ├── TicketData
    └── CompanyInfo

invoice_letter_pdf.dart
    ├── FacturaElectronicaRepository
    ├── SaleTotalsCalculator
    └── PrinterSettingsRepository

quote_printer.dart
    ├── EmpresaService
    ├── ThemeSettingsRepository
    └── Printing (paquete)

daily_cash_close_ticket_printer.dart
    ├── OperationFlowService
    ├── CashRepository
    ├── PrinterSettingsRepository
    ├── TicketLayoutConfig
    ├── CompanyInfoRepository
    └── UnifiedTicketPrinter
```

---

## 10. CONCLUSIÓN

El módulo de impresión de FULLPOS está **bien estructurado** con una arquitectura que sigue el patrón de **punto de entrada único** (`UnifiedTicketPrinter`). Sin embargo, arrastra **código legacy** que debería ser eliminado para evitar confusión y posibles bugs.

La **FUENTE ÚNICA DE VERDAD** para datos de empresa es `CompanyInfoRepository.getCurrentCompanyInfo()`, y para el layout del ticket es `TicketRenderer.buildLines()`.

**Prioridades para refactorización:**
1. 🥇 Eliminar vistas previas legacy (`ticket_preview_widget.dart`)
2. 🥇 Eliminar código deprecado (`ticket_printer.dart`, `ticket_template.dart`, `receipt_printer_service.dart`, `sale_invoice_pdf_service.dart`)
3. 🥈 Unificar `TicketBuilder.buildPdf()` para que use `TicketRenderer.buildLines()` internamente
4. 🥈 Mejorar manejo de errores con mensajes específicos para el usuario
5. 🥉 Agregar sistema de cola de impresión para evitar conflictos
6. 🥉 Agregar logs estructurados para diagnóstico de problemas de impresión

---

## 📦 RESUMEN PARA REPLICAR

Para **replicar este módulo completo en otro proyecto**, necesitas:

### Archivos a crear (19 archivos):
1. `lib/core/printing/unified_ticket_printer.dart` - Punto de entrada único
2. `lib/core/printing/thermal_printer_service.dart` - Servicio de impresión
3. `lib/core/printing/invoice_letter_pdf.dart` - Factura PDF carta
4. `lib/core/printing/quote_printer.dart` - Cotizaciones PDF
5. `lib/core/printing/unified_ticket_preview_widget.dart` - Vista previa unificada
6. `lib/core/printing/simplified_ticket_preview_widget.dart` - Vista previa simplificada
7. `lib/core/printing/models/models.dart` - Barrel export
8. `lib/core/printing/models/company_info.dart` - Info de empresa
9. `lib/core/printing/models/ticket_data.dart` - Datos del ticket
10. `lib/core/printing/models/ticket_layout_config.dart` - Config layout
11. `lib/core/printing/models/ticket_builder.dart` - Constructor PDF
12. `lib/core/printing/models/ticket_renderer.dart` - Renderer líneas
13. `lib/core/printing/models/receipt_text_utils.dart` - Utilidades texto
14. `lib/core/printing/repositories/ticket_config_repository.dart` - Repo config
15. `lib/features/settings/data/printer_settings_model.dart` - Modelo settings
16. `lib/features/settings/data/printer_settings_repository.dart` - Repo settings
17. `lib/features/settings/ui/printer_settings_page.dart` - UI settings
18. `lib/features/cash/data/daily_cash_close_ticket_printer.dart` - Cierre caja
19. `lib/core/update/print_activity_tracker.dart` - Tracker actividad

### Dependencias (pubspec.yaml):
```yaml
dependencies:
  printing: ^5.13.4        # Listar impresoras e imprimir PDFs
  pdf: ^3.11.1             # Generar documentos PDF
  intl: ^0.19.0            # Formateo de fechas y números
```

### Archivos a NO crear (legacy):
- ❌ `lib/core/printing/ticket_printer.dart`
- ❌ `lib/core/printing/ticket_template.dart`
- ❌ `lib/core/printing/receipt_printer_service.dart`
- ❌ `lib/core/printing/sale_invoice_pdf_service.dart`
- ❌ `lib/core/printing/ticket_preview_widget.dart`

### Puntos de integración:
- `CompanyInfoRepository.getCurrentCompanyInfo()` - Fuente única de datos de empresa
- `PrinterSettingsRepository.getOrCreate()` - Configuración de impresora
- `PrintActivityTracker.instance` - Tracking de actividad de impresión
- `UnifiedTicketPrinter.printTicket()` - Método principal de impresión
- `UnifiedTicketPrinter.printSaleTicket()` - Imprimir desde SaleModel
- `UnifiedTicketPrinter.autoPrintSale()` - Auto-impresión al cobrar
- `UnifiedTicketPrinter.reprintSale()` - Reimpresión
- `DailyCashCloseTicketPrinter.printDailyCloseTicket()` - Cierre de caja
- `InvoiceLetterPdf.generate()` - Factura PDF carta
- `QuotePrinter.generatePdf()` - Cotización PDF
f