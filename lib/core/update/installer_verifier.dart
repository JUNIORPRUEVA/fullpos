import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'app_update_policy.dart';

class InstallerVerificationException implements Exception {
  const InstallerVerificationException(this.code);
  final String code;
}

class InstallerVerifier {
  Future<void> verify({
    required File file,
    required Directory approvedRoot,
    required AppUpdatePolicy policy,
    bool allowPartialFilename = false,
  }) async {
    final root = p.normalize(p.absolute(approvedRoot.path));
    final path = p.normalize(p.absolute(file.path));
    final basename = p.basename(path);
    final validFilename =
        basename == policy.installerFilename ||
        (allowPartialFilename &&
            basename == '${policy.installerFilename}.part');
    if (!p.isWithin(root, path) || !validFilename || !await file.exists()) {
      throw const InstallerVerificationException('invalid_path');
    }

    final size = await file.length();
    if (size <= 0) {
      throw const InstallerVerificationException('empty_file');
    }
    if (policy.installerSizeBytes != null &&
        size != policy.installerSizeBytes) {
      throw const InstallerVerificationException('size_mismatch');
    }

    final prefix = await file
        .openRead(0, size < 512 ? size : 512)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    if (prefix.length < 2 || prefix[0] != 0x4d || prefix[1] != 0x5a) {
      throw const InstallerVerificationException('invalid_pe_header');
    }
    final textPrefix = utf8
        .decode(prefix, allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    if (textPrefix.startsWith('<!doctype html') ||
        textPrefix.startsWith('<html') ||
        textPrefix.startsWith('{') ||
        textPrefix.startsWith('[')) {
      throw const InstallerVerificationException('web_error_document');
    }

    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString().toLowerCase() != policy.sha256.toLowerCase()) {
      throw const InstallerVerificationException('sha256_mismatch');
    }
  }

  Future<bool> verifyWindowsPublisherSignature(File file) async {
    // Authenticode is intentionally not claimed until FullTech SRL signs builds.
    return false;
  }
}
