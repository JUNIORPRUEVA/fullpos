// Smoke test for FULLPOS -> backend connectivity.
// Usage (from FULLPOS project root):
//   dart run tool/smoke_backend.dart
// Optional:
//   set BACKEND_BASE_URL=https://api.fulltechrd.com
//   dart run tool/smoke_backend.dart

import 'dart:convert';
import 'dart:io';

String _origin() {
  final env = Platform.environment['BACKEND_BASE_URL']?.trim();
  final raw = (env == null || env.isEmpty) ? 'https://api.fulltechrd.com' : env;
  return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
}

Future<void> _getJson(String path) async {
  final origin = _origin();
  final uri = Uri.parse('$origin$path');

  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 10);

  stdout.writeln('GET $uri');
  try {
    final req = await client.getUrl(uri);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();

    stdout.writeln('-> ${res.statusCode}');
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(decoded));
      } catch (_) {
        stdout.writeln(body.length > 1000 ? body.substring(0, 1000) : body);
      }
    }
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  await _getJson('/api/health');
  stdout.writeln('---');
  await _getJson('/api/health/db');
  stdout.writeln('---');
  await _getJson('/health');
}
