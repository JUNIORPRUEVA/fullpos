import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/electronic_sequence_model.dart';

void main() {
  test('ElectronicSequenceModel parses backend camelCase payloads as configured sequences', () {
    final sequence = ElectronicSequenceModel.fromMap({
      'id': 7,
      'companyId': 9,
      'branchId': 0,
      'documentTypeCode': '31',
      'prefix': 'E31',
      'startNumber': 1,
      'currentNumber': 0,
      'endNumber': 120,
      'status': 'ACTIVE',
      'updatedAtMs': 1710000000000,
    });

    expect(sequence.companyId, 9);
    expect(sequence.branchId, 0);
    expect(sequence.documentTypeCode, '31');
    expect(sequence.hasValidDocumentType, isTrue);
    expect(sequence.hasValidPrefix, isTrue);
    expect(sequence.hasAuthorizedRange, isTrue);
    expect(sequence.isConfigured, isTrue);
    expect(sequence.statusLabel, 'Activa');
  });
}