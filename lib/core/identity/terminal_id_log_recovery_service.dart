import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../recovery/app_recovery.dart';
import '../storage/fullpos_paths.dart';
import 'identity_recovery_bundle.dart';

class TerminalIdLogRecoveryResult {
  const TerminalIdLogRecoveryResult._({
    required this.recovered,
    this.terminalId,
    this.sourcePath,
    this.reason,
  });

  const TerminalIdLogRecoveryResult.recovered({
    required String terminalId,
    required String sourcePath,
  }) : this._(recovered: true, terminalId: terminalId, sourcePath: sourcePath);

  const TerminalIdLogRecoveryResult.notRecovered(String reason)
    : this._(recovered: false, reason: reason);

  final bool recovered;
  final String? terminalId;
  final String? sourcePath;
  final String? reason;
}

class TerminalIdLogRecoveryService {
  const TerminalIdLogRecoveryService();

  Future<TerminalIdLogRecoveryResult> recover({required String reason}) async {
    final prefs = await SharedPreferences.getInstance();
    final currentTerminal = _trim(
      prefs.getString(IdentityRecoveryBundle.terminalIdKey),
    );
    if (currentTerminal != null) {
      return const TerminalIdLogRecoveryResult.notRecovered(
        'terminal_id_already_present',
      );
    }

    final identity = await _loadCurrentIdentity(prefs);
    if (identity.businessIds.isEmpty) {
      await IdentityRecoveryBundle.instance.log(
        'terminal_log_recovery_blocked reason=$reason validation=no_business_id',
      );
      return const TerminalIdLogRecoveryResult.notRecovered('no_business_id');
    }
    if (identity.licenseKeys.isEmpty) {
      await IdentityRecoveryBundle.instance.log(
        'terminal_log_recovery_blocked reason=$reason validation=no_license_key',
      );
      return const TerminalIdLogRecoveryResult.notRecovered('no_license_key');
    }

    final candidate = await _findValidCandidate(identity);
    if (candidate == null) {
      await IdentityRecoveryBundle.instance.log(
        'terminal_log_recovery_not_found reason=$reason',
      );
      return const TerminalIdLogRecoveryResult.notRecovered(
        'no_valid_log_candidate',
      );
    }

    await _createSafetyBackup(reason: reason);

    await prefs.setString(
      IdentityRecoveryBundle.terminalIdKey,
      candidate.terminalId,
    );
    await _restoreSqliteIdentity(
      terminalId: candidate.terminalId,
      businessId: candidate.businessId,
      licenseKey: identity.primaryLicenseKey,
    );

    final data = await _buildRestoredBundle(
      prefs: prefs,
      identity: identity,
      terminalId: candidate.terminalId,
      source: 'terminal_log_recovery_$reason',
    );
    await IdentityRecoveryBundle.instance.saveBundle(
      data,
      reason: 'terminal_log_recovery_$reason',
    );
    await _replicatePrimaryBundlesToBackups();

    await prefs.remove(IdentityRecoveryBundle.recoveryRequiredKey);
    await prefs.remove(IdentityRecoveryBundle.recoveryReasonKey);
    await AppRecoveryController.instance.clearResolved();
    await IdentityRecoveryBundle.instance.log(
      'terminal_log_recovery_success reason=$reason '
      'terminalId=${_mask(candidate.terminalId)} '
      'businessId=${_mask(candidate.businessId)} '
      'source=${candidate.path}:${candidate.lineNumber}',
    );

    return TerminalIdLogRecoveryResult.recovered(
      terminalId: candidate.terminalId,
      sourcePath: candidate.path,
    );
  }

  Future<_CurrentIdentity> _loadCurrentIdentity(SharedPreferences prefs) async {
    final businessIds = <String>{};
    final licenseKeys = <String>{};

    void addBusiness(String? value) {
      final v = _trim(value);
      if (v != null) businessIds.add(v);
    }

    void addLicense(String? value) {
      final v = _trim(value);
      if (v != null) licenseKeys.add(v);
    }

    void addLastInfo(String? raw) {
      final decoded = _decodeJsonObject(raw);
      if (decoded == null) return;
      addBusiness(decoded['businessId']?.toString());
      addBusiness(decoded['business_id']?.toString());
      addLicense(decoded['licenseKey']?.toString());
      addLicense(decoded['license_key']?.toString());
    }

    addBusiness(prefs.getString(IdentityRecoveryBundle.businessIdKey));
    addLicense(prefs.getString(IdentityRecoveryBundle.licenseKeyKey));
    addLastInfo(prefs.getString(IdentityRecoveryBundle.licenseLastInfoKey));

    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
    if (bundle != null) {
      addBusiness(bundle.businessId);
      addLicense(bundle.licenseKey);
      addLastInfo(bundle.licenseLastInfo);
    }

    try {
      final dbPath = await AppDb.databasePath();
      if (await File(dbPath).exists()) {
        final db = await openDatabase(
          dbPath,
          readOnly: true,
          singleInstance: false,
        );
        try {
          final rows = await db.query(
            'app_identity',
            where: 'id = 1',
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final row = rows.first;
            addBusiness(row['business_id']?.toString());
            addLicense(row['license_key']?.toString());
          }
        } finally {
          await db.close();
        }
      }
    } catch (e) {
      await IdentityRecoveryBundle.instance.log(
        'terminal_log_recovery_db_identity_read_failed error=$e',
      );
    }

    return _CurrentIdentity(businessIds: businessIds, licenseKeys: licenseKeys);
  }

  Future<_LogTerminalCandidate?> _findValidCandidate(
    _CurrentIdentity identity,
  ) async {
    final logFiles = await _localLogFiles();
    for (final file in logFiles) {
      _LogTerminalCandidate? best;
      var lineNumber = 0;
      try {
        final lines = file
            .openRead()
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        await for (final line in lines) {
          lineNumber++;
          final candidate = _candidateFromLine(
            line,
            path: file.path,
            lineNumber: lineNumber,
          );
          if (candidate == null) continue;
          final validation = _validateCandidate(candidate, identity);
          if (validation == null) return candidate;
          best ??= candidate;
        }
      } catch (e) {
        await IdentityRecoveryBundle.instance.log(
          'terminal_log_recovery_scan_failed path=${file.path} error=$e',
        );
      }
      if (best != null) {
        await IdentityRecoveryBundle.instance.log(
          'terminal_log_recovery_candidate_rejected path=${best.path} '
          'line=${best.lineNumber}',
        );
      }
    }
    return null;
  }

  Future<List<File>> _localLogFiles() async {
    final support = await getApplicationSupportDirectory();
    final dirs = <Directory>[
      await FullPosPaths.appLogsDir(),
      Directory(p.join(support.path, 'logs')),
      Directory(p.join(support.path, 'FULLPOS', 'logs')),
    ];
    final files = <File>[];
    for (final dir in dirs) {
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path).toLowerCase();
        if (!name.endsWith('.log') && !name.endsWith('.txt')) continue;
        files.add(entity);
      }
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  _LogTerminalCandidate? _candidateFromLine(
    String line, {
    required String path,
    required int lineNumber,
  }) {
    final normalized = _normalizeLogLine(line);
    final terminalId =
        _extractString(normalized, 'terminalId') ??
        _extractString(normalized, 'terminal_id');
    final terminal = _trim(terminalId);
    if (terminal == null || terminal.toLowerCase() == 'null') return null;

    final businessId =
        _extractString(normalized, 'businessId') ??
        _extractString(normalized, 'business_id');
    final business = _trim(businessId);
    if (business == null) return null;

    final deviceId =
        _extractString(normalized, 'deviceId') ??
        _extractString(normalized, 'device_id');
    final licenseKey =
        _extractString(normalized, 'licenseKey') ??
        _extractString(normalized, 'license_key');

    return _LogTerminalCandidate(
      path: path,
      lineNumber: lineNumber,
      terminalId: terminal,
      businessId: business,
      deviceId: _trim(deviceId),
      licenseKey: _trim(licenseKey),
    );
  }

  String? _validateCandidate(
    _LogTerminalCandidate candidate,
    _CurrentIdentity identity,
  ) {
    if (candidate.terminalId.trim().isEmpty) return 'blank_terminal_id';
    final device = candidate.deviceId;
    if (device != null && device != candidate.terminalId) {
      return 'device_id_mismatch';
    }
    if (!identity.businessIds.contains(candidate.businessId)) {
      return 'business_id_mismatch';
    }
    final candidateLicense = candidate.licenseKey;
    if (candidateLicense == null) return 'missing_license_key';
    if (!identity.matchesLicense(candidateLicense)) {
      return 'license_key_mismatch';
    }
    return null;
  }

  Future<void> _restoreSqliteIdentity({
    required String terminalId,
    required String businessId,
    required String? licenseKey,
  }) async {
    final dbPath = await AppDb.databasePath();
    if (!await File(dbPath).exists()) return;
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await _ensureIdentitySchema(db);
      final now = DateTime.now().millisecondsSinceEpoch;
      final update = <String, Object?>{
        'terminal_id': terminalId,
        'updated_at_ms': now,
      };
      final current = await db.query('app_identity', where: 'id = 1', limit: 1);
      if (current.isNotEmpty) {
        final row = current.first;
        if (_trim(row['business_id']?.toString()) == null) {
          update['business_id'] = businessId;
        }
        if (licenseKey != null &&
            _trim(row['license_key']?.toString()) == null) {
          update['license_key'] = licenseKey;
        }
      }
      await db.update('app_identity', update, where: 'id = 1');
    } finally {
      await db.close();
    }
  }

  Future<IdentityRecoveryBundleData> _buildRestoredBundle({
    required SharedPreferences prefs,
    required _CurrentIdentity identity,
    required String terminalId,
    required String source,
  }) async {
    final existing = await IdentityRecoveryBundle.instance.loadBestAvailable();
    final lastInfo = _trim(
      prefs.getString(IdentityRecoveryBundle.licenseLastInfoKey),
    );
    final now = DateTime.now().toUtc();
    final data = IdentityRecoveryBundleData(
      businessId:
          _trim(prefs.getString(IdentityRecoveryBundle.businessIdKey)) ??
          existing?.businessId ??
          identity.primaryBusinessId,
      licenseKey:
          _trim(prefs.getString(IdentityRecoveryBundle.licenseKeyKey)) ??
          existing?.licenseKey ??
          identity.primaryLicenseKey,
      licenseDeviceId:
          _trim(prefs.getString(IdentityRecoveryBundle.licenseDeviceIdKey)) ??
          existing?.licenseDeviceId,
      terminalId: terminalId,
      licenseLastInfo: lastInfo ?? existing?.licenseLastInfo,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      source: source,
      appVersion: const String.fromEnvironment(
        'FULLPOS_APP_VERSION',
        defaultValue: '1.0.0+1',
      ),
      checksum: '',
    );
    return data.copyWith(
      checksum: IdentityRecoveryBundle.checksumForJson(
        data.toJson(includeChecksum: false),
      ),
    );
  }

  Future<void> _createSafetyBackup({required String reason}) async {
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final backups = await FullPosPaths.backupsDir();
    final dir = Directory(p.join(backups.path, 'identity_log_recovery', stamp));
    await dir.create(recursive: true);

    Future<void> copyIfExists(File file, String name) async {
      try {
        if (await file.exists()) {
          await file.copy(p.join(dir.path, name));
        }
      } catch (e) {
        await IdentityRecoveryBundle.instance.log(
          'terminal_log_recovery_backup_copy_failed path=${file.path} error=$e',
        );
      }
    }

    await copyIfExists(
      await IdentityRecoveryBundle.instance.primaryFile(),
      'identity_bundle.json',
    );
    await copyIfExists(
      await IdentityRecoveryBundle.instance.backupFile(),
      'identity_bundle.bak.json',
    );
    await copyIfExists(
      await IdentityRecoveryBundle.instance.documentsMirrorFile(),
      'documents_identity_bundle.json',
    );
    await copyIfExists(
      await IdentityRecoveryBundle.instance.documentsMirrorBackupFile(),
      'documents_identity_bundle.bak.json',
    );
    await copyIfExists(File(await AppDb.databasePath()), 'fullpos.db');

    await File(p.join(dir.path, 'restore_reason.txt')).writeAsString(
      'reason=$reason\ncreatedAt=${DateTime.now().toUtc().toIso8601String()}\n',
      flush: true,
    );
    await IdentityRecoveryBundle.instance.log(
      'terminal_log_recovery_safety_backup_created path=${dir.path}',
    );
  }

  Future<void> _replicatePrimaryBundlesToBackups() async {
    Future<void> copy(File source, File target) async {
      if (!await source.exists()) return;
      await target.parent.create(recursive: true);
      await source.copy(target.path);
    }

    await copy(
      await IdentityRecoveryBundle.instance.primaryFile(),
      await IdentityRecoveryBundle.instance.backupFile(),
    );
    await copy(
      await IdentityRecoveryBundle.instance.documentsMirrorFile(),
      await IdentityRecoveryBundle.instance.documentsMirrorBackupFile(),
    );
  }
}

class _CurrentIdentity {
  const _CurrentIdentity({
    required this.businessIds,
    required this.licenseKeys,
  });

  final Set<String> businessIds;
  final Set<String> licenseKeys;

  String? get primaryBusinessId =>
      businessIds.isEmpty ? null : businessIds.first;

  String? get primaryLicenseKey =>
      licenseKeys.isEmpty ? null : licenseKeys.first;

  bool matchesLicense(String candidate) {
    final normalized = _trim(candidate);
    if (normalized == null) return false;
    for (final local in licenseKeys) {
      if (local == normalized) return true;
      final localSuffix = _licenseSuffix(local);
      final candidateSuffix = _licenseSuffix(normalized);
      if (localSuffix != null && localSuffix == candidateSuffix) return true;
    }
    return false;
  }
}

class _LogTerminalCandidate {
  const _LogTerminalCandidate({
    required this.path,
    required this.lineNumber,
    required this.terminalId,
    required this.businessId,
    this.deviceId,
    this.licenseKey,
  });

  final String path;
  final int lineNumber;
  final String terminalId;
  final String businessId;
  final String? deviceId;
  final String? licenseKey;
}

String _normalizeLogLine(String line) {
  return line.replaceAll(r'\"', '"').replaceAll("'", '"');
}

String? _extractString(String line, String key) {
  final quoted = RegExp('"$key"\\s*:\\s*"([^"]*)"').firstMatch(line);
  if (quoted != null) return quoted.group(1);
  final plain = RegExp('"$key"\\s*:\\s*([^,}\\s]+)').firstMatch(line);
  final value = plain?.group(1);
  if (value == null || value == 'null') return null;
  return value;
}

Map<String, dynamic>? _decodeJsonObject(String? raw) {
  final text = _trim(raw);
  if (text == null) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {}
  return null;
}

String? _licenseSuffix(String value) {
  final normalized = _trim(value);
  if (normalized == null) return null;
  if (normalized.length <= 6) return normalized;
  return normalized.substring(normalized.length - 6);
}

String? _trim(String? value) {
  final text = (value ?? '').trim();
  return text.isEmpty ? null : text;
}

String _mask(String value) {
  if (value.length <= 8) return '****';
  return '${value.substring(0, 4)}****${value.substring(value.length - 4)}';
}

Future<void> _ensureIdentitySchema(DatabaseExecutor db) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await db.execute('''
    CREATE TABLE IF NOT EXISTS app_identity (
      id INTEGER PRIMARY KEY CHECK(id = 1),
      terminal_id TEXT NULL,
      business_id TEXT NULL,
      license_key TEXT NULL,
      license_device_id TEXT NULL,
      install_id TEXT NULL,
      created_at_ms INTEGER NOT NULL,
      updated_at_ms INTEGER NOT NULL
    )
  ''');
  await db.insert('app_identity', {
    'id': 1,
    'created_at_ms': now,
    'updated_at_ms': now,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}
