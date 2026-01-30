/// Validador y normalizador de números telefónicos para República Dominicana
class PhoneValidator {
  /// Códigos de área válidos en República Dominicana
  static const List<String> _validAreaCodes = [
    '809', // Original RD
    '829', // Claro
    '849', // Orange
    '858', // Altacel
    '878', // Indotel
    '953', // Claro (movil)
    '950', // Claro (movil)
  ];

  /// Valida que el número de teléfono tenga el formato correcto para RD
  /// Acepta formatos como: 8095551234, (809) 555-1234, 809-555-1234, +1-809-555-1234, etc.
  static bool isValidRDPhone(String phone) {
    if (phone.isEmpty) return false;

    final digits = _extractDigitsLenient(phone);
    if (digits.isEmpty) return false;

    // RD: 10 dígitos (código área + número). Aquí ya removimos el prefijo 1.
    if (digits.length != 10) return false;

    // Mantener lista de áreas como “preferencia”, pero no bloquear por completo.
    // Si quieres ser más estricto, cambia a: return _validAreaCodes.contains(areaCode);
    final areaCode = digits.substring(0, 3);
    final isKnownAreaCode = _validAreaCodes.contains(areaCode);
    return isKnownAreaCode || RegExp(r'^\d{3}$').hasMatch(areaCode);
  }

  /// Validador flexible (recomendado para formularios):
  /// - Acepta números nacionales/internacionales
  /// - Permite +, espacios, guiones, paréntesis
  /// - Requiere entre 7 y 15 dígitos
  static bool isValidPhoneLenient(String phone) {
    if (phone.trim().isEmpty) return false;
    final digits = _extractDigitsLenient(phone);
    if (digits.isEmpty) return false;
    return digits.length >= 7 && digits.length <= 15;
  }

  static String _extractDigitsLenient(String phone) {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    // Remover prefijos internacionales comunes: 00...
    while (digits.startsWith('00') && digits.length > 2) {
      digits = digits.substring(2);
    }

    // Si comienza con 1 (código país USA/RD) y sobran dígitos, removerlo.
    if (digits.startsWith('1') && digits.length > 10) {
      digits = digits.substring(1);
    }

    return digits;
  }

  /// Normaliza el número telefónico al formato internacional +1XXXXXXXXXX
  /// Si el número es válido, retorna el número normalizado con +1
  /// Si no es válido, retorna null
  static String? normalizeRDPhone(String phone) {
    if (!isValidRDPhone(phone)) return null;

    final digits = _extractDigitsLenient(phone);
    if (digits.length != 10) return null;
    return '+1$digits';
  }

  /// Obtiene el formato legible del teléfono (809) 555-1234
  static String? formatRDPhone(String phone) {
    final normalized = normalizeRDPhone(phone);
    if (normalized == null) return null;

    // Remover el +1 del inicio
    final digits = normalized.substring(2);

    // Formato: (809) 555-1234
    return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
  }

  /// Extrae solo los dígitos del teléfono sin el +1
  static String? extractDigits(String phone) {
    final normalized = normalizeRDPhone(phone);
    if (normalized == null) return null;
    return normalized.substring(2); // Remover +1
  }
}
