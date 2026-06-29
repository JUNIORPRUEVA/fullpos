import 'package:shared_preferences/shared_preferences.dart';

import '../storage/prefs_safe.dart';
import 'identity_recovery_bundle.dart';

class LicenseReactivationMarker {
  const LicenseReactivationMarker();

  static const String requiredKey = 'license.reactivation_required_v1';
  static const String reasonKey = 'license.reactivation_reason_v1';
  static const String temporaryTerminalKey =
      'identity.temporary_terminal_id_v1';

  Future<bool> isRequired() async {
    final prefs = await _prefs();
    return prefs.getBool(requiredKey) == true;
  }

  Future<String?> reason() async {
    final prefs = await _prefs();
    final raw = (prefs.getString(reasonKey) ?? '').trim();
    return raw.isEmpty ? null : raw;
  }

  Future<void> require({
    required String reason,
    String? temporaryTerminalId,
  }) async {
    final prefs = await _prefs();
    await prefs.setBool(requiredKey, true);
    await prefs.setString(reasonKey, reason.trim());
    final terminal = (temporaryTerminalId ?? '').trim();
    if (terminal.isNotEmpty) {
      await prefs.setString(temporaryTerminalKey, terminal);
    }
    await IdentityRecoveryBundle.instance.log(
      'license_reactivation_required reason=$reason '
      'temporaryTerminalId=${_mask(terminal)}',
    );
  }

  Future<void> clear({required String reason}) async {
    final prefs = await _prefs();
    await prefs.remove(requiredKey);
    await prefs.remove(reasonKey);
    await prefs.remove(temporaryTerminalKey);
    await IdentityRecoveryBundle.instance.log(
      'license_reactivation_cleared reason=$reason',
    );
  }

  Future<SharedPreferences> _prefs() async {
    final prefs = await PrefsSafe.getInstance();
    if (prefs != null) return prefs;
    return SharedPreferences.getInstance();
  }
}

String _mask(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'null';
  if (v.length <= 4) return '***';
  return '${v.substring(0, 4)}...${v.substring(v.length - 2)}';
}
