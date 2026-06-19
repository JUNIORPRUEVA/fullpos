import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kAppVersion = String.fromEnvironment(
  'FULLPOS_APP_VERSION',
  defaultValue: '1.0.0+1',
);

class IdentityRecoveryException implements Exception {
  const IdentityRecoveryException(this.message);

  final String message;

  @override
  String toString() => 'IdentityRecoveryException: $message';
}

class IdentityRecoveryBundleData {
  const IdentityRecoveryBundleData({
    required this.businessId,
    required this.licenseKey,
    required this.licenseDeviceId,
    required this.terminalId,
    required this.licenseLastInfo,
    required this.createdAt,
    required this.updatedAt,
    required this.source,
    required this.appVersion,
    required this.checksum,
  });

  final String? businessId;
  final String? licenseKey;
  final String? licenseDeviceId;
  final String? terminalId;
  final String? licenseLastInfo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String source;
  final String? appVersion;
  final String checksum;

  bool get hasAnyCriticalValue =>
      _notBlank(businessId) ||
      _notBlank(licenseKey) ||
      _notBlank(licenseDeviceId) ||
      _notBlank(terminalId) ||
      _notBlank(licenseLastInfo);

  bool get hasReliableIdentity =>
      _notBlank(businessId) || _notBlank(terminalId);

  Map<String, dynamic> toJson({bool includeChecksum = true}) {
    return {
      'businessId': businessId,
      'licenseKey': licenseKey,
      'licenseDeviceId': licenseDeviceId,
      'terminalId': terminalId,
      'licenseLastInfo': licenseLastInfo,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'source': source,
      'appVersion': appVersion,
      if (includeChecksum) 'checksum': checksum,
    };
  }

  IdentityRecoveryBundleData copyWith({
    String? businessId,
    String? licenseKey,
    String? licenseDeviceId,
    String? terminalId,
    String? licenseLastInfo,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? source,
    String? appVersion,
    String? checksum,
  }) {
    return IdentityRecoveryBundleData(
      businessId: businessId ?? this.businessId,
      licenseKey: licenseKey ?? this.licenseKey,
      licenseDeviceId: licenseDeviceId ?? this.licenseDeviceId,
      terminalId: terminalId ?? this.terminalId,
      licenseLastInfo: licenseLastInfo ?? this.licenseLastInfo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      appVersion: appVersion ?? this.appVersion,
      checksum: checksum ?? this.checksum,
    );
  }

  static IdentityRecoveryBundleData? fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse((json['createdAt'] ?? '').toString());
    final updatedAt = DateTime.tryParse((json['updatedAt'] ?? '').toString());
    if (createdAt == null || updatedAt == null) return null;
    return IdentityRecoveryBundleData(
      businessId: _nullableTrim(json['businessId']),
      licenseKey: _nullableTrim(json['licenseKey']),
      licenseDeviceId: _nullableTrim(json['licenseDeviceId']),
      terminalId: _nullableTrim(json['terminalId']),
      licenseLastInfo: _nullableTrim(json['licenseLastInfo']),
      createdAt: createdAt,
      updatedAt: updatedAt,
      source: (json['source'] ?? '').toString().trim(),
      appVersion: _nullableTrim(json['appVersion']),
      checksum: (json['checksum'] ?? '').toString().trim(),
    );
  }
}

class IdentityRecoveryBundle {
  IdentityRecoveryBundle._();

  static final IdentityRecoveryBundle instance = IdentityRecoveryBundle._();

  static const String businessIdKey = 'business.business_id_v1';
  static const String licenseLastInfoKey = 'license.lastInfo';
  static const String licenseDeviceIdKey = 'license.deviceId';
  static const String licenseKeyKey = 'license.licenseKey';
  static const String terminalIdKey = 'terminal_id';
  static const String recoveryRequiredKey = 'identity.recovery_required';
  static const String recoveryReasonKey = 'identity.recovery_reason';

  Future<void> _queue = Future<void>.value();

  Future<File> primaryFile() async {
    final dir = await _identityDir();
    return File(p.join(dir.path, 'identity_bundle.json'));
  }

  Future<File> backupFile() async {
    final dir = await _identityDir();
    return File(p.join(dir.path, 'identity_bundle.bak.json'));
  }

  Future<File> documentsMirrorFile() async {
    final dir = await _documentsIdentityDir();
    return File(p.join(dir.path, 'identity_bundle.json'));
  }

  Future<File> documentsMirrorBackupFile() async {
    final dir = await _documentsIdentityDir();
    return File(p.join(dir.path, 'identity_bundle.bak.json'));
  }

  Future<bool> saveFromCurrentState(String reason) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final lastInfo = _trimOrNull(sp.getString(licenseLastInfoKey));
      final businessId =
          _trimOrNull(sp.getString(businessIdKey)) ??
          _businessIdFromLastInfo(lastInfo);
      final data = await _buildData(
        businessId: businessId,
        licenseKey: _trimOrNull(sp.getString(licenseKeyKey)),
        licenseDeviceId: _trimOrNull(sp.getString(licenseDeviceIdKey)),
        terminalId: _trimOrNull(sp.getString(terminalIdKey)),
        licenseLastInfo: lastInfo,
        source: reason,
      );
      if (!data.hasAnyCriticalValue) return false;
      await saveBundle(data, reason: reason);
      await log(
        'bundle_saved reason=$reason businessId=${_mask(data.businessId)} '
        'terminalId=${_mask(data.terminalId)} licenseKey=${_maskLicense(data.licenseKey)}',
      );
      return true;
    } catch (e, st) {
      await log('bundle_save_failed reason=$reason error=$e\n$st');
      return false;
    }
  }

  Future<void> saveBundle(
    IdentityRecoveryBundleData data, {
    required String reason,
  }) {
    _queue = _queue.then((_) => _saveBundleImpl(data, reason: reason));
    return _queue;
  }

  Future<IdentityRecoveryBundleData?> loadBestAvailable() async {
    final candidates = <File>[
      await primaryFile(),
      await backupFile(),
      await documentsMirrorFile(),
      await documentsMirrorBackupFile(),
    ];

    for (final file in candidates) {
      final data = await _readBundle(file);
      if (data == null) continue;
      final validation = validateBundle(data);
      if (validation == null) return data;
      await log('bundle_invalid path=${file.path} reason=$validation');
    }
    return null;
  }

  Future<IdentityRecoveryBundleData?> loadFromFile(File file) async {
    final data = await _readBundle(file);
    if (data == null) return null;
    final validation = validateBundle(data);
    if (validation != null) {
      await log('bundle_file_invalid path=${file.path} reason=$validation');
      return null;
    }
    return data;
  }

  String? validateBundle(IdentityRecoveryBundleData data) {
    if (!data.hasAnyCriticalValue) return 'empty_bundle';
    if (!_notBlank(data.checksum)) return 'missing_checksum';
    if (data.checksum != _checksumFor(data.toJson(includeChecksum: false))) {
      return 'checksum_mismatch';
    }
    if (data.businessId != null && data.businessId!.trim().isEmpty) {
      return 'blank_business_id';
    }
    if (data.terminalId != null && data.terminalId!.trim().isEmpty) {
      return 'blank_terminal_id';
    }
    final lastInfo = data.licenseLastInfo;
    if (_notBlank(lastInfo)) {
      final parsed = _decodeJsonObject(lastInfo!);
      if (parsed == null) return 'license_last_info_not_parseable';
      final infoBusinessId = _businessIdFromLastInfo(lastInfo);
      if (_notBlank(infoBusinessId) &&
          _notBlank(data.businessId) &&
          infoBusinessId != data.businessId) {
        return 'license_business_id_conflict';
      }
    }
    return null;
  }

  Future<bool> recoverToSharedPreferences(String reason) async {
    final data = await loadBestAvailable();
    if (data == null) {
      if (await hasPriorInstallationEvidence()) {
        await markRecoveryRequired('${reason}_no_valid_bundle');
        await log('recovery_required reason=${reason}_no_valid_bundle');
      }
      return false;
    }
    return restoreBundleToSharedPreferences(data, reason: reason);
  }

  Future<bool> restoreBundleToSharedPreferences(
    IdentityRecoveryBundleData data, {
    required String reason,
    bool allowBusinessIdOverwrite = false,
  }) async {
    final validation = validateBundle(data);
    if (validation != null) {
      await log(
        'restore_blocked_invalid reason=$reason validation=$validation',
      );
      return false;
    }

    final sp = await SharedPreferences.getInstance();
    final localBusinessId = _trimOrNull(sp.getString(businessIdKey));
    if (_notBlank(localBusinessId) &&
        _notBlank(data.businessId) &&
        localBusinessId != data.businessId &&
        !allowBusinessIdOverwrite) {
      await markRecoveryRequired('${reason}_business_id_conflict');
      await log(
        'restore_blocked_conflict reason=$reason '
        'local=${_mask(localBusinessId)} bundle=${_mask(data.businessId)}',
      );
      return false;
    }

    if (_notBlank(data.businessId) && !_notBlank(localBusinessId)) {
      await sp.setString(businessIdKey, data.businessId!.trim());
      await log(
        'business_id_restored reason=$reason businessId=${_mask(data.businessId)}',
      );
    }
    if (_notBlank(data.licenseLastInfo) &&
        !_notBlank(sp.getString(licenseLastInfoKey))) {
      await sp.setString(licenseLastInfoKey, data.licenseLastInfo!.trim());
      await log('license_last_info_restored reason=$reason');
    }
    if (_notBlank(data.licenseKey) && !_notBlank(sp.getString(licenseKeyKey))) {
      await sp.setString(licenseKeyKey, data.licenseKey!.trim());
      await log(
        'license_key_restored reason=$reason key=${_maskLicense(data.licenseKey)}',
      );
    }
    if (_notBlank(data.licenseDeviceId) &&
        !_notBlank(sp.getString(licenseDeviceIdKey))) {
      await sp.setString(licenseDeviceIdKey, data.licenseDeviceId!.trim());
      await log(
        'license_device_id_restored reason=$reason deviceId=${_mask(data.licenseDeviceId)}',
      );
    }
    if (_notBlank(data.terminalId) && !_notBlank(sp.getString(terminalIdKey))) {
      await sp.setString(terminalIdKey, data.terminalId!.trim());
      await log(
        'terminal_id_restored reason=$reason terminalId=${_mask(data.terminalId)}',
      );
    }

    await sp.remove(recoveryRequiredKey);
    await sp.remove(recoveryReasonKey);
    await saveFromCurrentState('recovery_$reason');
    return true;
  }

  Future<Map<String, Object?>> compareWithCurrentPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final bundle = await loadBestAvailable();
    return {
      'hasBundle': bundle != null,
      'bundleBusinessId': bundle?.businessId,
      'prefsBusinessId': _trimOrNull(sp.getString(businessIdKey)),
      'bundleTerminalId': bundle?.terminalId,
      'prefsTerminalId': _trimOrNull(sp.getString(terminalIdKey)),
      'bundleLicenseDeviceId': bundle?.licenseDeviceId,
      'prefsLicenseDeviceId': _trimOrNull(sp.getString(licenseDeviceIdKey)),
    };
  }

  Future<bool> hasReliableIdentity() async {
    final bundle = await loadBestAvailable();
    return bundle?.hasReliableIdentity == true;
  }

  Future<bool> hasPriorInstallationEvidence() async {
    final bundle = await loadBestAvailable();
    if (bundle != null &&
        (bundle.hasReliableIdentity ||
            _notBlank(bundle.licenseDeviceId) ||
            _notBlank(bundle.licenseLastInfo))) {
      return true;
    }
    if (await hasCorruptPreferencesQuarantine()) return true;
    final support = await getApplicationSupportDirectory();
    final licenseFallback = File(
      p.join(support.path, 'FullPOS', 'license.dat'),
    );
    if (await licenseFallback.exists()) return true;
    final appData = Platform.isWindows ? Platform.environment['APPDATA'] : null;
    if (appData != null && appData.trim().isNotEmpty) {
      final appDataDir = Directory(appData.trim());
      if (p.equals(support.path, appDataDir.path) ||
          p.isWithin(appDataDir.path, support.path)) {
        final license = File(p.join(appDataDir.path, 'FullPOS', 'license.dat'));
        if (await license.exists()) return true;
      }
    }
    return false;
  }

  Future<bool> hasCorruptPreferencesQuarantine() async {
    final candidates = await sharedPreferencesCandidateFiles();
    for (final file in candidates) {
      final dir = file.parent;
      if (!await dir.exists()) continue;
      await for (final entity in dir.list()) {
        if (entity is File &&
            p.basename(entity.path).startsWith(p.basename(file.path)) &&
            entity.path.contains('.corrupt_')) {
          return true;
        }
      }
    }
    return false;
  }

  Future<List<File>> sharedPreferencesCandidateFiles() async {
    final supportDir = await getApplicationSupportDirectory();
    return <File>[
      File(p.join(supportDir.path, 'shared_preferences.json')),
      File(
        p.join(
          supportDir.path,
          'shared_preferences',
          'shared_preferences.json',
        ),
      ),
      File(p.join(supportDir.path, 'flutter_shared_preferences.json')),
    ];
  }

  Future<void> markRecoveryRequired(String reason) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(recoveryRequiredKey, true);
      await sp.setString(recoveryReasonKey, reason);
    } catch (_) {
      // If prefs cannot be opened, the caller is already in recovery flow.
    }
  }

  Future<bool> isRecoveryRequired() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(recoveryRequiredKey) == true;
    } catch (_) {
      return true;
    }
  }

  Future<void> quarantineInvalidBundle(String reason) async {
    final files = <File>[
      await primaryFile(),
      await backupFile(),
      await documentsMirrorFile(),
      await documentsMirrorBackupFile(),
    ];
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    for (final file in files) {
      if (!await file.exists()) continue;
      final target = File('${file.path}.bad_$stamp');
      try {
        await file.rename(target.path);
      } catch (_) {
        try {
          await file.copy(target.path);
          await file.delete();
        } catch (_) {}
      }
    }
    await log('bundle_quarantined reason=$reason');
  }

  Future<void> log(String message) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final logDir = Directory(p.join(supportDir.path, 'logs'));
      if (!await logDir.exists()) await logDir.create(recursive: true);
      final file = File(p.join(logDir.path, 'identity_recovery.log'));
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // Logging must never block recovery.
    }
  }

  Future<void> _saveBundleImpl(
    IdentityRecoveryBundleData data, {
    required String reason,
  }) async {
    final validation = validateBundle(data);
    if (validation != null) {
      await log('bundle_save_blocked reason=$reason validation=$validation');
      return;
    }

    final primary = await primaryFile();
    final backup = await backupFile();
    await _safeWrite(primary: primary, backup: backup, data: data);

    final mirror = await documentsMirrorFile();
    final mirrorBackup = await documentsMirrorBackupFile();
    await _safeWrite(primary: mirror, backup: mirrorBackup, data: data);
  }

  Future<void> _safeWrite({
    required File primary,
    required File backup,
    required IdentityRecoveryBundleData data,
  }) async {
    if (!await primary.parent.exists()) {
      await primary.parent.create(recursive: true);
    }
    final tmp = File('${primary.path}.tmp');
    final raw = const JsonEncoder.withIndent('  ').convert(data.toJson());
    await tmp.writeAsString(raw, flush: true);
    final readBack = await _readBundle(tmp);
    if (readBack == null || validateBundle(readBack) != null) {
      try {
        await tmp.delete();
      } catch (_) {}
      throw const IdentityRecoveryException('tmp bundle validation failed');
    }
    if (await primary.exists()) {
      try {
        await primary.copy(backup.path);
      } catch (_) {}
    }
    try {
      if (await primary.exists()) await primary.delete();
      await tmp.rename(primary.path);
    } catch (_) {
      await tmp.copy(primary.path);
      await tmp.delete();
    }
  }

  Future<IdentityRecoveryBundleData?> _readBundle(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return IdentityRecoveryBundleData.fromJson(
        decoded.cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<IdentityRecoveryBundleData> _buildData({
    required String? businessId,
    required String? licenseKey,
    required String? licenseDeviceId,
    required String? terminalId,
    required String? licenseLastInfo,
    required String source,
  }) async {
    final existing = await loadBestAvailable();
    final now = DateTime.now().toUtc();
    final data = IdentityRecoveryBundleData(
      businessId: businessId,
      licenseKey: licenseKey,
      licenseDeviceId: licenseDeviceId,
      terminalId: terminalId,
      licenseLastInfo: licenseLastInfo,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      source: source,
      appVersion: _kAppVersion,
      checksum: '',
    );
    return data.copyWith(
      checksum: _checksumFor(data.toJson(includeChecksum: false)),
    );
  }

  Future<Directory> _identityDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'identity'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _documentsIdentityDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'FULLPOS_BACKUPS', 'identity'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

String _checksumFor(Map<String, dynamic> map) {
  final raw = jsonEncode(_sortJson(map));
  return sha256.convert(utf8.encode(raw)).toString();
}

dynamic _sortJson(dynamic value) {
  if (value is Map) {
    final keys = value.keys.map((e) => e.toString()).toList()..sort();
    return {for (final key in keys) key: _sortJson(value[key])};
  }
  if (value is List) return value.map(_sortJson).toList();
  return value;
}

Map<String, dynamic>? _decodeJsonObject(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {}
  return null;
}

String? _businessIdFromLastInfo(String? raw) {
  if (!_notBlank(raw)) return null;
  final decoded = _decodeJsonObject(raw!);
  if (decoded == null) return null;
  final value = decoded['businessId'] ?? decoded['business_id'];
  return _nullableTrim(value);
}

String? _nullableTrim(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

String? _trimOrNull(String? value) => _nullableTrim(value);

bool _notBlank(String? value) => value != null && value.trim().isNotEmpty;

String _mask(String? value) {
  final v = value ?? '';
  if (v.length <= 8) return v.isEmpty ? '(empty)' : '****';
  return '${v.substring(0, 4)}****${v.substring(v.length - 4)}';
}

String _maskLicense(String? value) {
  final v = value ?? '';
  if (v.length <= 6) return v.isEmpty ? '(empty)' : '****';
  return '${v.substring(0, 3)}****${v.substring(v.length - 3)}';
}
