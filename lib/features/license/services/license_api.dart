import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/license_models.dart';

class LicenseApi {
  final http.Client _client;

  LicenseApi({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String baseUrl, String path) {
    var b = baseUrl.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    if (!path.startsWith('/')) path = '/$path';
    return Uri.parse('$b$path');
  }

  Future<Map<String, dynamic>> _postJson({
    required String baseUrl,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final res = await _client.post(
      _uri(baseUrl, path),
      headers: {
        'content-type': 'application/json',
        'accept': 'application/json',
      },
      body: jsonEncode(body),
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
  }) {
    return _postJson(
      baseUrl: baseUrl,
      path: '/api/licenses/check',
      body: {
        'license_key': licenseKey,
        'device_id': deviceId,
        'project_code': projectCode,
      },
    );
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
    var path = '/api/licenses/verify-offline-file';
    if (deviceIdCheck != null && deviceIdCheck.trim().isNotEmpty) {
      path =
          '$path?device_id=${Uri.encodeQueryComponent(deviceIdCheck.trim())}';
    }
    return _postJson(baseUrl: baseUrl, path: path, body: licenseFile);
  }
}
