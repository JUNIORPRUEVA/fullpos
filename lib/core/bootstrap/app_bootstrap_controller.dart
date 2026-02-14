import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/settings/data/user_model.dart';
import '../../features/settings/providers/business_settings_provider.dart';
import '../db/app_db.dart';
import '../db/auto_repair.dart';
import '../db_hardening/db_hardening.dart';
import '../errors/error_mapper.dart';
import '../logging/app_logger.dart';
import '../database/recovery/database_recovery_service.dart';
import '../debug/loader_watchdog.dart';
import '../session/session_manager.dart';
import '../window/window_service.dart';
import '../../features/registration/services/business_registration_service.dart';

enum BootStatus { loading, ready, error }

@immutable
class BootSnapshot {
  final BootStatus status;
  final String message;
  final String? errorMessage;
  final bool isLoggedIn;
  final bool isAdmin;
  final UserPermissions permissions;

  const BootSnapshot({
    required this.status,
    required this.message,
    required this.errorMessage,
    required this.isLoggedIn,
    required this.isAdmin,
    required this.permissions,
  });

  const BootSnapshot.loading([String message = 'Iniciando...'])
    : this(
        status: BootStatus.loading,
        message: message,
        errorMessage: null,
        isLoggedIn: false,
        isAdmin: false,
        permissions: const UserPermissions(),
      );

  BootSnapshot copyWith({
    BootStatus? status,
    String? message,
    String? errorMessage,
    bool? isLoggedIn,
    bool? isAdmin,
    UserPermissions? permissions,
  }) {
    return BootSnapshot(
      status: status ?? this.status,
      message: message ?? this.message,
      errorMessage: errorMessage ?? this.errorMessage,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      isAdmin: isAdmin ?? this.isAdmin,
      permissions: permissions ?? this.permissions,
    );
  }
}

final appBootstrapProvider = ChangeNotifierProvider<AppBootstrapController>((
  ref,
) {
  return AppBootstrapController(ref)..ensureStarted();
});

class AppBootstrapController extends ChangeNotifier {
  AppBootstrapController(this._ref) {
    _sessionSub = SessionManager.changes.listen((_) {
      unawaited(_reloadAuthSnapshot());
    });
  }

  final Ref _ref;
  StreamSubscription<void>? _sessionSub;
  LoaderWatchdog? _watchdog;

  BootSnapshot _snapshot = const BootSnapshot.loading();
  BootSnapshot get snapshot => _snapshot;

  int _runToken = 0;
  bool get isStarted => _runToken > 0;

  Future<void>? _authReloadInFlight;
  bool _authReloadPending = false;

  void ensureStarted() {
    if (isStarted) return;
    retry();
  }

  Future<void> retry() async {
    final token = ++_runToken;
    _watchdog?.dispose();
    _watchdog = LoaderWatchdog.start(stage: 'bootstrap');
    _setSnapshot(const BootSnapshot.loading('Iniciando...'));

    final startedAt = DateTime.now();
    _log('start');

    try {
      await WidgetsBinding.instance.endOfFrame;
      if (token != _runToken) return;

      _setMessage('Cargando configuración...');
      await _ref
          .read(businessSettingsProvider.notifier)
          .reload()
          .timeout(const Duration(seconds: 20));
      _log('settings loaded');
      if (token != _runToken) return;

      _setMessage('Abriendo base de datos...');
      try {
        await AppDb.database.timeout(const Duration(seconds: 20));
      } catch (_) {
        // Si la DB está tan dañada que falla al abrir, intentar auto-reparación
        // (restaurar último backup) y luego reintentar la apertura.
        _setMessage('Reparando base de datos...');
        await AutoRepair.instance
            .ensureDbHealthy(reason: 'bootstrap_open_failed')
            .timeout(const Duration(seconds: 45));
        await AppDb.database.timeout(const Duration(seconds: 20));
      }
      _log('open db ok');
      if (token != _runToken) return;

      // Asegurar salud e intentar restauración automática antes del preflight.
      _setMessage('Reparando base de datos...');
      await AutoRepair.instance
          .ensureDbHealthy(reason: 'bootstrap')
          .timeout(const Duration(seconds: 45));
      _log('auto repair ok');
      if (token != _runToken) return;

      _setMessage('Verificando base de datos...');
      await DbHardening.instance.preflight().timeout(
        const Duration(seconds: 45),
      );
      _log('preflight ok');
      if (token != _runToken) return;

      _setMessage('Verificando integridad...');
      await DatabaseRecoveryService.run().timeout(const Duration(seconds: 45));
      _log('recovery ok');
      if (token != _runToken) return;

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        _setMessage('Preparando ventana...');
        await WindowService.init();
        _log('window ok');
        if (token != _runToken) return;
      }

      _setMessage('Cargando sesión...');
      await _reloadAuthSnapshot().timeout(const Duration(seconds: 20));
      _log('session loaded');
      if (token != _runToken) return;

      // Registro nube offline-first: reintentar una vez lo pendiente.
      // No debe bloquear el arranque.
      unawaited(BusinessRegistrationService().retryPendingOnce());

      const minSplash = Duration(milliseconds: 900);
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < minSplash) {
        await Future<void>.delayed(minSplash - elapsed);
      }
      if (token != _runToken) return;

      _setSnapshot(
        _snapshot.copyWith(status: BootStatus.ready, errorMessage: null),
      );
      _log('ready');
      _watchdog?.dispose();
      _watchdog = null;
    } catch (e, st) {
      _log('error: $e');
      final ex = ErrorMapper.map(e, st, 'bootstrap');
      unawaited(AppLogger.instance.logError(ex, module: 'bootstrap'));
      if (kDebugMode) {
        debugPrint('$st');
      }
      _setSnapshot(
        _snapshot.copyWith(
          status: BootStatus.error,
          errorMessage: ex.messageUser,
        ),
      );
      _watchdog?.dispose();
      _watchdog = null;
    }
  }

  Future<void> _reloadAuthSnapshot() {
    final existing = _authReloadInFlight;
    if (existing != null) {
      // Si hay un reload en curso y llega otro cambio de sesión (login/logout),
      // marcamos pendiente para re-ejecutar al terminar. Esto evita estados
      // "stale" cuando el usuario hace login/logout rápido.
      _authReloadPending = true;
      return existing;
    }

    final future = _reloadAuthSnapshotImpl();
    _authReloadInFlight = future.whenComplete(() {
      if (_authReloadInFlight == future) {
        _authReloadInFlight = null;
      }
      if (_authReloadPending) {
        _authReloadPending = false;
        unawaited(_reloadAuthSnapshot());
      }
    });
    return _authReloadInFlight!;
  }

  /// Fuerza una recarga de estado de autenticación (login/logout/permisos).
  /// Útil cuando el caller necesita que el router tenga el snapshot actualizado
  /// antes de navegar.
  Future<void> refreshAuth() async {
    // Ejecutar al menos un reload y, si hubo cambios durante ese reload,
    // esperar al siguiente para "asentar" el snapshot final.
    await _reloadAuthSnapshot();
    // En flujos rápidos puede haber más de un cambio; evitar loops infinitos.
    for (var i = 0; i < 2; i++) {
      if (!_authReloadPending && _authReloadInFlight == null) break;
      await _reloadAuthSnapshot();
    }
  }

  /// Fuerza el estado de sesión en memoria (source-of-truth para routing).
  /// Se usa en login/logout para evitar estados "pegados" hasta reiniciar.
  void forceLoggedOut() {
    _setSnapshot(
      _snapshot.copyWith(
        isLoggedIn: false,
        isAdmin: false,
        permissions: UserPermissions.none(),
      ),
    );
  }

  void forceLoggedIn() {
    if (_snapshot.isLoggedIn) return;
    _setSnapshot(_snapshot.copyWith(isLoggedIn: true));
  }

  Future<void> _reloadAuthSnapshotImpl() async {
    final isLoggedIn = await SessionManager.isLoggedIn();
    if (!isLoggedIn) {
      _setSnapshot(
        _snapshot.copyWith(
          isLoggedIn: false,
          isAdmin: false,
          permissions: UserPermissions.none(),
        ),
      );
      return;
    }

    // IMPORTANTE:
    // Primero marcar "logueado" aunque falle cargar permisos.
    // Si esta carga falla, el router se quedaría pensando que no hay sesión
    // y la navegación login/logout se ve "rota" hasta reiniciar.
    if (!_snapshot.isLoggedIn) {
      _setSnapshot(_snapshot.copyWith(isLoggedIn: true));
    }

    try {
      final permissionsFuture = AuthRepository.getCurrentPermissions();
      final isAdminFuture = AuthRepository.isAdmin();
      final permissions = await permissionsFuture;
      final isAdmin = await isAdminFuture;

      _setSnapshot(
        _snapshot.copyWith(
          isLoggedIn: true,
          isAdmin: isAdmin,
          permissions: permissions,
        ),
      );
    } catch (_) {
      // No bloquear UI por un fallo puntual leyendo permisos.
      _setSnapshot(
        _snapshot.copyWith(
          isLoggedIn: true,
          isAdmin: false,
          permissions: UserPermissions.none(),
        ),
      );
    }
  }

  void _setMessage(String message) {
    _watchdog?.step(message);
    _setSnapshot(_snapshot.copyWith(message: message));
  }

  void _setSnapshot(BootSnapshot next) {
    _snapshot = next;
    notifyListeners();
    assert(() {
      debugPrint(
        '[BOOT] snapshot: status=${_snapshot.status} loggedIn=${_snapshot.isLoggedIn} admin=${_snapshot.isAdmin}',
      );
      return true;
    }());
  }

  static void _log(String message) {
    debugPrint('[BOOT] $message');
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _sessionSub = null;
    _watchdog?.dispose();
    _watchdog = null;
    super.dispose();
  }
}
