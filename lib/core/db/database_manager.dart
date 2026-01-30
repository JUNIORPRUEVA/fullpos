import 'dart:async';

import 'package:sqflite/sqflite.dart';

import 'app_db.dart';

/// Centraliza el ciclo de vida de la DB.
///
/// Objetivos:
/// - Una sola instancia de DB durante el runtime.
/// - Cierre/reapertura serializados (evita carreras "database already closed").
/// - Punto único para llamadas a close() del handle principal.
class DatabaseManager {
  DatabaseManager._();

  static final DatabaseManager instance = DatabaseManager._();

  Future<void>? _reopenInFlight;

  Future<Database> get database => AppDb.database;

  Map<String, Object?> diagnosticsSnapshot() => AppDb.diagnosticsSnapshot();

  /// Garantiza que exista un handle abierto.
  ///
  /// Nota: No cierra el handle de forma agresiva. Si ya está abierto, no hace nada.
  Future<Database> ensureOpen() => AppDb.database;

  /// Cierra el handle principal de forma serializada.
  Future<void> close({String? reason}) async {
    // Serializar con reaperturas para evitar interleavings.
    await _reopenInFlight;
    await AppDb.close();
  }

  /// Reabre el handle principal de forma serializada.
  ///
  /// Importante: se usa como recuperación ante errores de "database_closed".
  Future<Database> reopen({String? reason}) async {
    final existing = _reopenInFlight;
    if (existing != null) {
      await existing;
      return AppDb.database;
    }

    final future = _reopenImpl(reason: reason);
    _reopenInFlight = future.whenComplete(() {
      if (identical(_reopenInFlight, future)) {
        _reopenInFlight = null;
      }
    });

    await _reopenInFlight;
    return AppDb.database;
  }

  Future<void> _reopenImpl({String? reason}) async {
    // Si ya hay un handle abierto, no lo cerramos: evita tumbar operaciones en curso.
    final snap = AppDb.diagnosticsSnapshot();
    final isOpen = (snap['isOpen'] as bool?) ?? false;
    if (isOpen) {
      await AppDb.database;
      return;
    }

    await AppDb.close();
    await AppDb.database;
  }
}
