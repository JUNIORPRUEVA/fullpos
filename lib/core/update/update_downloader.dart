import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_update_policy.dart';
import 'installer_verifier.dart';

typedef DownloadProgress = void Function(int received, int? total);

class UpdateDownloader {
  UpdateDownloader({InstallerVerifier? verifier})
    : _verifier = verifier ?? InstallerVerifier();

  final InstallerVerifier _verifier;
  HttpClient? _activeClient;
  Future<File>? _inFlight;

  bool get isDownloading => _inFlight != null;

  Future<Directory> updateRoot() async {
    final local = await getApplicationSupportDirectory();
    final normalized = p.normalize(local.path);
    final appDataIndex = normalized.toLowerCase().lastIndexOf(
      '${p.separator}appdata${p.separator}roaming',
    );
    final localAppData = appDataIndex >= 0
        ? '${normalized.substring(0, appDataIndex)}${p.separator}AppData${p.separator}Local'
        : (Platform.environment['LOCALAPPDATA'] ?? local.path);
    return Directory(p.join(localAppData, 'FullPOS', 'updates'));
  }

  Future<File> download(
    AppUpdatePolicy policy, {
    required DownloadProgress onProgress,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _download(policy, onProgress: onProgress);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  void cancel() {
    _activeClient?.close(force: true);
    _activeClient = null;
  }

  Future<File> _download(
    AppUpdatePolicy policy, {
    required DownloadProgress onProgress,
  }) async {
    final root = await updateRoot();
    await root.create(recursive: true);
    final finalFile = File(p.join(root.path, policy.localInstallerFilename));
    final partFile = File('${finalFile.path}.part');

    if (await finalFile.exists()) {
      try {
        await _verifier.verify(
          file: finalFile,
          approvedRoot: root,
          policy: policy,
        );
        onProgress(await finalFile.length(), policy.installerSizeBytes);
        return finalFile;
      } catch (_) {
        await finalFile.delete();
      }
    }
    if (await partFile.exists()) await partFile.delete();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 20);
    _activeClient = client;
    IOSink? output;
    try {
      var uri = policy.installerUrl;
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        AppUpdatePolicy.validateInstallerUri(uri);
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 12));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'FullPOS Updater');
        response = await request.close().timeout(const Duration(seconds: 20));
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) {
            throw const HttpException('Redirect without location');
          }
          uri = uri.resolve(location);
          continue;
        }
        break;
      }
      if (response == null ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw HttpException('Download failed: HTTP ${response?.statusCode}');
      }

      final total = response.contentLength > 0
          ? response.contentLength
          : policy.installerSizeBytes;
      output = partFile.openWrite(mode: FileMode.writeOnly);
      var received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        output.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await output.flush();
      await output.close();
      output = null;

      await _verifier.verify(
        file: partFile,
        approvedRoot: root,
        policy: policy,
        allowPartialFilename: true,
      );
      await partFile.rename(finalFile.path);
      await _cleanObsoleteInstallers(root, keep: finalFile);
      return finalFile;
    } catch (_) {
      await output?.close();
      if (await partFile.exists()) await partFile.delete();
      rethrow;
    } finally {
      client.close(force: true);
      if (identical(_activeClient, client)) _activeClient = null;
    }
  }

  Future<void> _cleanObsoleteInstallers(
    Directory root, {
    required File keep,
  }) async {
    if (!await root.exists()) return;
    final files = await root
        .list()
        .where(
          (entity) =>
              entity is File &&
              p.basename(entity.path).startsWith('FullPOS-Setup-v') &&
              p.extension(entity.path).toLowerCase() == '.exe',
        )
        .cast<File>()
        .toList();
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (final file in files.skip(2)) {
      if (p.equals(file.path, keep.path)) continue;
      await file.delete();
    }
  }
}
