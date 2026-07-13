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

AppUpdateCoordinator _coordinator(AppUpdatePolicy policy) {
  return AppUpdateCoordinator.testing(
    repository: _PolicyRepository(policy),
    safetyValidator: const _SafeValidator(),
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

  // Test 1: App content is always visible, no blocking UI.
  testWidgets(
    'app content is always visible regardless of update state',
    (tester) async {
      final coordinator = _coordinator(_policy(mandatory: true));
      await tester.pumpWidget(_app(coordinator));

      // Before check, app content is visible
      expect(find.text('FullPOS listo'), findsOneWidget);

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

      // During any phase, app content must still be visible
      expect(find.text('FullPOS listo'), findsOneWidget);

      // No blocking UI should ever appear
      expect(find.text('Actualización requerida'), findsNothing);
      expect(find.text('Instalar ahora'), findsNothing);
      expect(find.text('Cerrar FullPOS'), findsNothing);
      expect(find.text('Actualización lista para instalar'), findsNothing);
      expect(find.text('No se puede actualizar todavía'), findsNothing);
      expect(find.text('Revisar proceso'), findsNothing);
      expect(find.text('Más tarde'), findsOneWidget);
    },
  );

  // Test 2: Center dialog notification appears when new update is detected.
  testWidgets(
    'center dialog notification appears when new update is available',
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

      expect(find.text('Actualización disponible'), findsOneWidget);
      expect(
        find.text('Hay una nueva versión de FullPOS lista para revisar.'),
        findsOneWidget,
      );
      expect(find.text('Ver actualización'), findsOneWidget);
      expect(find.byTooltip('Cerrar'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  // Test 3: Dialog appears only once per session.
  testWidgets(
    'update dialog appears only once per session',
    (tester) async {
      final coordinator = _coordinator(_policy(mandatory: true));
      await tester.pumpWidget(_app(coordinator));

      // First check
      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Actualización disponible'), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Actualización disponible'), findsNothing);

      // Simulate a second state change (e.g., re-check)
      await tester.runAsync(
        () => coordinator.check().timeout(
          const Duration(seconds: 5),
          onTimeout: () => null,
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text('Actualización disponible'), findsNothing);
    },
  );

  // Test 4: Mandatory update does not block the user.
  testWidgets(
    'mandatory update does not block the user',
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

      // App content is always visible
      expect(find.text('FullPOS listo'), findsOneWidget);

      // No blocking overlay or dialog
      expect(find.text('Actualización requerida'), findsNothing);
      expect(find.text('Cerrar FullPOS'), findsNothing);
    },
  );

  // Test 5: Optional update shows only the small notification dialog.
  testWidgets(
    'optional update shows only the small notification dialog',
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

      // App content is visible
      expect(find.text('FullPOS listo'), findsOneWidget);

      expect(find.text('Actualización disponible'), findsOneWidget);
      expect(find.text('Actualización lista para instalar'), findsNothing);
      expect(find.text('Instalar ahora'), findsNothing);
      expect(find.text('Más tarde'), findsOneWidget);
    },
  );

  // Test 6: Back navigation is never blocked.
  testWidgets(
    'back navigation is never blocked',
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

      // App content is visible
      expect(find.text('FullPOS listo'), findsOneWidget);

      // Back navigation should work (no overlay to block it)
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();

      // No blocking UI should appear
      expect(find.text('Actualización requerida'), findsNothing);
    },
  );

  // Test 7: build() always returns child widget.
  testWidgets(
    'build always returns child widget',
    (tester) async {
      final coordinator = _coordinator(_policy(mandatory: true));
      await tester.pumpWidget(_app(coordinator));

      // The child widget is always rendered
      expect(find.text('FullPOS listo'), findsOneWidget);

      // No update gate overlay replaces the child
      expect(
        find.byType(UpdateGate),
        findsOneWidget,
      );
    },
  );
}
