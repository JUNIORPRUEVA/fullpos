import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import 'printer_settings_model.dart';

class PrinterSettingsRepository {
  PrinterSettingsRepository._();

  static const Map<String, String> _expectedColumns = {
    'selected_printer_name': 'TEXT',
    'paper_width_mm': 'INTEGER NOT NULL DEFAULT 80',
    'chars_per_line': 'INTEGER NOT NULL DEFAULT 48',
    'auto_print_on_payment': 'INTEGER NOT NULL DEFAULT 0',
    'auto_open_drawer_on_charge_without_ticket': 'INTEGER NOT NULL DEFAULT 0',
    'copies': 'INTEGER NOT NULL DEFAULT 1',
    'show_itbis': 'INTEGER NOT NULL DEFAULT 1',
    'show_electronic_invoice_reference': 'INTEGER NOT NULL DEFAULT 1',
    'show_cashier': 'INTEGER NOT NULL DEFAULT 1',
    'show_client': 'INTEGER NOT NULL DEFAULT 1',
    'show_payment_method': 'INTEGER NOT NULL DEFAULT 1',
    'show_discounts': 'INTEGER NOT NULL DEFAULT 1',
    'show_code': 'INTEGER NOT NULL DEFAULT 1',
    'show_datetime': 'INTEGER NOT NULL DEFAULT 1',
    'header_business_name': "TEXT DEFAULT 'FULLPOS'",
    'header_rnc': 'TEXT',
    'header_address': 'TEXT',
    'header_phone': 'TEXT',
    'header_extra': 'TEXT',
    'footer_message': "TEXT DEFAULT 'Gracias por su compra'",
    'warranty_policy': "TEXT NOT NULL DEFAULT ''",
    'left_margin': 'INTEGER NOT NULL DEFAULT 0',
    'right_margin': 'INTEGER NOT NULL DEFAULT 0',
    'auto_cut': 'INTEGER NOT NULL DEFAULT 1',
    'itbis_rate': 'REAL NOT NULL DEFAULT 0.18',
    'font_family': "TEXT NOT NULL DEFAULT 'arial'",
    'font_size': "TEXT NOT NULL DEFAULT 'normal'",
    'show_logo': 'INTEGER NOT NULL DEFAULT 1',
    'logo_size': 'INTEGER NOT NULL DEFAULT 70',
    'show_business_data': 'INTEGER NOT NULL DEFAULT 1',
    'show_subtotal_itbis_total': 'INTEGER NOT NULL DEFAULT 1',
    'auto_height': 'INTEGER NOT NULL DEFAULT 1',
    'top_margin': 'INTEGER NOT NULL DEFAULT 8',
    'bottom_margin': 'INTEGER NOT NULL DEFAULT 8',
    'font_size_level': 'INTEGER NOT NULL DEFAULT 6',
    'line_spacing_level': 'INTEGER NOT NULL DEFAULT 6',
    'section_spacing_level': 'INTEGER NOT NULL DEFAULT 6',
    'section_separator_style': "TEXT NOT NULL DEFAULT 'single'",
    'header_alignment': "TEXT NOT NULL DEFAULT 'center'",
    'details_alignment': "TEXT NOT NULL DEFAULT 'left'",
    'totals_alignment': "TEXT NOT NULL DEFAULT 'right'",
  };

  static Future<void> _ensureSchema() async {
    final db = await AppDb.database;
    final tableInfo = await db.rawQuery(
      'PRAGMA table_info(${DbTables.printerSettings})',
    );
    final existingColumns = tableInfo
        .map((row) => row['name'] as String)
        .toSet();

    for (final entry in _expectedColumns.entries) {
      if (existingColumns.contains(entry.key)) continue;
      await db.execute(
        'ALTER TABLE ${DbTables.printerSettings} ADD COLUMN ${entry.key} ${entry.value}',
      );
    }
  }

  /// Obtiene la configuración actual de impresora
  static Future<PrinterSettingsModel?> getSettings() async {
    await _ensureSchema();
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
    await _ensureSchema();
    final existing = await getSettings();
    if (existing != null) return existing;

    // Crear configuración por defecto con plantilla profesional
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultSettings = {
      'selected_printer_name': null,
      'paper_width_mm': 80,
      // 80mm Epson/ESC-POS de 576 dots: usar 48 columnas reales.
      'chars_per_line': 48,
      'auto_print_on_payment': 0,
      'auto_open_drawer_on_charge_without_ticket': 0,
      'copies': 1,
      'show_itbis': 1,
      'show_electronic_invoice_reference': 1,
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
      // Evitar 'arialBlack' por defecto: demasiado pesado en tickets.
      'font_family': 'arial',
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
    await _ensureSchema();
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
    await _ensureSchema();
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Obtener la impresora actual para mantenerla
    final currentSettings = await getSettings();
    final currentPrinter = currentSettings?.selectedPrinterName;
    final currentId = currentSettings?.id ?? 1;

    final defaults = {
      'selected_printer_name': currentPrinter, // Mantener impresora actual
      'paper_width_mm': 80,
      'chars_per_line': 48,
      'auto_print_on_payment': 0,
      'auto_open_drawer_on_charge_without_ticket': 0,
      'copies': 1,
      'show_itbis': 1,
      'show_electronic_invoice_reference': 1,
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
      'font_family': 'arial',
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
    await _ensureSchema();
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Obtener la impresora actual para mantenerla
    final currentSettings = await getSettings();
    final currentPrinter = currentSettings?.selectedPrinterName;
    final currentId = currentSettings?.id ?? 1;

    final professional = {
      'selected_printer_name': currentPrinter, // Mantener impresora actual
      'paper_width_mm': 80,
      'chars_per_line': 48,
      'auto_print_on_payment': 1, // Activar auto-impresión
      'auto_open_drawer_on_charge_without_ticket': 0,
      'copies': 1,
      'show_itbis': 1,
      'show_electronic_invoice_reference': 1,
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
      'font_family': 'arial',
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
