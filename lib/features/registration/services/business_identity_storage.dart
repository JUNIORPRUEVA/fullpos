import 'package:shared_preferences/shared_preferences.dart';

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

class BusinessOnboardingProfile {
  final String? businessId;
  final String businessName;
  final String role;
  final String ownerName;
  final String phone;
  final String? email;
  final DateTime? trialStart;
  final bool demoConsumed;
  final bool onboardingCompleted;

  const BusinessOnboardingProfile({
    required this.businessId,
    required this.businessName,
    required this.role,
    required this.ownerName,
    required this.phone,
    required this.email,
    required this.trialStart,
    required this.demoConsumed,
    required this.onboardingCompleted,
  });

  bool get hasMinimumData =>
      businessName.trim().isNotEmpty &&
      role.trim().isNotEmpty &&
      ownerName.trim().isNotEmpty &&
      phone.trim().isNotEmpty;
}

class BusinessIdentityStorage {
  static const _kBusinessId = 'business.business_id_v1';
  static const _kBusinessName = 'business.business_name_v1';
  static const _kRole = 'business.role_v1';
  static const _kOwnerName = 'business.owner_name_v1';
  static const _kPhone = 'business.phone_v1';
  static const _kEmail = 'business.email_v1';
  static const _kTrialStartIso = 'business.trial_start_iso_v1';
  static const _kDemoConsumed = 'business.demo_consumed_v1';
  static const _kOnboardingCompleted = 'business.onboarding_completed_v1';

  /// Limpia datos de identidad NO críticos (nombre, rol, teléfono, email, trial).
  /// NO borra el businessId. Para borrar businessId usar [clearBusinessIdentity].
  Future<void> clearProfile() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kBusinessName);
    await sp.remove(_kRole);
    await sp.remove(_kOwnerName);
    await sp.remove(_kPhone);
    await sp.remove(_kEmail);
    await sp.remove(_kTrialStartIso);
    await sp.remove(_kDemoConsumed);
    await sp.remove(_kOnboardingCompleted);
  }

  /// Limpia solo el acceso temporal de demo/trial.
  ///
  /// Mantiene los datos del cliente (negocio, tipo, representante, WhatsApp,
  /// email y businessId), pero evita que el router deje entrar por una demo
  /// local después de resetear la licencia.
  Future<void> clearTrialAccess() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kTrialStartIso);
    await sp.setBool(_kDemoConsumed, true);
  }

  /// Limpia TODO incluyendo businessId.
  /// Solo debe llamarse desde [unlinkBusinessIdentity] o flujo admin explícito.
  Future<void> clearAll() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kBusinessId);
    await sp.remove(_kBusinessName);
    await sp.remove(_kRole);
    await sp.remove(_kOwnerName);
    await sp.remove(_kPhone);
    await sp.remove(_kEmail);
    await sp.remove(_kTrialStartIso);
    await sp.remove(_kDemoConsumed);
    await sp.remove(_kOnboardingCompleted);
  }

  Future<bool> isDemoConsumed() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kDemoConsumed) == true;
  }

  Future<void> markDemoConsumed() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kDemoConsumed, true);
  }

  Future<bool> isOnboardingCompleted() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kOnboardingCompleted) == true;
  }

  Future<void> setOnboardingCompleted(bool value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kOnboardingCompleted, value);
  }

  Future<bool> hasMinimumProfileData() async {
    final profile = await getOnboardingProfile();
    return profile?.hasMinimumData == true;
  }

  /// Obtiene el businessId actual.
  /// Si no existe, retorna null. NO genera UUID automáticamente.
  Future<String?> getBusinessId() async {
    final sp = await SharedPreferences.getInstance();
    final v = (sp.getString(_kBusinessId) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  /// Guarda un businessId.
  /// Por defecto [overwrite=false]: si ya existe uno diferente, no lo sobrescribe.
  /// [overwrite=true]: solo para flujo admin explícito.
  Future<void> setBusinessId(
    String businessId, {
    bool overwrite = false,
  }) async {
    final sp = await SharedPreferences.getInstance();
    final v = businessId.trim();
    if (v.isEmpty) return;

    final existing = (sp.getString(_kBusinessId) ?? '').trim();
    if (existing.isNotEmpty && existing != v && !overwrite) {
      return;
    }

    await sp.setString(_kBusinessId, v);
  }

  /// Versión segura de ensureBusinessId: NO genera UUID.
  /// Si existe, lo retorna. Si no existe, retorna null.
  /// Para compatibilidad con código legacy que espera un String no-null.
  @Deprecated(
    'Usar getBusinessId() en su lugar. Este método ya no genera UUID.',
  )
  Future<String?> ensureBusinessId() async {
    return getBusinessId();
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

  Future<void> setTrialStart(DateTime trialStart) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kTrialStartIso, trialStart.toUtc().toIso8601String());
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

  Future<BusinessOnboardingProfile?> getOnboardingProfile() async {
    final sp = await SharedPreferences.getInstance();
    final businessId = (sp.getString(_kBusinessId) ?? '').trim();
    final businessName = (sp.getString(_kBusinessName) ?? '').trim();
    final role = (sp.getString(_kRole) ?? '').trim();
    final ownerName = (sp.getString(_kOwnerName) ?? '').trim();
    final phone = (sp.getString(_kPhone) ?? '').trim();
    final email = (sp.getString(_kEmail) ?? '').trim();
    final trialRaw = (sp.getString(_kTrialStartIso) ?? '').trim();
    final trialStart = trialRaw.isEmpty ? null : DateTime.tryParse(trialRaw);
    final demoConsumed = sp.getBool(_kDemoConsumed) == true;
    final onboardingCompleted = sp.getBool(_kOnboardingCompleted) == true;

    if (businessId.isEmpty &&
        businessName.isEmpty &&
        role.isEmpty &&
        ownerName.isEmpty &&
        phone.isEmpty &&
        email.isEmpty &&
        trialStart == null &&
        !demoConsumed &&
        !onboardingCompleted) {
      return null;
    }

    return BusinessOnboardingProfile(
      businessId: businessId.isEmpty ? null : businessId,
      businessName: businessName,
      role: role,
      ownerName: ownerName,
      phone: phone,
      email: email.isEmpty ? null : email,
      trialStart: trialStart,
      demoConsumed: demoConsumed,
      onboardingCompleted: onboardingCompleted,
    );
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
