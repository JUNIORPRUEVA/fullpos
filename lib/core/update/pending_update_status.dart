import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_update_policy.dart';
import 'app_version.dart';

class PendingUpdateStatus {
  const PendingUpdateStatus({
    required this.version,
    required this.build,
    required this.status,
    required this.startedAt,
    required this.installerPath,
  });

  final String version;
  final int build;
  final String status;
  final DateTime startedAt;
  final String installerPath;

  AppVersion get targetVersion => AppVersion.parse(version, buildNumber: build);

  Map<String, dynamic> toJson() => {
    'version': version,
    'build': build,
    'status': status,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'installerPath': installerPath,
  };

  factory PendingUpdateStatus.fromJson(Map<String, dynamic> json) {
    return PendingUpdateStatus(
      version: json['version'].toString(),
      build: json['build'] is num
          ? (json['build'] as num).toInt()
          : int.parse(json['build'].toString()),
      status: json['status'].toString(),
      startedAt: DateTime.parse(json['startedAt'].toString()).toUtc(),
      installerPath: json['installerPath'].toString(),
    );
  }
}

class PendingUpdateStatusStore {
  const PendingUpdateStatusStore({required this.updateRoot});

  final Future<Directory> Function() updateRoot;

  Future<File> file({bool createRoot = true}) async {
    final root = await updateRoot();
    if (createRoot) await root.create(recursive: true);
    return File(p.join(root.path, 'pending_update_status.json'));
  }

  Future<void> markInstalling({
    required AppUpdatePolicy policy,
    required File installer,
  }) async {
    final status = PendingUpdateStatus(
      version: policy.latest.semantic,
      build: policy.latest.build,
      status: 'installing',
      startedAt: DateTime.now().toUtc(),
      installerPath: installer.path,
    );
    await (await file()).writeAsString(
      jsonEncode(status.toJson()),
      flush: true,
    );
  }

  Future<PendingUpdateStatus?> read() async {
    final root = await updateRoot();
    if (!await root.exists()) return null;
    final statusFile = await file(createRoot: false);
    if (!await statusFile.exists()) return null;
    final decoded = jsonDecode(await statusFile.readAsString());
    if (decoded is! Map<String, dynamic>) return null;
    return PendingUpdateStatus.fromJson(decoded);
  }

  Future<void> writeStatus(PendingUpdateStatus status, String value) async {
    final updated = PendingUpdateStatus(
      version: status.version,
      build: status.build,
      status: value,
      startedAt: status.startedAt,
      installerPath: status.installerPath,
    );
    await (await file()).writeAsString(
      jsonEncode(updated.toJson()),
      flush: true,
    );
  }

  Future<void> delete() async {
    final statusFile = await file();
    if (await statusFile.exists()) await statusFile.delete();
  }
}
