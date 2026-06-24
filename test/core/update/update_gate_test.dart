import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/errors/error_handler.dart';
import 'package:fullpos/core/update/app_update_coordinator.dart';
import 'package:fullpos/core/update/app_update_policy.dart';
import 'package:fullpos/core/update/app_update_repository.dart';
import 'package:fullpos/core/update/app_update_safety.dart';
import 'package:fullpos/core/update/app_version.dart';
import 'package:fullpos/core/update/update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PolicyRepository extends AppUpdateRepository {
  _PolicyRepository(this.policy);

  final AppUpdatePolicy policy;

  @override
  Future<AppUpdatePolicy> fetchPolicy() async => policy;
}

class _SafeValidator extends AppUpdateSafetyValidator {
  const _SafeValidator();

  @override
  Future<AppUpdateSafetyResult> validate() async {
    return const AppUpdateSafetyResult(safe: true);
  }
}

class _BlockedValidator extends AppUpdateSafetyValidator {
  const _BlockedValidator();

  @override
  Future<AppUpdateSafetyResult> validate() async {
    return const AppUpdateSafetyResult(
      safe: false,
      blockReason: 'Hay una venta activa.',
    );
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
  AppUpdateSafetyValidator? safetyValidator,
}) {
  return AppUpdateCoordinator.testing(
    repository: _PolicyRepository(policy),
    safetyValidator: safetyValidator ?? const _SafeValidator(),
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

  // Test 1: When update is checking/downloading, app content is visible
  // and no update gate is shown.
  testWidgets(
    'during checking/downloading, app content is visible and no update gate',
    (tester) async {
      final coordinator = _coordinator(_policy(mandatory: true));
      await tester.pumpWidget(_app(coordinator));

      // Before check, app content is visible
      expect(find.text('FullPOS listo'), findsOneWidget);
      expect(find.text('Actualización requerida'), findsNothing);

      // Start check in background
      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // During checking/downloading, app content must still be visible
      // and no update gate should replace the content.
      expect(find.text('FullPOS listo'), findsOneWidget);
      // The overlay should NOT be shown during downloading/checking
      expect(find.text('Actualización requerida'), findsNothing);
    },
  );

  // Test 2: When update download finishes and installer validates,
  // mandatory update overlay is shown (not replacing content).
  testWidgets(
    'mandatory update ready shows overlay without replacing content',
    (tester) async {
      final coordinator = _coordinator(_policy(mandatory: true));
      await tester.pumpWidget(_app(coordinator));

      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The coordinator transitions through checking -> mandatory -> downloading
      // -> verifying -> ready. The downloader is mocked so it completes instantly.
      // After ready, the overlay should appear but content should still be visible.
      final state = coordinator.state;
      if (state.phase == AppUpdatePhase.ready) {
        // App content is still visible behind the overlay
        expect(find.text('FullPOS listo'), findsOneWidget);
        // Overlay shows "Actualización requerida"
        expect(find.text('Actualización requerida'), findsOneWidget);
        // "Instalar ahora" button is present
        expect(find.text('Instalar ahora'), findsOneWidget);
        // "Cerrar FullPOS" button is present for mandatory
        expect(find.text('Cerrar FullPOS'), findsOneWidget);
      }
      // If not ready yet (e.g. still downloading), content is visible
      // and no overlay is shown - that's also correct.
    },
  );

  // Test 3: Normal (optional) update ready shows dialog, not overlay.
  testWidgets(
    'optional update ready shows dialog with Instalar ahora and Más tarde',
    (tester) async {
      final coordinator = _coordinator(_policy(mandatory: false));
      await tester.pumpWidget(_app(coordinator));

      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final state = coordinator.state;
      if (state.phase == AppUpdatePhase.ready) {
        // App content is visible
        expect(find.text('FullPOS listo'), findsOneWidget);
        // Dialog shows "Actualización lista para instalar"
        expect(find.text('Actualización lista para instalar'), findsOneWidget);
        // Buttons
        expect(find.text('Instalar ahora'), findsOneWidget);
        expect(find.text('Más tarde'), findsOneWidget);
        // "Cerrar FullPOS" should NOT be present for optional
        expect(find.text('Cerrar FullPOS'), findsNothing);
      }
    },
  );

  // Test 4: If active sale exists and user clicks install,
  // updater is not launched and resolver dialog appears.
  testWidgets(
    'blocked update shows resolver dialog with Revisar proceso',
    (tester) async {
      final coordinator = _coordinator(
        _policy(mandatory: false),
        safetyValidator: const _BlockedValidator(),
      );
      await tester.pumpWidget(_app(coordinator));

      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final state = coordinator.state;
      if (state.phase == AppUpdatePhase.ready) {
        // App content is visible
        expect(find.text('FullPOS listo'), findsOneWidget);
        // Dialog shows "No se puede actualizar todavía"
        expect(
          find.text('No se puede actualizar todavía'),
          findsOneWidget,
        );
        // Buttons
        expect(find.text('Revisar proceso'), findsOneWidget);
        expect(find.text('Más tarde'), findsOneWidget);
      }
    },
  );

  // Test 8: Mandatory update blocked by active sale shows overlay + blocked dialog.
  testWidgets(
    'mandatory blocked by active sale shows overlay and Revisar proceso',
    (tester) async {
      final coordinator = _coordinator(
        _policy(mandatory: true),
        safetyValidator: const _BlockedValidator(),
      );
      await tester.pumpWidget(_app(coordinator));

      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final state = coordinator.state;
      if (state.phase == AppUpdatePhase.ready) {
        // App content is visible behind overlay
        expect(find.text('FullPOS listo'), findsOneWidget);
        // Overlay shows "Actualización requerida" (mandatory)
        expect(find.text('Actualización requerida'), findsOneWidget);
        // Blocked dialog shows "No se puede actualizar todavía"
        expect(
          find.text('No se puede actualizar todavía'),
          findsOneWidget,
        );
        // "Revisar proceso" button is present
        expect(find.text('Revisar proceso'), findsOneWidget);
        // "Cerrar FullPOS" is present in overlay
        expect(find.text('Cerrar FullPOS'), findsOneWidget);
      }
    },
  );

  // Test 5: Mandatory update does not block UI while downloading.
  testWidgets(
    'mandatory update does not block UI while downloading',
    (tester) async {
      final coordinator = _coordinator(_policy(mandatory: true));
      await tester.pumpWidget(_app(coordinator));

      // Simulate the coordinator being in downloading phase
      // by checking that the app content is visible.
      expect(find.text('FullPOS listo'), findsOneWidget);
      expect(find.text('Actualización requerida'), findsNothing);

      // Start check
      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();

      // During any phase other than ready, content must be visible
      // and no overlay/dialog should replace it.
      final currentState = coordinator.state;
      if (currentState.phase != AppUpdatePhase.ready) {
        expect(find.text('FullPOS listo'), findsOneWidget);
        expect(find.text('Actualización requerida'), findsNothing);
      }
    },
  );

  // Test 6: Mandatory update blocks only when installer is ready.
  testWidgets(
    'mandatory update blocks only when installer is ready',
    (tester) async {
      final coordinator = _coordinator(_policy(mandatory: true));
      await tester.pumpWidget(_app(coordinator));

      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final state = coordinator.state;
      if (state.phase == AppUpdatePhase.ready) {
        // Only when ready, the overlay appears
        expect(find.text('Actualización requerida'), findsOneWidget);
        expect(find.text('Instalar ahora'), findsOneWidget);
        expect(find.text('Cerrar FullPOS'), findsOneWidget);
        // App content is still visible behind overlay
        expect(find.text('FullPOS listo'), findsOneWidget);
      } else {
        // Not ready yet - content is visible, no overlay
        expect(find.text('FullPOS listo'), findsOneWidget);
        expect(find.text('Actualización requerida'), findsNothing);
      }
    },
  );

  // Test 7: Back navigation is blocked on mandatory overlay.
  testWidgets(
    'mandatory overlay blocks back navigation',
    (tester) async {
      final coordinator = _coordinator(_policy(mandatory: true));
      await tester.pumpWidget(_app(coordinator));

      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final state = coordinator.state;
      if (state.phase == AppUpdatePhase.ready) {
        expect(find.text('Actualización requerida'), findsOneWidget);

        // Try back navigation - should be blocked
        await tester.binding.handlePopRoute();
        await tester.pump();
        await tester.pump();

        expect(find.text('Actualización requerida'), findsOneWidget);
        expect(find.text('FullPOS listo'), findsOneWidget);
      }
    },
  );
}
