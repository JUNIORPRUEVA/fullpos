class InventoryMutationFields {
  const InventoryMutationFields._();

  static Map<String, Object?> productTouched({
    required int now,
    String lastModifiedBy = 'fullpos_local',
  }) {
    return {
      'sync_status': 'pending',
      'local_updated_at_ms': now,
      'last_modified_by': lastModifiedBy,
      'last_sync_error': null,
      'needs_sync': 1,
      'updated_at_ms': now,
    };
  }
}
