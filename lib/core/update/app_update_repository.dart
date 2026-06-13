import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../network/api_client.dart';
import 'app_update_policy.dart';

class AppUpdateRepository {
  AppUpdateRepository({ApiClient? api}) : _api = api ?? ApiClient();

  static const _cacheKey = 'app_update_policy_cache_v1';
  static const _cacheSchema = 1;
  final ApiClient _api;

  Future<AppUpdatePolicy> fetchPolicy() async {
    final json = await _api.getJsonMap(
      '/api/app-updates/fullpos/windows',
      timeout: const Duration(seconds: 15),
      retry: true,
    );
    final policy = AppUpdatePolicy.fromJson(json);
    await _storeValidated(policy);
    return policy;
  }

  Future<AppUpdatePolicy?> readValidatedCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['schemaVersion'] != _cacheSchema) {
        return null;
      }
      final policyJson = decoded['policy'];
      if (policyJson is! Map) return null;
      return AppUpdatePolicy.fromJson(
        policyJson.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeValidated(AppUpdatePolicy policy) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await readValidatedCache();
    if (current != null && current.publishedAt.isAfter(policy.publishedAt)) {
      return;
    }
    await prefs.setString(
      _cacheKey,
      jsonEncode({
        'schemaVersion': _cacheSchema,
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
        'policy': policy.toJson(),
      }),
    );
  }
}
