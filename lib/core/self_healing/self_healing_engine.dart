import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/tables.dart';
import '../identity/identity_recovery_bundle.dart';
import '../identity/terminal_id_log_recovery_service.dart';
import '../recovery/app_recovery.dart';
import '../recovery/recovery_lock.dart';
import '../session/session_manager.dart';

enum HealingSeverity { info, warning, repairable, blocking }

enum HealingAction {
  none,
  restoreDatabase,
  restoreTerminalId,
  restorePrefsFromBundle,
  clearStaleRecovery,
  clearInvalidSession,
  showRecovery,
}

class HealingIssue {
  const HealingIssue({
    required this.code,
    required this.message,
    required this.severity,
  });

  final String code;
  final String message;
  final HealingSeverity severity;
}

class HealingResult {
  const HealingResult({
    required this.ok,
    required this.action,
    required this.message,
  });

  final bool ok;
  final HealingAction action;
  final String message;
}

class HealingEvidence {
  const HealingEvidence({
    required this.officialDbPath,
    required this.officialDbExists,
    required this.dbCandidates,
    required this.hasPriorInstallation,
    required this.identity,
    required this.pathHints,
  });

  final String officialDbPath;
  final bool officialDbExists;
  final List<DatabaseCandidate> dbCandidates;
  final bool hasPriorInstallation;
  final IdentityEvidence identity;
  final List<String> pathHints;
}

class HealingReport {
  const HealingReport({
    required this.evidence,
    required this.issues,
    required this.results,
    required this.repaired,
    required this.needsRecovery,
  });

  final HealingEvidence evidence;
  final List<HealingIssue> issues;
  final List<HealingResult> results;
  final bool repaired;
  final bool needsRecovery;
}

class DatabaseCandidate {
  const DatabaseCandidate({
    required this.path,
    required this.sizeBytes,
    required this.integrityOk,
    required this.hasCoreTables,
    required this.realDataScore,
    required this.totalRows,
    required this.isDemoLike,
  });

  final String path;
  final int sizeBytes;
  final bool integrityOk;
  final bool hasCoreTables;
  final int realDataScore;
  final int totalRows;
  final bool isDemoLike;

  bool get isSafeRestoreCandidate =>
      integrityOk && hasCoreTables && realDataScore > 0 && !isDemoLike;
}

class IdentityEvidence {
  const IdentityEvidence({
    required this.businessIds,
    required this.licenseKeys,
    required this.terminalIds,
    required this.deviceIds,
  });

  final Set<String> businessIds;
  final Set<String> licenseKeys;
  final Set<String> terminalIds;
  final Set<String> deviceIds;

  bool get hasBusinessConflict => businessIds.length > 1;
  bool get hasLicenseConflict => licenseKeys.length > 1;
}

class SelfHealingEngine {
  const SelfHealingEngine();

  Future<HealingReport> run({String reason = 'bootstrap'}) async {
    try {
      await RecoveryLock.acquire('self_healing_$reason');
    } on AppRecoveryRequiredException catch (e) {
      await SelfHealingLog.write('lock_blocked reason=$reason error=$e');
      final evidence = await collectEvidence();
      return HealingReport(
        evidence: evidence,
        issues: const [
          HealingIssue(
            code: 'recovery_lock_active',
            message: 'Ya hay una recuperación en curso.',
            severity: HealingSeverity.blocking,
          ),
        ],
        results: const [
          HealingResult(
            ok: false,
            action: HealingAction.showRecovery,
            message: 'Recovery lock activo.',
          ),
        ],
        repaired: false,
        needsRecovery: true,
      );
    }

    final issues = <HealingIssue>[];
    final results = <HealingResult>[];
    var repaired = false;
    var needsRecovery = false;
    HealingEvidence evidence;

    try {
      evidence = await collectEvidence();
      await SelfHealingLog.write(
        'evidence officialDb=${evidence.officialDbPath} '
        'exists=${evidence.officialDbExists} '
        'prior=${evidence.hasPriorInstallation} '
        'dbCandidates=${evidence.dbCandidates.length} '
        'businessIds=${evidence.identity.businessIds.length} '
        'terminalIds=${evidence.identity.terminalIds.length}',
      );

      if (evidence.identity.hasBusinessConflict) {
        issues.add(
          const HealingIssue(
            code: 'business_id_conflict',
            message: 'Hay más de un businessId en las fuentes locales.',
            severity: HealingSeverity.blocking,
          ),
        );
      }
      if (evidence.identity.hasLicenseConflict) {
        issues.add(
          const HealingIssue(
            code: 'license_key_conflict',
            message: 'Hay más de una licencia en las fuentes locales.',
            severity: HealingSeverity.blocking,
          ),
        );
      }

      if (issues.any((i) => i.severity == HealingSeverity.blocking)) {
        await _requireRecovery('self_healing_identity_conflict', issues);
        needsRecovery = true;
      } else {
        final dbResult = await DatabaseHealer().repairIfNeeded(evidence);
        results.add(dbResult);
        repaired = repaired || dbResult.ok;
        if (!dbResult.ok && dbResult.action == HealingAction.showRecovery) {
          needsRecovery = true;
        }

        if (!needsRecovery) {
          final identityResult = await IdentityHealer().repairIfNeeded();
          results.add(identityResult);
          repaired = repaired || identityResult.ok;
          if (!identityResult.ok &&
              identityResult.action == HealingAction.showRecovery) {
            needsRecovery = true;
          }
        }

        if (!needsRecovery) {
          final sessionResult = await SessionHealer().repairIfNeeded();
          results.add(sessionResult);
          repaired = repaired || sessionResult.ok;
        }

        if (!needsRecovery) {
          final recoveryResult = await RecoveryStateHealer().repairIfResolved();
          results.add(recoveryResult);
          repaired = repaired || recoveryResult.ok;
        }
      }

      if (!needsRecovery) {
        final verifyResult = await verify();
        results.add(verifyResult);
        if (!verifyResult.ok &&
            verifyResult.action == HealingAction.showRecovery) {
          needsRecovery = true;
        }
      }

      if (!needsRecovery) {
        await AppRecoveryController.instance.clearResolved();
      }

      return HealingReport(
        evidence: evidence,
        issues: issues,
        results: results,
        repaired: repaired,
        needsRecovery: needsRecovery,
      );
    } catch (e, st) {
      await SelfHealingLog.write('engine_error reason=$reason error=$e\n$st');
      final fallbackEvidence = await collectEvidence();
      await _requireRecovery('self_healing_unhandled', [
        HealingIssue(
          code: 'self_healing_unhandled',
          message: e.toString(),
          severity: HealingSeverity.blocking,
        ),
      ]);
      return HealingReport(
        evidence: fallbackEvidence,
        issues: [
          HealingIssue(
            code: 'self_healing_unhandled',
            message: e.toString(),
            severity: HealingSeverity.blocking,
          ),
        ],
        results: const [
          HealingResult(
            ok: false,
            action: HealingAction.showRecovery,
            message: 'Error no controlado durante autoreparación.',
          ),
        ],
        repaired: false,
        needsRecovery: true,
      );
    } finally {
      await RecoveryLock.release();
    }
  }

  Future<HealingEvidence> collectEvidence() async {
    final dbEvidence = await DatabaseEvidenceCollector().collect();
    final identity = await IdentityEvidenceCollector().collect();
    final pathHints = await PathHealer().detect();
    return HealingEvidence(
      officialDbPath: dbEvidence.officialDbPath,
      officialDbExists: dbEvidence.officialDbExists,
      dbCandidates: dbEvidence.candidates,
      hasPriorInstallation:
          dbEvidence.hasBackupEvidence ||
          identity.businessIds.isNotEmpty ||
          identity.licenseKeys.isNotEmpty ||
          identity.terminalIds.isNotEmpty,
      identity: identity,
      pathHints: pathHints,
    );
  }

  Future<HealingResult> verify() async {
    final recovery = AppRecoveryController.instance.state;
    if (recovery.active) {
      return HealingResult(
        ok: false,
        action: HealingAction.showRecovery,
        message: 'Recovery activo: ${recovery.reason ?? 'unknown'}',
      );
    }
    return const HealingResult(
      ok: true,
      action: HealingAction.none,
      message: 'Self-healing verificado.',
    );
  }

  Future<void> _requireRecovery(
    String reason,
    List<HealingIssue> issues,
  ) async {
    await AppRecoveryController.instance.requireIdentityRecovery(
      reason,
      details: issues.map((i) => '${i.code}: ${i.message}').join('\n'),
    );
    await SelfHealingLog.write(
      'recovery_required reason=$reason issues=${issues.map((i) => i.code).join(',')}',
    );
  }
}

class DatabaseEvidence {
  const DatabaseEvidence({
    required this.officialDbPath,
    required this.officialDbExists,
    required this.hasBackupEvidence,
    required this.candidates,
  });

  final String officialDbPath;
  final bool officialDbExists;
  final bool hasBackupEvidence;
  final List<DatabaseCandidate> candidates;
}

class DatabaseEvidenceCollector {
  Future<DatabaseEvidence> collect() async {
    final official = await AppDb.databasePath();
    final paths = <String>{official};
    final roots = await _candidateRoots();
    var hasBackupEvidence = false;

    for (final root in roots) {
      if (!await root.exists()) continue;
      if (p.basename(root.path).toUpperCase().contains('FULLPOS_BACKUPS')) {
        hasBackupEvidence = true;
      }
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final name = p.basename(entity.path).toLowerCase();
        if (name.endsWith('-wal') || name.endsWith('-shm')) continue;
        if (_looksLikeDatabaseFile(name)) paths.add(entity.path);
      }
    }

    final candidates = <DatabaseCandidate>[];
    for (final path in paths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final candidate = await _inspect(file);
      if (candidate != null) candidates.add(candidate);
    }
    candidates.sort(_compareCandidates);

    return DatabaseEvidence(
      officialDbPath: official,
      officialDbExists: await File(official).exists(),
      hasBackupEvidence: hasBackupEvidence,
      candidates: candidates,
    );
  }

  Future<List<Directory>> _candidateRoots() async {
    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    final roots = <Directory>[
      docs,
      support,
      Directory(p.join(docs.path, 'FULLPOS_BACKUPS')),
      Directory(p.join(support.path, 'FULLPOS_BACKUPS')),
    ];
    const isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
    if (isFlutterTest) return roots;

    final appData = Platform.environment['APPDATA'];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final userProfile = Platform.environment['USERPROFILE'];
    for (final value in [appData, localAppData]) {
      final base = _trim(value);
      if (base == null) continue;
      roots.add(Directory(p.join(base, 'FullPOS')));
      roots.add(Directory(p.join(base, 'FULLTECH, SRL')));
    }
    final profile = _trim(userProfile);
    if (profile != null) {
      roots.add(Directory(p.join(profile, 'OneDrive', 'Documentos')));
      roots.add(Directory(p.join(profile, 'OneDrive', 'Documents')));
      roots.add(Directory(p.join(profile, 'Documents')));
    }
    return roots;
  }

  bool _looksLikeDatabaseFile(String name) {
    return name == AppDb.dbFileName.toLowerCase() ||
        (name.contains('fullpos') &&
            (name.endsWith('.db') ||
                name.endsWith('.sqlite') ||
                name.contains('reparada') ||
                name.contains('old') ||
                name.contains('corrupt') ||
                name.contains('backup')));
  }

  Future<DatabaseCandidate?> _inspect(File file) async {
    Database? db;
    try {
      final size = await file.length();
      if (size <= 0) return null;
      db = await openDatabase(
        file.path,
        readOnly: true,
        singleInstance: false,
      ).timeout(const Duration(seconds: 5));
      final quick = await db.rawQuery('PRAGMA quick_check;');
      final integrity = await db.rawQuery('PRAGMA integrity_check;');
      final quickOk = _pragmaOk(quick);
      final integrityOk = _pragmaOk(integrity);
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final names = tables.map((r) => (r['name'] ?? '').toString()).toSet();
      final hasCoreTables =
          names.contains(DbTables.users) &&
          names.contains(DbTables.products) &&
          names.contains(DbTables.sales) &&
          names.contains(DbTables.cashboxDaily);
      final counts = <String, int>{};
      for (final table in const [
        DbTables.users,
        DbTables.products,
        DbTables.sales,
        DbTables.clients,
        DbTables.cashboxDaily,
        DbTables.cashSessions,
        DbTables.cashMovements,
      ]) {
        if (!names.contains(table)) continue;
        counts[table] =
            Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM $table'),
            ) ??
            0;
      }
      final demoProducts = names.contains(DbTables.products)
          ? Sqflite.firstIntValue(
                  await db.rawQuery(
                    "SELECT COUNT(*) FROM ${DbTables.products} WHERE code LIKE '${AppDb.demoProductCodePrefix}%'",
                  ),
                ) ??
                0
          : 0;
      final totalRows = counts.values.fold<int>(0, (a, b) => a + b);
      final realDataScore =
          (counts[DbTables.sales] ?? 0) * 5 +
          (counts[DbTables.clients] ?? 0) * 3 +
          (counts[DbTables.cashMovements] ?? 0) * 3 +
          (counts[DbTables.cashSessions] ?? 0) * 2 +
          (counts[DbTables.products] ?? 0);
      final productCount = counts[DbTables.products] ?? 0;
      final isDemoLike =
          productCount > 0 &&
          demoProducts >= productCount &&
          (counts[DbTables.sales] ?? 0) == 0 &&
          (counts[DbTables.clients] ?? 0) == 0;
      return DatabaseCandidate(
        path: file.path,
        sizeBytes: size,
        integrityOk: quickOk && integrityOk,
        hasCoreTables: hasCoreTables,
        realDataScore: realDataScore,
        totalRows: totalRows,
        isDemoLike: isDemoLike,
      );
    } catch (e) {
      await SelfHealingLog.write(
        'db_candidate_invalid path=${file.path} error=$e',
      );
      return null;
    } finally {
      try {
        await db?.close();
      } catch (_) {}
    }
  }

  bool _pragmaOk(List<Map<String, Object?>> rows) {
    final value = rows.isNotEmpty ? rows.first.values.first?.toString() : null;
    return value?.toLowerCase() == 'ok';
  }

  int _compareCandidates(DatabaseCandidate a, DatabaseCandidate b) {
    final safe = b.isSafeRestoreCandidate.toString().compareTo(
      a.isSafeRestoreCandidate.toString(),
    );
    if (safe != 0) return safe;
    final score = b.realDataScore.compareTo(a.realDataScore);
    if (score != 0) return score;
    final rows = b.totalRows.compareTo(a.totalRows);
    if (rows != 0) return rows;
    return b.sizeBytes.compareTo(a.sizeBytes);
  }
}

class DatabaseHealer {
  Future<HealingResult> repairIfNeeded(HealingEvidence evidence) async {
    if (evidence.officialDbExists) {
      return const HealingResult(
        ok: false,
        action: HealingAction.none,
        message: 'DB oficial existe; no se toca.',
      );
    }
    if (!evidence.hasPriorInstallation) {
      return const HealingResult(
        ok: false,
        action: HealingAction.none,
        message: 'Sin instalación previa; se permite flujo normal.',
      );
    }

    final safe = evidence.dbCandidates
        .where((c) => c.path != evidence.officialDbPath)
        .where((c) => c.isSafeRestoreCandidate)
        .toList();
    if (safe.isEmpty) {
      await AppRecoveryController.instance.requireDatabaseRecovery(
        'main_database_missing_prior_installation',
        details: 'No hay DB candidata válida con datos reales.',
        dbPath: evidence.officialDbPath,
      );
      await SelfHealingLog.write('db_restore_skipped reason=no_safe_candidate');
      return const HealingResult(
        ok: false,
        action: HealingAction.showRecovery,
        message: 'No hay DB candidata segura.',
      );
    }

    final selected = safe.first;
    await _backupBeforeRestore(evidence.officialDbPath, selected.path);
    final target = File(evidence.officialDbPath);
    await target.parent.create(recursive: true);
    await File(selected.path).copy(target.path);
    await SelfHealingLog.write(
      'db_restored source=${selected.path} target=${target.path} '
      'score=${selected.realDataScore} size=${selected.sizeBytes}',
    );
    return HealingResult(
      ok: true,
      action: HealingAction.restoreDatabase,
      message: 'DB restaurada desde ${selected.path}',
    );
  }

  Future<void> _backupBeforeRestore(
    String officialPath,
    String sourcePath,
  ) async {
    final docs = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final dir = Directory(
      p.join(docs.path, 'FULLPOS_BACKUPS', 'self_healing_db_restore', stamp),
    );
    await dir.create(recursive: true);
    final official = File(officialPath);
    if (await official.exists()) {
      await official.copy(p.join(dir.path, p.basename(official.path)));
    }
    await File(
      sourcePath,
    ).copy(p.join(dir.path, 'selected_${p.basename(sourcePath)}'));
    await File(p.join(dir.path, 'restore_manifest.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'officialPath': officialPath,
        'sourcePath': sourcePath,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }
}

class IdentityEvidenceCollector {
  Future<IdentityEvidence> collect() async {
    final businessIds = <String>{};
    final licenseKeys = <String>{};
    final terminalIds = <String>{};
    final deviceIds = <String>{};

    void add(Set<String> target, Object? value) {
      final v = _trim(value?.toString());
      if (v != null && v.toLowerCase() != 'null') target.add(v);
    }

    void addJson(String? raw) {
      final text = _trim(raw);
      if (text == null) return;
      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map) return;
        add(businessIds, decoded['businessId'] ?? decoded['business_id']);
        add(licenseKeys, decoded['licenseKey'] ?? decoded['license_key']);
        add(terminalIds, decoded['terminalId'] ?? decoded['terminal_id']);
        add(deviceIds, decoded['deviceId'] ?? decoded['device_id']);
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      add(businessIds, prefs.getString(IdentityRecoveryBundle.businessIdKey));
      add(licenseKeys, prefs.getString(IdentityRecoveryBundle.licenseKeyKey));
      add(terminalIds, prefs.getString(IdentityRecoveryBundle.terminalIdKey));
      add(
        deviceIds,
        prefs.getString(IdentityRecoveryBundle.licenseDeviceIdKey),
      );
      addJson(prefs.getString(IdentityRecoveryBundle.licenseLastInfoKey));
    } catch (_) {}

    for (final file in [
      await IdentityRecoveryBundle.instance.primaryFile(),
      await IdentityRecoveryBundle.instance.backupFile(),
      await IdentityRecoveryBundle.instance.documentsMirrorFile(),
      await IdentityRecoveryBundle.instance.documentsMirrorBackupFile(),
    ]) {
      try {
        if (!await file.exists()) continue;
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is! Map) continue;
        add(businessIds, decoded['businessId']);
        add(licenseKeys, decoded['licenseKey']);
        add(terminalIds, decoded['terminalId']);
        add(deviceIds, decoded['licenseDeviceId']);
        addJson(decoded['licenseLastInfo']?.toString());
      } catch (_) {}
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
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('app_identity','app_metadata')",
          );
          final names = tables.map((r) => r['name']?.toString()).toSet();
          if (names.contains('app_identity')) {
            final rows = await db.query('app_identity', limit: 1);
            if (rows.isNotEmpty) {
              final row = rows.first;
              add(businessIds, row['business_id']);
              add(licenseKeys, row['license_key']);
              add(terminalIds, row['terminal_id']);
              add(deviceIds, row['license_device_id']);
            }
          }
        } finally {
          await db.close();
        }
      }
    } catch (_) {}

    return IdentityEvidence(
      businessIds: businessIds,
      licenseKeys: licenseKeys,
      terminalIds: terminalIds,
      deviceIds: deviceIds,
    );
  }
}

class IdentityHealer {
  Future<HealingResult> repairIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final terminal = _trim(
      prefs.getString(IdentityRecoveryBundle.terminalIdKey),
    );
    if (terminal == null) {
      final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
      final bundleTerminal = _trim(bundle?.terminalId);
      if (bundle != null && bundleTerminal != null) {
        final restored = await IdentityRecoveryBundle.instance
            .restoreBundleToSharedPreferences(
              bundle,
              reason: 'self_healing_terminal_from_bundle',
            );
        if (restored) {
          await SelfHealingLog.write('terminal_restored_from_bundle');
          return const HealingResult(
            ok: true,
            action: HealingAction.restorePrefsFromBundle,
            message: 'terminal_id restaurado desde bundle.',
          );
        }
      }

      final fromLog = await const TerminalIdLogRecoveryService().recover(
        reason: 'self_healing',
      );
      if (fromLog.recovered) {
        return const HealingResult(
          ok: true,
          action: HealingAction.restoreTerminalId,
          message: 'terminal_id restaurado desde logs.',
        );
      }
      final hasIdentity =
          _trim(prefs.getString(IdentityRecoveryBundle.businessIdKey)) !=
              null ||
          _trim(prefs.getString(IdentityRecoveryBundle.licenseKeyKey)) !=
              null ||
          bundle?.hasAnyCriticalValue == true;
      if (hasIdentity) {
        try {
          await SessionManager.ensureTerminalId();
          return const HealingResult(
            ok: true,
            action: HealingAction.restoreTerminalId,
            message: 'terminal_id restaurado desde una fuente local.',
          );
        } on IdentityRecoveryException {
          return const HealingResult(
            ok: false,
            action: HealingAction.showRecovery,
            message:
                'terminal_id faltante sin candidato validado; requiere reactivación.',
          );
        }
      }
    }

    return const HealingResult(
      ok: false,
      action: HealingAction.none,
      message: 'Identidad sin reparación necesaria.',
    );
  }
}

class SessionHealer {
  Future<HealingResult> repairIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('logged_user_id');
    if (userId == null || prefs.getBool('logged_in') != true) {
      return const HealingResult(
        ok: false,
        action: HealingAction.none,
        message: 'Sin sesión activa.',
      );
    }
    final valid = await _isValidUser(userId);
    if (!valid) {
      await SessionManager.clearInvalidSession(
        reason: 'self_healing_invalid_user',
      );
      await SelfHealingLog.write('invalid_session_cleared userId=$userId');
      return const HealingResult(
        ok: true,
        action: HealingAction.clearInvalidSession,
        message: 'Sesión inválida limpiada.',
      );
    }
    return const HealingResult(
      ok: false,
      action: HealingAction.none,
      message: 'Sesión válida.',
    );
  }

  Future<bool> _isValidUser(int userId) async {
    try {
      final dbPath = await AppDb.databasePath();
      if (!await File(dbPath).exists()) return false;
      final db = await openDatabase(
        dbPath,
        readOnly: true,
        singleInstance: false,
      );
      try {
        final rows = await db.query(
          DbTables.users,
          columns: ['id', 'is_active', 'deleted_at_ms'],
          where: 'id = ?',
          whereArgs: [userId],
          limit: 1,
        );
        if (rows.isEmpty) return false;
        final row = rows.first;
        return row['is_active'] != 0 && row['deleted_at_ms'] == null;
      } finally {
        await db.close();
      }
    } catch (_) {
      return false;
    }
  }
}

class CashboxHealer {
  Future<HealingResult> repairIfNeeded() async {
    return const HealingResult(
      ok: false,
      action: HealingAction.none,
      message: 'Cashbox validado sin cambios destructivos.',
    );
  }
}

class LicenseHealer {
  Future<HealingResult> validateOnly() async {
    return const HealingResult(
      ok: false,
      action: HealingAction.none,
      message: 'Licencia sólo validada por identidad; no modificada.',
    );
  }
}

class RecoveryStateHealer {
  Future<HealingResult> repairIfResolved() async {
    final state = AppRecoveryController.instance.state;
    if (!state.active) {
      return const HealingResult(
        ok: false,
        action: HealingAction.none,
        message: 'No hay recovery_state activo.',
      );
    }
    if (state.kind == AppRecoveryKind.database) {
      final path = await AppDb.databasePath();
      if (!await File(path).exists()) {
        return const HealingResult(
          ok: false,
          action: HealingAction.showRecovery,
          message: 'Recovery de DB sigue activo.',
        );
      }
    }
    if (state.kind == AppRecoveryKind.identity) {
      final prefs = await SharedPreferences.getInstance();
      final business = _trim(
        prefs.getString(IdentityRecoveryBundle.businessIdKey),
      );
      final terminal = _trim(
        prefs.getString(IdentityRecoveryBundle.terminalIdKey),
      );
      if (business == null && terminal == null) {
        return const HealingResult(
          ok: false,
          action: HealingAction.showRecovery,
          message: 'Recovery de identidad sigue activo.',
        );
      }
    }
    await AppRecoveryController.instance.clearResolved();
    await SelfHealingLog.write('stale_recovery_state_cleared');
    return const HealingResult(
      ok: true,
      action: HealingAction.clearStaleRecovery,
      message: 'Recovery viejo limpiado.',
    );
  }
}

class PathHealer {
  Future<List<String>> detect() async {
    final hints = <String>[];
    final docs = await getApplicationDocumentsDirectory();
    final support = await getApplicationSupportDirectory();
    hints.add('documents=${docs.path}');
    hints.add('support=${support.path}');
    final oneDrive = Platform.environment['OneDrive'];
    if (_trim(oneDrive) != null) hints.add('onedrive=$oneDrive');
    final appData = Platform.environment['APPDATA'];
    if (_trim(appData) != null) hints.add('appdata=$appData');
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (_trim(localAppData) != null) hints.add('localappdata=$localAppData');
    await SelfHealingLog.write('path_hints ${hints.join(' | ')}');
    return hints;
  }
}

class SelfHealingLog {
  const SelfHealingLog._();

  static Future<void> write(String message) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '${DateTime.now().toUtc().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  static Future<File> _file() async {
    const isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
    if (Platform.isWindows && !isFlutterTest) {
      final local = _trim(Platform.environment['LOCALAPPDATA']);
      if (local != null) {
        return File(p.join(local, 'FullPOS', 'logs', 'self_healing.log'));
      }
    }
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'FullPOS', 'logs', 'self_healing.log'));
  }
}

String? _trim(String? value) {
  final text = (value ?? '').trim();
  return text.isEmpty ? null : text;
}
