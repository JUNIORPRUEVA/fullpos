import 'dart:convert';

import '../../../core/config/backend_config.dart';
import '../../../core/network/api_client.dart';

abstract final class OwnerAppDistribution {
  static const String androidDownloadUrl =
      'https://github.com/JUNIORPRUEVA/fullposOwner_release/releases/latest/download/app-debug.apk';
  static const String promotionalImageUrl =
      'https://i.postimg.cc/prxyFZXH/Chat-GPT-Image-12-jun-2026-08-47-40-p-m.png';
  static const String androidSha256 =
      'd34a676ac6277032f8ac4c51d8c02043efbbfeb473d96285d95ff9d310bcc73c';
}

class OwnerAppLinks {
  final String? androidUrl;
  final String? iosUrl;
  final String? version;

  const OwnerAppLinks({this.androidUrl, this.iosUrl, this.version});

  static Future<OwnerAppLinks> fetch() async {
    final api = ApiClient(baseUrl: backendBaseUrl);
    final res = await api.get('/api/downloads/owner-app');
    if (res.statusCode != 200) {
      throw Exception('No se pudo obtener links (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return OwnerAppLinks(
      androidUrl: data['androidUrl'] as String?,
      iosUrl: data['iosUrl'] as String?,
      version: data['version'] as String?,
    );
  }
}
