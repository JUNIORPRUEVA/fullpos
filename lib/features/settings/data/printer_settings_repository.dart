import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'printer_settings_model.dart';

class PrinterSettingsRepository {
  PrinterSettingsRepository._();

  /// Obtiene la configuración actual de impresora
  static Future<PrinterSettingsModel?> getSettings() async {
    final db = await AppDb.database;

    final result = await db.query(
      DbTables.printerSettings,
      orderBy: 'id ASC',
      limit: 1,
    );

    if (result.isEmpty) return null;
    return PrinterSettingsModel.fromMap(result.first);
  }

  /// Obtiene la configuración o crea una por defecto (plantilla profesional)
  static Future<PrinterSettingsModel> getOrCreate() async {
    final existing = await getSettings();
    if (existing != null) return existing;

    // Crear configuración por defecto con plantilla profesional
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultSettings = {
      'selected_printer_name': null,
      'paper_width_mm': 80,
      // 80mm: por defecto usar 42 (Seguro) para evitar cortes/desalineación.
      'chars_per_line': 42,
      'auto_print_on_payment': 0,
      'auto_open_drawer_on_charge_without_ticket': 0,
      'copies': 1,
      'show_itbis': 1,
      'show_ncf': 1,
      'show_cashier': 1,
      'show_client': 1,
      'show_payment_method': 1,
      'show_discounts': 1,
      'show_code': 1,
      'show_datetime': 1,
      'header_business_name': 'FULLPOS',
      'header_rnc': '',
      'header_address': '',
      'header_phone': '',
      'header_extra': '',
      'footer_message': '¡Gracias por su preferencia!',
      'warranty_policy': '',
      'left_margin': 0,
      'right_margin': 0,
      'auto_cut': 1,
      'itbis_rate': 0.18,
      'created_at_ms': now,
      'updated_at_ms': now,
      // Nuevos campos - plantilla profesional
      'font_family': 'arialBlack',
      'font_size': 'normal',
      'show_logo': 1,
      // Logo más visible por defecto.
      'logo_size': 70,
      'show_business_data': 1,
      'show_subtotal_itbis_total': 1,
      'auto_height': 1,
      'top_margin': 8,
      'bottom_margin': 8,
      'font_size_level': 6,
      'line_spacing_level': 6,
      'section_spacing_level': 6,
      'section_separator_style': 'single',
    };

    final db = await AppDb.database;
    final insertedId = await db.insert(
      DbTables.printerSettings,
      defaultSettings,
    );

    return PrinterSettingsModel.fromMap({...defaultSettings, 'id': insertedId});
  }

  /// Actualiza la configuración de impresora
  static Future<void> updateSettings(PrinterSettingsModel settings) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;
    final settingsToUpdate = settings.copyWith(updatedAtMs: now);
    final map = settingsToUpdate.toMap();
    map.remove('id');

    final targetId = settings.id ?? (await getSettings())?.id;
    if (targetId == null) {
      // DB sin fila de configuración (instalación/corrupción). Re-crear.
      await db.insert(DbTables.printerSettings, map);
      return;
    }

    final rows = await db.update(
      DbTables.printerSettings,
      map,
      where: 'id = ?',
      whereArgs: [targetId],
    );

    if (rows == 0) {
      final fallbackId = (await getSettings())?.id;
      if (fallbackId == null) {
        await db.insert(DbTables.printerSettings, map);
        return;
      }
      await db.update(
        DbTables.printerSettings,
        map,
        where: 'id = ?',
        whereArgs: [fallbackId],
      );
    }
  }

  /// Restablece configuración a valores por defecto (mantiene la impresora seleccionada)
  static Future<PrinterSettingsModel> resetToDefaults() async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Obtener la impresora actual para mantenerla
    final currentSettings = await getSettings();
    final currentPrinter = currentSettings?.selectedPrinterName;
    final currentId = currentSettings?.id ?? 1;

    final defaults = {
      'selected_printer_name': currentPrinter, // Mantener impresora actual
      'paper_width_mm': 80,
      'chars_per_line': 42,
      'auto_print_on_payment': 0,
      'auto_open_drawer_on_charge_without_ticket': 0,
      'copies': 1,
      'show_itbis': 1,
      'show_ncf': 1,
      'show_cashier': 1,
      'show_client': 1,
      'show_payment_method': 1,
      'show_discounts': 1,
      'show_code': 1,
      'show_datetime': 1,
      'header_business_name': 'FULLPOS',
      'header_rnc': '',
      'header_address': '',
      'header_phone': '',
      'header_extra': '',
      'footer_message': 'Gracias por su compra',
      'warranty_policy': currentSettings?.warrantyPolicy ?? '',
      'left_margin': 0,
      'right_margin': 0,
      'auto_cut': 1,
      'itbis_rate': 0.18,
      'updated_at_ms': now,
      // Nuevos campos
      'font_family': 'arialBlack',
      'font_size': 'normal',
      'show_logo': 1,
      'logo_size': 70,
      'show_business_data': 1,
      'show_subtotal_itbis_total': 1,
      'auto_height': 1,
      'top_margin': 8,
      'bottom_margin': 8,
      'font_size_level': 6,
      'line_spacing_level': 6,
      'section_spacing_level': 6,
      'section_separator_style':
          currentSettings?.sectionSeparatorStyle ?? 'single',
    };

    await db.update(
      DbTables.printerSettings,
      defaults,
      where: 'id = ?',
      whereArgs: [currentId],
    );

    return getOrCreate();
  }

  /// Restaura la plantilla profesional ejecutiva (mantiene la impresora seleccionada)
  static Future<PrinterSettingsModel> resetToProfessional() async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Obtener la impresora actual para mantenerla
    final currentSettings = await getSettings();
    final currentPrinter = currentSettings?.selectedPrinterName;
    final currentId = currentSettings?.id ?? 1;

    final professional = {
      'selected_printer_name': currentPrinter, // Mantener impresora actual
      'paper_width_mm': 80,
      'chars_per_line': 42,
      'auto_print_on_payment': 1, // Activar auto-impresión
      'auto_open_drawer_on_charge_without_ticket': 0,
      'copies': 1,
      'show_itbis': 1,
      'show_ncf': 1,
      'show_cashier': 1,
      'show_client': 1,
      'show_payment_method': 1,
      'show_discounts': 1,
      'show_code': 1,
      'show_datetime': 1,
      'header_business_name': currentSettings?.headerBusinessName ?? 'FULLPOS',
      'header_rnc': currentSettings?.headerRnc ?? '',
      'header_address': currentSettings?.headerAddress ?? '',
      'header_phone': currentSettings?.headerPhone ?? '',
      'header_extra': currentSettings?.headerExtra ?? '',
      'footer_message': '¡Gracias por su preferencia!',
      'warranty_policy': currentSettings?.warrantyPolicy ?? '',
      'left_margin': 0,
      'right_margin': 0,
      'auto_cut': 1,
      'itbis_rate': 0.18,
      'updated_at_ms': now,
      // Estilo profesional ejecutivo
      // Plantilla ejecutiva pero con alineación perfecta
      'font_family': 'arialBlack',
      'font_size': 'normal',
      'show_logo': 1,
      'logo_size': 70,
      'show_business_data': 1,
      'show_subtotal_itbis_total': 1,
      'auto_height': 1,
      'top_margin': 10,
      'bottom_margin': 10,
      'font_size_level': 6,
      'line_spacing_level': 6,
      'section_spacing_level': 6,
      'section_separator_style':
          currentSettings?.sectionSeparatorStyle ?? 'single',
    };

    await db.update(
      DbTables.printerSettings,
      professional,
      where: 'id = ?',
      whereArgs: [currentId],
    );

    return getOrCreate();
  }
}
