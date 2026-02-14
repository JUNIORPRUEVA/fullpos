import 'dart:convert';

import '../../../core/network/api_client.dart';

class BusinessRegistrationApi {
  BusinessRegistrationApi();

  Future<void> register({
    required String baseUrl,
    required Map<String, dynamic> payload,
  }) async {
    final api = ApiClient(baseUrl: baseUrl);

    Future<void> postAndValidate(String path) async {
      final res = await api.postJson(
        path,
        body: payload,
        timeout: const Duration(seconds: 8),
      );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Registro falló: HTTP ${res.statusCode} ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['ok'] == false) {
        throw Exception((decoded['message'] ?? 'Registro no exitoso').toString());
      }
    }

    // Spec primary path: /businesses/register
    try {
      await postAndValidate('/businesses/register');
    } catch (_) {
      // If baseUrl already includes /api or server only exposes /api/businesses.
      await postAndValidate('/api/businesses/register');
    }
  }
}
