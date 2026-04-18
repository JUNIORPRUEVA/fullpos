class ElectronicCompanyModel {
  final int? id;
  final String businessName;
  final String tradeName;
  final String rnc;
  final String emissionAddress;
  final String phone;
  final String email;
  final String environment;
  final String apiToken;
  final String certificateName;
  final int? certificateValidFromMs;
  final int? certificateValidToMs;
  final String certificateStatus;
  final int automaticEmission;
  final int updatedAtMs;

  const ElectronicCompanyModel({
    this.id,
    required this.businessName,
    required this.tradeName,
    required this.rnc,
    required this.emissionAddress,
    required this.phone,
    required this.email,
    required this.environment,
    required this.apiToken,
    required this.certificateName,
    this.certificateValidFromMs,
    this.certificateValidToMs,
    this.certificateStatus = '',
    required this.automaticEmission,
    required this.updatedAtMs,
  });

  factory ElectronicCompanyModel.defaults() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ElectronicCompanyModel(
      businessName: '',
      tradeName: '',
      rnc: '',
      emissionAddress: '',
      phone: '',
      email: '',
      environment: 'pruebas',
      apiToken: '',
      certificateName: '',
      certificateValidFromMs: null,
      certificateValidToMs: null,
      certificateStatus: '',
      automaticEmission: 1,
      updatedAtMs: now,
    );
  }

  bool get isEnabled => automaticEmission == 1;

  List<String> missingRequiredFields({bool requireToken = false}) {
    final missing = <String>[];
    if (requireToken && apiToken.trim().isEmpty) missing.add('Token DGII');
    return missing;
  }

  bool get isReadyForEmission => isEnabled && missingRequiredFields().isEmpty;

  bool get hasCertificateConfigured => certificateName.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'environment': environment,
    'api_token': apiToken,
    'certificate_name': certificateName,
    'certificate_valid_from_ms': certificateValidFromMs,
    'certificate_valid_to_ms': certificateValidToMs,
    'certificate_status': certificateStatus,
    'automatic_emission': automaticEmission,
    'updated_at_ms': updatedAtMs,
  };

  factory ElectronicCompanyModel.fromMap(Map<String, dynamic> map) {
    return ElectronicCompanyModel(
      id: map['id'] as int?,
      businessName: '',
      tradeName: '',
      rnc: '',
      emissionAddress: '',
      phone: '',
      email: '',
      environment: map['environment'] as String? ?? 'pruebas',
      apiToken: map['api_token'] as String? ?? '',
      certificateName: map['certificate_name'] as String? ?? '',
      certificateValidFromMs: map['certificate_valid_from_ms'] as int?,
      certificateValidToMs: map['certificate_valid_to_ms'] as int?,
      certificateStatus: map['certificate_status'] as String? ?? '',
      automaticEmission: map['automatic_emission'] as int? ?? 1,
      updatedAtMs: map['updated_at_ms'] as int? ?? 0,
    );
  }

  ElectronicCompanyModel copyWith({
    int? id,
    String? businessName,
    String? tradeName,
    String? rnc,
    String? emissionAddress,
    String? phone,
    String? email,
    String? environment,
    String? apiToken,
    String? certificateName,
    int? certificateValidFromMs,
    int? certificateValidToMs,
    String? certificateStatus,
    int? automaticEmission,
    int? updatedAtMs,
  }) {
    return ElectronicCompanyModel(
      id: id ?? this.id,
      businessName: businessName ?? this.businessName,
      tradeName: tradeName ?? this.tradeName,
      rnc: rnc ?? this.rnc,
      emissionAddress: emissionAddress ?? this.emissionAddress,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      environment: environment ?? this.environment,
      apiToken: apiToken ?? this.apiToken,
      certificateName: certificateName ?? this.certificateName,
      certificateValidFromMs:
          certificateValidFromMs ?? this.certificateValidFromMs,
      certificateValidToMs: certificateValidToMs ?? this.certificateValidToMs,
      certificateStatus: certificateStatus ?? this.certificateStatus,
      automaticEmission: automaticEmission ?? this.automaticEmission,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
