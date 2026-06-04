import 'dart:developer' as developer;

import 'business_identity_storage.dart';

/// Resultado de la validación de identidad.
class BusinessIdentityValidationResult {
  final bool allowed;
  final String? resolvedBusinessId;
  final String reason;
  final String severity; // 'info', 'warn', 'critical'

  const BusinessIdentityValidationResult({
    required this.allowed,
    this.resolvedBusinessId,
    required this.reason,
    this.severity = 'info',
  });
}

/// Guardia central de identidad de negocio.
///
/// Reglas inviolables:
/// - El businessId es PERMANENTE. Una vez creado, NUNCA cambia automáticamente.
/// - No se genera UUID automáticamente si no existe.
/// - No se sobrescribe en silencio desde cache/backend.
/// - Solo se crea en flujo formal de activación/administración controlada.
class BusinessIdentityGuard {
  BusinessIdentityGuard._();

  /// Valida un businessId entrante contra el businessId actual.
  ///
  /// [currentBusinessId]: businessId actual en storage local (puede ser null).
  /// [incomingBusinessId]: businessId que se quiere validar (puede ser null/vacío).
  /// [source]: origen del incoming (license_cache, backend, offline_file, admin, local).
  /// [allowInitialSet]: si es true, permite establecer businessId cuando no existe local.
  /// [allowRestoreWhenLocalMissing]: si es true, permite restaurar desde fuente confiable cuando local es null.
  /// [allowOverwrite]: si es true, permite sobrescribir (solo admin explícito).
  static Future<BusinessIdentityValidationResult> validateIncomingBusinessId({
    String? currentBusinessId,
    String? incomingBusinessId,
    required String source,
    bool allowInitialSet = false,
    bool allowRestoreWhenLocalMissing = false,
    bool allowOverwrite = false,
  }) async {
    final local = (currentBusinessId ?? '').trim();
    final incoming = (incomingBusinessId ?? '').trim();

    // Caso 1: Ambos existen y son iguales → permitir
    if (local.isNotEmpty && incoming.isNotEmpty && local == incoming) {
      _logEvent(
        source: source,
        currentBusinessId: local,
        incomingBusinessId: incoming,
        action: 'allowed',
        reason: 'businessId coincide',
        severity: 'info',
      );
      return BusinessIdentityValidationResult(
        allowed: true,
        resolvedBusinessId: local,
        reason: 'businessId coincide',
        severity: 'info',
      );
    }

    // Caso 2: Local existe, incoming vacío → usar local (permitir)
    if (local.isNotEmpty && incoming.isEmpty) {
      _logEvent(
        source: source,
        currentBusinessId: local,
        incomingBusinessId: incoming,
        action: 'allowed',
        reason: 'incoming vacío, se mantiene local',
        severity: 'info',
      );
      return BusinessIdentityValidationResult(
        allowed: true,
        resolvedBusinessId: local,
        reason: 'incoming vacío, se mantiene local',
        severity: 'info',
      );
    }

    // Caso 3: Local existe, incoming existe, son DIFERENTES → BLOQUEAR
    if (local.isNotEmpty && incoming.isNotEmpty && local != incoming) {
      _logEvent(
        source: source,
        currentBusinessId: local,
        incomingBusinessId: incoming,
        action: 'blocked',
        reason: 'CONFLICTO: businessId local ($local) ≠ incoming ($incoming) desde $source',
        severity: 'critical',
      );
      return BusinessIdentityValidationResult(
        allowed: false,
        resolvedBusinessId: local,
        reason:
            'La licencia pertenece a otra empresa o la identidad local no coincide. '
            'BusinessId local: $local, entrante: $incoming (fuente: $source). '
            'No se puede sobrescribir automáticamente.',
        severity: 'critical',
      );
    }

    // Caso 4: Local vacío, incoming existe
    if (local.isEmpty && incoming.isNotEmpty) {
      // 4a: allowInitialSet → permitir establecer por primera vez
      if (allowInitialSet) {
        _logEvent(
          source: source,
          currentBusinessId: local,
          incomingBusinessId: incoming,
          action: 'allowed_initial_set',
          reason: 'businessId inicial establecido desde $source',
          severity: 'info',
        );
        return BusinessIdentityValidationResult(
          allowed: true,
          resolvedBusinessId: incoming,
          reason: 'businessId inicial establecido desde $source',
          severity: 'info',
        );
      }

      // 4b: allowRestoreWhenLocalMissing → restaurar desde fuente confiable
      if (allowRestoreWhenLocalMissing) {
        _logEvent(
          source: source,
          currentBusinessId: local,
          incomingBusinessId: incoming,
          action: 'restored',
          reason: 'businessId restaurado desde $source (local estaba vacío)',
          severity: 'warn',
        );
        return BusinessIdentityValidationResult(
          allowed: true,
          resolvedBusinessId: incoming,
          reason: 'businessId restaurado desde $source',
          severity: 'warn',
        );
      }

      // 4c: No hay permiso → bloquear
      _logEvent(
        source: source,
        currentBusinessId: local,
        incomingBusinessId: incoming,
        action: 'blocked',
        reason:
            'businessId local vacío pero incoming existe desde $source. '
            'No se permite restauración automática sin autorización.',
        severity: 'warn',
      );
      return BusinessIdentityValidationResult(
        allowed: false,
        resolvedBusinessId: null,
        reason:
            'No se encontró una identidad de empresa válida. '
            'Debe activar la licencia o restaurar la identidad manualmente.',
        severity: 'warn',
      );
    }

    // Caso 5: Ambos vacíos → no hay identidad
    _logEvent(
      source: source,
      currentBusinessId: local,
      incomingBusinessId: incoming,
      action: 'blocked',
      reason: 'No hay businessId disponible (local e incoming vacíos)',
      severity: 'warn',
    );
    return BusinessIdentityValidationResult(
      allowed: false,
      resolvedBusinessId: null,
      reason:
          'No se encontró una identidad de empresa válida. '
          'Debe activar la licencia.',
      severity: 'warn',
    );
  }

  /// Valida y aplica un businessId entrante al storage si es seguro hacerlo.
  ///
  /// Retorna el businessId resuelto o lanza [BusinessIdentityConflictException].
  static Future<String> resolveAndApply({
    required BusinessIdentityStorage storage,
    String? incomingBusinessId,
    required String source,
    bool allowInitialSet = false,
    bool allowRestoreWhenLocalMissing = false,
    bool allowOverwrite = false,
  }) async {
    final currentBusinessId = await storage.getBusinessId();
    final result = await validateIncomingBusinessId(
      currentBusinessId: currentBusinessId,
      incomingBusinessId: incomingBusinessId,
      source: source,
      allowInitialSet: allowInitialSet,
      allowRestoreWhenLocalMissing: allowRestoreWhenLocalMissing,
      allowOverwrite: allowOverwrite,
    );

    if (!result.allowed) {
      throw BusinessIdentityConflictException(
        currentBusinessId: currentBusinessId,
        incomingBusinessId: incomingBusinessId,
        source: source,
        reason: result.reason,
      );
    }

    if (result.resolvedBusinessId != null &&
        result.resolvedBusinessId != currentBusinessId) {
      await storage.setBusinessId(
        result.resolvedBusinessId!,
        overwrite: allowOverwrite,
      );
    }

    return result.resolvedBusinessId ?? currentBusinessId ?? '';
  }

  static void _logEvent({
    required String source,
    required String currentBusinessId,
    required String incomingBusinessId,
    required String action,
    required String reason,
    required String severity,
  }) {
    final event = {
      'event': 'business_identity_check',
      'source': source,
      'currentBusinessId': currentBusinessId.isNotEmpty ? currentBusinessId : '(empty)',
      'incomingBusinessId': incomingBusinessId.isNotEmpty ? incomingBusinessId : '(empty)',
      'action': action,
      'reason': reason,
      'severity': severity,
    };
    if (severity == 'critical') {
      developer.log('$event', name: 'BusinessIdentityGuard', level: 1000);
    } else if (severity == 'warn') {
      developer.log('$event', name: 'BusinessIdentityGuard', level: 900);
    } else {
      developer.log('$event', name: 'BusinessIdentityGuard', level: 800);
    }
  }
}

/// Excepción lanzada cuando hay un conflicto de businessId que no se puede resolver automáticamente.
class BusinessIdentityConflictException implements Exception {
  final String? currentBusinessId;
  final String? incomingBusinessId;
  final String source;
  final String reason;

  const BusinessIdentityConflictException({
    this.currentBusinessId,
    this.incomingBusinessId,
    required this.source,
    required this.reason,
  });

  @override
  String toString() {
    return 'BusinessIdentityConflictException: $reason '
        '(local: $currentBusinessId, incoming: $incomingBusinessId, source: $source)';
  }
}
