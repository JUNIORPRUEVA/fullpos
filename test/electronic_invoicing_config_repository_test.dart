import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/facturacion_electronica/data/electronic_invoicing_config_repository.dart';
import 'package:fullpos/features/facturacion_electronica/data/models/electronic_sequence_model.dart';

void main() {
  test('mergeResolvedElectronicSequences preserves local current usage', () {
    final remote = [
      ElectronicSequenceModel(
        companyId: 1,
        branchId: 0,
        documentTypeCode: '31',
        prefix: 'E31',
        startNumber: 1,
        currentNumber: 0,
        endNumber: 31,
        status: 'ACTIVE',
        updatedAtMs: 10,
      ),
      ElectronicSequenceModel(
        companyId: 1,
        branchId: 0,
        documentTypeCode: '32',
        prefix: 'E32',
        startNumber: 1,
        currentNumber: 0,
        endNumber: 32,
        status: 'ACTIVE',
        updatedAtMs: 10,
      ),
    ];

    final local = [
      ElectronicSequenceModel(
        companyId: 1,
        branchId: 0,
        documentTypeCode: '31',
        prefix: 'E31',
        startNumber: 1,
        currentNumber: 2,
        endNumber: 31,
        status: 'ACTIVE',
        updatedAtMs: 20,
      ),
      ElectronicSequenceModel(
        companyId: 1,
        branchId: 0,
        documentTypeCode: '32',
        prefix: 'E32',
        startNumber: 1,
        currentNumber: 0,
        endNumber: 32,
        status: 'ACTIVE',
        updatedAtMs: 20,
      ),
    ];

    final merged = mergeResolvedElectronicSequences(
      remote: remote,
      local: local,
    );

    expect(merged, hasLength(2));
    expect(merged.first.documentTypeCode, '31');
    expect(merged.first.currentNumber, 2);
    expect(merged.first.status, 'ACTIVE');
    expect(merged.last.documentTypeCode, '32');
    expect(merged.last.currentNumber, 0);
  });

  test('mergeResolvedElectronicSequences marks exhausted when local reached end', () {
    final merged = mergeResolvedElectronicSequences(
      remote: [
        ElectronicSequenceModel(
          companyId: 1,
          branchId: 0,
          documentTypeCode: '31',
          prefix: 'E31',
          startNumber: 1,
          currentNumber: 0,
          endNumber: 2,
          status: 'ACTIVE',
          updatedAtMs: 10,
        ),
      ],
      local: [
        ElectronicSequenceModel(
          companyId: 1,
          branchId: 0,
          documentTypeCode: '31',
          prefix: 'E31',
          startNumber: 1,
          currentNumber: 2,
          endNumber: 2,
          status: 'EXHAUSTED',
          updatedAtMs: 20,
        ),
      ],
    );

    expect(merged.single.currentNumber, 2);
    expect(merged.single.status, 'EXHAUSTED');
  });
}
