/// Configuración fija del sistema de licencias.
///
/// Nota: el cliente NO debe configurar esta URL.
const kLicenseBackendBaseUrl =
    'https://fulltechpos-proyects-fulltechpos-backend-wed.gcdndd.easypanel.host';

const kFullposProjectCode = 'FULLPOS';

/// Cada cuánto forzar re-verificación contra backend.
const kLicenseGateRefreshHours = 6;

/// Intervalo del "heartbeat" del router para re-evaluar el gate de licencia.
///
/// Nota: sin un canal push (WebSocket/SSE), el cambio en backend solo puede
/// reflejarse en el cliente mediante polling. Un valor bajo hace que acciones
/// como Bloquear/Desbloquear se vean casi al instante.
const kLicenseGateHeartbeatInterval = Duration(seconds: 5);

/// Tiempo durante el cual consideramos el estado cacheado como "fresco".
///
/// Si es muy bajo, el router re-valida (y potencialmente consulta el backend)
/// en prácticamente cada navegación, causando latencia perceptible.
///
/// Nota: el router también usa un "heartbeat" para re-evaluar el gate.
const kLicenseGateFreshWindow = Duration(minutes: 5);

/// Public key (raw Ed25519 32-byte) en Base64 para validar archivos offline.
///
/// IMPORTANTE: esto permite verificación/activación sin internet.
/// Si se rota la llave de firma en el backend, esta constante debe actualizarse.
const kOfflineLicenseSigningPublicKeyB64 =
    'N3LMxPTgiq+8NEE3PgPANO6rB5ZLKA+pS4sDruVik88=';
