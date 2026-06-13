import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/update/app_update_coordinator.dart';
import 'package:fullpos/core/update/app_update_policy.dart';
import 'package:fullpos/core/update/app_update_repository.dart';
import 'package:fullpos/core/update/app_version.dart';
import 'package:fullpos/core/update/installer_launcher.dart';
import 'package:fullpos/core/update/update_downloader.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppUpdatePolicy policy({bool mandatory = false}) {
  return AppUpdatePolicy.fromJson({
    'projectCode': 'fullpos',
    'platform': 'windows',
    'latestVersion': '1.0.2',
    'latestBuild': 6,
    'minimumSupportedVersion': '1.0.1',
    'minimumSupportedBuild': 5,
    'mandatory': mandatory,
    'enabled': true,
    'installerUrl':
        'https://github.com/JUNIORPRUEVA/fullpos-releases/releases/download/v1.0.2/FullPOS-Setup.exe',
    'installerFilename': 'FullPOS-Setup.exe',
    'installerSizeBytes': 100,
    'sha256': List<String>.filled(64, 'a').join(),
    'releaseTitle': 'FullPOS v1.0.2',
    'releaseNotes': ['Mejoras.'],
    'publishedAt': '2026-06-12T22:00:00Z',
  });
}

class _FakeRepository extends AppUpdateRepository {
  _FakeRepository({this.remote, this.cached, this.error});

  final AppUpdatePolicy? remote;
  final AppUpdatePolicy? cached;
  final Object? error;
  int calls = 0;
  Completer<void>? blocker;

  @override
  Future<AppUpdatePolicy> fetchPolicy() async {
    calls++;
    await blocker?.future;
    if (error != null) throw error!;
    return remote!;
  }

  @override
  Future<AppUpdatePolicy?> readValidatedCache() async => cached;
}

class _FakeDownloader extends UpdateDownloader {
  int calls = 0;
  bool active = false;
  final Completer<File> completer = Completer<File>();

  @override
  bool get isDownloading => active;

  @override
  Future<File> download(
    AppUpdatePolicy policy, {
    required DownloadProgress onProgress,
  }) {
    calls++;
    active = true;
    onProgress(50, 100);
    return completer.future.whenComplete(() => active = false);
  }
}

class _FakeLauncher extends InstallerLauncher {
  int calls = 0;
  bool active = false;
  final Completer<void> completer = Completer<void>();

  @override
  bool get isLaunching => active;

  @override
  Future<void> launch(File installer, AppUpdatePolicy policy) {
    calls++;
    active = true;
    return completer.future.whenComplete(() => active = false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('backend failure without cached mandatory policy allows use', () async {
    final repository = _FakeRepository(error: TimeoutException('offline'));
    final coordinator = AppUpdateCoordinator.testing(
      repository: repository,
      installedVersionLoader: () async => AppVersion.parse('1.0.1+5'),
    );
    await coordinator.check();
    expect(coordinator.state.phase, AppUpdatePhase.offline);
    expect(coordinator.state.isMandatory, isFalse);
  });

  test('cached mandatory policy remains enforced during outage', () async {
    final repository = _FakeRepository(
      error: TimeoutException('offline'),
      cached: policy(mandatory: true),
    );
    final coordinator = AppUpdateCoordinator.testing(
      repository: repository,
      installedVersionLoader: () async => AppVersion.parse('1.0.1+5'),
    );
    await coordinator.check();
    expect(coordinator.state.phase, AppUpdatePhase.mandatory);
    expect(coordinator.state.isMandatory, isTrue);
  });

  test('prevents duplicate update checks', () async {
    final repository = _FakeRepository(remote: policy())
      ..blocker = Completer<void>();
    final coordinator = AppUpdateCoordinator.testing(
      repository: repository,
      installedVersionLoader: () async => AppVersion.parse('1.0.1+5'),
    );
    final first = coordinator.check();
    final second = coordinator.check();
    await Future<void>.delayed(Duration.zero);
    expect(repository.calls, 1);
    repository.blocker!.complete();
    await Future.wait([first, second]);
    expect(repository.calls, 1);
  });

  test('prevents duplicate downloads and installer launches', () async {
    final downloader = _FakeDownloader();
    final launcher = _FakeLauncher();
    final coordinator = AppUpdateCoordinator.testing(
      repository: _FakeRepository(remote: policy()),
      downloader: downloader,
      launcher: launcher,
      installedVersionLoader: () async => AppVersion.parse('1.0.1+5'),
    );
    await coordinator.check();

    final firstDownload = coordinator.downloadAndInstall();
    final secondDownload = coordinator.downloadAndInstall();
    await Future<void>.delayed(Duration.zero);
    expect(downloader.calls, 1);

    final temp = await Directory.systemTemp.createTemp('fullpos_launch_test_');
    final installer = File(
      '${temp.path}${Platform.pathSeparator}FullPOS-Setup.exe',
    );
    await installer.writeAsBytes([0x4d, 0x5a]);
    downloader.completer.complete(installer);
    await Future.wait([firstDownload, secondDownload]);

    final firstLaunch = coordinator.launchInstaller();
    final secondLaunch = coordinator.launchInstaller();
    await Future<void>.delayed(Duration.zero);
    expect(launcher.calls, 1);
    launcher.completer.complete();
    await Future.wait([firstLaunch, secondLaunch]);
    await temp.delete(recursive: true);
  });
}
