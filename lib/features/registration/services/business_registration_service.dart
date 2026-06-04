import '../../../features/license/license_config.dart';
import '../../license/services/license_storage.dart';
import '../../../core/utils/id_utils.dart';
import 'business_identity_guard.dart';
import 'business_identity_storage.dart';
import 'business_registration_api.dart';
import 'pending_registration_queue.dart';

class BusinessRegistrationService {
  final BusinessIdentityStorage identityStorage;
  final PendingRegistrationQueue queue;
  final BusinessRegistrationApi api;
  final LicenseStorage licenseStorage;

  BusinessRegistrationService({
    BusinessIdentityStorage? identityStorage,
    PendingRegistrationQueue? queue,
    BusinessRegistrationApi? api,
    LicenseStorage? licenseStorage,
  }) : identityStorage = identityStorage ?? BusinessIdentityStorage(),
       queue = queue ?? PendingRegistrationQueue(),
       api = api ?? BusinessRegistrationApi(),
       licenseStorage = licenseStorage ?? LicenseStorage();

  /// Resuelve el businessId canónico de forma segura.
  ///
  /// Reglas:
  /// - Si local existe y cache coincide → usar local.
  /// - Si local existe y cache vacío → usar local.
  /// - Si local existe y cache diferente → BLOQUEAR (conflicto).
  /// - Si local vacío y cache existe → restaurar desde cache (allowRestoreWhenLocalMissing).
  /// - Si ambos vacíos → lanzar excepción (no generar UUID).
  Future<String?> _resolveCanonicalBusinessId() async {
    final localBusinessId = await identityStorage.getBusinessId();
    final cachedLicenseBusinessId =
        ((await licenseStorage.getLastInfo())?.businessId ?? '').trim();

    if ((localBusinessId ?? '').trim().isEmpty &&
        cachedLicenseBusinessId.isEmpty) {
      return null;
    }

    // Usar el guardia central para validar
    final result = await BusinessIdentityGuard.resolveAndApply(
      storage: identityStorage,
      incomingBusinessId: cachedLicenseBusinessId.isNotEmpty
          ? cachedLicenseBusinessId
          : null,
      source: 'license_cache',
      allowInitialSet: false,
      allowRestoreWhenLocalMissing: cachedLicenseBusinessId.isNotEmpty,
      allowOverwrite: false,
    );

    return result;
  }

  Future<Map<String, dynamic>> buildPayload({
    required String businessName,
    required String role,
    required String ownerName,
    required String phone,
    String? email,
    required DateTime trialStart,
    required String appVersion,
  }) async {
    final businessId = await _resolveCanonicalBusinessId();
    return {
      if (businessId != null && businessId.trim().isNotEmpty)
        'business_id': businessId,
      'business_name': businessName.trim(),
      'role': role.trim(),
      'owner_name': ownerName.trim(),
      'phone': phone.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
      'trial_start': trialStart.toUtc().toIso8601String(),
      'app_version': appVersion.trim(),
    };
  }

  Future<void> registerNowOrQueue(Map<String, dynamic> payload) async {
    var payloadToSend = Map<String, dynamic>.from(payload);

    try {
      await _registerWithBusinessIdReconcile(payloadToSend);
      return;
    } on BusinessRegistrationException catch (e) {
      final item = PendingRegistrationItem(
        id: IdUtils.uuidV4(),
        payload: payloadToSend,
        attempts: 0,
        lastError: e.toString(),
        createdAt: DateTime.now(),
        lastAttemptAt: null,
      );
      await queue.enqueue(item);
      return;
    } catch (e) {
      final item = PendingRegistrationItem(
        id: IdUtils.uuidV4(),
        payload: payloadToSend,
        attempts: 0,
        lastError: e.toString(),
        createdAt: DateTime.now(),
        lastAttemptAt: null,
      );
      await queue.enqueue(item);
    }
  }

  Future<void> retryPendingOnce() async {
    final items = await queue.load();
    if (items.isEmpty) return;

    for (final item in items) {
      final payloadToSend = Map<String, dynamic>.from(item.payload);
      final next = item.copyWith(
        attempts: item.attempts + 1,
        lastAttemptAt: DateTime.now(),
      );
      await queue.replaceItem(next);

      try {
        await _registerWithBusinessIdReconcile(payloadToSend);
        await queue.removeById(item.id);
      } catch (e) {
        final failed = PendingRegistrationItem(
          id: next.id,
          payload: payloadToSend,
          attempts: next.attempts,
          lastError: e.toString(),
          createdAt: next.createdAt,
          lastAttemptAt: next.lastAttemptAt,
        );
        await queue.replaceItem(failed);
      }
    }
  }

  Future<void> _registerWithBusinessIdReconcile(
    Map<String, dynamic> payloadToSend,
  ) async {
    try {
      final response = await api.register(
        baseUrl: kLicenseBackendBaseUrl,
        payload: payloadToSend,
      );
      final backendBusinessId = (response?['business_id'] ?? '').toString().trim();
      if (backendBusinessId.isNotEmpty) {
        await BusinessIdentityGuard.resolveAndApply(
          storage: identityStorage,
          incomingBusinessId: backendBusinessId,
          source: 'backend_registration_success',
          allowInitialSet: true,
          allowRestoreWhenLocalMissing: true,
          allowOverwrite: false,
        );
      }
      return;
    } on BusinessRegistrationException catch (e) {
      final backendCode = (e.code ?? '').trim().toUpperCase();
      final existingBusinessId = (e.existingBusinessId ?? '').trim();

      if (backendCode == 'BUSINESS_ID_CONFLICT' &&
          existingBusinessId.isNotEmpty) {
        // NO sobrescribir automáticamente. El conflicto debe resolverse manualmente.
        // Lanzar excepción clara para que el flujo de registro falle y muestre error.
        throw BusinessIdentityConflictException(
          currentBusinessId: await identityStorage.getBusinessId(),
          incomingBusinessId: existingBusinessId,
          source: 'backend',
          reason:
              'BUSINESS_ID_CONFLICT: El backend reporta que este negocio ya tiene '
              'un business_id diferente ($existingBusinessId). '
              'No se puede sobrescribir automáticamente. '
              'Debe desvincular la empresa actual o contactar a soporte.',
        );
      }
      rethrow;
    }
  }
}
