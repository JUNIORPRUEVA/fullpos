import 'dart:convert';

enum BackupMode { local, cloud }

enum BackupStatus { success, failed, pendingUpload, inProgress }

enum BackupTrigger { manual, autoWindowClose, autoLifecycle }

class BackupMeta {
  const BackupMeta({
    required this.createdAtIso,
    required this.trigger,
    required this.appVersion,
    required this.platform,
    required this.dbFileName,
    required this.includedPaths,
    required this.dbVersion,
    this.checksumSha256,
    this.notes,
    this.integrityCheckOk,
  });

  final String createdAtIso;
  final BackupTrigger trigger;
  final String appVersion;
  final String platform;
  final String dbFileName;
  final List<String> includedPaths;
  final int dbVersion;
  final String? checksumSha256;
  final String? notes;
  final bool? integrityCheckOk;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAtIso,
    'trigger': trigger.name,
    'appVersion': appVersion,
    'platform': platform,
    'dbFileName': dbFileName,
    'includedPaths': includedPaths,
    'dbVersion': dbVersion,
    if (checksumSha256 != null) 'checksumSha256': checksumSha256,
    if (notes != null) 'notes': notes,
    if (integrityCheckOk != null) 'integrityCheckOk': integrityCheckOk,
  };

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}

class BackupResult {
  const BackupResult({
    required this.ok,
    this.path,
    this.messageUser,
    this.messageDev,
    this.integrityCheckOk,
    this.checksumSha256,
    this.sizeBytes,
  });

  final bool ok;
  final String? path;
  final String? messageUser;
  final String? messageDev;
  final bool? integrityCheckOk;
  final String? checksumSha256;
  final int? sizeBytes;
}

class BackupHistoryEntry {
  BackupHistoryEntry({
    required this.id,
    required this.empresaId,
    required this.createdAtMs,
    required this.mode,
    required this.status,
    required this.dbVersion,
    required this.appVersion,
    this.deviceId,
    this.usuarioId,
    this.filePath,
    this.cloudBackupId,
    this.sizeBytes,
    this.checksumSha256,
    this.notes,
    this.errorMessage,
  });

  final String id;
  final String empresaId;
  final int createdAtMs;
  final BackupMode mode;
  final BackupStatus status;
  final int dbVersion;
  final String appVersion;
  final String? deviceId;
  final int? usuarioId;
  final String? filePath;
  final String? cloudBackupId;
  final int? sizeBytes;
  final String? checksumSha256;
  final String? notes;
  final String? errorMessage;

  BackupHistoryEntry copyWith({
    BackupMode? mode,
    BackupStatus? status,
    String? filePath,
    bool clearFilePath = false,
    String? cloudBackupId,
    int? sizeBytes,
    String? checksumSha256,
    String? notes,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return BackupHistoryEntry(
      id: id,
      empresaId: empresaId,
      createdAtMs: createdAtMs,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      dbVersion: dbVersion,
      appVersion: appVersion,
      deviceId: deviceId,
      usuarioId: usuarioId,
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      cloudBackupId: cloudBackupId ?? this.cloudBackupId,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      checksumSha256: checksumSha256 ?? this.checksumSha256,
      notes: notes ?? this.notes,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'empresa_id': empresaId,
    'created_at': createdAtMs,
    'mode': mode.name.toUpperCase(),
    'status': _statusToDb(status),
    'file_path': filePath,
    'cloud_backup_id': cloudBackupId,
    'size_bytes': sizeBytes,
    'checksum_sha256': checksumSha256,
    'db_version': dbVersion,
    'app_version': appVersion,
    'notes': notes,
    'error_message': errorMessage,
    'device_id': deviceId,
    'usuario_id': usuarioId,
  };

  static BackupHistoryEntry fromMap(Map<String, dynamic> map) {
    return BackupHistoryEntry(
      id: map['id'] as String,
      empresaId: map['empresa_id'] as String,
      createdAtMs: map['created_at'] as int,
      mode: _modeFromDb(map['mode'] as String?),
      status: _statusFromDb(map['status'] as String?),
      filePath: map['file_path'] as String?,
      cloudBackupId: map['cloud_backup_id'] as String?,
      sizeBytes: map['size_bytes'] as int?,
      checksumSha256: map['checksum_sha256'] as String?,
      dbVersion: map['db_version'] as int? ?? 0,
      appVersion: map['app_version'] as String? ?? 'unknown',
      notes: map['notes'] as String?,
      errorMessage: map['error_message'] as String?,
      deviceId: map['device_id'] as String?,
      usuarioId: map['usuario_id'] as int?,
    );
  }

  static String _statusToDb(BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return 'SUCCESS';
      case BackupStatus.failed:
        return 'FAILED';
      case BackupStatus.pendingUpload:
        return 'PENDING_UPLOAD';
      case BackupStatus.inProgress:
        return 'IN_PROGRESS';
    }
  }

  static BackupStatus _statusFromDb(String? value) {
    switch (value) {
      case 'SUCCESS':
        return BackupStatus.success;
      case 'FAILED':
        return BackupStatus.failed;
      case 'PENDING_UPLOAD':
        return BackupStatus.pendingUpload;
      case 'IN_PROGRESS':
      default:
        return BackupStatus.inProgress;
    }
  }

  static BackupMode _modeFromDb(String? value) {
    switch (value) {
      case 'CLOUD':
        return BackupMode.cloud;
      case 'LOCAL':
      default:
        return BackupMode.local;
    }
  }
}

class DangerActionLogEntry {
  DangerActionLogEntry({
    required this.id,
    required this.empresaId,
    required this.usuarioId,
    required this.action,
    required this.createdAtMs,
    required this.confirmedByPhrase,
    required this.result,
    this.errorMessage,
  });

  final String id;
  final String empresaId;
  final int usuarioId;
  final String action;
  final int createdAtMs;
  final String confirmedByPhrase;
  final String result;
  final String? errorMessage;

  Map<String, dynamic> toMap() => {
    'id': id,
    'empresa_id': empresaId,
    'usuario_id': usuarioId,
    'action': action,
    'created_at': createdAtMs,
    'confirmed_by_phrase': confirmedByPhrase,
    'result': result,
    'error_message': errorMessage,
  };

  factory DangerActionLogEntry.fromMap(Map<String, dynamic> map) {
    return DangerActionLogEntry(
      id: map['id'] as String,
      empresaId: map['empresa_id'] as String,
      usuarioId: map['usuario_id'] as int? ?? 0,
      action: map['action'] as String? ?? 'UNKNOWN',
      createdAtMs: map['created_at'] as int? ?? 0,
      confirmedByPhrase: map['confirmed_by_phrase'] as String? ?? '',
      result: map['result'] as String? ?? 'UNKNOWN',
      errorMessage: map['error_message'] as String?,
    );
  }
}
