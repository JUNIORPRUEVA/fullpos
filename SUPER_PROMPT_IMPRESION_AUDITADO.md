# SUPER PROMPT AUDITADO - MODULO DE IMPRESION FULLPOS

Usa este prompt para recrear en otra app el modulo de impresion de FULLPOS con la misma arquitectura, configuracion, formatos de ticket, estilos, tamanos, flujo de impresion, vista previa, cierre de caja y PDF de factura/cotizacion.

---

## PROMPT PARA PEGAR EN OTRA APP

Quiero que implementes un modulo completo de impresion POS identico al modulo actual de FULLPOS. Debe estar pensado para Flutter/Dart, impresoras termicas Windows/USB de 80 mm y 58 mm, y debe generar tickets como PDF termico usando los paquetes `pdf` y `printing`, no ESC/POS directo como flujo principal.

### 1. Objetivo general

Construye un sistema de impresion centralizado con estas capacidades:

- Configurar impresora del sistema.
- Seleccionar papel termico de 80 mm o 58 mm.
- Definir caracteres por linea: 48 para 80 mm y 32 para 58 mm.
- Imprimir ticket de venta.
- Reimprimir ventas como copia.
- Auto-imprimir al cobrar si la configuracion lo permite.
- Abrir cajon de dinero enviando un trabajo minimo a la impresora.
- Imprimir ticket de prueba.
- Imprimir regla de ancho para calibrar columnas.
- Imprimir cierre de turno/caja.
- Generar factura PDF tamano carta.
- Generar cotizacion PDF.
- Generar vista previa del ticket con el mismo layout de impresion.
- Bloquear actualizaciones o procesos criticos mientras haya impresion activa mediante un tracker.

El punto de entrada unico debe ser un servicio llamado `UnifiedTicketPrinter`.

### 2. Dependencias requeridas

Agrega estas dependencias:

```yaml
dependencies:
  pdf: ^3.11.1
  printing: ^5.13.4
  intl: ^0.19.0
```

Si la app ya tiene paquetes ESC/POS, dejalos solo como legado o compatibilidad. El flujo principal debe ser PDF termico con `Printing.directPrintPdf()`.

### 3. Estructura de archivos obligatoria

Crea esta estructura:

```text
lib/core/printing/
  unified_ticket_printer.dart
  thermal_printer_service.dart
  invoice_letter_pdf.dart
  quote_printer.dart
  unified_ticket_preview_widget.dart
  simplified_ticket_preview_widget.dart
  receipt_typography.dart
  product_catalog_printer.dart
  purchase_order_printer.dart
  reports_printer.dart
  models/
    models.dart
    company_info.dart
    ticket_data.dart
    ticket_layout_config.dart
    ticket_builder.dart
    ticket_renderer.dart
    receipt_text_utils.dart
  repositories/
    ticket_config_repository.dart

lib/features/settings/data/
  printer_settings_model.dart
  printer_settings_repository.dart

lib/features/settings/ui/
  printer_settings_page.dart

lib/features/cash/data/
  daily_cash_close_ticket_printer.dart

lib/core/update/
  print_activity_tracker.dart
```

No hagas que cada pantalla imprima por su cuenta. Toda impresion de ticket debe pasar por `UnifiedTicketPrinter`.

### 4. Modelo de configuracion de impresora

Crea un modelo `PrinterSettingsModel` con estos campos:

```dart
class PrinterSettingsModel {
  final int? id;
  final String? selectedPrinterName;
  final int paperWidthMm;
  final int charsPerLine;
  final int autoPrintOnPayment;
  final int autoOpenDrawerOnChargeWithoutTicket;
  final int copies;
  final int showItbis;
  final int showElectronicInvoiceReference;
  final int showCashier;
  final int showClient;
  final int showPaymentMethod;
  final int showDiscounts;
  final int showCode;
  final int showDatetime;
  final String headerBusinessName;
  final String? headerRnc;
  final String? headerAddress;
  final String? headerPhone;
  final String? headerExtra;
  final String footerMessage;
  final String warrantyPolicy;
  final int leftMargin;
  final int rightMargin;
  final int autoCut;
  final double itbisRate;
  final int createdAtMs;
  final int updatedAtMs;
  final String fontFamily;
  final String fontSize;
  final int showLogo;
  final int logoSize;
  final int showBusinessData;
  final int showSubtotalItbisTotal;
  final int autoHeight;
  final int topMargin;
  final int bottomMargin;
  final int fontSizeLevel;
  final int lineSpacingLevel;
  final int sectionSpacingLevel;
  final String sectionSeparatorStyle;
  final String headerAlignment;
  final String detailsAlignment;
  final String totalsAlignment;
}
```

Valores por defecto reales:

- `selectedPrinterName`: null.
- `paperWidthMm`: 80.
- `charsPerLine`: 48.
- `autoPrintOnPayment`: 0.
- `autoOpenDrawerOnChargeWithoutTicket`: 0.
- `copies`: 1.
- `showItbis`: 1.
- `showElectronicInvoiceReference`: 1.
- `showCashier`: 1.
- `showClient`: 1.
- `showPaymentMethod`: 1.
- `showDiscounts`: 1.
- `showCode`: 1.
- `showDatetime`: 1.
- `headerBusinessName`: `FULLPOS`.
- `headerRnc`, `headerAddress`, `headerPhone`, `headerExtra`: texto vacio o null.
- `footerMessage`: `¡Gracias por su preferencia!` al crear configuracion nueva desde repositorio.
- `warrantyPolicy`: texto vacio.
- `leftMargin`: 0.
- `rightMargin`: 0.
- `autoCut`: 1.
- `itbisRate`: 0.18.
- `fontFamily`: `arial`.
- `fontSize`: `normal`.
- `showLogo`: 1.
- `logoSize`: 70.
- `showBusinessData`: 1.
- `showSubtotalItbisTotal`: 1.
- `autoHeight`: 1.
- `topMargin`: 8.
- `bottomMargin`: 8.
- `fontSizeLevel`: 6.
- `lineSpacingLevel`: 6.
- `sectionSpacingLevel`: 6.
- `sectionSeparatorStyle`: `single`.
- `headerAlignment`: `center`.
- `detailsAlignment`: `left`.
- `totalsAlignment`: `right`.

La tabla SQLite debe llamarse `printer_settings`. El repositorio debe tener `_ensureSchema()` que revise `PRAGMA table_info(printer_settings)` y agregue columnas faltantes con `ALTER TABLE`.

Metodos obligatorios del repositorio:

- `getSettings()`
- `getOrCreate()`
- `updateSettings(PrinterSettingsModel settings)`
- `resetToDefaults()`
- `resetToProfessional()`

`resetToDefaults()` debe mantener la impresora actual. `resetToProfessional()` tambien debe mantener impresora y datos del negocio existentes, pero activar `autoPrintOnPayment = 1`.

### 5. Pantalla de configuracion de impresora

Crea `PrinterSettingsPage` con estas secciones:

1. Intro: titulo `Impresora y ticket`.
2. Impresora:
   - Dropdown de impresoras usando `UnifiedTicketPrinter.getAvailablePrinters()`.
   - Boton de refrescar impresoras.
   - Selector segmentado de papel: `58 mm` y `80 mm`.
   - Si selecciona 58 mm, guardar `paperWidthMm = 58` y `charsPerLine = 32`.
   - Si selecciona 80 mm, guardar `paperWidthMm = 80` y `charsPerLine = 48`.
   - Boton `Probar impresion`, que primero persiste cambios y luego llama `UnifiedTicketPrinter.printTestTicket()`.
3. Logo y negocio:
   - Switch `Mostrar logo`.
   - Selector segmentado de tamano de logo:
     - pequeno: 40.
     - normal: 70.
     - grande: 100.
   - Switch `Mostrar datos del negocio`.
4. Tamano del texto:
   - Segmentado `small`, `normal`, `large`.
   - Etiquetas: `Pequeña`, `Normal`, `Grande`.
5. Formato del ticket:
   - Segmentado `Compacto` y `Detallado`.
   - Compacto debe apagar cliente, cajero, subtotal/ITBIS/total detallado, descuentos y referencia electronica.
   - Detallado debe encender cliente, cajero, subtotal/ITBIS/total, descuentos, referencia electronica, metodo de pago, fecha, codigo e ITBIS.
6. Mensaje y garantia:
   - Campo `Encabezado adicional`.
   - Campo `Mensaje final`.
   - Campo multilinea `Politica de garantia`.

La pantalla debe auto-guardar con debounce de 250 ms y tener boton `Guardar ahora`. Antes de imprimir prueba debe persistir la configuracion porque el motor de impresion lee desde base de datos.

### 6. Servicio de impresion termica

Crea `ThermalPrinterService`:

- `getAvailablePrinters()` usa `Printing.listPrinters()`.
- `findPrinter(String? name)` busca por nombre exacto y cachea impresora/nombre.
- `checkPrinterStatus()` devuelve si hay impresora configurada y si esta disponible.
- `printDocument({required pw.Document document, PrinterSettingsModel? settings, int? overrideCopies})`.
- `getPageFormat(PrinterSettingsModel settings)`.
- `clearCache()`.

Reglas de impresion:

- Si no hay `selectedPrinterName`, devolver error `No hay impresora configurada`.
- Si `copies <= 0`, devolver exito con mensaje `Sin copias configuradas (0)`.
- Buscar impresora por nombre exacto.
- Guardar PDF una sola vez con `document.save()`.
- Para cada copia llamar:

```dart
await Printing.directPrintPdf(
  printer: printer,
  onLayout: (PdfPageFormat format) async => pdfBytes,
  name: 'Ticket_${DateTime.now().millisecondsSinceEpoch}',
  usePrinterSettings: true,
);
```

Formato termico:

- Papel 80 mm: ancho imprimible real 72 mm.
- Papel 58 mm: ancho imprimible real 48 mm.
- Alto del rollo: 2000 mm finitos, no infinito.
- Margen izquierdo/derecho: limitar de 0 a 4 mm.
- Margen superior/inferior interno: 2 mm en `ThermalPrinterService.getPageFormat`.

### 7. Configuracion de layout del ticket

Crea `TicketLayoutConfig`.

Mapeo desde `PrinterSettingsModel`:

- 80 mm: `paperWidthDots = 576`, `printableWidthMm = 72`, chars normalizados de 42 a 48.
- 58 mm: `paperWidthDots = 384`, `printableWidthMm = 48`, chars normalizados de 28 a 32.
- `showLogo = settings.showLogo == 1`.
- `logoScale = settings.logoSize / 80.0`.
- `logoSizePx = settings.logoSize`.
- `showCompanyInfo = settings.showBusinessData == 1`.
- `showClientInfo = settings.showClient == 1`.
- `showPaymentInfo = settings.showPaymentMethod == 1`.
- `showFooterMessage = settings.footerMessage.isNotEmpty`.
- Si footer esta vacio, usar `¡GRACIAS POR LA COMPRA!`.
- `warrantyPolicy = settings.warrantyPolicy`.
- `fontSize`: `small`, `normal`, `large`.
- `fontFamily`: `courier`, `arial`, `arialBlack`, `roboto`, `sansSerif`.
- `showDateTime`, `showTicketCode`, `showElectronicInvoiceReference`, `showItbis`, `showCashier`, `showTotalsBreakdown`, `autoCut`.
- Margenes y niveles de fuente/espaciado.

Tamano base de fuente:

- 58 mm small: 9.0.
- 58 mm normal: 10.0.
- 58 mm large: 12.0.
- 80 mm small: 10.0.
- 80 mm normal: 11.0.
- 80 mm large: 13.0.

Escala por `fontSizeLevel`:

```dart
0.8 + (fontSizeLevel - 1) * (0.6 / 9)
```

Espaciado de linea:

```dart
0.4 + (lineSpacingLevel - 1) * (1.2 / 9)
```

Espaciado de secciones:

```dart
0.5 + (sectionSpacingLevel - 1) * (1.5 / 9)
```

### 8. Datos del ticket

Crea `TicketData` con:

- `ticketNumber`
- `dateTime`
- `cashierName`
- `client`
- `items`
- `subtotal`
- `discount`
- `itbis`
- `itbisRate`
- `total`
- `paymentMethod`
- `paidAmount`
- `pendingAmount`
- `lastPaymentAmount`
- `changeAmount`
- datos de credito: interes, plazo, cuotas, vencimiento, nota.
- `electronicInvoiceCode`
- fiscal local: `fiscalReceiptNumber`, `fiscalReceiptName`, `fiscalReceiptCode`, `fiscalReceiptExpirationDate`.
- electronico DGII: `electronicDocumentType`, `electronicDgiiStatus`, `electronicTrackId`, `electronicDgiiCode`, `electronicDgiiMessage`, `electronicEnvironment`.
- `isCopy`
- `extraLegend`
- `statusLabel`
- `isLayaway`
- `type`: `sale`, `quote`, `refund`, `credit`, `copy`.

Crea `TicketItemData` con nombre, codigo, cantidad, precio unitario, total y descuento opcional.

Crea `ClientInfo` con nombre, telefono, RNC, email y direccion.

### 9. Fuente unica de datos del negocio

Crea `CompanyInfoRepository.getCurrentCompanyInfo()` como fuente unica para el encabezado del ticket.

Debe cargar:

- nombre
- direccion
- telefono 1
- telefono 2
- RNC
- email
- slogan
- website
- ruta de logo
- bytes del logo si el archivo existe

Debe leer primero desde la configuracion principal de empresa. Si falla, intentar desde configuracion de negocio. Si todo falla, usar:

```dart
CompanyInfo(name: 'FULLTECH, SRL', slogan: 'FULLPOS')
```

El ticket no debe depender de texto de empresa duplicado manualmente dentro de configuracion de impresora, salvo como respaldo.

### 10. Renderer de ticket por lineas

Crea `TicketRenderer.buildLines(TicketData data)` como fuente unica de verdad para el ticket de texto/columnas.

Estructura del ticket:

1. Encabezado de empresa:
   - nombre centrado.
   - RNC centrado si existe.
   - telefono centrado si existe.
   - direccion envuelta y centrada si existe.
   - linea separadora.
2. Tipo de documento:
   - `FACTURA ELECTRONICA` si hay e-CF o tipo electronico.
   - `FACTURA CREDITO FISCAL` si aplica RNC/tipo fiscal.
   - `FACTURA DE CONSUMO` para venta normal.
   - `COTIZACION`, `DEVOLUCION`, `NOTA DE CREDITO`, `COPIA` para otros tipos.
   - Si `isCopy`, imprimir `COPIA`.
   - Si `extraLegend`, imprimirlo centrado.
   - linea separadora.
3. Metadatos:
   - `FECHA: dd/MM/yyyy` y `HORA: HH:mm`.
   - `DOC: ticketNumber` y `CAJA: cashierName`.
4. Cliente:
   - Si requiere bloque fiscal: `CLIENTE FISCAL`, empresa, RNC y telefono.
   - Si no: `CLI: <cliente o GENERAL>`.
5. Comprobante fiscal:
   - `COMPROBANTE FISCAL`
   - `TIPO:`
   - `NCF:`
   - `VENCE:`
6. Bloque electronico:
   - `DOC. FE:`
   - `E-CF:`
   - `ESTADO DGII:`
   - `TRACK ID:`
   - `AMBIENTE:`
   - `CODIGO DGII:`
   - `MENSAJE DGII:`
7. Detalle de productos:
   - encabezado con columnas: cantidad, producto, total.
   - 80 mm usa cantidad 5 chars, total 11 chars.
   - 58 mm usa cantidad 4 chars, total 8 chars.
   - producto se trunca con ellipsis.
8. Totales:
   - si `showTotalsBreakdown`: `SUBT.:`, `DESC.:`, `BASE:`, `ITBIS X%:`.
   - siempre imprimir `TOTAL:`.
9. Pago:
   - `TIPO PAGO: EFECTIVO/TARJETA/TRANSFERENCIA/CREDITO/APARTADO`.
   - efectivo/normal: `RECIBIDO:` y `CAMBIO:` si hay cambio.
   - credito/apartado: `ABONO:`, `PAGADO:`, `PEND.:`.
10. Footer:
   - linea vacia.
   - footer centrado en mayusculas.
11. Garantia:
   - si existe `warrantyPolicy`, imprimir `POLITICA GARANTIA`, separadores y texto envuelto.
12. Corte:
   - si `autoCut`, agregar tres lineas vacias al final.

Todo texto debe sanitizarse para tickets y ninguna linea debe exceder `maxCharsPerLine`.

### 11. Utilidades de texto

Crea `ReceiptText` con:

- `line(char, width)`.
- `fitText(text, width)`.
- `padRight(text, width)`.
- `padLeft(text, width)`, conservando el final si excede.
- `truncateWithEllipsis(text, width)`.
- `formatLine(left, right, width)`.
- `alignColumns(values, widths, aligns)`.
- `formatProductRow(qty, name, total, width)`.
- `wrapText(text, width)`.
- `money(value)` usando formato con coma de miles y dos decimales.

### 12. Builder PDF termico

Crea `TicketBuilder`:

- `buildPlainText(data)` debe llamar `TicketRenderer.buildLines(data).join('\n')`.
- `buildPdf(data)` debe llamar `TicketRenderer.buildLines(data)` y luego `buildPdfFromLines(...)`.
- `buildPdfFromLines(lines, includeLogo, sourceData)` debe crear `pw.Document`.

Reglas PDF:

- Usar ancho imprimible de `TicketLayoutConfig.printableWidthMm`.
- Alto del rollo: 2000 mm.
- Margenes laterales desde layout, limitados 0 a 4 mm.
- Margen top/bottom desde layout, limitado 0 a 120 puntos.
- Usar fuente Courier para conservar columnas; CourierBold para resaltar.
- Para cierre de caja se permite Helvetica/HelveticaBold para verse mas limpio.
- Calcular fuente maxima que cabe:

```dart
contentWidthPts / (maxCharsPerLine * 0.60)
```

- Usar safety 0.98.
- No exceder 16.0.
- Minimo 5.5.
- En 80 mm preferir cuerpo mas oscuro/bold para que no salga lavado.

Para ventas (`TicketType.sale`) genera una version PDF estructurada mas visual, no solo monoespaciada:

- Header con logo si existe.
- Nombre de empresa fuerte.
- Metadata de documento/fecha/cajero.
- Seccion de cliente.
- Bloque fiscal/electronico si aplica.
- Tabla compacta con columnas `CANT`, `PRODUCTO`, `P/U`, `TOTAL`.
- Totales alineados a la derecha.
- Pago en bloque.
- Footer y politica de garantia.

### 13. Servicio unificado de impresion

Crea `UnifiedTicketPrinter` con estos metodos:

- `printTicket({required TicketData data, int? overrideCopies})`
- `printCustomLines({required List<String> lines, required String ticketNumber, bool includeLogo = true, int? overrideCopies, TicketLayoutConfig? layoutOverride})`
- `printSaleTicket({required SaleModel sale, required List<SaleItemModel> items, String? cashierName, int? overrideCopies, double? pendingAmount, double? lastPaymentAmount, String? statusLabel, bool isLayaway = false})`
- `autoPrintSale(...)`
- `reprintSale(...)`
- `printTestTicket()`
- `openCashDrawerPulse()`
- `printWidthRulerTest()`
- `generatePreviewText({TicketData? data})`
- `getPreviewConfig()`
- `getAvailablePrinters()`
- `checkPrinterStatus()`

Flujo interno de `printTicket`:

1. `PrintActivityTracker.instance.markPrintStarted()`.
2. Cargar empresa con `CompanyInfoRepository.getCurrentCompanyInfo()`.
3. Cargar settings con `PrinterSettingsRepository.getOrCreate()`.
4. Crear layout con `TicketLayoutConfig.fromPrinterSettings(settings)`.
5. Aplicar optimizacion de impresion:
   - Si 80 mm, forzar `maxCharsPerLine = 48`.
   - Limitar `lineSpacingLevel` maximo 4.
   - Limitar `sectionSpacingLevel` maximo 4.
   - Si es venta, forzar visibles: cliente, pago, fecha, codigo, referencia electronica, cajero y desglose de totales.
6. Crear `TicketBuilder(layout, company)`.
7. Generar PDF.
8. Imprimir con `ThermalPrinterService.printDocument(...)`.
9. Devolver `PrintTicketResult`.
10. En `finally`, llamar `markPrintCompleted()`.

`autoPrintSale` debe revisar `settings.autoPrintOnPayment`. Si no esta en 1, devolver exito con `skipped = true` y mensaje `Auto-print desactivado`.

`reprintSale` debe crear `TicketData` con `isCopy = true` y por defecto imprimir 1 copia.

`openCashDrawerPulse` debe validar impresora configurada y mandar un PDF minimo con dos lineas en blanco, sin logo.

`printWidthRulerTest` debe imprimir:

- titulo centrado `PRUEBA DE ANCHO (X CHARS)`.
- linea separadora.
- regla `0123456789...`.
- linea con `L` a la izquierda y `R` a la derecha.
- texto `SI SE CORTA: CAMBIE A 42`.

### 14. Ticket de cierre de caja

Crea `DailyCashCloseTicketPrinter.printDailyCloseTicket(...)`.

Debe construir lineas con:

- nombre de empresa.
- RNC.
- telefono.
- separador.
- `<H2C>CORTE DE TURNO`.
- caja.
- cajero.
- fecha de negocio.
- apertura.
- cierre.
- fondo inicial.
- total vendido.
- salidas caja.
- efectivo esperado.
- efectivo final.
- diferencia.
- tickets.
- ventas por efectivo, tarjeta, transferencia, credito.
- abonos credito.
- abonos apartado.
- entradas manuales.
- salidas manuales.
- nota opcional.
- bloque `<H2C>MOVIMIENTOS`.
- ultimos 8 movimientos con hora, razon y monto.
- si hay mas de 8, imprimir `MOVIMIENTOS ADICIONALES:`.
- tres lineas vacias si `autoCut`.

Debe imprimir mediante `UnifiedTicketPrinter.printCustomLines(...)`.

### 15. Factura PDF carta

Crea `InvoiceLetterPdf.generate(...)` para factura en tamano carta:

- `PdfPageFormat.letter`.
- Margenes de 40 pt.
- Logo de empresa.
- Header con empresa, RNC, telefono, direccion, email.
- Titulo dinamico:
  - `FACTURA ELECTRONICA`
  - `FACTURA FISCAL`
  - `FACTURA`
- Datos de cliente.
- Datos fiscales/electronicos.
- Tabla de productos.
- Subtotal, descuento, ITBIS y total.
- Politica de garantia desde `PrinterSettingsRepository`.
- Footer desde configuracion.
- Redes o datos adicionales si existen.

### 16. Cotizaciones PDF

Crea `QuotePrinter` con:

- `generatePdf()`.
- `printQuote()`.
- `showPreview()`.

Debe usar A4, margenes alrededor de 44 pt, logo, datos de empresa, numero de cotizacion, estado, cliente, tabla de productos, resumen, notas, condiciones y footer con pagina.

### 17. Vistas previas

Crea dos vistas:

- `UnifiedTicketPreviewWidget`: vista visual/profesional.
- `SimplifiedTicketPreviewWidget`: vista monoespaciada que use exactamente `TicketRenderer.buildLines()` como fuente.

La vista simplificada debe ser la referencia para comparar si el ticket va a salir alineado.

### 18. Tracker de impresion

Crea:

```dart
class PrintActivityTracker {
  static final PrintActivityTracker instance = PrintActivityTracker._();
  int _activePrintJobs = 0;
  bool get isPrinting => _activePrintJobs > 0;
  bool get hasPendingPrintJobs => _activePrintJobs > 0;
  void markPrintStarted() => _activePrintJobs++;
  void markPrintCompleted() { if (_activePrintJobs > 0) _activePrintJobs--; }
  Future<bool> waitUntilIdle(Duration timeout) async { ... }
}
```

Debe usarse alrededor de impresiones reales para que el sistema sepa si hay trabajos activos.

### 19. Integraciones obligatorias

En ventas:

- Al cobrar, si el usuario eligio imprimir, llamar `UnifiedTicketPrinter.printSaleTicket`.
- Si solo quiere abrir caja sin ticket, llamar `UnifiedTicketPrinter.openCashDrawerPulse`.
- Para descarga PDF carta, llamar `InvoiceLetterPdf.generate`.
- Para reimpresiones desde historial/facturas/devoluciones, llamar `UnifiedTicketPrinter.printSaleTicket` o `reprintSale`.

En caja:

- Cierre de caja debe imprimir con `DailyCashCloseTicketPrinter` o `UnifiedTicketPrinter.printCustomLines`.

En configuracion:

- La pantalla debe listar impresoras, guardar seleccion, imprimir prueba y permitir formato compacto/detallado.

### 20. Resultado esperado del ticket

El ticket termico debe salir asi, respetando el ancho:

```text
                 EMPRESA
              RNC: 000000000
              TEL: 8090000000
------------------------------------------------
              FACTURA DE CONSUMO
------------------------------------------------
FECHA: 16/07/2026              HORA: 14:30
DOC: FAC-0001                  CAJA: JUAN
CLI: CLIENTE GENERAL
------------------------------------------------
 CANT PRODUCTO                             TOTAL
------------------------------------------------
    2 Producto de Prueba                1,000.00
------------------------------------------------
SUBT.:                                  1,000.00
BASE:                                   1,000.00
ITBIS 18%:                                180.00
------------------------------------------------
TOTAL:                                  1,180.00
------------------------------------------------
TIPO PAGO:                              EFECTIVO
RECIBIDO:                               1,200.00
CAMBIO:                                    20.00
------------------------------------------------

             GRACIAS POR SU PREFERENCIA
```

### 21. Checklist de aceptacion

El modulo esta correcto si:

- Lista impresoras del sistema.
- Guarda la impresora seleccionada.
- Cambiar a 58 mm ajusta chars a 32.
- Cambiar a 80 mm ajusta chars a 48.
- Prueba de impresion sale por la impresora seleccionada.
- Ticket de venta sale con logo si existe.
- El ticket no se corta en 80 mm.
- La regla de ancho muestra 48 caracteres en 80 mm.
- Reimpresion marca copia.
- Auto-print respeta `autoPrintOnPayment`.
- Cierre de caja imprime resumen y movimientos.
- Footer y garantia salen al final.
- PDF carta tiene datos fiscales y totales.
- No hay logica de impresion duplicada en pantallas.
- El tracker marca impresion activa y vuelve a idle al terminar.

---

## NOTAS DE AUDITORIA DEL CODIGO FULLPOS ACTUAL

- El flujo principal actual no imprime comandos ESC/POS directamente; genera PDF y usa `printing`.
- Los paquetes ESC/POS existen en `pubspec.yaml`, pero el modulo activo usa `UnifiedTicketPrinter`, `TicketBuilder`, `ThermalPrinterService` y `Printing.directPrintPdf()`.
- `TicketRenderer.buildLines()` es la fuente principal para lineas monoespaciadas.
- `TicketBuilder.buildPdf()` usa el renderer, pero para ventas tiene un render PDF estructurado especial.
- La configuracion real se guarda en SQLite tabla `printer_settings`.
- La pantalla actual de configuracion es compacta y no expone todos los campos internos; muchos campos existen para persistencia/compatibilidad.
- Hay archivos legacy en el repo (`ticket_printer.dart`, `ticket_template.dart`, `receipt_printer_service.dart`, `sale_invoice_pdf_service.dart`, `ticket_preview_widget.dart`). No usarlos como arquitectura nueva salvo que se requiera migracion.
