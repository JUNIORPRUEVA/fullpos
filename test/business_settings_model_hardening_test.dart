import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/settings/data/business_settings_model.dart';

void main() {
  test('BusinessSettings.fromMap tolera fechas corruptas', () {
    final settings = BusinessSettings.fromMap({
      'id': 1,
      'business_name': 'Mi Negocio',
      'created_at': '',
      'updated_at': 'NO_ES_FECHA',
      'cloud_allowed_roles': '["admin"]',
    });

    expect(settings.businessName, 'Mi Negocio');
    // No debe lanzar; debe devolver DateTime válido.
    expect(settings.createdAt, isA<DateTime>());
    expect(settings.updatedAt, isA<DateTime>());
  });

  test('BusinessSettings.fromMap acepta timestamp ms en created_at/updated_at', () {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final settings = BusinessSettings.fromMap({
      'id': 1,
      'business_name': 'FULLPOS',
      'created_at': nowMs,
      'updated_at': nowMs,
    });

    expect(settings.createdAt.millisecondsSinceEpoch, nowMs);
    expect(settings.updatedAt.millisecondsSinceEpoch, nowMs);
  });
}
