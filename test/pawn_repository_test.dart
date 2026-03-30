import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/pawn/data/pawn_model.dart';
import 'package:fullpos/features/pawn/data/pawn_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pawn repository stores and updates records in memory', () async {
    final id = await PawnRepository.insert(
      PawnModel(
        clientId: 7,
        descripcion: 'Anillo de plata',
        monto: 2500,
        status: 'activo',
        createdAtMs: 1000,
      ),
    );

    final created = await PawnRepository.getById(id);
    expect(created, isNotNull);
    expect(created!.descripcion, 'Anillo de plata');
    expect(created.status, 'activo');

    final updated = PawnModel(
      id: id,
      clientId: 7,
      descripcion: 'Anillo de plata con piedra',
      monto: 3000,
      status: 'renovado',
      createdAtMs: created.createdAtMs,
    );

    final ok = await PawnRepository.update(updated);
    expect(ok, isTrue);

    final all = await PawnRepository.getAll();
    final saved = all.firstWhere((pawn) => pawn.id == id);
    expect(saved.monto, 3000);
    expect(saved.status, 'renovado');
  });
}
