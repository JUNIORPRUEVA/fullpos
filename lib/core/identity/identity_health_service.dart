import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../session/session_manager.dart';
import 'identity_recovery_bundle.dart';
import '../recovery/app_recovery.dart';

enum IdentityHealthStatus { ok, repaired, needsRecovery }

class IdentityHealthResult {
  const IdentityHealthResult(this.status, {this.details});

  final IdentityHealthStatus status;
  final String? details;

  bool get ok => status == IdentityHealthStatus.ok;
  bool get repaired => status == IdentityHealthStatus.repaired;
  bool get needsRecovery => status == IdentityHealthStatus.needsRecovery;
}

class IdentityHealthService {
  const IdentityHealthService();

  Future<IdentityHealthResult> check() async {
    try {
      return await syncPrefsBundleAndDb();
    } catch (e) {
      await AppRecoveryController.instance.requireIdentityRecovery(
        'identity_health_unhandled',
        details: e.toString(),
      );
      return IdentityHealthResult(
        IdentityHealthStatus.needsRecovery,
        details: e.toString(),
      );
    }
  }

  Future<IdentityHealthResult> syncPrefsBundleAndDb() async {
    final db = await AppDb.database;
    await AppDb.ensureIdentitySchema(db);

    final prefs = await SharedPreferences.getInstance();
    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
    final dbValues = await _loadDbIdentity(db);

    final prefValues = <String, String?>{
      'terminal_id': _trim(
        prefs.getString(IdentityRecoveryBundle.terminalIdKey),
      ),
      'business_id': _trim(
        prefs.getString(IdentityRecoveryBundle.businessIdKey),
      ),
      'license_key': _trim(
        prefs.getString(IdentityRecoveryBundle.licenseKeyKey),
      ),
      'license_device_id': _trim(
        prefs.getString(IdentityRecoveryBundle.licenseDeviceIdKey),
      ),
      'install_id': _trim(prefs.getString('install_id')),
    };

    if (prefValues['business_id'] == null) {
      prefValues['business_id'] = _trim(bundle?.businessId);
    }
    if (prefValues['terminal_id'] == null) {
      prefValues['terminal_id'] = _trim(bundle?.terminalId);
    }
    if (prefValues['license_key'] == null) {
      prefValues['license_key'] = _trim(bundle?.licenseKey);
    }
    if (prefValues['license_device_id'] == null) {
      prefValues['license_device_id'] = _trim(bundle?.licenseDeviceId);
    }

    final conflict = _firstConflict(prefValues, dbValues);
    if (conflict != null) {
      await AppRecoveryController.instance.requireIdentityRecovery(
        'identity_conflict',
        details: conflict,
        dbPath: await AppDb.databasePath(),
      );
      return IdentityHealthResult(
        IdentityHealthStatus.needsRecovery,
        details: conflict,
      );
    }

    var changed = false;
    changed = await repairMissingPrefsFromDb(dbValues: dbValues) || changed;
    changed =
        await repairMissingDbFromPrefs(
          db: db,
          prefValues: prefValues,
          dbValues: dbValues,
        ) ||
        changed;

    if (changed) {
      await IdentityRecoveryBundle.instance.saveFromCurrentState(
        'identity_health_repaired',
      );
      await AppRecoveryController.instance.clearResolved();
      return const IdentityHealthResult(IdentityHealthStatus.repaired);
    }

    await AppRecoveryController.instance.clearResolved();
    return const IdentityHealthResult(IdentityHealthStatus.ok);
  }

  Future<bool> repairMissingPrefsFromDb({
    Map<String, String?>? dbValues,
  }) async {
    final db = await AppDb.database;
    final values = dbValues ?? await _loadDbIdentity(db);
    final prefs = await SharedPreferences.getInstance();
    var changed = false;

    Future<void> setIfMissing(String prefKey, String dbKey) async {
      final local = _trim(prefs.getString(prefKey));
      final incoming = _trim(values[dbKey]);
      if (local == null && incoming != null) {
        await prefs.setString(prefKey, incoming);
        changed = true;
      }
    }

    await setIfMissing(IdentityRecoveryBundle.terminalIdKey, 'terminal_id');
    await setIfMissing(IdentityRecoveryBundle.businessIdKey, 'business_id');
    await setIfMissing(IdentityRecoveryBundle.licenseKeyKey, 'license_key');
    await setIfMissing(
      IdentityRecoveryBundle.licenseDeviceIdKey,
      'license_device_id',
    );
    await setIfMissing('install_id', 'install_id');

    return changed;
  }

  Future<bool> repairMissingDbFromPrefs({
    Database? db,
    Map<String, String?>? prefValues,
    Map<String, String?>? dbValues,
  }) async {
    final database = db ?? await AppDb.database;
    await AppDb.ensureIdentitySchema(database);
    final prefs = await SharedPreferences.getInstance();
    final local =
        prefValues ??
        {
          'terminal_id': _trim(
            prefs.getString(IdentityRecoveryBundle.terminalIdKey),
          ),
          'business_id': _trim(
            prefs.getString(IdentityRecoveryBundle.businessIdKey),
          ),
          'license_key': _trim(
            prefs.getString(IdentityRecoveryBundle.licenseKeyKey),
          ),
          'license_device_id': _trim(
            prefs.getString(IdentityRecoveryBundle.licenseDeviceIdKey),
          ),
          'install_id': _trim(prefs.getString('install_id')),
        };
    final current = dbValues ?? await _loadDbIdentity(database);
    final update = <String, Object?>{};
    for (final key in local.keys) {
      if (_trim(current[key]) == null && _trim(local[key]) != null) {
        update[key] = local[key];
      }
    }
    if (update.isEmpty) return false;
    update['updated_at_ms'] = DateTime.now().millisecondsSinceEpoch;
    await database.update('app_identity', update, where: 'id = 1');
    return true;
  }

  static Future<void> validateCurrentSessionUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('logged_user_id');
    if (userId == null) return;
    final db = await AppDb.database;
    final rows = await db.query(
      'users',
      columns: ['id', 'is_active', 'deleted_at_ms'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    final invalid =
        rows.isEmpty ||
        rows.first['is_active'] == 0 ||
        rows.first['deleted_at_ms'] != null;
    if (!invalid) return;
    await SessionManager.clearInvalidSession(
      reason: 'session_invalid_user_cleared',
    );
    await IdentityRecoveryBundle.instance.log('session_invalid_user_cleared');
  }

  Future<Map<String, String?>> _loadDbIdentity(Database db) async {
    await AppDb.ensureIdentitySchema(db);
    final rows = await db.query('app_identity', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return const {};
    final row = rows.first;
    return {
      'terminal_id': _trim(row['terminal_id']),
      'business_id': _trim(row['business_id']),
      'license_key': _trim(row['license_key']),
      'license_device_id': _trim(row['license_device_id']),
      'install_id': _trim(row['install_id']),
    };
  }

  String? _firstConflict(
    Map<String, String?> prefValues,
    Map<String, String?> dbValues,
  ) {
    for (final key in prefValues.keys) {
      final prefs = _trim(prefValues[key]);
      final db = _trim(dbValues[key]);
      if (prefs != null && db != null && prefs != db) {
        return '$key prefs=$prefs sqlite=$db';
      }
    }
    return null;
  }
}

String? _trim(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}
