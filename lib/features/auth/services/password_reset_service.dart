import 'dart:convert';

import '../../../core/network/api_client.dart';
import '../../../features/license/license_config.dart';
import '../../registration/services/business_identity_storage.dart';

Map<String, dynamic> _decodeJsonMap(String raw) {
  try {
    final decoded = raw.isEmpty ? const <String, dynamic>{} : jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
  } catch (_) {}
  return const <String, dynamic>{};
}

class PasswordResetService {
  PasswordResetService({
    BusinessIdentityStorage? identityStorage,
    ApiClient? apiClient,
    Future<String?> Function()? businessIdLoader,
  }) : _identityStorage = identityStorage ?? BusinessIdentityStorage(),
       _apiClient = apiClient ?? ApiClient(baseUrl: kLicenseBackendBaseUrl),
       _businessIdLoader = businessIdLoader;

  final BusinessIdentityStorage _identityStorage;
  final ApiClient _apiClient;
  final Future<String?> Function()? _businessIdLoader;

  Future<String> _requireBusinessId() async {
    final businessId =
        await (_businessIdLoader?.call() ?? _identityStorage.getBusinessId());
    if (businessId == null || businessId.trim().isEmpty) {
      throw StateError(
        'No se encontró el business_id local. Verifica que la PC esté registrada.',
      );
    }
    return businessId.trim();
  }

  String _extractMessage(Map<String, dynamic> data, String fallback) {
    final message = (data['message'] ?? '').toString().trim();
    if (message.isNotEmpty) return message;
    final error = (data['error'] ?? '').toString().trim();
    if (error.isNotEmpty) return error;
    return fallback;
  }

  Future<void> confirmSupportToken({
    required String username,
    required String token,
  }) async {
    final businessId = await _requireBusinessId();
    final rawToken = token.trim();
    final compactToken = rawToken.replaceAll(RegExp(r'\s+'), '');
    final isAdminPanelToken = RegExp(
      r'^[a-fA-F0-9]{64}$',
    ).hasMatch(compactToken);
    final payload = {
      'business_id': businessId,
      if (!isAdminPanelToken) 'username': username.trim().toLowerCase(),
      'token': isAdminPanelToken
          ? compactToken.toLowerCase()
          : rawToken.toUpperCase(),
    };

    final res = await _apiClient.postJson(
      isAdminPanelToken
          ? '/api/password-reset/admin-token/validate'
          : '/api/password-reset/support-token/confirm',
      body: payload,
      timeout: const Duration(seconds: 12),
    );
    final data = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        _extractMessage(
          data,
          'No se pudo validar el token (HTTP ${res.statusCode})',
        ),
      );
    }

    if (data['ok'] != true) {
      throw Exception(_extractMessage(data, 'Token inválido o expirado'));
    }
  }

  Future<String> requestSupportMessage({
    required String username,
    String? message,
  }) async {
    final businessId = await _requireBusinessId();

    final identity = await _identityStorage.getIdentity();
    final payload = {
      'business_id': businessId,
      'username': username.trim().toLowerCase(),
      'business_name': identity?.businessName.trim(),
      'owner_name': identity?.ownerName.trim(),
      'phone': identity?.phone.trim(),
      'email': identity?.email?.trim(),
      'message':
          (message ??
                  'Cliente solicita recuperación de contraseña administrador.')
              .trim(),
    };

    final res = await _apiClient.postJson(
      '/api/support/request',
      body: payload,
      timeout: const Duration(seconds: 15),
    );
    final data = _decodeJsonMap(res.body);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        _extractMessage(
          data,
          'No se pudo enviar la solicitud (HTTP ${res.statusCode})',
        ),
      );
    }

    if (data['ok'] != true) {
      throw Exception(
        (data['message'] ?? 'No se pudo enviar la solicitud').toString(),
      );
    }

    final msg = (data['message'] ?? '').toString().trim();
    return msg.isNotEmpty
        ? msg
        : 'Tu mensaje fue enviado. Mantente pendiente a la respuesta de soporte.';
  }
}
