import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirstRunAuthFlags {
  FirstRunAuthFlags._();

  static const String _keyFirstRunCompleted = 'firstRunCompleted';
  static const String _keyMustChangePassword = 'mustChangePassword';

  static Future<bool> isFirstRunCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFirstRunCompleted) ?? false;
  }

  static Future<void> setFirstRunCompleted(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFirstRunCompleted, value);
  }

  static Future<bool> mustChangePassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyMustChangePassword) ?? false;
  }

  static Future<void> setMustChangePassword(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMustChangePassword, value);
  }

  static void log(String message) {
    // Control logs only; never include secrets.
    debugPrint('[AUTH] $message');
  }
}
