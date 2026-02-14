import 'dart:convert';

import '../../../core/network/api_client.dart';

class BusinessLicenseApi {
  BusinessLicenseApi();

  Future<String?> getLicenseToken({
    required String baseUrl,
    required String businessId,
  }) async {
    final api = ApiClient(baseUrl: baseUrl);

    Future<String?> getAndDecode(String path) async {
      final res = await api.get(
        path,
        headers: const {'accept': 'application/json'},
        timeout: const Duration(seconds: 8),
      );

      if (res.statusCode == 204) return null;
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('HTTP ${res.statusCode} ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return null;

      final token = (decoded['license_token'] ?? '').toString().trim();
      return token.isEmpty ? null : token;
    }

    try {
      return await getAndDecode('/businesses/$businessId/license');
    } catch (_) {
      return await getAndDecode('/api/businesses/$businessId/license');
    }
  }
}
