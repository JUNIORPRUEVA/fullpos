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

class PasswordResetRequestResult {
  final String requestId;
  final DateTime? expiresAt;

  const PasswordResetRequestResult({
    required this.requestId,
    required this.expiresAt,
  });
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

  Future<PasswordResetRequestResult> requestCode({
    required String username,
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
    };

    Map<String, dynamic> data;
    String? firstErrorMessage;
    try {
      final res = await api.postJson(
        '/api/password-reset/request',
        body: payload,
        timeout: const Duration(seconds: 12),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        data = _decodeJsonMap(res.body);
      } else {
        final errData = _decodeJsonMap(res.body);
        final message = _extractMessage(
          errData,
          'No se pudo solicitar el código (HTTP ${res.statusCode})',
        );

        // Solo intentamos fallback cuando la ruta principal no existe.
        if (res.statusCode == 404) {
          firstErrorMessage = message;
          throw Exception(message);
        }

        throw Exception(message);
      }
    } catch (error) {
      final fallbackRes = await api.postJson(
        '/password-reset/request',
        body: payload,
        timeout: const Duration(seconds: 12),
      );
      if (fallbackRes.statusCode < 200 || fallbackRes.statusCode >= 300) {
        final fallbackData = _decodeJsonMap(fallbackRes.body);
        final fallbackMsg = _extractMessage(
          fallbackData,
          'No se pudo solicitar el código (HTTP ${fallbackRes.statusCode})',
        );

        // Si también falla fallback y ya teníamos mensaje útil del primario,
        // devolvemos el más específico para el usuario.
        if (firstErrorMessage != null && firstErrorMessage!.isNotEmpty) {
          throw Exception(firstErrorMessage);
        }

        final errorText = error.toString().replaceFirst('Exception: ', '').trim();
        if (errorText.isNotEmpty && !errorText.startsWith('ApiException')) {
          throw Exception('$fallbackMsg. Detalle: $errorText');
        }

        throw Exception(
          fallbackMsg,
        );
      }
      data = _decodeJsonMap(fallbackRes.body);
    }

    if (data['ok'] != true) {
      throw Exception(
        (data['message'] ?? 'No se pudo solicitar el código').toString(),
      );
    }

    final requestId = (data['request_id'] ?? '').toString().trim();
    if (requestId.isEmpty) {
      throw Exception('Respuesta inválida del backend (request_id vacío)');
    }

    final expiresRaw = (data['expires_at'] ?? '').toString().trim();
    final expiresAt = expiresRaw.isEmpty ? null : DateTime.tryParse(expiresRaw);

    return PasswordResetRequestResult(requestId: requestId, expiresAt: expiresAt);
  }

  Future<void> confirmCode({
    required String username,
    required String requestId,
    required String code,
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
      'request_id': requestId.trim(),
      'code': code.trim(),
    };

    Map<String, dynamic> data;
    String? firstErrorMessage;
    try {
      final res = await api.postJson(
        '/api/password-reset/confirm',
        body: payload,
        timeout: const Duration(seconds: 12),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        data = _decodeJsonMap(res.body);
      } else {
        final errData = _decodeJsonMap(res.body);
        final message = _extractMessage(
          errData,
          'No se pudo validar el código (HTTP ${res.statusCode})',
        );

        if (res.statusCode == 404) {
          firstErrorMessage = message;
          throw Exception(message);
        }

        throw Exception(message);
      }
    } catch (error) {
      final fallbackRes = await api.postJson(
        '/password-reset/confirm',
        body: payload,
        timeout: const Duration(seconds: 12),
      );
      if (fallbackRes.statusCode < 200 || fallbackRes.statusCode >= 300) {
        final errData = _decodeJsonMap(fallbackRes.body);
        final fallbackMsg = _extractMessage(
          errData,
          'No se pudo validar el código (HTTP ${fallbackRes.statusCode})',
        );

        if (firstErrorMessage != null && firstErrorMessage!.isNotEmpty) {
          throw Exception(firstErrorMessage);
        }

        final errorText = error.toString().replaceFirst('Exception: ', '').trim();
        if (errorText.isNotEmpty && !errorText.startsWith('ApiException')) {
          throw Exception('$fallbackMsg. Detalle: $errorText');
        }

        throw Exception(
          fallbackMsg,
        );
      }
      data = _decodeJsonMap(fallbackRes.body);
    }

    if (data['ok'] != true) {
      throw Exception((data['message'] ?? 'Código inválido o expirado').toString());
    }
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

        if (firstErrorMessage != null && firstErrorMessage!.isNotEmpty) {
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
}
