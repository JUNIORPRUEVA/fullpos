import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_manager.dart';
import '../../registration/services/business_identity_storage.dart';
import '../license_config.dart';
import '../data/license_models.dart';
import '../models/license_ui_error.dart';
import 'business_license_api.dart';
import 'business_license_sync.dart';
import 'license_error_mapper.dart';
import 'license_file_repair.dart';
import 'license_file_storage.dart';
import 'license_api.dart';
import 'license_storage.dart';

@immutable
class LicenseState {
  final bool loading;
  final String? error;
  final String? errorCode;
  final LicenseInfo? info;
  final LicenseUiError? uiError;

  const LicenseState({
    required this.loading,
    required this.error,
    required this.errorCode,
    required this.info,
    required this.uiError,
  });

  factory LicenseState.initial() => const LicenseState(
    loading: false,
    error: null,
    errorCode: null,
    info: null,
    uiError: null,
  );

  LicenseState copyWith({
    bool? loading,
    String? error,
    String? errorCode,
    LicenseInfo? info,
    LicenseUiError? uiError,
  }) {
    return LicenseState(
      loading: loading ?? this.loading,
      error: error,
      errorCode: errorCode,
      info: info ?? this.info,
      uiError: uiError,
    );
  }
}

final licenseStorageProvider = Provider<LicenseStorage>(
  (ref) => LicenseStorage(),
);
final licenseApiProvider = Provider<LicenseApi>((ref) => LicenseApi());

final licenseControllerProvider =
    StateNotifierProvider<LicenseController, LicenseState>((ref) {
      return LicenseController(
        api: ref.read(licenseApiProvider),
        storage: ref.read(licenseStorageProvider),
      )..load();
    });

class LicenseController extends StateNotifier<LicenseState> {
  final LicenseApi api;
  final LicenseStorage storage;
  final BusinessLicenseApi businessApi;
  final BusinessLicenseSync businessSync;
  final LicenseFileRepair fileRepair;
  final LicenseFileStorage fileStorage;

  LicenseController({
    required this.api,
    required this.storage,
    BusinessLicenseApi? businessApi,
    BusinessLicenseSync? businessSync,
    LicenseFileRepair? fileRepair,
    LicenseFileStorage? fileStorage,
  }) : businessApi = businessApi ?? BusinessLicenseApi(),
       businessSync = businessSync ?? BusinessLicenseSync(),
       fileRepair = fileRepair ?? LicenseFileRepair(),
       fileStorage = fileStorage ?? LicenseFileStorage(),
       super(LicenseState.initial());

  void _setUiError(LicenseUiError err, {String? legacyErrorCode}) {
    state = state.copyWith(
      loading: false,
      uiError: err,
      // Mantener `error` para compatibilidad (snackbars legacy), pero siempre
      // en formato humano.
      error: err.message,
      errorCode: legacyErrorCode ?? state.errorCode,
    );
  }

  Future<void> load() async {
    state = state.copyWith(
      loading: true,
      error: null,
      errorCode: null,
      uiError: null,
    );
    try {
      final licenseKey = await storage.getLicenseKey();
      final deviceId = await _ensureDeviceId();
      final last = await storage.getLastInfo();

      // Intentar refrescar clave pública de firma (no bloqueante).
      // Si no hay internet, se ignora.
      unawaited(_refreshOfflineSigningPublicKey());

      LicenseInfo? merged = last;
      if (merged != null) {
        merged = LicenseInfo(
          backendBaseUrl: kLicenseBackendBaseUrl,
          licenseKey: licenseKey ?? merged.licenseKey,
          deviceId: deviceId,
          projectCode: merged.projectCode.isEmpty
              ? kFullposProjectCode
              : merged.projectCode,
          ok: merged.ok,
          code: merged.code,
          tipo: merged.tipo,
          estado: merged.estado,
          motivo: merged.motivo,
          fechaInicio: merged.fechaInicio,
          fechaFin: merged.fechaFin,
          maxDispositivos: merged.maxDispositivos,
          usados: merged.usados,
          lastCheckedAt: merged.lastCheckedAt,
        );
      } else {
        // Estado inicial sin verificación.
        if (licenseKey != null && licenseKey.isNotEmpty) {
          merged = LicenseInfo(
            backendBaseUrl: kLicenseBackendBaseUrl,
            licenseKey: licenseKey,
            deviceId: deviceId,
            projectCode: kFullposProjectCode,
            ok: false,
          );
        }
      }

      state = state.copyWith(loading: false, info: merged);
    } catch (e) {
      _setUiError(
        LicenseErrorMapper.map(
          e,
          context: const LicenseErrorContext(operation: 'load'),
        ),
      );
    }
  }

  Future<void> _refreshOfflineSigningPublicKey() async {
    try {
      final map = await api.getPublicSigningKey(
        baseUrl: kLicenseBackendBaseUrl,
      );
      if (map['ok'] != true) return;

      final jwk = map['jwk'];
      if (jwk is! Map) return;
      final x = (jwk['x'] ?? '').toString().trim();
      if (x.isEmpty) return;

      // jwk.x viene en base64url. Lo normalizamos a base64 clásico.
      final raw = _base64UrlDecode(x);
      if (raw.length != 32) return;
      final normalizedB64 = base64Encode(raw);

      await storage.setOfflineSigningPublicKeyB64(normalizedB64);
    } catch (_) {
      // Ignorar: offline-first.
    }
  }

  List<int> _base64UrlDecode(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return base64Decode(s);
  }

  Future<String> _ensureDeviceId() async {
    // Reusar el terminalId existente para mantener consistencia en desktop.
    final terminalId = await SessionManager.ensureTerminalId();
    await storage.setDeviceId(terminalId);
    return terminalId;
  }

  Future<void> saveLicenseKey({required String licenseKey}) async {
    await storage.setLicenseKey(licenseKey);
    await load();
  }

  Future<void> activate() async {
    final licenseKey = await storage.getLicenseKey();
    final deviceId = await _ensureDeviceId();
    if (licenseKey == null || licenseKey.isEmpty) {
      state = state.copyWith(
        error: 'Ingresa la clave de licencia',
        errorCode: null,
      );
      return;
    }

    state = state.copyWith(
      loading: true,
      error: null,
      errorCode: null,
      uiError: null,
    );
    try {
      final map = await api.activate(
        baseUrl: kLicenseBackendBaseUrl,
        licenseKey: licenseKey,
        deviceId: deviceId,
        projectCode: kFullposProjectCode,
      );

      final info = LicenseInfo(
        backendBaseUrl: kLicenseBackendBaseUrl,
        licenseKey: licenseKey,
        deviceId: deviceId,
        projectCode: kFullposProjectCode,
        ok: map['ok'] == true,
        code: map['code']?.toString(),
        tipo: map['tipo']?.toString(),
        estado: map['estado']?.toString(),
        fechaInicio: DateTime.tryParse((map['fecha_inicio'] ?? '').toString()),
        fechaFin: DateTime.tryParse((map['fecha_fin'] ?? '').toString()),
        maxDispositivos: _asInt(map['max_dispositivos']),
        usados: _asInt(map['usados']),
        lastCheckedAt: DateTime.now(),
      );

      await storage.setLastInfo(info);
      state = state.copyWith(loading: false, info: info);
    } on LicenseApiException catch (e) {
      _setUiError(
        LicenseErrorMapper.map(
          e,
          context: LicenseErrorContext(
            operation: 'activate',
            endpoint: '/api/licenses/activate',
            httpStatusCode: e.statusCode,
            backendCode: e.code,
          ),
        ),
        legacyErrorCode: e.code,
      );
    } catch (e) {
      _setUiError(
        LicenseErrorMapper.map(
          e,
          context: const LicenseErrorContext(
            operation: 'activate',
            endpoint: '/api/licenses/activate',
          ),
        ),
      );
    }
  }

  Future<void> check() async {
    final licenseKey = await storage.getLicenseKey();
    final deviceId = await _ensureDeviceId();
    if (licenseKey == null || licenseKey.isEmpty) {
      state = state.copyWith(
        error: 'Ingresa la clave de licencia',
        errorCode: null,
      );
      return;
    }

    state = state.copyWith(
      loading: true,
      error: null,
      errorCode: null,
      uiError: null,
    );
    try {
      final map = await api.check(
        baseUrl: kLicenseBackendBaseUrl,
        licenseKey: licenseKey,
        deviceId: deviceId,
        projectCode: kFullposProjectCode,
      );

      final info = LicenseInfo(
        backendBaseUrl: kLicenseBackendBaseUrl,
        licenseKey: licenseKey,
        deviceId: deviceId,
        projectCode: kFullposProjectCode,
        ok: map['ok'] == true,
        code: map['code']?.toString(),
        tipo: map['tipo']?.toString(),
        estado: map['estado']?.toString(),
        motivo: (map['motivo'] ?? map['notas'] ?? map['motivo_bloqueo'])
            ?.toString(),
        fechaInicio: DateTime.tryParse((map['fecha_inicio'] ?? '').toString()),
        fechaFin: DateTime.tryParse((map['fecha_fin'] ?? '').toString()),
        lastCheckedAt: DateTime.now(),
      );

      await storage.setLastInfo(info);

      if (info.ok) {
        state = state.copyWith(loading: false, info: info);
        return;
      }

      final code = (info.code ?? '').toUpperCase();
      final msg = switch (code) {
        'BLOCKED' => 'La cuenta está bloqueada',
        'EXPIRED' => 'La licencia está vencida',
        'NOT_FOUND' => 'Licencia no encontrada o activación revocada',
        _ => 'Licencia no válida',
      };
      state = state.copyWith(
        loading: false,
        info: info,
        error: msg,
        errorCode: info.code,
        uiError: LicenseErrorMapper.map(
          LicenseApiException(message: msg, statusCode: null, code: info.code),
          context: LicenseErrorContext(
            operation: 'check',
            endpoint: '/api/licenses/check',
            backendCode: info.code,
          ),
        ),
      );
    } catch (e) {
      _setUiError(
        LicenseErrorMapper.map(
          e,
          context: const LicenseErrorContext(
            operation: 'check',
            endpoint: '/api/licenses/check',
          ),
        ),
      );
    }
  }

  Future<void> startDemo({
    required String nombreNegocio,
    required String rolNegocio,
    required String contactoNombre,
    required String contactoTelefono,
  }) async {
    final deviceId = await _ensureDeviceId();

    state = state.copyWith(
      loading: true,
      error: null,
      errorCode: null,
      uiError: null,
    );
    try {
      final map = await api.startDemo(
        baseUrl: kLicenseBackendBaseUrl,
        deviceId: deviceId,
        projectCode: kFullposProjectCode,
        nombreNegocio: nombreNegocio,
        rolNegocio: rolNegocio,
        contactoNombre: contactoNombre,
        contactoTelefono: contactoTelefono,
      );

      final licenseKey = (map['license_key'] ?? '').toString().trim();
      if (licenseKey.isNotEmpty) {
        await storage.setLicenseKey(licenseKey);
      }

      // Después de crear demo, activamos para registrar este dispositivo.
      await activate();
    } on LicenseApiException catch (e) {
      _setUiError(
        LicenseErrorMapper.map(
          e,
          context: LicenseErrorContext(
            operation: 'startDemo',
            endpoint: '/api/licenses/start-demo',
            httpStatusCode: e.statusCode,
            backendCode: e.code,
          ),
        ),
        legacyErrorCode: e.code,
      );
    } catch (e) {
      _setUiError(
        LicenseErrorMapper.map(
          e,
          context: const LicenseErrorContext(
            operation: 'startDemo',
            endpoint: '/api/licenses/start-demo',
          ),
        ),
      );
    }
  }

  Future<void> applyOfflineLicenseFile(Map<String, dynamic> licenseFile) async {
    final deviceId = await _ensureDeviceId();
    state = state.copyWith(
      loading: true,
      error: null,
      errorCode: null,
      uiError: null,
    );
    try {
      // Verificación OFFLINE 100% local: no requiere internet.
      final payload = (licenseFile['payload'] is Map)
          ? (licenseFile['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final signatureB64 = (licenseFile['signature'] ?? '').toString().trim();
      final alg = (licenseFile['alg'] ?? '').toString().trim();

      if (payload.isEmpty || signatureB64.isEmpty) {
        throw const LicenseApiException(
          message: 'Archivo de licencia inválido',
        );
      }
      if (alg.isNotEmpty && alg.toUpperCase() != 'ED25519') {
        throw const LicenseApiException(
          message: 'Archivo de licencia inválido (algoritmo no soportado)',
        );
      }

      // Firma: Ed25519 sobre JSON.stringify(payload) (mismo formato que backend).
      final payloadJson = jsonEncode(payload);
      final signatureBytes = base64Decode(signatureB64);
      final storedKeyB64 = await storage.getOfflineSigningPublicKeyB64();
      final pubKeyBytes = base64Decode(
        (storedKeyB64 ?? kOfflineLicenseSigningPublicKeyB64).trim(),
      );
      if (pubKeyBytes.length != 32) {
        throw const LicenseApiException(
          message:
              'Verificación offline no configurada (clave pública inválida)',
        );
      }

      final algorithm = Ed25519();
      final publicKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);

      final isValid = await algorithm.verify(
        utf8.encode(payloadJson),
        signature: Signature(signatureBytes, publicKey: publicKey),
      );

      if (!isValid) {
        throw const LicenseApiException(
          message: 'Archivo de licencia inválido (firma no válida)',
        );
      }

      // Validaciones de negocio (proyecto / dispositivo / vencimiento)
      final projectCode = (payload['project_code'] ?? '').toString().trim();
      if (projectCode.isNotEmpty && projectCode != kFullposProjectCode) {
        throw LicenseApiException(
          message: 'Archivo de licencia no corresponde a $kFullposProjectCode',
        );
      }

      // Binding por business_id (nuevo flujo). Si existe, debe coincidir con el local.
      final payloadBusinessId = (payload['business_id'] ?? '')
          .toString()
          .trim();
      if (payloadBusinessId.isNotEmpty) {
        final identity = BusinessIdentityStorage();
        final local = await identity.getBusinessId();
        if (local == null || local.trim().isEmpty) {
          await identity.setBusinessId(payloadBusinessId);
        } else if (local.trim() != payloadBusinessId) {
          throw const LicenseApiException(
            message: 'Este archivo no corresponde a este negocio',
          );
        }
      }

      final payloadDeviceId = (payload['device_id'] ?? '').toString().trim();
      if (payloadDeviceId.isNotEmpty && payloadDeviceId != deviceId) {
        throw const LicenseApiException(
          message: 'Este archivo no corresponde a este dispositivo',
        );
      }

      final fechaFin = DateTime.tryParse(
        (payload['expires_at'] ?? payload['fecha_fin'] ?? '').toString(),
      );
      if (fechaFin != null && fechaFin.isBefore(DateTime.now())) {
        throw const LicenseApiException(message: 'La licencia está vencida');
      }

      final licenseKey = (payload['license_key'] ?? '').toString().trim();
      if (licenseKey.isEmpty) {
        throw const LicenseApiException(
          message: 'Archivo de licencia sin clave',
        );
      }

      await storage.setLicenseKey(licenseKey);

      // Guardar estado local como ACTIVA. Si no hay internet, el router usará
      // este cache para permitir acceso.
      final info = LicenseInfo(
        backendBaseUrl: kLicenseBackendBaseUrl,
        licenseKey: licenseKey,
        deviceId: deviceId,
        projectCode: kFullposProjectCode,
        ok: true,
        code: 'OK',
        tipo: (payload['plan'] ?? payload['tipo'] ?? '').toString().trim(),
        estado: 'ACTIVA',
        motivo: null,
        fechaInicio: DateTime.tryParse(
          (payload['starts_at'] ?? payload['fecha_inicio'] ?? '').toString(),
        ),
        fechaFin: fechaFin,
        maxDispositivos: _asInt(
          payload['max_devices'] ?? payload['max_dispositivos'],
        ),
        usados: null,
        lastCheckedAt: DateTime.now(),
      );
      await storage.setLastInfo(info);
      state = state.copyWith(loading: false, info: info);
    } on LicenseApiException catch (e) {
      _setUiError(
        LicenseErrorMapper.map(
          e,
          context: LicenseErrorContext(
            operation: 'applyOfflineLicenseFile',
            endpoint: 'local_file',
            backendCode: e.code,
            httpStatusCode: e.statusCode,
          ),
        ),
        legacyErrorCode: e.code,
      );
    } catch (e) {
      _setUiError(
        LicenseErrorMapper.map(
          e,
          context: const LicenseErrorContext(
            operation: 'applyOfflineLicenseFile',
            endpoint: 'local_file',
          ),
        ),
      );
    }
  }

  /// Fuerza un intento de descargar y aplicar license.dat desde la nube
  /// usando business_id (flujo nuevo). Esto NO rompe el gate del router;
  /// simplemente permite que la pantalla muestre "Esperando activación".
  Future<void> syncBusinessLicenseNow() async {
    state = state.copyWith(loading: true, error: null, errorCode: null);

    final identity = BusinessIdentityStorage();
    final businessId = await identity.getBusinessId();
    if (businessId == null || businessId.trim().isEmpty) {
      _setUiError(
        const LicenseUiError(
          type: LicenseErrorType.unknown,
          title: 'Falta información del negocio',
          message:
              'Completa la información del negocio para poder activar y descargar tu licencia.',
          supportCode: 'LIC-BIZ-01',
          actions: [LicenseAction.openWhatsapp, LicenseAction.copySupportCode],
          technicalSummary: 'business_id missing',
          endpoint: '/businesses/:id/license',
        ),
      );
      return;
    }

    try {
      final token = await businessApi.getLicenseToken(
        baseUrl: kLicenseBackendBaseUrl,
        businessId: businessId.trim(),
      );

      if (token == null) {
        _setUiError(
          const LicenseUiError(
            type: LicenseErrorType.notActivated,
            title: 'Esperando activación',
            message:
                'Tu solicitud fue recibida. Cuando el administrador active tu licencia, se descargará automáticamente.',
            supportCode: 'LIC-ACT-01',
            actions: [
              LicenseAction.retry,
              LicenseAction.openWhatsapp,
              LicenseAction.copySupportCode,
            ],
            technicalSummary: 'HTTP 204 / token null',
            endpoint: '/businesses/:id/license',
          ),
        );
        return;
      }

      await fileStorage.writeToken(token);

      final ok = await businessSync.applyLocalLicenseIfValid();
      if (!ok) {
        _setUiError(
          const LicenseUiError(
            type: LicenseErrorType.corruptedLocalFile,
            title: 'Licencia dañada',
            message:
                'Encontramos un archivo de licencia inválido en esta computadora. Podemos repararlo y volver a sincronizar.',
            supportCode: 'LIC-FILE-01',
            actions: [
              LicenseAction.repairAndRetry,
              LicenseAction.openWhatsapp,
              LicenseAction.copySupportCode,
            ],
            technicalSummary: 'license.dat token invalid',
            endpoint: '/businesses/:id/license',
          ),
        );
        return;
      }

      await load();
    } catch (e) {
      _setUiError(
        LicenseErrorMapper.map(
          e,
          context: const LicenseErrorContext(
            operation: 'syncBusinessLicenseNow',
            endpoint: '/businesses/:id/license',
          ),
        ),
      );
    }
  }

  Future<String?> repairLocalLicenseFile() async {
    return fileRepair.quarantineLocalLicenseFile();
  }

  Future<void> repairAndRetrySync() async {
    await repairLocalLicenseFile();
    await syncBusinessLicenseNow();
  }

  Future<void> clearLocal() async {
    await storage.clearAll();
    state = LicenseState.initial();
    await load();
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}
