import '../../../features/license/license_config.dart';
import '../../../core/utils/id_utils.dart';
import 'business_identity_storage.dart';
import 'business_registration_api.dart';
import 'pending_registration_queue.dart';

class BusinessRegistrationService {
  final BusinessIdentityStorage identityStorage;
  final PendingRegistrationQueue queue;
  final BusinessRegistrationApi api;

  BusinessRegistrationService({
    BusinessIdentityStorage? identityStorage,
    PendingRegistrationQueue? queue,
    BusinessRegistrationApi? api,
  })  : identityStorage = identityStorage ?? BusinessIdentityStorage(),
        queue = queue ?? PendingRegistrationQueue(),
        api = api ?? BusinessRegistrationApi();

  Future<Map<String, dynamic>> buildPayload({
    required String businessName,
    required String role,
    required String ownerName,
    required String phone,
    String? email,
    required DateTime trialStart,
    required String appVersion,
  }) async {
    final businessId = await identityStorage.ensureBusinessId();
    return {
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
      await api.register(baseUrl: kLicenseBackendBaseUrl, payload: payloadToSend);
      return;
    } on BusinessRegistrationException catch (e) {
      final backendCode = (e.code ?? '').trim().toUpperCase();
      final existingBusinessId = (e.existingBusinessId ?? '').trim();

      if (backendCode == 'BUSINESS_ID_CONFLICT' && existingBusinessId.isNotEmpty) {
        await identityStorage.setBusinessId(existingBusinessId);
        payloadToSend['business_id'] = existingBusinessId;
        await api.register(baseUrl: kLicenseBackendBaseUrl, payload: payloadToSend);
        return;
      }
      rethrow;
    }
  }
}
