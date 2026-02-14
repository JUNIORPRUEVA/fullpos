import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/id_utils.dart';

class BusinessIdentity {
  final String businessId;
  final String businessName;
  final String role;
  final String ownerName;
  final String phone;
  final String? email;
  final DateTime trialStart;

  const BusinessIdentity({
    required this.businessId,
    required this.businessName,
    required this.role,
    required this.ownerName,
    required this.phone,
    required this.email,
    required this.trialStart,
  });
}

class BusinessIdentityStorage {
  static const _kBusinessId = 'business.business_id_v1';
  static const _kBusinessName = 'business.business_name_v1';
  static const _kRole = 'business.role_v1';
  static const _kOwnerName = 'business.owner_name_v1';
  static const _kPhone = 'business.phone_v1';
  static const _kEmail = 'business.email_v1';
  static const _kTrialStartIso = 'business.trial_start_iso_v1';

  Future<String> ensureBusinessId() async {
    final sp = await SharedPreferences.getInstance();
    final existing = (sp.getString(_kBusinessId) ?? '').trim();
    if (existing.isNotEmpty) return existing;
    final id = IdUtils.uuidV4();
    await sp.setString(_kBusinessId, id);
    return id;
  }

  Future<String?> getBusinessId() async {
    final sp = await SharedPreferences.getInstance();
    final v = (sp.getString(_kBusinessId) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  Future<void> setBusinessId(String businessId) async {
    final sp = await SharedPreferences.getInstance();
    final v = businessId.trim();
    if (v.isEmpty) return;
    await sp.setString(_kBusinessId, v);
  }

  Future<DateTime?> getTrialStart() async {
    final sp = await SharedPreferences.getInstance();
    final raw = (sp.getString(_kTrialStartIso) ?? '').trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<DateTime> ensureTrialStartNowIfMissing() async {
    final sp = await SharedPreferences.getInstance();
    final existing = (sp.getString(_kTrialStartIso) ?? '').trim();
    final parsed = DateTime.tryParse(existing);
    if (parsed != null) return parsed;

    final now = DateTime.now().toUtc();
    await sp.setString(_kTrialStartIso, now.toIso8601String());
    return now;
  }

  Future<void> saveBusinessProfile({
    required String businessName,
    required String role,
    required String ownerName,
    required String phone,
    String? email,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kBusinessName, businessName.trim());
    await sp.setString(_kRole, role.trim());
    await sp.setString(_kOwnerName, ownerName.trim());
    await sp.setString(_kPhone, phone.trim());
    if (email != null && email.trim().isNotEmpty) {
      await sp.setString(_kEmail, email.trim());
    } else {
      await sp.remove(_kEmail);
    }
  }

  Future<BusinessIdentity?> getIdentity() async {
    final sp = await SharedPreferences.getInstance();

    final businessId = (sp.getString(_kBusinessId) ?? '').trim();
    if (businessId.isEmpty) return null;

    final trialRaw = (sp.getString(_kTrialStartIso) ?? '').trim();
    final trialStart = DateTime.tryParse(trialRaw);
    if (trialStart == null) return null;

    final businessName = (sp.getString(_kBusinessName) ?? '').trim();
    final role = (sp.getString(_kRole) ?? '').trim();
    final ownerName = (sp.getString(_kOwnerName) ?? '').trim();
    final phone = (sp.getString(_kPhone) ?? '').trim();
    final email = (sp.getString(_kEmail) ?? '').trim();

    if (businessName.isEmpty ||
        role.isEmpty ||
        ownerName.isEmpty ||
        phone.isEmpty) {
      return null;
    }

    return BusinessIdentity(
      businessId: businessId,
      businessName: businessName,
      role: role,
      ownerName: ownerName,
      phone: phone,
      email: email.isEmpty ? null : email,
      trialStart: trialStart,
    );
  }
}
