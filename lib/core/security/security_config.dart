import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/tables.dart';
import '../session/session_manager.dart';
import 'app_actions.dart';

class SecurityConfig {
  final Map<String, bool> overrideByAction;
  final bool offlinePinEnabled;
  final bool offlineBarcodeEnabled;
  final bool remoteEnabled;
  final bool virtualTokenEnabled;
  final bool scannerEnabled;
  final String scannerSuffix;
  final String? scannerPrefix;
  final int scannerTimeoutMs;

  SecurityConfig({
    required this.overrideByAction,
    this.offlinePinEnabled = false,
    this.offlineBarcodeEnabled = false,
    this.remoteEnabled = false,
    this.virtualTokenEnabled = false,
    this.scannerEnabled = true,
    this.scannerSuffix = '\n',
    this.scannerPrefix,
    this.scannerTimeoutMs = 80,
  });

  factory SecurityConfig.defaults() {
    final overrideDefaults = <String, bool>{};
    for (final row in AppActions.defaultOverrideTable) {
      overrideDefaults[row.actionCode] = row.requiresOverride;
    }
    return SecurityConfig(
      overrideByAction: overrideDefaults,
      offlinePinEnabled: false,
      offlineBarcodeEnabled: false,
      remoteEnabled: false,
      virtualTokenEnabled: false,
      scannerEnabled: true,
      scannerSuffix: '\n',
      scannerPrefix: '',
      scannerTimeoutMs: 80,
    );
  }

  SecurityConfig copyWith({
    Map<String, bool>? overrideByAction,
    bool? offlinePinEnabled,
    bool? offlineBarcodeEnabled,
    bool? remoteEnabled,
    bool? virtualTokenEnabled,
    bool? scannerEnabled,
    String? scannerSuffix,
    String? scannerPrefix,
    int? scannerTimeoutMs,
  }) {
    return SecurityConfig(
      overrideByAction: overrideByAction ?? this.overrideByAction,
      offlinePinEnabled: offlinePinEnabled ?? this.offlinePinEnabled,
      offlineBarcodeEnabled:
          offlineBarcodeEnabled ?? this.offlineBarcodeEnabled,
      remoteEnabled: remoteEnabled ?? this.remoteEnabled,
      virtualTokenEnabled: virtualTokenEnabled ?? this.virtualTokenEnabled,
      scannerEnabled: scannerEnabled ?? this.scannerEnabled,
      scannerSuffix: scannerSuffix ?? this.scannerSuffix,
      scannerPrefix: scannerPrefix ?? this.scannerPrefix,
      scannerTimeoutMs: scannerTimeoutMs ?? this.scannerTimeoutMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'override_by_action': overrideByAction,
    'offline_pin_enabled': offlinePinEnabled,
    'offline_barcode_enabled': offlineBarcodeEnabled,
    'remote_enabled': remoteEnabled,
    'virtual_token_enabled': virtualTokenEnabled,
    'scanner_enabled': scannerEnabled,
    'scanner_suffix': scannerSuffix,
    'scanner_prefix': scannerPrefix,
    'scanner_timeout_ms': scannerTimeoutMs,
  };

  factory SecurityConfig.fromJson(Map<String, dynamic> json) {
    final overrides = <String, bool>{};
    final rawOverrides = json['override_by_action'];
    if (rawOverrides is Map) {
      rawOverrides.forEach((key, value) {
        overrides[key.toString()] = (value as bool?) ?? false;
      });
    }
    return SecurityConfig(
      overrideByAction: overrides,
      offlinePinEnabled: json['offline_pin_enabled'] as bool? ?? false,
      offlineBarcodeEnabled: json['offline_barcode_enabled'] as bool? ?? false,
      remoteEnabled: json['remote_enabled'] as bool? ?? false,
      virtualTokenEnabled: json['virtual_token_enabled'] as bool? ?? false,
      scannerEnabled: json['scanner_enabled'] as bool? ?? true,
      scannerSuffix: json['scanner_suffix'] as String? ?? '\n',
      scannerPrefix: json['scanner_prefix'] as String?,
      scannerTimeoutMs: json['scanner_timeout_ms'] as int? ?? 80,
    );
  }
}

class SecurityConfigRepository {
  SecurityConfigRepository._();

  static String _configKey(int companyId) =>
      'security_config_company_$companyId';
  static String _scannerKey(int companyId, String terminalId) =>
      'security_scanner_${companyId}_$terminalId';

  static Future<SecurityConfig> load({
    int? companyId,
    String? terminalId,
  }) async {
    final db = await AppDb.database;
    final resolvedCompanyId =
        companyId ?? await SessionManager.companyId() ?? 1;
    final rows = await db.query(
      DbTables.appConfig,
      where: 'key = ?',
      whereArgs: [_configKey(resolvedCompanyId)],
      limit: 1,
    );

    SecurityConfig base = rows.isNotEmpty
        ? SecurityConfig.fromJson(
            jsonDecode(rows.first['value'] as String) as Map<String, dynamic>,
          )
        : SecurityConfig.defaults();

    if (terminalId != null && terminalId.isNotEmpty) {
      final scannerRows = await db.query(
        DbTables.appConfig,
        where: 'key = ?',
        whereArgs: [_scannerKey(resolvedCompanyId, terminalId)],
        limit: 1,
      );
      if (scannerRows.isNotEmpty) {
        try {
          final scannerJson =
              jsonDecode(scannerRows.first['value'] as String)
                  as Map<String, dynamic>;
          base = base.copyWith(
            scannerEnabled:
                scannerJson['scanner_enabled'] as bool? ?? base.scannerEnabled,
            scannerSuffix:
                scannerJson['scanner_suffix'] as String? ?? base.scannerSuffix,
            scannerPrefix:
                scannerJson['scanner_prefix'] as String? ?? base.scannerPrefix,
            scannerTimeoutMs:
                scannerJson['scanner_timeout_ms'] as int? ??
                base.scannerTimeoutMs,
          );
        } catch (_) {}
      }
    }

    return base;
  }

  static Future<void> save({
    required SecurityConfig config,
    required int companyId,
    String? terminalId,
  }) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(DbTables.appConfig, {
      'key': _configKey(companyId),
      'value': jsonEncode(config.toJson()),
      'updated_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (terminalId != null && terminalId.isNotEmpty) {
      await db.insert(DbTables.appConfig, {
        'key': _scannerKey(companyId, terminalId),
        'value': jsonEncode({
          'scanner_enabled': config.scannerEnabled,
          'scanner_suffix': config.scannerSuffix,
          'scanner_prefix': config.scannerPrefix,
          'scanner_timeout_ms': config.scannerTimeoutMs,
        }),
        'updated_at_ms': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Future<bool> requiresOverride(
    String actionCode, {
    int? companyId,
    SecurityConfig? cached,
  }) async {
    final config =
        cached ??
        await load(
          companyId: companyId,
          terminalId:
              await SessionManager.terminalId() ??
              await SessionManager.ensureTerminalId(),
        );
    final override = config.overrideByAction[actionCode];
    if (override != null) return override;
    final action = AppActions.findByCode(actionCode);
    return action?.requiresOverrideByDefault ?? false;
  }
}
