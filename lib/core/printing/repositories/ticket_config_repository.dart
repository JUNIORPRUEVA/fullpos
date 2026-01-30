import '../../db/app_db.dart';
import '../models/ticket_layout_config.dart';
import '../../../features/settings/data/printer_settings_model.dart'
    show TicketFontSize, TicketFontFamily;

/// Repositorio para la configuración del ticket
/// Guarda y carga la configuración de diseño del ticket desde SQLite
class TicketConfigRepository {
  static const String _tableName = 'ticket_settings';

  /// Columnas esperadas en la tabla
  static const Map<String, String> _expectedColumns = {
    'id': 'INTEGER PRIMARY KEY DEFAULT 1',
    'paper_width_dots': 'INTEGER DEFAULT 576',
    'max_chars_per_line': 'INTEGER DEFAULT 42',
    'show_logo': 'INTEGER DEFAULT 1',
    'logo_scale': 'REAL DEFAULT 0.7',
    'logo_size_px': 'INTEGER DEFAULT 60',
    'bold_header': 'INTEGER DEFAULT 1',
    'show_company_info': 'INTEGER DEFAULT 1',
    'show_client_info': 'INTEGER DEFAULT 1',
    'show_payment_info': 'INTEGER DEFAULT 1',
    'show_footer_message': 'INTEGER DEFAULT 1',
    'footer_message': "TEXT DEFAULT 'Gracias por su compra'",
    'powered_by': "TEXT DEFAULT 'Powered by FULLTECH, SRL'",
    'font_size': "TEXT DEFAULT 'normal'",
    'font_family': "TEXT DEFAULT 'arialBlack'",
    'show_date_time': 'INTEGER DEFAULT 1',
    'show_ticket_code': 'INTEGER DEFAULT 1',
    'show_ncf': 'INTEGER DEFAULT 1',
    'show_itbis': 'INTEGER DEFAULT 1',
    'show_cashier': 'INTEGER DEFAULT 1',
    'show_totals_breakdown': 'INTEGER DEFAULT 1',
    'auto_cut': 'INTEGER DEFAULT 1',
    'left_margin_mm': 'INTEGER DEFAULT 0',
    'right_margin_mm': 'INTEGER DEFAULT 0',
    'top_margin_px': 'INTEGER DEFAULT 8',
    'bottom_margin_px': 'INTEGER DEFAULT 8',
    'font_size_level': 'INTEGER NOT NULL DEFAULT 5',
    'line_spacing_level': 'INTEGER NOT NULL DEFAULT 5',
    'section_spacing_level': 'INTEGER NOT NULL DEFAULT 5',
    'created_at': 'TEXT DEFAULT CURRENT_TIMESTAMP',
    'updated_at': 'TEXT DEFAULT CURRENT_TIMESTAMP',
  };

  /// Inicializar tabla de configuración
  static Future<void> initTable() async {
    final db = await AppDb.database;

    // Verificar si la tabla existe
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='$_tableName'",
    );

    if (tables.isEmpty) {
      // Crear tabla nueva
      final columns = _expectedColumns.entries
          .map((e) => '${e.key} ${e.value}')
          .join(',\n          ');

      await db.execute('CREATE TABLE $_tableName ($columns)');

      // Insertar configuración por defecto
      await db.insert(_tableName, {
        'id': 1,
        'footer_message': 'Gracias por su compra',
        'powered_by': 'Powered by FULLTECH, SRL',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      // Tabla existe, verificar y agregar columnas faltantes
      await _migrateTableColumns(db);
    }
  }

  /// Migrar tabla agregando columnas faltantes
  static Future<void> _migrateTableColumns(dynamic db) async {
    try {
      final tableInfo = await db.rawQuery('PRAGMA table_info($_tableName)');
      final existingColumns = tableInfo
          .map((row) => row['name'] as String)
          .toSet();

      for (final entry in _expectedColumns.entries) {
        if (!existingColumns.contains(entry.key) && entry.key != 'id') {
          try {
            await db.execute(
              'ALTER TABLE $_tableName ADD COLUMN ${entry.key} ${entry.value}',
            );
            // ignore: avoid_print
            print('✅ Columna ${entry.key} agregada a $_tableName');
          } catch (e) {
            // ignore: avoid_print
            print('⚠️ No se pudo agregar columna ${entry.key}: $e');
          }
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error migrando tabla $_tableName: $e');
    }
  }

  /// Cargar configuración del ticket
  Future<TicketLayoutConfig> load() async {
    try {
      await initTable();
      final db = await AppDb.database;

      final results = await db.query(_tableName, where: 'id = 1');

      if (results.isEmpty) {
        return TicketLayoutConfig.professional80mm();
      }

      return _fromMap(results.first);
    } catch (e) {
      // ignore: avoid_print
      print('Error cargando configuración del ticket: $e');
      return TicketLayoutConfig.professional80mm();
    }
  }

  /// Guardar configuración del ticket
  Future<void> save(TicketLayoutConfig config) async {
    try {
      await initTable();
      final db = await AppDb.database;

      final map = _toMap(config);
      map['updated_at'] = DateTime.now().toIso8601String();

      // Verificar si existe
      final existing = await db.query(_tableName, where: 'id = 1');

      if (existing.isEmpty) {
        map['id'] = 1;
        map['created_at'] = DateTime.now().toIso8601String();
        await db.insert(_tableName, map);
      } else {
        await db.update(_tableName, map, where: 'id = ?', whereArgs: [1]);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Error guardando configuración del ticket: $e');
      rethrow;
    }
  }

  /// Convertir Map a TicketLayoutConfig
  TicketLayoutConfig _fromMap(Map<String, dynamic> map) {
    return TicketLayoutConfig(
      paperWidthDots: map['paper_width_dots'] as int? ?? 576,
      maxCharsPerLine: map['max_chars_per_line'] as int? ?? 42,
      showLogo: (map['show_logo'] as int? ?? 1) == 1,
      logoScale: (map['logo_scale'] as num?)?.toDouble() ?? 0.7,
      logoSizePx: map['logo_size_px'] as int? ?? 60,
      boldHeader: (map['bold_header'] as int? ?? 1) == 1,
      showCompanyInfo: (map['show_company_info'] as int? ?? 1) == 1,
      showClientInfo: (map['show_client_info'] as int? ?? 1) == 1,
      showPaymentInfo: (map['show_payment_info'] as int? ?? 1) == 1,
      showFooterMessage: (map['show_footer_message'] as int? ?? 1) == 1,
      footerMessage:
          map['footer_message'] as String? ?? 'Gracias por su compra',
      fontSize: _parseFontSize(map['font_size'] as String? ?? 'normal'),
      fontFamily: _parseFontFamily(
        map['font_family'] as String? ?? 'arialBlack',
      ),
      showDateTime: (map['show_date_time'] as int? ?? 1) == 1,
      showTicketCode: (map['show_ticket_code'] as int? ?? 1) == 1,
      showNcf: (map['show_ncf'] as int? ?? 1) == 1,
      showItbis: (map['show_itbis'] as int? ?? 1) == 1,
      showCashier: (map['show_cashier'] as int? ?? 1) == 1,
      showTotalsBreakdown: (map['show_totals_breakdown'] as int? ?? 1) == 1,
      autoCut: (map['auto_cut'] as int? ?? 1) == 1,
      leftMarginMm: map['left_margin_mm'] as int? ?? 0,
      rightMarginMm: map['right_margin_mm'] as int? ?? 0,
      topMarginPx: map['top_margin_px'] as int? ?? 8,
      bottomMarginPx: map['bottom_margin_px'] as int? ?? 8,
      fontSizeLevel: map['font_size_level'] as int? ?? 5,
      lineSpacingLevel: map['line_spacing_level'] as int? ?? 5,
      sectionSpacingLevel: map['section_spacing_level'] as int? ?? 5,
    );
  }

  /// Convertir TicketLayoutConfig a Map
  Map<String, dynamic> _toMap(TicketLayoutConfig config) {
    return {
      'paper_width_dots': config.paperWidthDots,
      'max_chars_per_line': config.maxCharsPerLine,
      'show_logo': config.showLogo ? 1 : 0,
      'logo_scale': config.logoScale,
      'logo_size_px': config.logoSizePx,
      'bold_header': config.boldHeader ? 1 : 0,
      'show_company_info': config.showCompanyInfo ? 1 : 0,
      'show_client_info': config.showClientInfo ? 1 : 0,
      'show_payment_info': config.showPaymentInfo ? 1 : 0,
      'show_footer_message': config.showFooterMessage ? 1 : 0,
      'footer_message': config.footerMessage,
      'font_size': _fontSizeToString(config.fontSize),
      'font_family': _fontFamilyToString(config.fontFamily),
      'show_date_time': config.showDateTime ? 1 : 0,
      'show_ticket_code': config.showTicketCode ? 1 : 0,
      'show_ncf': config.showNcf ? 1 : 0,
      'show_itbis': config.showItbis ? 1 : 0,
      'show_cashier': config.showCashier ? 1 : 0,
      'show_totals_breakdown': config.showTotalsBreakdown ? 1 : 0,
      'auto_cut': config.autoCut ? 1 : 0,
      'left_margin_mm': config.leftMarginMm,
      'right_margin_mm': config.rightMarginMm,
      'top_margin_px': config.topMarginPx,
      'bottom_margin_px': config.bottomMarginPx,
      'font_size_level': config.fontSizeLevel,
      'line_spacing_level': config.lineSpacingLevel,
      'section_spacing_level': config.sectionSpacingLevel,
    };
  }

  TicketFontSize _parseFontSize(String value) {
    switch (value) {
      case 'small':
        return TicketFontSize.small;
      case 'large':
        return TicketFontSize.large;
      default:
        return TicketFontSize.normal;
    }
  }

  TicketFontFamily _parseFontFamily(String value) {
    switch (value) {
      case 'arial':
        return TicketFontFamily.arial;
      case 'arialBlack':
        return TicketFontFamily.arialBlack;
      case 'roboto':
        return TicketFontFamily.roboto;
      case 'sansSerif':
        return TicketFontFamily.sansSerif;
      default:
        return TicketFontFamily.courier;
    }
  }

  String _fontSizeToString(TicketFontSize size) {
    switch (size) {
      case TicketFontSize.small:
        return 'small';
      case TicketFontSize.large:
        return 'large';
      default:
        return 'normal';
    }
  }

  String _fontFamilyToString(TicketFontFamily family) {
    switch (family) {
      case TicketFontFamily.arial:
        return 'arial';
      case TicketFontFamily.arialBlack:
        return 'arialBlack';
      case TicketFontFamily.roboto:
        return 'roboto';
      case TicketFontFamily.sansSerif:
        return 'sansSerif';
      default:
        return 'courier';
    }
  }

  /// Obtener el valor de powered_by guardado
  Future<String> getPoweredBy() async {
    try {
      await initTable();
      final db = await AppDb.database;
      final results = await db.query(
        _tableName,
        columns: ['powered_by'],
        where: 'id = 1',
      );

      if (results.isNotEmpty && results.first['powered_by'] != null) {
        return results.first['powered_by'] as String;
      }
      return 'Powered by FULLTECH, SRL';
    } catch (e) {
      return 'Powered by FULLTECH, SRL';
    }
  }

  /// Actualizar solo el powered_by
  Future<void> updatePoweredBy(String value) async {
    try {
      await initTable();
      final db = await AppDb.database;

      await db.update(
        _tableName,
        {'powered_by': value, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [1],
      );
    } catch (e) {
      // ignore: avoid_print
      print('Error actualizando powered_by: $e');
    }
  }

  /// Resetear a valores por defecto
  Future<void> resetToDefault() async {
    await save(TicketLayoutConfig.professional80mm());
  }
}
