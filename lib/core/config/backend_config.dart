/// Base URL del backend (nube) usado por FULLPOS.
///
/// Puedes sobreescribirlo al compilar con:
/// `--dart-define=BACKEND_BASE_URL=https://tu-servidor.com`
const String backendBaseUrl = String.fromEnvironment(
  'BACKEND_BASE_URL',
  defaultValue: 'https://fullpos-proyecto-producion-fullpos-bakend.gcdndd.easypanel.host',
);

/// Endpoint para aprovisionar credenciales de acceso remoto (Owner).
const String provisionOwnerPath = '/api/auth/provision-owner';
