import 'package:shared_preferences/shared_preferences.dart';

class BackupPrefs {
  BackupPrefs._();

  static final BackupPrefs instance = BackupPrefs._();

  static const String _keepLocalCopyKey = 'backup_keep_local_copy';

  Future<bool> getKeepLocalCopy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keepLocalCopyKey) ?? false;
  }

  Future<void> setKeepLocalCopy(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keepLocalCopyKey, value);
  }
}
