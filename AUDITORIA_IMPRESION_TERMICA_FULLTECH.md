# Auditoria de impresion termica FullTech

Fecha: 2026-07-17
Motor visible en configuracion: Thermal PDF v2.1.0

## Mapa real de flujo

| Accion | Archivo inicial | Metodo inicial | Servicio real | Builder/composer real | Salida final |
| --- | --- | --- | --- | --- | --- |
| Cobro con impresion | `lib/features/sales/ui/sales_page.dart` | `_runSaleOutputs()` | `UnifiedTicketPrinter.printSaleTicket()` | `TicketBuilder.buildPdf()` / `_buildStructuredSalesPdf()` | PDF via `Printing.directPrintPdf()` |
| Reimprimir venta reciente | `lib/features/sales/ui/sales_page.dart` | `_printRecentSale()` | `UnifiedTicketPrinter.printSaleTicket()` | `TicketBuilder.buildPdf()` / `_buildStructuredSalesPdf()` | PDF via `Printing.directPrintPdf()` |
| Reimprimir factura | `lib/features/sales/ui/factura_page.dart` | `_printTicket()` | `UnifiedTicketPrinter.printSaleTicket()` | `TicketBuilder.buildPdf()` / `_buildStructuredSalesPdf()` | PDF via `Printing.directPrintPdf()` |
| Reimprimir desde devoluciones | `lib/features/sales/ui/returns_list_page.dart` | `_printTicket()` | `UnifiedTicketPrinter.printSaleTicket()` | `TicketBuilder.buildPdf()` / `_buildStructuredSalesPdf()` | PDF via `Printing.directPrintPdf()` |
| Cierre de turno | `lib/features/cash/ui/cash_close_dialog.dart` | `_printClosingTicket()` | `UnifiedTicketPrinter.printCustomLines()` | `SessionCloseTicketComposer.buildLines()` + `TicketBuilder.buildPdfFromLines()` | PDF via `Printing.directPrintPdf()` |
| Reimprimir cierre/historial | `lib/features/cash/ui/cash_history_page.dart` | print action | `UnifiedTicketPrinter.printCustomLines()` | `SessionCloseTicketComposer.buildLines()` + `TicketBuilder.buildPdfFromLines()` | PDF via `Printing.directPrintPdf()` |
| Prueba de impresion | `lib/features/settings/ui/printer_settings_page.dart` | `_printTest()` | `UnifiedTicketPrinter.printTestTicket()` | `TicketBuilder.buildPdf()` | PDF via `Printing.directPrintPdf()` |
| Prueba de estilos | `lib/features/settings/ui/printer_settings_page.dart` | `_printStyleTest()` | `UnifiedTicketPrinter.printStyleDiagnosticsTicket()` | `TicketBuilder.buildStyleDiagnosticsPdf()` | PDF via `Printing.directPrintPdf()` |
| Apertura de cajon | `sales_page.dart` / `cash_drawer_settings_page.dart` | drawer action | `UnifiedTicketPrinter.openCashDrawerPulse()` | `TicketBuilder.buildPdfFromLines()` minimo | PDF via `Printing.directPrintPdf()` |
| Cotizacion | `quote_dialog.dart` / `quotes_page.dart` | quote print/preview | `QuotePrinter` | `QuotePrinter.generatePdf()` | PDF via `Printing.directPrintPdf()` o preview |

## Causa de que los cambios anteriores no aparecieran

1. El cierre de turno visible no usaba `DailyCashCloseTicketPrinter`; usa `SessionCloseTicketComposer` desde `cash_close_dialog.dart` y `cash_history_page.dart`.
2. El directorio `dist/FULLPOS_Windows_Release` estaba viejo. Probar ese ejecutable no incluia cambios recientes.
3. El `.exe` de Flutter es solo el wrapper; la logica Dart compilada vive en `data/app.so`. La version nueva queda confirmada por la fecha de `data/app.so`.

## Implementacion oficial

- Entrada unica para tickets termicos: `UnifiedTicketPrinter`.
- Salida fisica final: `ThermalPrinterService.printDocument()`.
- Adaptador final: `Printing.directPrintPdf()`.
- Factura/venta: `TicketBuilder._buildStructuredSalesPdf()`.
- Cierre de turno: `SessionCloseTicketComposer.buildLines()` + `TicketBuilder.buildPdfFromLines()`.
- Configuracion global: `PrinterSettingsRepository`, tabla `printer_settings`, una sola fila activa.

## Archivos legacy detectados

Estos archivos existen, pero no son la ruta oficial de botones actuales:

- `lib/core/printing/ticket_printer.dart`
- `lib/core/printing/ticket_template.dart`
- `lib/core/printing/receipt_printer_service.dart`
- `lib/core/printing/sale_invoice_pdf_service.dart`
- `lib/core/printing/ticket_preview_widget.dart`
- `lib/features/cash/data/daily_cash_close_ticket_printer.dart` para el cierre visible actual.

## Cambios aplicados

- Trazas `[PRINT TRACE]` en el servicio unificado y adaptador final.
- Hash/tamano de PDF enviado a impresora en `ThermalPrinterService`.
- Carga de fuentes TTF `RobotoMono-Regular` y `RobotoMono-Medium` para negrita real y acentos.
- Factura termica redisenada con jerarquia visual, total destacado y productos 58 mm en dos lineas.
- Cierre de turno real reforzado en `SessionCloseTicketComposer`.
- Boton `Probar estilos` en configuracion.
- Version visible del motor: `Thermal PDF v2.1.0`.
- Configuracion de impresora reforzada como global de una sola fila.

## Artefactos generados

- `artifacts/printing/ticket_factura_58mm.pdf`
- `artifacts/printing/ticket_factura_80mm.pdf`
- `artifacts/printing/ticket_cierre_58mm.pdf`
- `artifacts/printing/ticket_cierre_80mm.pdf`
- `artifacts/printing/ticket_estilos_58mm.pdf`
- `artifacts/printing/ticket_estilos_80mm.pdf`

## Build nuevo

- Release: `build/windows/x64/runner/Release/fullpos.exe`
- Dist nuevo: `dist/FULLPOS_Windows_Release_20260717_110312/fullpos.exe`
- Logica Dart compilada: `data/app.so`, fecha `2026-07-17 11:02:58 AM`.
- Version Windows: `1.0.30+32`.

## Verificacion

- `flutter analyze`: sin issues.
- `flutter test test/core/printing/invoice_letter_pdf_test.dart`: passed.
- `flutter build windows --release`: exitoso.

## Pendiente fisico

La confirmacion fisica debe hacerse desde Configuracion > Impresora y ticket > `Probar estilos`, usando el build nuevo. El ticket debe mostrar diferencias visibles entre normal, negrita, grande y grande/negrita.
