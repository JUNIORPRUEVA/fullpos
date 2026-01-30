import 'pawn_model.dart';

/// Repositorio de empeño
/// Implementación CRUD en memoria para pruebas
class PawnRepository {
  PawnRepository._();

  static final List<PawnModel> _pawnList = [];
  static int _autoIncrementId = 1;

  static Future<List<PawnModel>> getAll() async {
    return List.unmodifiable(_pawnList);
  }

  static Future<PawnModel?> getById(int id) async {
    try {
      return _pawnList.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  static Future<int> insert(PawnModel pawn) async {
    final newPawn = PawnModel(
      id: _autoIncrementId++,
      clientId: pawn.clientId,
      descripcion: pawn.descripcion,
      monto: pawn.monto,
      status: pawn.status,
      createdAtMs: pawn.createdAtMs,
    );
    _pawnList.add(newPawn);
    return newPawn.id!;
  }

  static Future<bool> update(PawnModel pawn) async {
    final idx = _pawnList.indexWhere((p) => p.id == pawn.id);
    if (idx == -1) return false;
    _pawnList[idx] = pawn;
    return true;
  }

  static Future<bool> delete(int id) async {
    final before = _pawnList.length;
    _pawnList.removeWhere((p) => p.id == id);
    final after = _pawnList.length;
    return before > after;
  }
}
