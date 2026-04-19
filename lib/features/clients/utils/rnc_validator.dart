class RncValidator {
  RncValidator._();

  static String digitsOnly(String value) {
    return value.replaceAll(RegExp(r'\D'), '');
  }

  static String? normalize(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;

    final digits = digitsOnly(raw);
    if (digits.length != 9) {
      return null;
    }

    return digits;
  }

  static bool isValidBasic(String? value) {
    return normalize(value) != null;
  }

  static String? format(String? value) {
    final normalized = normalize(value);
    if (normalized == null) return null;
    return normalized;
  }
}