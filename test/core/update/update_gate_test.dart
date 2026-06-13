import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/errors/error_handler.dart';
import 'package:fullpos/core/update/app_update_coordinator.dart';
import 'package:fullpos/core/update/app_update_policy.dart';
import 'package:fullpos/core/update/app_update_repository.dart';
import 'package:fullpos/core/update/app_version.dart';
import 'package:fullpos/core/update/update_downloader.dart';
import 'package:fullpos/core/update/update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PolicyRepository extends AppUpdateRepository {
  _PolicyRepository(this.policy);

  final AppUpdatePolicy policy;

  @override
  Future<AppUpdatePolicy> fetchPolicy() async => policy;
}

class _TrackingDownloader extends UpdateDownloader {
  int calls = 0;
  bool active = false;
  final completer = Completer<File>();

  @override
  bool get isDownloading => active;

  @override
  Future<File> download(
    AppUpdatePolicy policy, {
    required DownloadProgress onProgress,
  }) {
    calls++;
    active = true;
    return completer.future.whenComplete(() => active = false);
  }
}

AppUpdatePolicy _policy({required bool mandatory}) {
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

AppUpdateCoordinator _coordinator(
  AppUpdatePolicy policy, {
  UpdateDownloader? downloader,
}) {
  return AppUpdateCoordinator.testing(
    repository: _PolicyRepository(policy),
    downloader: downloader,
    installedVersionLoader: () async => AppVersion.parse('1.0.1+5'),
  );
}

Widget _app(AppUpdateCoordinator coordinator) {
  return MaterialApp(
    navigatorKey: ErrorHandler.navigatorKey,
    home: UpdateGate(
      coordinator: coordinator,
      child: const Scaffold(body: Text('FullPOS listo')),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('optional update opens once and Más tarde continues', (
    tester,
  ) async {
    final coordinator = _coordinator(_policy(mandatory: false));
    await tester.pumpWidget(_app(coordinator));

    await coordinator.check();
    await tester.pumpAndSettle();

    expect(find.text('Nueva versión disponible'), findsOneWidget);
    expect(find.text('Actualizar ahora'), findsOneWidget);
    expect(find.text('Más tarde'), findsOneWidget);

    await coordinator.check(manual: true);
    await tester.pumpAndSettle();
    expect(find.text('Nueva versión disponible'), findsOneWidget);

    await tester.tap(find.text('Más tarde'));
    await tester.pumpAndSettle();

    expect(find.text('Nueva versión disponible'), findsNothing);
    expect(find.text('FullPOS listo'), findsOneWidget);
    expect(coordinator.state.phase, AppUpdatePhase.current);
  });

  testWidgets('Actualizar ahora starts the existing download flow', (
    tester,
  ) async {
    final downloader = _TrackingDownloader();
    final coordinator = _coordinator(
      _policy(mandatory: false),
      downloader: downloader,
    );
    await tester.pumpWidget(_app(coordinator));

    await coordinator.check();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actualizar ahora'));
    await tester.pumpAndSettle();

    expect(downloader.calls, 1);
    expect(coordinator.state.phase, AppUpdatePhase.downloading);
    expect(find.text('Nueva versión disponible'), findsNothing);

    downloader.completer.completeError(StateError('test cleanup'));
    await tester.pumpAndSettle();
  });

  testWidgets('mandatory update replaces and blocks application content', (
    tester,
  ) async {
    final coordinator = _coordinator(_policy(mandatory: true));
    await tester.pumpWidget(_app(coordinator));

    await coordinator.check();
    await tester.pumpAndSettle();

    expect(find.text('Actualización requerida'), findsOneWidget);
    expect(find.text('FullPOS listo'), findsNothing);
    expect(find.text('Más tarde'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Actualización requerida'), findsOneWidget);
    expect(find.text('FullPOS listo'), findsNothing);
  });
}
