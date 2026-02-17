import 'dart:convert';

import '../../../core/network/api_client.dart';

class BusinessRegistrationException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  final String? existingBusinessId;

  const BusinessRegistrationException({
    required this.statusCode,
    required this.message,
    this.code,
    this.existingBusinessId,
  });

  @override
  String toString() {
    return 'BusinessRegistrationException(status=$statusCode code=$code message=$message existingBusinessId=$existingBusinessId)';
  }
}

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

      Map<String, dynamic>? decodedMap;
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          decodedMap = decoded;
        }
      } catch (_) {}

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw BusinessRegistrationException(
          statusCode: res.statusCode,
          message: (decodedMap?['message'] ?? 'Registro falló').toString(),
          code: decodedMap?['code']?.toString(),
          existingBusinessId: decodedMap?['existing_business_id']?.toString(),
        );
      }

      final decoded = decodedMap ?? jsonDecode(res.body);
      if (decoded is Map && decoded['ok'] == false) {
        throw BusinessRegistrationException(
          statusCode: res.statusCode,
          message: (decoded['message'] ?? 'Registro no exitoso').toString(),
          code: decoded['code']?.toString(),
          existingBusinessId: decoded['existing_business_id']?.toString(),
        );
      }
    }

    // Spec primary path: /businesses/register
    try {
      await postAndValidate('/businesses/register');
      return;
    } on BusinessRegistrationException catch (e) {
      // For business failures (409, 422, etc), preserve exact backend error.
      // Only fallback to /api when endpoint is not found.
      if (e.statusCode != 404) {
        rethrow;
      }
    } catch (_) {
      // Try /api variant for base URLs with a mounted API prefix.
    }

    await postAndValidate('/api/businesses/register');
  }
}
