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

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'environment': environment,
    'api_token': apiToken,
    'certificate_name': certificateName,
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
      automaticEmission: automaticEmission ?? this.automaticEmission,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}