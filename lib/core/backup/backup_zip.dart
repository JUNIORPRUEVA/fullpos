import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class BackupZip {
  BackupZip._();

  static Future<void> createZip({
    required String outputZipPath,
    required List<Map<String, String>> files,
    required String metaJson,
  }) async {
    final outFile = File(outputZipPath);
    final outDir = outFile.parent;
    if (!await outDir.exists()) await outDir.create(recursive: true);

    if (await outFile.exists()) {
      await outFile.delete();
    }

    final encoder = ZipFileEncoder();
    encoder.create(outputZipPath);

    // Siempre incluir meta.
    final metaTemp = File(p.join(outDir.path, '__backup_meta.json'));
    await metaTemp.writeAsString(metaJson, flush: true);
    encoder.addFile(metaTemp, 'meta/backup.json');

    for (final entry in files) {
      final sourcePath = entry['sourcePath'];
      final zipPath = entry['zipPath'];
      if (sourcePath == null || zipPath == null) continue;

      final file = File(sourcePath);
      if (!await file.exists()) continue;
      encoder.addFile(file, zipPath);
    }

    encoder.close();

    try {
      await metaTemp.delete();
    } catch (_) {
      // Ignorar.
    }
  }

  static Future<void> extractZip({
    required String zipPath,
    required String outDirPath,
  }) async {
    final dir = Directory(outDirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final inputStream = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeBuffer(inputStream);
    inputStream.close();

    for (final file in archive.files) {
      final filename = file.name;
      final outPath = p.join(outDirPath, filename);
      if (file.isFile) {
        final outFile = File(outPath);
        if (!await outFile.parent.exists()) {
          await outFile.parent.create(recursive: true);
        }
        await outFile.writeAsBytes(file.content as List<int>, flush: true);
      } else {
        final outDir = Directory(outPath);
        if (!await outDir.exists()) await outDir.create(recursive: true);
      }
    }
  }

  static Future<List<String>> listEntries(String zipPath) async {
    final inputStream = InputFileStream(zipPath);
    final archive = ZipDecoder().decodeBuffer(inputStream);
    inputStream.close();
    return archive.files.map((f) => f.name).toList(growable: false);
  }
}
