import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../identity/identity_recovery_bundle.dart';
import '../storage/fullpos_paths.dart';

enum AppRecoveryKind { identity, database }

class AppRecoveryState {
  const AppRecoveryState._({
    required this.active,
    this.kind,
    this.reason,
    this.details,
    this.createdAt,
    this.updatedAt,
    this.appVersion,
    this.dbPath,
  });

  const AppRecoveryState.inactive()
    : this._(
        active: false,
        kind: null,
        reason: null,
        details: null,
        createdAt: null,
        updatedAt: null,
        appVersion: null,
        dbPath: null,
      );

  const AppRecoveryState.active({
    required AppRecoveryKind kind,
    required String reason,
    String? details,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? appVersion,
    String? dbPath,
  }) : this._(
         active: true,
         kind: kind,
         reason: reason,
         details: details,
         createdAt: createdAt,
         updatedAt: updatedAt,
         appVersion: appVersion,
         dbPath: dbPath,
       );

  final bool active;
  final AppRecoveryKind? kind;
  final String? reason;
  final String? details;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? appVersion;
  final String? dbPath;

  Map<String, dynamic> toJson() => {
    'recoveryType': kind?.name,
    'message': reason,
    'technicalDetails': details,
    'createdAt': (createdAt ?? DateTime.now().toUtc()).toIso8601String(),
    'updatedAt': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
    'appVersion': appVersion,
    'dbPath': dbPath,
  };

  static AppRecoveryState? fromJson(Map<String, dynamic> json) {
    final type = (json['recoveryType'] ?? '').toString().trim();
    AppRecoveryKind? kind;
    for (final candidate in AppRecoveryKind.values) {
      if (candidate.name == type) {
        kind = candidate;
        break;
      }
    }
    if (kind == null) return null;
    return AppRecoveryState.active(
      kind: kind,
      reason: (json['message'] ?? 'recovery_required').toString(),
      details: (json['technicalDetails'] ?? '').toString().trim().isEmpty
          ? null
          : json['technicalDetails'].toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      appVersion: (json['appVersion'] ?? '').toString().trim().isEmpty
          ? null
          : json['appVersion'].toString(),
      dbPath: (json['dbPath'] ?? '').toString().trim().isEmpty
          ? null
          : json['dbPath'].toString(),
    );
  }
}

class AppRecoveryController extends ValueNotifier<AppRecoveryState> {
  AppRecoveryController._() : super(const AppRecoveryState.inactive());

  static final AppRecoveryController instance = AppRecoveryController._();

  AppRecoveryState get state => value;
  bool get isActive => value.active;

  Future<void> loadPersisted() async {
    final file = await recoveryStateFile();
    if (!await file.exists()) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      final loaded = AppRecoveryState.fromJson(decoded.cast<String, dynamic>());
      if (loaded == null) return;
      _set(loaded);
      await IdentityRecoveryBundle.instance.log(
        'app_recovery_state_loaded reason=${loaded.reason}',
      );
    } catch (e) {
      await IdentityRecoveryBundle.instance.log(
        'app_recovery_state_load_failed error=$e',
      );
    }
  }

  Future<void> requireIdentityRecovery(
    String reason, {
    String? details,
    String? dbPath,
  }) async {
    final now = DateTime.now().toUtc();
    _set(
      AppRecoveryState.active(
        kind: AppRecoveryKind.identity,
        reason: reason,
        details: details,
        createdAt: state.createdAt,
        updatedAt: now,
        appVersion: _appVersion,
        dbPath: dbPath,
      ),
    );
    await _persist();
    await IdentityRecoveryBundle.instance.markRecoveryRequired(reason);
    await IdentityRecoveryBundle.instance.log(
      'app_recovery_identity_required reason=$reason details=${details ?? ''}',
    );
  }

  Future<void> requireDatabaseRecovery(
    String reason, {
    String? details,
    String? dbPath,
  }) async {
    final now = DateTime.now().toUtc();
    _set(
      AppRecoveryState.active(
        kind: AppRecoveryKind.database,
        reason: reason,
        details: details,
        createdAt: state.createdAt,
        updatedAt: now,
        appVersion: _appVersion,
        dbPath: dbPath,
      ),
    );
    await _persist();
    await IdentityRecoveryBundle.instance.log(
      'app_recovery_database_required reason=$reason details=${details ?? ''}',
    );
  }

  Future<void> clearResolved() async {
    _set(const AppRecoveryState.inactive());
    final file = await recoveryStateFile();
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void clearForTests() => _set(const AppRecoveryState.inactive());

  void _set(AppRecoveryState next) {
    value = next;
  }

  Future<void> _persist() async {
    final file = await recoveryStateFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
      flush: true,
    );
  }

  static Future<File> recoveryStateFile() async {
    final dir = await _recoveryDir();
    return File(p.join(dir.path, 'recovery_state.json'));
  }

  static Future<Directory> recoveryDir() => _recoveryDir();
}

class AppRecoveryRequiredException implements Exception {
  const AppRecoveryRequiredException(this.message);

  final String message;

  @override
  String toString() => 'AppRecoveryRequiredException: $message';
}

const String _appVersion = String.fromEnvironment(
  'FULLPOS_APP_VERSION',
  defaultValue: '1.0.0+1',
);

Future<Directory> _recoveryDir() async {
  const isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
  if (!isFlutterTest) {
    final root = await FullPosPaths.rootDir();
    return Directory(p.join(root.path, 'recovery'));
  }
  final support = await getApplicationSupportDirectory();
  return Directory(p.join(support.path, 'FullPOS', 'recovery'));
}
