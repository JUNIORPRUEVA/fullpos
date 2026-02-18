import 'app_config.dart';

/// Base URL del backend (nube) usado por FULLPOS.
///
/// Fuente de verdad: [AppConfig.apiBaseUrl].
///
/// Overrides soportados al compilar:
/// - `--dart-define=FULLPOS_API_URL=<tu-servidor>`
/// - (legacy) `--dart-define=BACKEND_BASE_URL=<tu-servidor>`
String get backendBaseUrl => AppConfig.apiBaseUrl;

/// Endpoint para aprovisionar credenciales de acceso remoto (Owner).
const String provisionOwnerPath = '/api/auth/provision-owner';

/// Endpoint para aprovisionar/actualizar usuarios (admin) para FULLPOS Owner.
const String provisionUserPath = '/api/auth/provision-user';
