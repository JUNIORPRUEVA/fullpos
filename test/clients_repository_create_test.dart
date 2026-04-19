import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/db/app_db.dart';
import 'package:fullpos/core/db/db_init.dart';
import 'package:fullpos/features/clients/data/client_model.dart';
import 'package:fullpos/features/clients/data/clients_repository.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProviderPlatform(this._docsDir);

  final Directory _docsDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => _docsDir.path;

  @override
  Future<String?> getLibraryPath() async => _docsDir.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docsDir;

  setUpAll(() async {
    DbInit.ensureInitialized();
    docsDir = await Directory.systemTemp.createTemp('fullpos_db_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir);
  });

  tearDownAll(() async {
    await AppDb.resetForTests();
    try {
      await docsDir.delete(recursive: true);
    } catch (_) {}
  });

  test('ClientsRepository.create guarda y se puede leer', () async {
    await AppDb.resetForTests();

    final now = DateTime.now().millisecondsSinceEpoch;
    final client = ClientModel(
      nombre: 'Juan Perez',
      telefono: '8295887858',
      createdAtMs: now,
      updatedAtMs: now,
    );

    final id = await ClientsRepository.create(client);
    expect(id, greaterThan(0));

    final fetched = await ClientsRepository.getById(id);
    expect(fetched, isNotNull);
    expect(fetched!.nombre, 'Juan Perez');
    expect(fetched.telefono, '+18295887858');
  });

  test('ClientsRepository.create permite cliente empresarial con RNC sin telefono', () async {
    await AppDb.resetForTests();

    final now = DateTime.now().millisecondsSinceEpoch;
    final client = ClientModel(
      nombre: 'EMPRESA FISCAL DEMO SRL',
      rnc: '131246796',
      createdAtMs: now,
      updatedAtMs: now,
    );

    final id = await ClientsRepository.create(client);
    final fetched = await ClientsRepository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.nombre, 'EMPRESA FISCAL DEMO SRL');
    expect(fetched.rnc, '131246796');
    expect(fetched.telefono, isNull);
  });

  test('ClientsRepository evita duplicados por RNC', () async {
    await AppDb.resetForTests();

    final now = DateTime.now().millisecondsSinceEpoch;
    await ClientsRepository.create(
      ClientModel(
        nombre: 'EMPRESA A',
        rnc: '131246796',
        createdAtMs: now,
        updatedAtMs: now,
      ),
    );

    expect(
      () => ClientsRepository.create(
        ClientModel(
          nombre: 'EMPRESA DUPLICADA',
          rnc: '131246796',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}

