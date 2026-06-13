import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_logger.dart';
import '../db/database_manager.dart';
import '../services/cloud_sync_service.dart';
import '../sync/product_sync_service.dart';
import 'app_update_policy.dart';
import 'app_update_repository.dart';
import 'app_version.dart';
import 'installer_launcher.dart';
import 'update_downloader.dart';

enum AppUpdatePhase {
  idle,
  checking,
  current,
  optional,
  mandatory,
  downloading,
  verifying,
  ready,
  launching,
  offline,
  failed,
  installIncomplete,
}

class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.installed,
    this.policy,
    this.receivedBytes = 0,
    this.totalBytes,
    this.message,
    this.presentationToken = 0,
  });

  final AppUpdatePhase phase;
  final AppVersion? installed;
  final AppUpdatePolicy? policy;
  final int receivedBytes;
  final int? totalBytes;
  final String? message;
  final int presentationToken;

  bool get isMandatory =>
      policy != null &&
      (policy!.decide(installed!) == UpdateDecision.mandatory);

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    AppVersion? installed,
    AppUpdatePolicy? policy,
    int? receivedBytes,
    int? totalBytes,
    String? message,
    int? presentationToken,
  }) => AppUpdateState(
    phase: phase ?? this.phase,
    installed: installed ?? this.installed,
    policy: policy ?? this.policy,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    message: message,
    presentationToken: presentationToken ?? this.presentationToken,
  );
}

class AppUpdateCoordinator extends ChangeNotifier {
  AppUpdateCoordinator._({
    AppUpdateRepository? repository,
    UpdateDownloader? downloader,
    InstallerLauncher? launcher,
    Future<AppVersion> Function()? installedVersionLoader,
    bool loggingEnabled = true,
  }) : _repository = repository ?? AppUpdateRepository(),
       _downloader = downloader ?? UpdateDownloader(),
       _launcher = launcher ?? InstallerLauncher(),
       _installedVersionLoader = installedVersionLoader ?? AppVersion.installed,
       _loggingEnabled = loggingEnabled;

  static final AppUpdateCoordinator instance = AppUpdateCoordinator._();

  @visibleForTesting
  factory AppUpdateCoordinator.testing({
    required AppUpdateRepository repository,
    UpdateDownloader? downloader,
    InstallerLauncher? launcher,
    required Future<AppVersion> Function() installedVersionLoader,
  }) => AppUpdateCoordinator._(
    repository: repository,
    downloader: downloader,
    launcher: launcher,
    installedVersionLoader: installedVersionLoader,
    loggingEnabled: false,
  );

  final AppUpdateRepository _repository;
  final UpdateDownloader _downloader;
  final InstallerLauncher _launcher;
  final Future<AppVersion> Function() _installedVersionLoader;
  final bool _loggingEnabled;

  AppUpdateState _state = const AppUpdateState();
  AppUpdateState get state => _state;

  Future<void>? _checkInFlight;
  Timer? _periodicTimer;
  String? _dismissedOptionalVersion;
  File? _verifiedInstaller;

  Future<void> ensureStarted() {
    if (!Platform.isWindows) return Future<void>.value();
    final existing = _checkInFlight;
    if (existing != null) return existing;
    if (_state.phase != AppUpdatePhase.idle) return Future<void>.value();
    _periodicTimer ??= Timer.periodic(const Duration(hours: 5), (_) {
      unawaited(check());
    });
    return check();
  }

  Future<void> check({bool manual = false}) {
    final existing = _checkInFlight;
    if (existing != null) return existing;
    final future = _check(manual: manual);
    _checkInFlight = future;
    return future.whenComplete(() {
      if (identical(_checkInFlight, future)) _checkInFlight = null;
    });
  }

  Future<void> _check({required bool manual}) async {
    final installed = await _installedVersionLoader();
    _setState(
      AppUpdateState(
        phase: AppUpdatePhase.checking,
        installed: installed,
        presentationToken: _state.presentationToken,
      ),
    );
    await _logInfo('Update check started installed=$installed');

    try {
      final policy = await _repository.fetchPolicy();
      await _applyPolicy(installed, policy, manual: manual);
    } catch (error) {
      final cached = await _repository.readValidatedCache();
      if (cached != null &&
          cached.decide(installed) == UpdateDecision.mandatory) {
        await _applyPolicy(installed, cached, manual: manual);
        return;
      }
      _setState(
        AppUpdateState(
          phase: AppUpdatePhase.offline,
          installed: installed,
          message: manual
              ? 'No se pudo consultar actualizaciones. Verifica tu conexión.'
              : null,
          presentationToken: _state.presentationToken,
        ),
      );
      await _logWarn(
        'Update check unavailable; no cached mandatory policy: $error',
      );
    }
  }

  Future<void> _applyPolicy(
    AppVersion installed,
    AppUpdatePolicy policy, {
    required bool manual,
  }) async {
    final decision = policy.decide(installed);
    await _logInfo(
      'Update policy latest=${policy.latest} minimum=${policy.minimumSupported} decision=${decision.name}',
    );
    if (decision == UpdateDecision.none) {
      await _completePreviousInstallIfNeeded(installed, policy);
      _setState(
        AppUpdateState(
          phase: AppUpdatePhase.current,
          installed: installed,
          policy: policy,
          message: manual ? 'FullPOS está actualizado.' : null,
          presentationToken: _state.presentationToken,
        ),
      );
      return;
    }

    final incomplete = await _isIncompleteInstall(installed, policy);
    final phase = incomplete
        ? AppUpdatePhase.installIncomplete
        : decision == UpdateDecision.mandatory
        ? AppUpdatePhase.mandatory
        : AppUpdatePhase.optional;
    final shouldPresentOptional =
        manual || _dismissedOptionalVersion != policy.latest.toString();
    _setState(
      AppUpdateState(
        phase: phase,
        installed: installed,
        policy: policy,
        presentationToken:
            shouldPresentOptional && phase == AppUpdatePhase.optional
            ? _state.presentationToken + 1
            : _state.presentationToken,
      ),
    );
  }

  void dismissOptional() {
    final policy = _state.policy;
    if (policy != null) _dismissedOptionalVersion = policy.latest.toString();
    _setState(_state.copyWith(phase: AppUpdatePhase.current));
  }

  Future<void> downloadAndInstall() async {
    final policy = _state.policy;
    final installed = _state.installed;
    if (policy == null || installed == null || _downloader.isDownloading) {
      return;
    }
    try {
      _setState(
        _state.copyWith(
          phase: AppUpdatePhase.downloading,
          receivedBytes: 0,
          totalBytes: policy.installerSizeBytes,
        ),
      );
      final file = await _downloader.download(
        policy,
        onProgress: (received, total) {
          _setState(
            _state.copyWith(
              phase: AppUpdatePhase.downloading,
              receivedBytes: received,
              totalBytes: total,
            ),
          );
        },
      );
      _setState(_state.copyWith(phase: AppUpdatePhase.verifying));
      _verifiedInstaller = file;
      _setState(_state.copyWith(phase: AppUpdatePhase.ready));
    } catch (error) {
      _verifiedInstaller = null;
      _setState(
        _state.copyWith(
          phase: AppUpdatePhase.failed,
          message:
              error.toString().contains('sha256') ||
                  error.toString().contains('mismatch')
              ? 'No se pudo verificar la actualización. El archivo será descargado nuevamente.'
              : 'No se pudo descargar la actualización. Verifica tu conexión y vuelve a intentarlo.',
        ),
      );
      await _logWarn('Update download or verification failed: $error');
    }
  }

  void cancelOptionalDownload() {
    if (_state.isMandatory) return;
    _downloader.cancel();
    dismissOptional();
  }

  Future<void> launchInstaller() async {
    final file = _verifiedInstaller;
    final policy = _state.policy;
    if (file == null || policy == null || _launcher.isLaunching) return;
    _setState(_state.copyWith(phase: AppUpdatePhase.launching));
    try {
      await _launcher.launch(file, policy);
    } catch (error) {
      _setState(
        _state.copyWith(
          phase: AppUpdatePhase.failed,
          message:
              'No se pudo abrir el instalador. FullPOS permanecerá abierto.',
        ),
      );
      await _logWarn('Installer launch failed: $error');
    }
  }

  Future<void> closeFullPos() async {
    CloudSyncService.instance.stopRealtimeSyncEngine();
    ProductSyncService.instance.stop();
    await DatabaseManager.instance.close(reason: 'update_gate_close');
    await AppLogger.instance.flush();
    exit(0);
  }

  Future<void> openUpdateFolder() async {
    final file = _verifiedInstaller;
    final storedPath = (await SharedPreferences.getInstance()).getString(
      'update_installer_path',
    );
    final path =
        file?.parent.path ??
        (storedPath == null ? null : File(storedPath).parent.path);
    if (path == null || !Platform.isWindows) return;
    await Process.start('explorer.exe', [path], runInShell: false);
  }

  Future<void> _completePreviousInstallIfNeeded(
    AppVersion installed,
    AppUpdatePolicy policy,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final target = prefs.getString('update_install_target');
    if (target == null) return;
    final targetVersion = AppVersion.parse(target);
    if (installed.compareTo(targetVersion) >= 0) {
      final path = prefs.getString('update_installer_path');
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      await prefs.remove('update_install_target');
      await prefs.remove('update_installer_path');
      await prefs.remove('update_install_attempted_at');
    }
  }

  Future<bool> _isIncompleteInstall(
    AppVersion installed,
    AppUpdatePolicy policy,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final target = prefs.getString('update_install_target');
    if (target != policy.latest.toString()) return false;
    return installed.compareTo(policy.latest) < 0;
  }

  void _setState(AppUpdateState value) {
    _state = value;
    notifyListeners();
  }

  Future<void> _logInfo(String message) {
    if (!_loggingEnabled) return Future<void>.value();
    return AppLogger.instance.logInfo(message, module: 'app_update');
  }

  Future<void> _logWarn(String message) {
    if (!_loggingEnabled) return Future<void>.value();
    return AppLogger.instance.logWarn(message, module: 'app_update');
  }
}
