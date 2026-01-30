import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/settings/data/user_model.dart';
import '../../features/settings/providers/business_settings_provider.dart';
import '../db/app_db.dart';
import '../db_hardening/db_hardening.dart';
import '../errors/error_mapper.dart';
import '../logging/app_logger.dart';
import '../database/recovery/database_recovery_service.dart';
import '../debug/loader_watchdog.dart';
import '../session/session_manager.dart';
import '../window/window_service.dart';

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
          .timeout(const Duration(seconds: 6));
      _log('settings loaded');
      if (token != _runToken) return;

      _setMessage('Abriendo base de datos...');
      await AppDb.database.timeout(const Duration(seconds: 10));
      _log('open db ok');
      if (token != _runToken) return;

      _setMessage('Verificando base de datos...');
      await DbHardening.instance.preflight().timeout(const Duration(seconds: 10));
      _log('preflight ok');
      if (token != _runToken) return;

      _setMessage('Verificando integridad...');
      await DatabaseRecoveryService.run().timeout(const Duration(seconds: 10));
      _log('recovery ok');
      if (token != _runToken) return;

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        _setMessage('Preparando ventana...');
        await WindowService.init();
        WindowService.scheduleInitialLayoutFix();
        WindowService.scheduleShowAfterFirstFrame();
        _log('window ok');
        if (token != _runToken) return;
      }

      _setMessage('Cargando sesión...');
      await _reloadAuthSnapshot().timeout(const Duration(seconds: 6));
      _log('session loaded');
      if (token != _runToken) return;

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
    if (existing != null) return existing;

    final future = _reloadAuthSnapshotImpl();
    _authReloadInFlight = future.whenComplete(() {
      if (_authReloadInFlight == future) {
        _authReloadInFlight = null;
      }
    });
    return _authReloadInFlight!;
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
  }

  void _setMessage(String message) {
    _watchdog?.step(message);
    _setSnapshot(_snapshot.copyWith(message: message));
  }

  void _setSnapshot(BootSnapshot next) {
    _snapshot = next;
    notifyListeners();
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
