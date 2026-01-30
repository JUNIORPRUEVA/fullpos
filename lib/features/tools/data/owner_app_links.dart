import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../core/config/backend_config.dart';

class OwnerAppLinks {
  final String? androidUrl;
  final String? iosUrl;
  final String? version;

  const OwnerAppLinks({this.androidUrl, this.iosUrl, this.version});

  static Future<OwnerAppLinks> fetch() async {
    final uri = Uri.parse('$backendBaseUrl/api/downloads/owner-app');
    final res = await http.get(uri);
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
