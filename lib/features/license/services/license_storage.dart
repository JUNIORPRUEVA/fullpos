import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/license_models.dart';

class LicenseStorage {
  static const _kBackendBaseUrl = 'license.backendBaseUrl';
  static const _kLicenseKey = 'license.licenseKey';
  static const _kDeviceId = 'license.deviceId';
  static const _kLastInfo = 'license.lastInfo';
  static const _kLastInfoSource = 'license.lastInfoSource';
  static const _kCloudDeniedAtIso = 'license.cloudDeniedAtIso_v1';
  static const _kSigningPubKeyB64 = 'license_signing_pubkey_b64_v1';

  /// Valores:
  /// - 'cloud': cache actualizado desde /businesses/:id/license
  /// - 'offline': cache proveniente de archivo aplicado por el usuario
  Future<String?> getLastInfoSource() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kLastInfoSource);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setLastInfoSource(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLastInfoSource, value.trim());
  }

  Future<void> clearLastInfo() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kLastInfo);
    await sp.remove(_kLastInfoSource);
  }

  /// Timestamp del último "204 no license" recibido desde la nube.
  ///
  /// Se usa para evitar que un TRIAL puramente local ignore una revocación
  /// explícita del backend cuando sí hubo conectividad.
  Future<DateTime?> getCloudDeniedAt() async {
    final sp = await SharedPreferences.getInstance();
    final raw = (sp.getString(_kCloudDeniedAtIso) ?? '').trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setCloudDeniedNow() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kCloudDeniedAtIso,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> clearCloudDenied() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kCloudDeniedAtIso);
  }

  Future<String?> getBackendBaseUrl() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kBackendBaseUrl);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setBackendBaseUrl(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kBackendBaseUrl, value.trim());
  }

  Future<String?> getLicenseKey() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kLicenseKey);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setLicenseKey(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLicenseKey, value.trim());
  }

  Future<String?> getDeviceId() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kDeviceId);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setDeviceId(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kDeviceId, value.trim());
  }

  Future<LicenseInfo?> getLastInfo() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kLastInfo);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return LicenseInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastInfo(LicenseInfo info) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kLastInfo, jsonEncode(info.toJson()));
  }

  Future<void> clearAll() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kBackendBaseUrl);
    await sp.remove(_kLicenseKey);
    await sp.remove(_kDeviceId);
    await sp.remove(_kLastInfo);
    await sp.remove(_kLastInfoSource);
    await sp.remove(_kCloudDeniedAtIso);
  }

  Future<String?> getOfflineSigningPublicKeyB64() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString(_kSigningPubKeyB64);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setOfflineSigningPublicKeyB64(String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kSigningPubKeyB64, value.trim());
  }

  /// Determina si hay una licencia activa según lo último guardado localmente.
  ///
  /// Nota: esto evita llamadas de red en el router. La pantalla de Licencia
  /// puede usar "Verificar" para refrescar el estado desde el backend.
  Future<bool> hasActiveLicenseCached() async {
    final info = await getLastInfo();
    if (info == null) return false;
    if (!info.isActive) return false;
    if (info.isExpired) return false;
    return true;
  }
}
