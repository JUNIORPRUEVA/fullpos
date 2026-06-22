class FiscalReceiptSettingsModel {
  final bool enabled;
  final int? defaultReceiptTypeId;

  const FiscalReceiptSettingsModel({
    required this.enabled,
    this.defaultReceiptTypeId,
  });

  FiscalReceiptSettingsModel copyWith({
    bool? enabled,
    int? defaultReceiptTypeId,
    bool clearDefaultReceiptTypeId = false,
  }) {
    return FiscalReceiptSettingsModel(
      enabled: enabled ?? this.enabled,
      defaultReceiptTypeId: clearDefaultReceiptTypeId
          ? null
          : defaultReceiptTypeId ?? this.defaultReceiptTypeId,
    );
  }
}

class FiscalReceiptTypeModel {
  final int? id;
  final String name;
  final String code;
  final String prefix;
  final int startNumber;
  final int endNumber;
  final int nextNumber;
  final int sequenceDigits;
  final int? expiresAtMs;
  final bool requiresCustomerTaxId;
  final bool requiresCustomerName;
  final bool allowFinalConsumer;
  final bool isDefault;
  final bool isActive;
  final String? note;
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;

  const FiscalReceiptTypeModel({
    this.id,
    required this.name,
    required this.code,
    required this.prefix,
    required this.startNumber,
    required this.endNumber,
    required this.nextNumber,
    this.sequenceDigits = 9,
    this.expiresAtMs,
    this.requiresCustomerTaxId = false,
    this.requiresCustomerName = false,
    this.allowFinalConsumer = true,
    this.isDefault = false,
    this.isActive = true,
    this.note,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.deletedAtMs,
  });

  bool get isExpired {
    final expires = expiresAtMs;
    if (expires == null) return false;
    final endOfDay = DateTime.fromMillisecondsSinceEpoch(expires);
    final limit = DateTime(endOfDay.year, endOfDay.month, endOfDay.day, 23, 59);
    return DateTime.now().isAfter(limit);
  }

  bool get isExhausted => nextNumber > endNumber;

  bool get isAvailable =>
      isActive && deletedAtMs == null && !isExpired && !isExhausted;

  String get nextReceiptNumber =>
      formatReceiptNumber(prefix, nextNumber, digits: sequenceDigits);

  static String formatReceiptNumber(
    String prefix,
    int sequence, {
    int digits = 9,
  }) {
    final safeDigits = digits.clamp(1, 12).toInt();
    return '${prefix.trim().toUpperCase()}${sequence.toString().padLeft(safeDigits, '0')}';
  }

  factory FiscalReceiptTypeModel.fromMap(Map<String, dynamic> map) {
    final code = ((map['code'] ?? map['type']) as String? ?? '').trim();
    final prefix = ((map['prefix'] ?? map['series'] ?? code) as String? ?? '')
        .trim();
    final name = ((map['name'] ?? map['display_name'] ?? code) as String? ?? '')
        .trim();
    return FiscalReceiptTypeModel(
      id: map['id'] as int?,
      name: name.isEmpty ? code : name,
      code: code.isEmpty ? prefix : code,
      prefix: prefix.isEmpty ? code : prefix,
      startNumber: map['start_number'] as int? ?? map['from_n'] as int? ?? 1,
      endNumber: map['end_number'] as int? ?? map['to_n'] as int? ?? 1,
      nextNumber: map['next_number'] as int? ?? map['next_n'] as int? ?? 1,
      sequenceDigits: map['sequence_digits'] as int? ?? 9,
      expiresAtMs: map['expires_at_ms'] as int?,
      requiresCustomerTaxId:
          (map['requires_customer_tax_id'] as int? ?? 0) == 1,
      requiresCustomerName: (map['requires_customer_name'] as int? ?? 0) == 1,
      allowFinalConsumer: (map['allow_final_consumer'] as int? ?? 1) == 1,
      isDefault: (map['is_default'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      note: map['note'] as String?,
      createdAtMs: map['created_at_ms'] as int? ?? 0,
      updatedAtMs: map['updated_at_ms'] as int? ?? 0,
      deletedAtMs: map['deleted_at_ms'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name.trim(),
      'code': code.trim().toUpperCase(),
      'prefix': prefix.trim().toUpperCase(),
      'type': code.trim().toUpperCase(),
      'series': prefix.trim().toUpperCase(),
      'start_number': startNumber,
      'end_number': endNumber,
      'next_number': nextNumber,
      'sequence_digits': sequenceDigits,
      'from_n': startNumber,
      'to_n': endNumber,
      'next_n': nextNumber,
      'expires_at_ms': expiresAtMs,
      'requires_customer_tax_id': requiresCustomerTaxId ? 1 : 0,
      'requires_customer_name': requiresCustomerName ? 1 : 0,
      'allow_final_consumer': allowFinalConsumer ? 1 : 0,
      'is_default': isDefault ? 1 : 0,
      'is_active': isActive ? 1 : 0,
      'note': note,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
      'deleted_at_ms': deletedAtMs,
    };
  }

  FiscalReceiptTypeModel copyWith({
    int? id,
    String? name,
    String? code,
    String? prefix,
    int? startNumber,
    int? endNumber,
    int? nextNumber,
    int? sequenceDigits,
    int? expiresAtMs,
    bool clearExpiresAtMs = false,
    bool? requiresCustomerTaxId,
    bool? requiresCustomerName,
    bool? allowFinalConsumer,
    bool? isDefault,
    bool? isActive,
    String? note,
    int? createdAtMs,
    int? updatedAtMs,
    int? deletedAtMs,
  }) {
    return FiscalReceiptTypeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      prefix: prefix ?? this.prefix,
      startNumber: startNumber ?? this.startNumber,
      endNumber: endNumber ?? this.endNumber,
      nextNumber: nextNumber ?? this.nextNumber,
      sequenceDigits: sequenceDigits ?? this.sequenceDigits,
      expiresAtMs: clearExpiresAtMs ? null : expiresAtMs ?? this.expiresAtMs,
      requiresCustomerTaxId:
          requiresCustomerTaxId ?? this.requiresCustomerTaxId,
      requiresCustomerName: requiresCustomerName ?? this.requiresCustomerName,
      allowFinalConsumer: allowFinalConsumer ?? this.allowFinalConsumer,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
      note: note ?? this.note,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      deletedAtMs: deletedAtMs ?? this.deletedAtMs,
    );
  }
}

class FiscalReceiptAssignment {
  final int receiptTypeId;
  final String receiptName;
  final String receiptCode;
  final String receiptPrefix;
  final String receiptNumber;
  final int sequenceNumber;
  final int? expirationDateMs;

  const FiscalReceiptAssignment({
    required this.receiptTypeId,
    required this.receiptName,
    required this.receiptCode,
    required this.receiptPrefix,
    required this.receiptNumber,
    required this.sequenceNumber,
    this.expirationDateMs,
  });
}
