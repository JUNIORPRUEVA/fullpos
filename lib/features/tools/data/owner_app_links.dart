import 'dart:convert';

import '../../../core/config/backend_config.dart';
import '../../../core/network/api_client.dart';

abstract final class OwnerAppDistribution {
  static const String androidDownloadUrl =
      'https://github.com/JUNIORPRUEVA/fullpos-releases/releases/latest/download/FullPOS-Owner-Android.apk';
  static const String promotionalImageUrl =
      'https://i.postimg.cc/prxyFZXH/Chat-GPT-Image-12-jun-2026-08-47-40-p-m.png';
  static const String androidSha256 =
      '7edbe59231fa8f5919782f2ab4e61eb4a386f07e199c43d3bf7741f6214c27f3';
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
