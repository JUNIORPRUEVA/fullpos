import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_update_policy.dart';
import 'installer_verifier.dart';
import '../storage/fullpos_paths.dart';

typedef DownloadProgress = void Function(int received, int? total);

class UpdateDownloadException implements Exception {
  const UpdateDownloadException({
    required this.message,
    required this.installerUrl,
    required this.destinationPath,
    this.statusCode,
    this.contentType,
    this.contentLength,
    this.partialFileSize,
    this.cause,
  });

  final String message;
  final Uri installerUrl;
  final String destinationPath;
  final int? statusCode;
  final String? contentType;
  final int? contentLength;
  final int? partialFileSize;
  final Object? cause;

  String get supportDetails => [
    'Installer URL: $installerUrl',
    if (statusCode != null) 'HTTP status code: $statusCode',
    if (contentType != null) 'Content-Type: $contentType',
    if (contentLength != null) 'Content-Length: $contentLength',
    'Destination path: $destinationPath',
    if (partialFileSize != null) 'Partial file size: $partialFileSize',
    'Exception type: ${cause?.runtimeType ?? runtimeType}',
    'Exception message: ${cause ?? message}',
  ].join('\n');

  @override
  String toString() => '$message\n$supportDetails';
}

class UpdateDownloader {
  UpdateDownloader({InstallerVerifier? verifier})
    : _verifier = verifier ?? InstallerVerifier();

  final InstallerVerifier _verifier;
  HttpClient? _activeClient;
  Future<File>? _inFlight;

  bool get isDownloading => _inFlight != null;

  Future<Directory> updateRoot() async {
    return FullPosPaths.updatesDir();
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
      Uri lastUri = uri;
      for (var redirects = 0; redirects <= 5; redirects++) {
        AppUpdatePolicy.validateInstallerUri(uri);
        lastUri = uri;
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
        throw UpdateDownloadException(
          message: 'Download failed',
          installerUrl: lastUri,
          destinationPath: finalFile.path,
          statusCode: response?.statusCode,
          contentType: response?.headers.contentType?.toString(),
          contentLength: response?.contentLength,
        );
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

      try {
        await _verifier.verify(
          file: partFile,
          approvedRoot: root,
          policy: policy,
          allowPartialFilename: true,
        );
      } catch (error) {
        throw UpdateDownloadException(
          message: 'Downloaded installer verification failed',
          installerUrl: lastUri,
          destinationPath: finalFile.path,
          statusCode: response.statusCode,
          contentType: response.headers.contentType?.toString(),
          contentLength: total,
          partialFileSize: await partFile.exists()
              ? await partFile.length()
              : 0,
          cause: error,
        );
      }
      await partFile.rename(finalFile.path);
      await _cleanObsoleteInstallers(root, keep: finalFile);
      return finalFile;
    } on UpdateDownloadException {
      await output?.close();
      if (await partFile.exists()) await partFile.delete();
      rethrow;
    } catch (error) {
      final partialSize = await partFile.exists() ? await partFile.length() : 0;
      await output?.close();
      if (await partFile.exists()) await partFile.delete();
      throw UpdateDownloadException(
        message: 'Download failed',
        installerUrl: policy.installerUrl,
        destinationPath: finalFile.path,
        partialFileSize: partialSize,
        cause: error,
      );
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
