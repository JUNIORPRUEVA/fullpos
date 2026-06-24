import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/errors/app_exception.dart';
import 'package:fullpos/core/errors/error_mapper.dart';

void main() {
  test('maps duplicate open shifts to a clear cash conflict', () {
    final ex = ErrorMapper.map(
      StateError('Hay varios turnos abiertos para este usuario (2).'),
      StackTrace.current,
      'auth/logout',
    );

    expect(ex.type, AppErrorType.conflict);
    expect(ex.code, 'cash_duplicate_open_shifts');
    expect(ex.messageUser, contains('más de un turno abierto'));
    expect(ex.messageUser, isNot(contains('StateError')));
  });

  test('maps cash close owner mismatch to a customer safe message', () {
    final ex = ErrorMapper.map(
      Exception('Este turno (#8) pertenece a otro usuario.'),
      StackTrace.current,
      'cash/close',
    );

    expect(ex.type, AppErrorType.forbidden);
    expect(ex.code, 'cash_shift_owner_mismatch');
    expect(ex.messageUser, contains('pertenece a otro usuario'));
    expect(ex.messageUser, isNot(contains('#8')));
  });

  test('generic unknown message is professional', () {
    final ex = ErrorMapper.map(
      Exception('raw technical failure'),
      StackTrace.current,
      'inventory',
    );

    expect(ex.type, AppErrorType.unknown);
    expect(ex.messageUser, startsWith('No se pudo completar la acción'));
    expect(ex.messageUser, isNot(contains('Ups')));
  });
}
