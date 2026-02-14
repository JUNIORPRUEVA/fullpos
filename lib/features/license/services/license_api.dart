import 'dart:convert';

import '../../../core/network/api_client.dart';

import '../data/license_models.dart';

class LicenseApi {
  LicenseApi();

  Future<Map<String, dynamic>> _postJson({
    required String baseUrl,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final api = ApiClient(baseUrl: baseUrl);
    final res = await api.postJson(
      path,
      headers: const {
        'accept': 'application/json',
      },
      body: body,
      timeout: const Duration(seconds: 8),
    );

    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) map = decoded;
    } catch (_) {
      // ignore
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (map?['message'] ?? map?['error'] ?? res.body).toString();
      final code = map?['code']?.toString();
      throw LicenseApiException(
        message: msg,
        statusCode: res.statusCode,
        code: code,
      );
    }

    if (map == null) {
      throw LicenseApiException(
        message: 'Respuesta inválida del servidor',
        statusCode: res.statusCode,
      );
    }

    if (map['ok'] == false) {
      throw LicenseApiException(
        message: (map['message'] ?? 'Operación no exitosa').toString(),
        statusCode: res.statusCode,
        code: map['code']?.toString(),
      );
    }

    return map;
  }

  Future<Map<String, dynamic>> activate({
    required String baseUrl,
    required String licenseKey,
    required String deviceId,
    required String projectCode,
  }) {
    return _postJson(
      baseUrl: baseUrl,
      path: '/api/licenses/activate',
      body: {
        'license_key': licenseKey,
        'device_id': deviceId,
        'project_code': projectCode,
      },
    );
  }

  Future<Map<String, dynamic>> check({
    required String baseUrl,
    required String licenseKey,
    required String deviceId,
    required String projectCode,
  }) async {
    final api = ApiClient(baseUrl: baseUrl);
    final res = await api.postJson(
      '/api/licenses/check',
      headers: const {
        'accept': 'application/json',
      },
      body: {
        'license_key': licenseKey,
        'device_id': deviceId,
        'project_code': projectCode,
      },
      timeout: const Duration(seconds: 8),
    );

    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) map = decoded;
    } catch (_) {
      // ignore
    }

    if (map == null) {
      throw LicenseApiException(
        message: 'Respuesta inválida del servidor',
        statusCode: res.statusCode,
      );
    }

    // Importante: check() DEBE devolver estados ok=false (BLOQUEADA/VENCIDA/NOT_FOUND)
    // para que el POS pueda redirigir a /license o /license-blocked.
    return map;
  }

  Future<Map<String, dynamic>> autoActivateByDevice({
    required String baseUrl,
    required String deviceId,
    required String projectCode,
  }) async {
    final api = ApiClient(baseUrl: baseUrl);
    final res = await api.postJson(
      '/api/licenses/auto-activate',
      headers: const {
        'accept': 'application/json',
      },
      body: {
        'device_id': deviceId,
        'project_code': projectCode,
      },
      timeout: const Duration(seconds: 8),
    );

    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) map = decoded;
    } catch (_) {
      // ignore
    }

    if (map == null) {
      throw LicenseApiException(
        message: 'Respuesta inválida del servidor',
        statusCode: res.statusCode,
      );
    }

    // Importante: puede devolver ok=false (NO_ACTIVE_LICENSE / NO_HISTORY / BLOCKED)
    // y eso se usa para decidir el gate del router.
    return map;
  }

  Future<Map<String, dynamic>> startDemo({
    required String baseUrl,
    required String deviceId,
    required String projectCode,
    required String nombreNegocio,
    required String rolNegocio,
    required String contactoNombre,
    required String contactoTelefono,
  }) {
    return _postJson(
      baseUrl: baseUrl,
      path: '/api/licenses/start-demo',
      body: {
        'project_code': projectCode,
        'device_id': deviceId,
        'nombre_negocio': nombreNegocio,
        'rol_negocio': rolNegocio,
        'contacto_nombre': contactoNombre,
        'contacto_telefono': contactoTelefono,
      },
    );
  }

  Future<Map<String, dynamic>> verifyOfflineFile({
    required String baseUrl,
    required Map<String, dynamic> licenseFile,
    String? deviceIdCheck,
  }) {
    final query = (deviceIdCheck != null && deviceIdCheck.trim().isNotEmpty)
        ? {'device_id': deviceIdCheck.trim()}
        : null;

    final api = ApiClient(baseUrl: baseUrl);
    return () async {
      final res = await api.postJson(
        '/api/licenses/verify-offline-file',
        headers: const {'accept': 'application/json'},
        queryParameters: query,
        body: licenseFile,
        timeout: const Duration(seconds: 8),
      );

      Map<String, dynamic>? map;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) map = decoded;
      } catch (_) {}

      if (res.statusCode < 200 || res.statusCode >= 300) {
        final msg = (map?['message'] ?? map?['error'] ?? res.body).toString();
        final code = map?['code']?.toString();
        throw LicenseApiException(
          message: msg,
          statusCode: res.statusCode,
          code: code,
        );
      }
      if (map == null) {
        throw LicenseApiException(
          message: 'Respuesta inválida del servidor',
          statusCode: res.statusCode,
        );
      }
      if (map['ok'] == false) {
        throw LicenseApiException(
          message: (map['message'] ?? 'Operación no exitosa').toString(),
          statusCode: res.statusCode,
          code: map['code']?.toString(),
        );
      }
      return map;
    }();
  }

  Future<Map<String, dynamic>> getPublicSigningKey({
    required String baseUrl,
  }) async {
    final api = ApiClient(baseUrl: baseUrl);
    final res = await api.get(
      '/api/licenses/public-signing-key',
      headers: const {
        'accept': 'application/json',
      },
      timeout: const Duration(seconds: 8),
    );

    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) map = decoded;
    } catch (_) {
      // ignore
    }

    if (map == null) {
      throw LicenseApiException(
        message: 'Respuesta inválida del servidor',
        statusCode: res.statusCode,
      );
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = (map['message'] ?? map['error'] ?? res.body).toString();
      throw LicenseApiException(
        message: msg,
        statusCode: res.statusCode,
        code: map['code']?.toString(),
      );
    }

    return map;
  }
}
