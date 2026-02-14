import 'dart:io' show Platform;

/// Configuración central de la app.
///
/// Fuente de verdad para URLs y metadata de red.
class AppConfig {
  AppConfig._();

  static const String defaultApiBaseUrl = 'https://api.fulltechrd.com';

  /// Base para enlaces externos de WhatsApp (soporte).
  static const String whatsappBaseUrl = 'https://wa.me';

  /// URLs de imágenes demo (semillas).
  ///
  /// Mantener aquí para evitar URLs hardcoded repartidas por el código.
  static const List<String> demoUnsplashImageUrls = [
    'https://images.unsplash.com/photo-1507721999472-8ed4421c4af2?auto=format&fit=crop&w=800&q=80&sig=1',
    'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=800&q=80&sig=2',
    'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80&sig=3',
    'https://images.unsplash.com/photo-1523419400524-fc1e0d787ab7?auto=format&fit=crop&w=800&q=80&sig=4',
    'https://images.unsplash.com/photo-1503389152951-9f343605f61e?auto=format&fit=crop&w=800&q=80&sig=5',
    'https://images.unsplash.com/photo-1503389152951-9f343605f61e?auto=format&fit=crop&w=800&q=80&sig=6',
    'https://images.unsplash.com/photo-1454991727061-2868c0807f7f?auto=format&fit=crop&w=800&q=80&sig=7',
    'https://images.unsplash.com/photo-1514996937319-344454492b37?auto=format&fit=crop&w=800&q=80&sig=8',
    'https://images.unsplash.com/photo-1454991924124-4c0796370749?auto=format&fit=crop&w=800&q=80&sig=9',
    'https://images.unsplash.com/photo-1507722407803-9ac805f252d2?auto=format&fit=crop&w=800&q=80&sig=10',
  ];

  static String? _apiBaseUrl;

  /// Inicializa/cacha configuración (llamar al arranque).
  static Future<void> init() async {
    _apiBaseUrl = _resolveApiBaseUrl();
  }

  /// Base URL oficial de la API.
  ///
  /// Overrides soportados (en orden):
  /// - `FULLPOS_API_URL` (nuevo)
  /// - `BACKEND_BASE_URL` (legacy / compatibilidad)
  static String get apiBaseUrl => _apiBaseUrl ??= _resolveApiBaseUrl();

  static String get appVersion => const String.fromEnvironment(
    'FULLPOS_APP_VERSION',
    defaultValue: '1.0.0+1',
  );

  static String get userAgent {
    final os = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;
    return 'FULLPOS/$appVersion ($os; $osVersion)';
  }

  static String _resolveApiBaseUrl() {
    final explicit = const String.fromEnvironment(
      'FULLPOS_API_URL',
      defaultValue: '',
    );
    if (explicit.trim().isNotEmpty) {
      return normalizeBaseUrl(explicit);
    }

    // Compatibilidad con builds existentes.
    final legacy = const String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue: '',
    );
    if (legacy.trim().isNotEmpty) {
      return normalizeBaseUrl(legacy);
    }

    return normalizeBaseUrl(defaultApiBaseUrl);
  }

  static String normalizeBaseUrl(String input) {
    var b = input.trim();
    if (b.isEmpty) return defaultApiBaseUrl;

    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      b = 'https://$b';
    }

    // Evitar / final para que Uri.replace(path: ...) sea consistente.
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }

    return b;
  }
}
