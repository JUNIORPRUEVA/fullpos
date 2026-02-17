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
  PasswordResetService({BusinessIdentityStorage? identityStorage})
    : _identityStorage = identityStorage ?? BusinessIdentityStorage();

  final BusinessIdentityStorage _identityStorage;

  String _extractMessage(
    Map<String, dynamic> data,
    String fallback,
  ) {
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
    final businessId = await _identityStorage.getBusinessId();
    if (businessId == null || businessId.trim().isEmpty) {
      throw StateError(
        'No se encontró el business_id local. Verifica que la PC esté registrada.',
      );
    }

    final api = ApiClient(baseUrl: kLicenseBackendBaseUrl);
    final payload = {
      'business_id': businessId,
      'username': username.trim(),
      'token': token.trim(),
    };

    Map<String, dynamic> data;
    String? firstErrorMessage;
    try {
      final res = await api.postJson(
        '/api/password-reset/support-token/confirm',
        body: payload,
        timeout: const Duration(seconds: 12),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        data = _decodeJsonMap(res.body);
      } else {
        final errData = _decodeJsonMap(res.body);
        final message = _extractMessage(
          errData,
          'No se pudo validar el token (HTTP ${res.statusCode})',
        );

        if (res.statusCode == 404) {
          firstErrorMessage = message;
          throw Exception(message);
        }

        throw Exception(message);
      }
    } catch (error) {
      final fallbackRes = await api.postJson(
        '/password-reset/support-token/confirm',
        body: payload,
        timeout: const Duration(seconds: 12),
      );
      if (fallbackRes.statusCode < 200 || fallbackRes.statusCode >= 300) {
        final errData = _decodeJsonMap(fallbackRes.body);
        final fallbackMsg = _extractMessage(
          errData,
          'No se pudo validar el token (HTTP ${fallbackRes.statusCode})',
        );

        if (firstErrorMessage != null && firstErrorMessage.isNotEmpty) {
          throw Exception(firstErrorMessage);
        }

        final errorText = error.toString().replaceFirst('Exception: ', '').trim();
        if (errorText.isNotEmpty && !errorText.startsWith('ApiException')) {
          throw Exception('$fallbackMsg. Detalle: $errorText');
        }

        throw Exception(fallbackMsg);
      }
      data = _decodeJsonMap(fallbackRes.body);
    }

    if (data['ok'] != true) {
      throw Exception((data['message'] ?? 'Token inválido o expirado').toString());
    }
  }

  Future<String> requestSupportMessage({
    required String username,
    String? message,
  }) async {
    final businessId = await _identityStorage.getBusinessId();
    if (businessId == null || businessId.trim().isEmpty) {
      throw StateError(
        'No se encontró el business_id local. Verifica que la PC esté registrada.',
      );
    }

    final identity = await _identityStorage.getIdentity();
    final api = ApiClient(baseUrl: kLicenseBackendBaseUrl);
    final payload = {
      'business_id': businessId,
      'username': username.trim(),
      'business_name': identity?.businessName.trim(),
      'owner_name': identity?.ownerName.trim(),
      'phone': identity?.phone.trim(),
      'email': identity?.email?.trim(),
      'message': (message ?? 'Cliente solicita recuperación de contraseña administrador.').trim(),
    };

    Map<String, dynamic> data;
    String? firstErrorMessage;
    try {
      final res = await api.postJson(
        '/api/support/request',
        body: payload,
        timeout: const Duration(seconds: 15),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        data = _decodeJsonMap(res.body);
      } else {
        final errData = _decodeJsonMap(res.body);
        final msg = _extractMessage(
          errData,
          'No se pudo enviar la solicitud (HTTP ${res.statusCode})',
        );

        if (res.statusCode == 404) {
          firstErrorMessage = msg;
          throw Exception(msg);
        }

        throw Exception(msg);
      }
    } catch (error) {
      final fallbackRes = await api.postJson(
        '/support/request',
        body: payload,
        timeout: const Duration(seconds: 15),
      );
      if (fallbackRes.statusCode < 200 || fallbackRes.statusCode >= 300) {
        final errData = _decodeJsonMap(fallbackRes.body);
        final fallbackMsg = _extractMessage(
          errData,
          'No se pudo enviar la solicitud (HTTP ${fallbackRes.statusCode})',
        );

        if (firstErrorMessage != null && firstErrorMessage.isNotEmpty) {
          throw Exception(firstErrorMessage);
        }

        final errorText = error.toString().replaceFirst('Exception: ', '').trim();
        if (errorText.isNotEmpty && !errorText.startsWith('ApiException')) {
          throw Exception('$fallbackMsg. Detalle: $errorText');
        }

        throw Exception(fallbackMsg);
      }
      data = _decodeJsonMap(fallbackRes.body);
    }

    if (data['ok'] != true) {
      throw Exception((data['message'] ?? 'No se pudo enviar la solicitud').toString());
    }

    final msg = (data['message'] ?? '').toString().trim();
    return msg.isNotEmpty
        ? msg
        : 'Tu mensaje fue enviado. Mantente pendiente a la respuesta de soporte.';
  }
}
