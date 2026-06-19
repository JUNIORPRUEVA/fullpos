import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/identity/identity_recovery_bundle.dart';
import '../../../core/storage/prefs_safe.dart';
import '../../registration/services/business_identity_storage.dart';
import '../data/license_models.dart';

class LicenseStorage {
  static const _kBackendBaseUrl = 'license.backendBaseUrl';
  static const _kLicenseKey = 'license.licenseKey';
  static const _kDeviceId = 'license.deviceId';
  static const _kLastInfo = 'license.lastInfo';
  static const _kLastInfoSource = 'license.lastInfoSource';
  static const _kCloudDeniedAtIso = 'license.cloudDeniedAtIso_v1';
  static const _kSigningPubKeyB64 = 'license_signing_pubkey_b64_v1';
  static const _kLastRenewalOrderId = 'license.lastRenewalOrderId_v1';
  static const _kLastPaypalOrderId = 'license.lastPaypalOrderId_v1';

  /// Valores:
  /// - 'cloud': cache actualizado desde /businesses/:id/license
  /// - 'offline': cache proveniente de archivo aplicado por el usuario
  Future<String?> getLastInfoSource() async {
    final sp = await _prefs();
    final v = sp.getString(_kLastInfoSource);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setLastInfoSource(String value) async {
    final sp = await _prefs();
    await sp.setString(_kLastInfoSource, value.trim());
    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'license_set_last_info_source',
    );
  }

  Future<void> clearLastInfo() async {
    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'license_clear_last_info_before',
    );
    final sp = await _prefs();
    await sp.remove(_kLastInfo);
    await sp.remove(_kLastInfoSource);
  }

  /// Timestamp del último "204 no license" recibido desde la nube.
  ///
  /// Se usa para evitar que un TRIAL puramente local ignore una revocación
  /// explícita del backend cuando sí hubo conectividad.
  Future<DateTime?> getCloudDeniedAt() async {
    final sp = await _prefs();
    final raw = (sp.getString(_kCloudDeniedAtIso) ?? '').trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setCloudDeniedNow() async {
    final sp = await _prefs();
    await sp.setString(
      _kCloudDeniedAtIso,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> clearCloudDenied() async {
    final sp = await _prefs();
    await sp.remove(_kCloudDeniedAtIso);
  }

  Future<String?> getBackendBaseUrl() async {
    final sp = await _prefs();
    final v = sp.getString(_kBackendBaseUrl);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setBackendBaseUrl(String value) async {
    final sp = await _prefs();
    await sp.setString(_kBackendBaseUrl, value.trim());
  }

  Future<String?> getLicenseKey() async {
    final sp = await _prefs();
    final v = sp.getString(_kLicenseKey);
    if (v == null) {
      await _recoverMissing('license_key_missing');
      final recovered = sp.getString(_kLicenseKey);
      if (recovered == null) return null;
      final trimmedRecovered = recovered.trim();
      return trimmedRecovered.isEmpty ? null : trimmedRecovered;
    }
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setLicenseKey(String value) async {
    final sp = await _prefs();
    await sp.setString(_kLicenseKey, value.trim());
    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'license_set_license_key',
    );
  }

  Future<String?> getDeviceId() async {
    final sp = await _prefs();
    final v = sp.getString(_kDeviceId);
    if (v == null) {
      await _recoverMissing('license_device_id_missing');
      final recovered = sp.getString(_kDeviceId);
      if (recovered == null) return null;
      final trimmedRecovered = recovered.trim();
      return trimmedRecovered.isEmpty ? null : trimmedRecovered;
    }
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setDeviceId(String value) async {
    final sp = await _prefs();
    await sp.setString(_kDeviceId, value.trim());
    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'license_set_device_id',
    );
  }

  Future<LicenseInfo?> getLastInfo() async {
    final sp = await _prefs();
    final raw = sp.getString(_kLastInfo);
    if (raw == null || raw.trim().isEmpty) {
      await _recoverMissing('license_last_info_missing');
      final recovered = sp.getString(_kLastInfo);
      if (recovered == null || recovered.trim().isEmpty) return null;
      return _parseLastInfo(recovered);
    }
    return _parseLastInfo(raw);
  }

  LicenseInfo? _parseLastInfo(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return LicenseInfo.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  Future<void> setLastInfo(LicenseInfo info) async {
    await _validateBusinessIdCompatibility(info);
    final sp = await _prefs();
    await sp.setString(_kLastInfo, jsonEncode(info.toJson()));
    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'license_set_last_info',
    );
  }

  Future<void> clearAll() async {
    await IdentityRecoveryBundle.instance.saveFromCurrentState(
      'license_clear_all_before',
    );
    final sp = await _prefs();
    await sp.remove(_kBackendBaseUrl);
    await sp.remove(_kLicenseKey);
    await sp.remove(_kDeviceId);
    await sp.remove(_kLastInfo);
    await sp.remove(_kLastInfoSource);
    await sp.remove(_kCloudDeniedAtIso);
    await sp.remove(_kLastRenewalOrderId);
    await sp.remove(_kLastPaypalOrderId);
  }

  Future<String?> getOfflineSigningPublicKeyB64() async {
    final sp = await _prefs();
    final v = sp.getString(_kSigningPubKeyB64);
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> setOfflineSigningPublicKeyB64(String value) async {
    final sp = await _prefs();
    await sp.setString(_kSigningPubKeyB64, value.trim());
  }

  Future<String?> getLastRenewalOrderId() async {
    final sp = await _prefs();
    final v = (sp.getString(_kLastRenewalOrderId) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  Future<void> setLastRenewalOrderId(String? value) async {
    final sp = await _prefs();
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      await sp.remove(_kLastRenewalOrderId);
      return;
    }
    await sp.setString(_kLastRenewalOrderId, normalized);
  }

  Future<String?> getLastPaypalOrderId() async {
    final sp = await _prefs();
    final v = (sp.getString(_kLastPaypalOrderId) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  Future<void> setLastPaypalOrderId(String? value) async {
    final sp = await _prefs();
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      await sp.remove(_kLastPaypalOrderId);
      return;
    }
    await sp.setString(_kLastPaypalOrderId, normalized);
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

  Future<SharedPreferences> _prefs() async {
    final prefs = await PrefsSafe.getInstance();
    if (prefs != null) return prefs;
    return SharedPreferences.getInstance();
  }

  Future<bool> _recoverMissing(String reason) {
    return IdentityRecoveryBundle.instance.recoverToSharedPreferences(reason);
  }

  Future<void> _validateBusinessIdCompatibility(LicenseInfo info) async {
    final infoBusinessId = (info.businessId ?? '').trim();
    if (infoBusinessId.isEmpty) return;

    final localBusinessId =
        ((await BusinessIdentityStorage().getBusinessId()) ?? '').trim();
    if (localBusinessId.isNotEmpty) {
      if (localBusinessId == infoBusinessId) return;
      await IdentityRecoveryBundle.instance.markRecoveryRequired(
        'license_last_info_local_business_id_conflict',
      );
      await IdentityRecoveryBundle.instance.log(
        'license_last_info_save_blocked_local_conflict',
      );
      throw StateError('license lastInfo local business_id conflict');
    }

    final bundle = await IdentityRecoveryBundle.instance.loadBestAvailable();
    final bundleBusinessId = (bundle?.businessId ?? '').trim();
    if (bundleBusinessId.isNotEmpty && bundleBusinessId != infoBusinessId) {
      await IdentityRecoveryBundle.instance.markRecoveryRequired(
        'license_last_info_business_id_conflict',
      );
      await IdentityRecoveryBundle.instance.log(
        'license_last_info_save_blocked_conflict',
      );
      throw StateError('license lastInfo business_id conflict');
    }
  }
}
