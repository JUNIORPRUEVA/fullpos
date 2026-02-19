import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../backup/backup_paths.dart';
import '../backup/backup_zip.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';
import '../logging/app_logger.dart';
import '../../features/settings/data/business_settings_model.dart';
import '../../features/settings/data/business_settings_repository.dart';

class SupportLogsUploadResult {
  const SupportLogsUploadResult({
    required this.ok,
    required this.zipPath,
    this.ticketId,
    this.serverMessage,
  });

  final bool ok;
  final String zipPath;
  final String? ticketId;
  final String? serverMessage;
}

class SupportLogsService {
  SupportLogsService._();

  static final SupportLogsService instance = SupportLogsService._();

  static const int _maxFiles = 200;
  static const int _maxTotalBytes = 25 * 1024 * 1024; // 25MB

  /// Crea un ZIP local con logs/diagnóstico para soporte.
  ///
  /// No sube nada a ningún backend. El ZIP se guarda en `FULLPOS_LOGS/`.
  Future<String> createZipOnly({String? errorMessage}) {
    return _createSupportZip(errorMessage: errorMessage);
  }

  Future<SupportLogsUploadResult> createZipAndUpload({
    String? errorMessage,
  }) async {
    final zipPath = await _createSupportZip(errorMessage: errorMessage);

    try {
      final settings = await _tryLoadSettings();
      final baseUrl = _resolveBaseUrl(settings);
      final cloudKey = settings?.cloudApiKey?.trim();

      final api = ApiClient(baseUrl: baseUrl);
      final uri = api.uri('/api/support/logs');
      final request = http.MultipartRequest('POST', uri);
      if (cloudKey != null && cloudKey.isNotEmpty) {
        request.headers['x-cloud-key'] = cloudKey;
      }

      request.fields['appVersion'] = AppConfig.appVersion;
      request.fields['os'] = Platform.operatingSystem;
      request.fields['osVersion'] = Platform.operatingSystemVersion;
      if (settings?.rnc != null && settings!.rnc!.trim().isNotEmpty) {
        request.fields['rnc'] = settings.rnc!.trim();
      }
      if (settings?.cloudCompanyId != null &&
          settings!.cloudCompanyId!.trim().isNotEmpty) {
        request.fields['cloudCompanyId'] = settings.cloudCompanyId!.trim();
      }
      if (errorMessage != null && errorMessage.trim().isNotEmpty) {
        request.fields['errorMessage'] = errorMessage.trim();
      }

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          zipPath,
          contentType: MediaType('application', 'zip'),
        ),
      );

      final response = await api.sendMultipart(
        request,
        timeout: const Duration(seconds: 45),
      );

      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Support logs upload failed status=${response.statusCode} body=$body',
          module: 'support',
        );
        return SupportLogsUploadResult(
          ok: false,
          zipPath: zipPath,
          serverMessage:
              _tryExtractMessage(body) ??
              'No se pudo enviar los logs (status ${response.statusCode}).',
        );
      }

      String? ticketId;
      String? message;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          ticketId = decoded['ticketId']?.toString();
          message = decoded['message']?.toString();
        }
      } catch (_) {
        // Ignore invalid JSON.
      }

      await AppLogger.instance.logInfo(
        'Support logs uploaded ok ticketId=${ticketId ?? 'n/a'}',
        module: 'support',
      );

      return SupportLogsUploadResult(
        ok: true,
        zipPath: zipPath,
        ticketId: ticketId,
        serverMessage: message,
      );
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Support logs upload exception: $e',
        module: 'support',
      );
      return SupportLogsUploadResult(
        ok: false,
        zipPath: zipPath,
        serverMessage: 'No se pudo conectar con el servidor de soporte.',
      );
    }
  }

  Future<String> _createSupportZip({String? errorMessage}) async {
    final docs = await BackupPaths.documentsDir();
    final outDir = Directory(p.join(docs.path, 'FULLPOS_LOGS'));
    if (!await outDir.exists()) await outDir.create(recursive: true);

    final now = DateTime.now();
    final stamp = now
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '');
    final zipPath = p.join(outDir.path, 'support_logs_$stamp.zip');

    final collected = await _collectLogFiles(excludePaths: {zipPath});

    final meta = <String, dynamic>{
      'ts': now.toIso8601String(),
      'appVersion': AppConfig.appVersion,
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'errorMessage': errorMessage,
      'fileCount': collected.length,
      'note': 'Este paquete NO incluye la base de datos.',
    };

    final files = <Map<String, String>>[];
    for (final entry in collected) {
      files.add({'sourcePath': entry.sourcePath, 'zipPath': entry.zipPath});
    }

    await BackupZip.createZip(
      outputZipPath: zipPath,
      files: files,
      metaJson: jsonEncode(meta),
    );

    return zipPath;
  }

  Future<BusinessSettings?> _tryLoadSettings() async {
    try {
      return await BusinessSettingsRepository().loadSettings();
    } catch (_) {
      return null;
    }
  }

  String _resolveBaseUrl(BusinessSettings? settings) {
    final endpoint = settings?.cloudEndpoint?.trim() ?? '';
    if (endpoint.isNotEmpty) return AppConfig.normalizeBaseUrl(endpoint);
    return AppConfig.apiBaseUrl;
  }

  String? _tryExtractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] != null) {
        return decoded['message']?.toString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<_SupportLogFile>> _collectLogFiles({
    required Set<String> excludePaths,
  }) async {
    final results = <_SupportLogFile>[];

    final supportDir = await getApplicationSupportDirectory();
    final appLogsDir = Directory(p.join(supportDir.path, 'logs'));

    final docs = await BackupPaths.documentsDir();
    final docsLogsDir = Directory(p.join(docs.path, 'FULLPOS_LOGS'));

    Future<void> scanDir(Directory dir, String zipRoot) async {
      if (!await dir.exists()) return;

      final entities = dir.listSync(recursive: true, followLinks: false);
      for (final e in entities) {
        if (e is! File) continue;

        final full = e.path;
        if (excludePaths.contains(full)) continue;

        final lower = full.toLowerCase();
        if (lower.endsWith('.zip')) continue;

        final name = p.basename(full);
        if (name.startsWith('.')) continue;

        if (!_isLogLike(name)) continue;

        String relative;
        try {
          relative = p.relative(full, from: dir.path);
        } catch (_) {
          relative = name;
        }

        final zipPath = p.join(zipRoot, relative).replaceAll('\\', '/');
        results.add(_SupportLogFile(sourcePath: full, zipPath: zipPath));
      }
    }

    await scanDir(appLogsDir, 'app_support/logs');
    await scanDir(docsLogsDir, 'documents/FULLPOS_LOGS');

    // De-duplicar por path.
    final unique = <String, _SupportLogFile>{};
    for (final r in results) {
      unique[r.sourcePath] = r;
    }

    final deduped = unique.values.toList(growable: false);
    deduped.sort((a, b) {
      final fa = File(a.sourcePath);
      final fb = File(b.sourcePath);
      try {
        final ma = fa.lastModifiedSync();
        final mb = fb.lastModifiedSync();
        return mb.compareTo(ma); // newest first
      } catch (_) {
        return 0;
      }
    });

    // Enforce caps by newest-first.
    final capped = <_SupportLogFile>[];
    var totalBytes = 0;
    for (final f in deduped) {
      if (capped.length >= _maxFiles) break;
      try {
        final file = File(f.sourcePath);
        final len = file.lengthSync();
        if (len <= 0) continue;
        if (totalBytes + len > _maxTotalBytes) continue;
        totalBytes += len;
        capped.add(f);
      } catch (_) {
        // Ignore unreadable files.
      }
    }

    return capped;
  }

  bool _isLogLike(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.log') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.json');
  }
}

class _SupportLogFile {
  const _SupportLogFile({required this.sourcePath, required this.zipPath});

  final String sourcePath;
  final String zipPath;
}
