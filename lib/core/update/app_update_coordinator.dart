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
import 'app_update_safety.dart';
import 'app_version.dart';
import 'installer_launcher.dart';
import 'pending_update_status.dart';
import 'update_block_reason.dart';
import 'update_downloader.dart';
import 'update_shutdown_coordinator.dart';

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
    this.supportDetails,
    this.blockReasons = const [],
    this.preparationStep,
    this.presentationToken = 0,
  });

  final AppUpdatePhase phase;
  final AppVersion? installed;
  final AppUpdatePolicy? policy;
  final int receivedBytes;
  final int? totalBytes;
  final String? message;
  final String? supportDetails;

  /// Razones estructuradas de bloqueo cuando la actualización no puede proceder.
  final List<UpdateBlockReason> blockReasons;

  final UpdatePreparationStep? preparationStep;
  final int presentationToken;

  bool get isMandatory =>
      policy != null &&
      (policy!.decide(installed!) == UpdateDecision.mandatory);

  /// `true` si hay razones de bloqueo activas.
  bool get isBlocked => blockReasons.isNotEmpty;

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    AppVersion? installed,
    AppUpdatePolicy? policy,
    int? receivedBytes,
    int? totalBytes,
    String? message,
    String? supportDetails,
    List<UpdateBlockReason>? blockReasons,
    UpdatePreparationStep? preparationStep,
    int? presentationToken,
  }) => AppUpdateState(
    phase: phase ?? this.phase,
    installed: installed ?? this.installed,
    policy: policy ?? this.policy,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    message: message,
    supportDetails: supportDetails,
    blockReasons: blockReasons ?? this.blockReasons,
    preparationStep: preparationStep,
    presentationToken: presentationToken ?? this.presentationToken,
  );
}

class AppUpdateCoordinator extends ChangeNotifier {
  static int _testingStoreSeed = 0;

  static Future<Directory> Function() _createTestingUpdateRoot() {
    final id = _testingStoreSeed++;
    return () async => Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}fullpos_update_test_${pid}_$id',
    );
  }

  AppUpdateCoordinator._({
    AppUpdateRepository? repository,
    UpdateDownloader? downloader,
    InstallerLauncher? launcher,
    PendingUpdateStatusStore? statusStore,
    AppUpdateSafetyValidator? safetyValidator,
    Future<AppVersion> Function()? installedVersionLoader,
    bool loggingEnabled = true,
    bool? autoDownloadUpdates,
  }) : _repository = repository ?? AppUpdateRepository(),
       _downloader = downloader ?? UpdateDownloader(),
       _launcher = launcher ?? InstallerLauncher(),
       _statusStore =
           statusStore ??
           (loggingEnabled
               ? PendingUpdateStatusStore(
                   updateRoot: (downloader ?? UpdateDownloader()).updateRoot,
                 )
               : PendingUpdateStatusStore(
                   updateRoot: _createTestingUpdateRoot(),
                 )),
       _safetyValidator = safetyValidator ?? const AppUpdateSafetyValidator(),
       _installedVersionLoader = installedVersionLoader ?? AppVersion.installed,
       _loggingEnabled = loggingEnabled,
       _autoDownloadUpdates = autoDownloadUpdates ?? false;

  static final AppUpdateCoordinator instance = AppUpdateCoordinator._();

  @visibleForTesting
  factory AppUpdateCoordinator.testing({
    required AppUpdateRepository repository,
    UpdateDownloader? downloader,
    InstallerLauncher? launcher,
    AppUpdateSafetyValidator? safetyValidator,
    required Future<AppVersion> Function() installedVersionLoader,
    bool? autoDownloadUpdates,
  }) => AppUpdateCoordinator._(
    repository: repository,
    downloader: downloader,
    launcher: launcher,
    safetyValidator: safetyValidator,
    installedVersionLoader: installedVersionLoader,
    loggingEnabled: false,
    autoDownloadUpdates: autoDownloadUpdates ?? downloader != null,
  );

  final AppUpdateRepository _repository;
  final UpdateDownloader _downloader;
  final InstallerLauncher _launcher;
  final PendingUpdateStatusStore _statusStore;
  final AppUpdateSafetyValidator _safetyValidator;
  final Future<AppVersion> Function() _installedVersionLoader;
  final bool _loggingEnabled;
  final bool _autoDownloadUpdates;

  bool get loggingEnabled => _loggingEnabled;

  AppUpdateState _state = const AppUpdateState();
  AppUpdateState get state => _state;

  Future<void>? _checkInFlight;
  Timer? _periodicTimer;
  String? _dismissedOptionalVersion;
  File? _verifiedInstaller;
  Future<void>? _downloadFlowInFlight;
  Future<void>? _launchFlowInFlight;
  bool _presentReadyWhenDownloadCompletes = false;

  Future<void> ensureStarted() {
    if (!Platform.isWindows) return Future<void>.value();
    final existing = _checkInFlight;
    if (existing != null) return existing;
    if (_state.phase != AppUpdatePhase.idle) return Future<void>.value();
    _periodicTimer ??= Timer.periodic(const Duration(minutes: 15), (_) {
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

    final policyFuture = _repository.fetchPolicy();
    final previousInstallMessageFuture = _resolvePendingInstallMessage(
      installed,
    );
    try {
      final policy = await policyFuture;
      final previousInstallMessage = await previousInstallMessageFuture;
      await _applyPolicy(
        installed,
        policy,
        manual: manual,
        startupMessage: previousInstallMessage,
      );
    } catch (error) {
      final previousInstallMessage = await previousInstallMessageFuture;
      final cached = await _repository.readValidatedCache();
      if (cached != null &&
          cached.decide(installed) == UpdateDecision.mandatory) {
        await _applyPolicy(
          installed,
          cached,
          manual: manual,
          startupMessage: previousInstallMessage,
        );
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
    String? startupMessage,
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
          message:
              startupMessage ?? (manual ? 'FullPOS está actualizado.' : null),
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
    _setState(
      AppUpdateState(
        phase: phase,
        installed: installed,
        policy: policy,
        presentationToken: _state.presentationToken,
      ),
    );
    await _logInfo('Update found target=${policy.latest} phase=${phase.name}');
    if (_autoDownloadUpdates) {
      unawaited(downloadAndInstall(presentWhenReady: manual));
    }
  }

  void dismissOptional() {
    final policy = _state.policy;
    if (policy != null) _dismissedOptionalVersion = policy.latest.toString();
    unawaited(_logInfo('User postponed installation target=${policy?.latest}'));
    _setState(_state.copyWith(phase: AppUpdatePhase.current));
  }

  Future<void> downloadAndInstall({bool presentWhenReady = true}) {
    if (presentWhenReady) _presentReadyWhenDownloadCompletes = true;
    final existing = _downloadFlowInFlight;
    if (existing != null) return existing;
    final future = _downloadAndPrepare(presentWhenReady: presentWhenReady);
    _downloadFlowInFlight = future;
    return future.whenComplete(() {
      if (identical(_downloadFlowInFlight, future)) {
        _downloadFlowInFlight = null;
      }
    });
  }

  Future<void> _downloadAndPrepare({required bool presentWhenReady}) async {
    final policy = _state.policy;
    final installed = _state.installed;
    if (policy == null || installed == null || _downloader.isDownloading) {
      return;
    }
    try {
      await _logInfo(
        'Starting background update download target=${policy.latest}',
      );
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
          if (total != null && total > 0) {
            final pct = ((received / total) * 100).clamp(0, 100).round();
            if (pct == 25 || pct == 50 || pct == 75 || pct == 100) {
              unawaited(
                _logInfo(
                  'Update download progress target=${policy.latest} percent=$pct received=$received total=$total',
                ),
              );
            }
          }
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
      final shouldPresent =
          presentWhenReady ||
          _presentReadyWhenDownloadCompletes ||
          _dismissedOptionalVersion != policy.latest.toString() ||
          _state.isMandatory;
      _presentReadyWhenDownloadCompletes = false;
      await _logInfo('Update download completed file=${file.path}');
      await _logInfo('Update ready to install target=${policy.latest}');
      _setState(
        _state.copyWith(
          phase: AppUpdatePhase.ready,
          presentationToken: shouldPresent
              ? _state.presentationToken + 1
              : _state.presentationToken,
        ),
      );
    } catch (error) {
      _verifiedInstaller = null;
      final errorStr = error.toString().toLowerCase();
      String userMessage;
      String? supportDetail;
      if (error is UpdateDownloadException) {
        supportDetail = error.supportDetails;
      }
      if (errorStr.contains('sha256') || errorStr.contains('mismatch')) {
        userMessage =
            'No se pudo verificar la actualización. El archivo será descargado nuevamente.';
        supportDetail ??= 'Verification failed: $error';
      } else if (errorStr.contains('404') || errorStr.contains('not found')) {
        userMessage =
            'El instalador de esta versión no está disponible en el servidor. Contacta soporte.';
        supportDetail ??= 'HTTP 404: $error';
      } else if (errorStr.contains('403') || errorStr.contains('forbidden')) {
        userMessage =
            'No tenemos permiso para descargar el instalador. Verifica la publicación del release.';
        supportDetail ??= 'HTTP 403: $error';
      } else if (errorStr.contains('format_exception') &&
          errorStr.contains('unapproved')) {
        userMessage =
            'No encontramos un instalador válido para esta actualización. Contacta soporte.';
        supportDetail ??= 'Unapproved installer URL: $error';
      } else if (errorStr.contains('web_error_document') ||
          errorStr.contains('invalid_pe_header') ||
          errorStr.contains('empty_file')) {
        userMessage =
            'El archivo descargado no parece ser un instalador válido.';
        supportDetail ??= 'Invalid installer file: $error';
      } else if (errorStr.contains('permission') ||
          errorStr.contains('access denied')) {
        userMessage =
            'No pudimos guardar el instalador en esta PC. Ejecuta FullPOS como administrador o contacta soporte.';
        supportDetail ??= 'File permission error: $error';
      } else if (errorStr.contains('timeout') ||
          errorStr.contains('timed out')) {
        userMessage =
            'La descarga tardó demasiado. Revisa tu conexión e intenta nuevamente.';
        supportDetail ??= 'Timeout: $error';
      } else {
        userMessage =
            'No pudimos descargar la actualización. Revisa tu conexión e intenta nuevamente.';
        supportDetail ??= '$error';
      }
      _setState(
        _state.copyWith(
          phase: AppUpdatePhase.failed,
          message: userMessage,
          supportDetails: supportDetail,
        ),
      );
      await _logWarn('Update download or verification failed: $error');
      await _logInfo('Download support detail: $supportDetail');
    }
  }

  void cancelOptionalDownload() {
    if (_state.isMandatory) return;
    _downloader.cancel();
    dismissOptional();
  }

  Future<void> launchInstaller() async {
    final existing = _launchFlowInFlight;
    if (existing != null) return existing;
    final future = _launchInstaller();
    _launchFlowInFlight = future;
    return future.whenComplete(() {
      if (identical(_launchFlowInFlight, future)) {
        _launchFlowInFlight = null;
      }
    });
  }

  Future<void> _launchInstaller() async {
    final file = _verifiedInstaller;
    final policy = _state.policy;
    if (file == null || policy == null || _launcher.isLaunching) return;
    await _logInfo('User clicked install now target=${policy.latest}');
    final safety = await _safetyValidator.validate();
    if (!safety.safe) {
      await _logWarn(
        'Installation blocked because app is not in a safe state: ${safety.blockReason}',
      );
      for (final reason in safety.blockReasons) {
        await _logWarn(
          'Update install blocked reason=${reason.code} title=${reason.title}',
        );
      }
      _setState(
        _state.copyWith(
          phase: AppUpdatePhase.ready,
          message:
              safety.blockReason ?? AppUpdateSafetyValidator.pendingWorkMessage,
          blockReasons: safety.blockReasons,
        ),
      );
      return;
    }

    if (safety.warning != null) {
      await _logWarn('Installation safety warning: ${safety.warning}');
    }
    _setState(
      _state.copyWith(
        phase: AppUpdatePhase.launching,
        preparationStep: UpdatePreparationStep.verifyingOpenProcesses,
      ),
    );
    try {
      await _logInfo('User started installation target=${policy.latest}');
      await _launcher.launch(
        file,
        policy,
        onProgress: (step) {
          _setState(
            _state.copyWith(
              phase: AppUpdatePhase.launching,
              preparationStep: step,
            ),
          );
        },
      );
    } on UpdatePreparationException catch (error) {
      _setState(
        _state.copyWith(phase: AppUpdatePhase.ready, message: error.message),
      );
      await _logWarn('Update preparation blocked: ${error.message}');
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
    // Intentar preparación segura antes de cerrar.
    // Si hay operaciones activas, el usuario verá el mensaje y podrá decidir.
    final safety = await _safetyValidator.validate();
    if (!safety.safe) {
      _setState(
        _state.copyWith(
          message:
              safety.blockReason ?? AppUpdateSafetyValidator.pendingWorkMessage,
        ),
      );
      await _logWarn('closeFullPos blocked: ${safety.blockReason}');
      return;
    }
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

  Future<String?> _resolvePendingInstallMessage(AppVersion installed) async {
    final pending = await _statusStore.read();
    if (pending == null || pending.status != 'installing') return null;
    if (installed.compareTo(pending.targetVersion) >= 0) {
      await _statusStore.delete();
      await _logInfo(
        'Pending update completed target=${pending.targetVersion} installed=$installed',
      );
      return 'FullPOS se actualizó correctamente. Ya estás usando la versión más reciente.';
    }
    await _statusStore.writeStatus(pending, 'failed');
    await _logWarn(
      'Pending update did not complete target=${pending.targetVersion} installed=$installed',
    );
    return 'La actualización no se completó correctamente. Puedes intentarlo nuevamente desde Actualizaciones.';
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
