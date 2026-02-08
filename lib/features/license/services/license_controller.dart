import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/session/session_manager.dart';
import '../license_config.dart';
import '../data/license_models.dart';
import 'license_api.dart';
import 'license_storage.dart';

@immutable
class LicenseState {
  final bool loading;
  final String? error;
  final LicenseInfo? info;

  const LicenseState({
    required this.loading,
    required this.error,
    required this.info,
  });

  factory LicenseState.initial() =>
      const LicenseState(loading: false, error: null, info: null);

  LicenseState copyWith({bool? loading, String? error, LicenseInfo? info}) {
    return LicenseState(
      loading: loading ?? this.loading,
      error: error,
      info: info ?? this.info,
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

  LicenseController({required this.api, required this.storage})
    : super(LicenseState.initial());

  Future<void> load() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final licenseKey = await storage.getLicenseKey();
      final deviceId = await _ensureDeviceId();
      final last = await storage.getLastInfo();

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
      state = state.copyWith(loading: false, error: e.toString());
    }
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
      state = state.copyWith(error: 'Ingresa la clave de licencia');
      return;
    }

    state = state.copyWith(loading: true, error: null);
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
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> check() async {
    final licenseKey = await storage.getLicenseKey();
    final deviceId = await _ensureDeviceId();
    if (licenseKey == null || licenseKey.isEmpty) {
      state = state.copyWith(error: 'Ingresa la clave de licencia');
      return;
    }

    state = state.copyWith(loading: true, error: null);
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
        fechaInicio: DateTime.tryParse((map['fecha_inicio'] ?? '').toString()),
        fechaFin: DateTime.tryParse((map['fecha_fin'] ?? '').toString()),
        lastCheckedAt: DateTime.now(),
      );

      await storage.setLastInfo(info);
      state = state.copyWith(loading: false, info: info);
    } on LicenseApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> startDemo({
    required String nombreNegocio,
    required String rolNegocio,
    required String contactoNombre,
    required String contactoTelefono,
  }) async {
    final deviceId = await _ensureDeviceId();

    state = state.copyWith(loading: true, error: null);
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
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> applyOfflineLicenseFile(Map<String, dynamic> licenseFile) async {
    final deviceId = await _ensureDeviceId();
    state = state.copyWith(loading: true, error: null);
    try {
      final map = await api.verifyOfflineFile(
        baseUrl: kLicenseBackendBaseUrl,
        licenseFile: licenseFile,
        deviceIdCheck: deviceId,
      );

      final signatureOk = map['signature_ok'] == true;
      final expired = map['expired'] == true;
      final deviceMatch = map['device_match'];
      if (!signatureOk) {
        throw const LicenseApiException(
          message: 'Archivo de licencia inválido (firma no válida)',
        );
      }
      if (expired) {
        throw const LicenseApiException(message: 'La licencia está vencida');
      }
      if (deviceMatch == false) {
        throw const LicenseApiException(
          message: 'Este archivo no corresponde a este dispositivo',
        );
      }

      final payload = (map['payload'] is Map)
          ? (map['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};
      final projectCode = (payload['project_code'] ?? '').toString().trim();
      if (projectCode.isNotEmpty && projectCode != kFullposProjectCode) {
        throw LicenseApiException(
          message: 'Archivo de licencia no corresponde a $kFullposProjectCode',
        );
      }

      final licenseKey = (payload['license_key'] ?? '').toString().trim();
      if (licenseKey.isEmpty) {
        throw const LicenseApiException(
          message: 'Archivo de licencia sin clave',
        );
      }

      await storage.setLicenseKey(licenseKey);

      // Activar contra backend para registrar el dispositivo y obtener fechas.
      await activate();
    } on LicenseApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
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
