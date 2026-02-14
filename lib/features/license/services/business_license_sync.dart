import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../registration/services/business_identity_storage.dart';
import '../data/license_models.dart';
import '../license_config.dart';
import 'business_license_api.dart';
import 'license_file_storage.dart';
import 'license_storage.dart';

class BusinessLicenseSync {
  static const _kLastPollIso = 'license.business_poll_at_iso_v1';

  final BusinessIdentityStorage _identity;
  final BusinessLicenseApi _api;
  final LicenseFileStorage _file;
  final LicenseStorage _storage;

  BusinessLicenseSync({
    BusinessIdentityStorage? identity,
    BusinessLicenseApi? api,
    LicenseFileStorage? file,
    LicenseStorage? storage,
  }) : _identity = identity ?? BusinessIdentityStorage(),
       _api = api ?? BusinessLicenseApi(),
       _file = file ?? LicenseFileStorage(),
       _storage = storage ?? LicenseStorage();

  Future<bool> applyLocalLicenseIfValid() async {
    final token = await _file.readToken();
    if (token == null) return false;

    try {
      final decoded = _decodeTokenToLicenseFile(token);
      final info = await _verifyLicenseFile(decoded);
      if (info == null) return false;

      await _storage.setLicenseKey(info.licenseKey);
      await _storage.setLastInfo(info);
      return info.isActive && !info.isExpired;
    } catch (_) {
      return false;
    }
  }

  Future<void> tryPollFromCloudIfDue({
    Duration minInterval = const Duration(minutes: 30),
    Duration networkTimeout = const Duration(seconds: 4),
  }) async {
    final businessId = await _identity.getBusinessId();
    if (businessId == null || businessId.trim().isEmpty) return;

    final sp = await SharedPreferences.getInstance();
    final lastIso = (sp.getString(_kLastPollIso) ?? '').trim();
    final last = DateTime.tryParse(lastIso);
    if (last != null) {
      final age = DateTime.now().difference(last);
      if (age < minInterval) return;
    }

    await sp.setString(_kLastPollIso, DateTime.now().toIso8601String());

    String? token;
    try {
      token = await _api
          .getLicenseToken(
            baseUrl: kLicenseBackendBaseUrl,
            businessId: businessId,
          )
          .timeout(networkTimeout);
    } catch (_) {
      return;
    }

    if (token == null) return;

    try {
      await _file.writeToken(token);
    } catch (_) {
      // Still try to apply even if file write fails.
    }

    // Apply to SharedPreferences cache so the router gate can use it offline.
    final decoded = _decodeTokenToLicenseFile(token);
    final info = await _verifyLicenseFile(decoded);
    if (info == null) return;

    await _storage.setLicenseKey(info.licenseKey);
    await _storage.setLastInfo(info);
  }

  Map<String, dynamic> _decodeTokenToLicenseFile(String token) {
    final bytes = _base64UrlDecode(token.trim());
    final raw = utf8.decode(bytes, allowMalformed: true);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw Exception('license_token inválido');
    }
    return decoded.cast<String, dynamic>();
  }

  List<int> _base64UrlDecode(String input) {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return base64Decode(s);
  }

  Future<LicenseInfo?> _verifyLicenseFile(
    Map<String, dynamic> licenseFile,
  ) async {
    final payload = (licenseFile['payload'] is Map)
        ? (licenseFile['payload'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final signatureB64 = (licenseFile['signature'] ?? '').toString().trim();
    final alg = (licenseFile['alg'] ?? '').toString().trim();

    if (payload.isEmpty || signatureB64.isEmpty) return null;
    if (alg.isNotEmpty && alg.toUpperCase() != 'ED25519') return null;

    // Firma: Ed25519 sobre JSON.stringify(payload) (mismo formato que backend).
    final payloadJson = jsonEncode(payload);
    final signatureBytes = base64Decode(signatureB64);
    final storedKeyB64 = await _storage.getOfflineSigningPublicKeyB64();
    final pubKeyBytes = base64Decode(
      (storedKeyB64 ?? kOfflineLicenseSigningPublicKeyB64).trim(),
    );
    if (pubKeyBytes.length != 32) return null;

    final algorithm = Ed25519();
    final publicKey = SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519);

    final isValid = await algorithm.verify(
      utf8.encode(payloadJson),
      signature: Signature(signatureBytes, publicKey: publicKey),
    );

    if (!isValid) return null;

    // Proyecto
    final projectCode = (payload['project_code'] ?? '').toString().trim();
    if (projectCode.isNotEmpty && projectCode != kFullposProjectCode) {
      return null;
    }

    // Business binding (nuevo flujo)
    final payloadBusinessId = (payload['business_id'] ?? '').toString().trim();
    if (payloadBusinessId.isNotEmpty) {
      final local = await _identity.getBusinessId();
      if (local == null || local.trim().isEmpty) {
        await _identity.setBusinessId(payloadBusinessId);
      } else if (local.trim() != payloadBusinessId) {
        return null;
      }
    }

    // Fechas (compat: old/new payload names)
    final expiresAt = DateTime.tryParse(
      (payload['expires_at'] ?? payload['fecha_fin'] ?? '').toString(),
    );
    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
      return null;
    }

    final startsAt = DateTime.tryParse(
      (payload['starts_at'] ?? payload['fecha_inicio'] ?? '').toString(),
    );

    final licenseKey = (payload['license_key'] ?? '').toString().trim();
    if (licenseKey.isEmpty) return null;

    final planOrTipo = (payload['plan'] ?? payload['tipo'] ?? '').toString();

    // No bloqueamos por device_id: si viene, se respeta para compat.
    final deviceId = (payload['device_id'] ?? '').toString().trim();

    return LicenseInfo(
      backendBaseUrl: kLicenseBackendBaseUrl,
      licenseKey: licenseKey,
      deviceId: deviceId,
      projectCode: kFullposProjectCode,
      ok: true,
      code: 'OK',
      tipo: planOrTipo.trim().isEmpty ? null : planOrTipo.trim(),
      estado: 'ACTIVA',
      motivo: null,
      fechaInicio: startsAt,
      fechaFin: expiresAt,
      maxDispositivos: _asInt(
        payload['max_devices'] ?? payload['max_dispositivos'],
      ),
      usados: null,
      lastCheckedAt: DateTime.now(),
    );
  }
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  return int.tryParse(v.toString());
}
