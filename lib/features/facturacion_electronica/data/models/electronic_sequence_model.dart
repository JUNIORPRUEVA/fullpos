class ElectronicSequenceModel {
  final int? id;
  final int companyId;
  final int branchId;
  final String documentTypeCode;
  final String prefix;
  final int startNumber;
  final int currentNumber;
  final int? endNumber;
  final String status;
  final int updatedAtMs;

  const ElectronicSequenceModel({
    this.id,
    required this.companyId,
    required this.branchId,
    required this.documentTypeCode,
    required this.prefix,
    required this.startNumber,
    required this.currentNumber,
    required this.endNumber,
    required this.status,
    required this.updatedAtMs,
  });

  factory ElectronicSequenceModel.defaults(String documentTypeCode) {
    return ElectronicSequenceModel(
      companyId: 0,
      branchId: 0,
      documentTypeCode: documentTypeCode,
      prefix: 'E$documentTypeCode',
      startNumber: 1,
      currentNumber: 0,
      endNumber: null,
      status: '',
      updatedAtMs: 0,
    );
  }

  bool get hasValidDocumentType =>
      RegExp(r'^\d{2}$').hasMatch(documentTypeCode.trim());

  bool get hasValidPrefix =>
      prefix.trim().toUpperCase() == 'E${documentTypeCode.trim()}';

  bool get hasAuthorizedRange =>
      endNumber != null &&
      startNumber >= 1 &&
      currentNumber >= 0 &&
      endNumber! >= startNumber &&
      endNumber! >= currentNumber;

  bool get hasValidCompany => companyId > 0;

  bool get isConfigured =>
      hasValidDocumentType &&
      hasValidPrefix &&
      hasAuthorizedRange &&
      hasValidCompany;

  int? get remainingCount {
    final limit = endNumber;
    if (limit == null) return null;
    return (limit - currentNumber).clamp(0, limit);
  }

  bool get isExhausted => status.trim().toUpperCase() == 'EXHAUSTED';

  bool get isInactive =>
      status.trim().toUpperCase() == 'INACTIVE' ||
      status.trim().toUpperCase() == 'PAUSED';

  bool get hasLowAvailability {
    final remaining = remainingCount;
    return remaining != null && remaining > 0 && remaining <= 25;
  }

  String get statusLabel {
    if (!isConfigured) {
      return 'No configurada';
    }
    switch (status.trim().toUpperCase()) {
      case 'ACTIVE':
        return 'Activa';
      case 'PAUSED':
        return 'Inactiva';
      case 'EXHAUSTED':
        return 'Agotada';
      case 'INACTIVE':
        return 'Inactiva';
      default:
        return 'No configurada';
    }
  }

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'company_id': companyId,
    'branch_id': branchId,
    'document_type_code': documentTypeCode,
    'prefix': prefix,
    'start_number': startNumber,
    'current_number': currentNumber,
    'end_number': endNumber,
    'status': status,
    'updated_at_ms': updatedAtMs,
  };

  factory ElectronicSequenceModel.fromMap(Map<String, Object?> map) {
    int? asInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '');
    }

    String asString(Object? value) => value?.toString() ?? '';

    return ElectronicSequenceModel(
      id: asInt(map['id']),
      companyId: asInt(map['company_id'] ?? map['companyId']) ?? 0,
      branchId: asInt(map['branch_id'] ?? map['branchId']) ?? 0,
      documentTypeCode: asString(
        map['document_type_code'] ?? map['documentTypeCode'],
      ),
      prefix: asString(map['prefix']),
      startNumber: asInt(map['start_number'] ?? map['startNumber']) ?? 1,
      currentNumber: asInt(map['current_number'] ?? map['currentNumber']) ?? 0,
      endNumber: asInt(map['end_number'] ?? map['endNumber']),
      status: asString(map['status']),
      updatedAtMs: asInt(map['updated_at_ms'] ?? map['updatedAtMs']) ?? 0,
    );
  }

  ElectronicSequenceModel copyWith({
    int? id,
    int? companyId,
    int? branchId,
    String? documentTypeCode,
    String? prefix,
    int? startNumber,
    int? currentNumber,
    int? endNumber,
    String? status,
    int? updatedAtMs,
  }) {
    return ElectronicSequenceModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      branchId: branchId ?? this.branchId,
      documentTypeCode: documentTypeCode ?? this.documentTypeCode,
      prefix: prefix ?? this.prefix,
      startNumber: startNumber ?? this.startNumber,
      currentNumber: currentNumber ?? this.currentNumber,
      endNumber: endNumber ?? this.endNumber,
      status: status ?? this.status,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
