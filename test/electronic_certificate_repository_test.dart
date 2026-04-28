import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/facturacion_electronica/data/electronic_certificate_repository.dart';

void main() {
  group('friendlyCertificateUploadErrorMessage', () {
    test('maps certificate upload errors to simple customer messages', () {
      expect(
        friendlyCertificateUploadErrorMessage(
          errorCode: 'ELECTRONIC_CERTIFICATE_PASSWORD_INVALID',
        ),
        'La contraseña no es correcta',
      );
      expect(
        friendlyCertificateUploadErrorMessage(
          errorCode: 'ELECTRONIC_CERTIFICATE_INVALID_FILE',
        ),
        'El certificado no es válido',
      );
      expect(
        friendlyCertificateUploadErrorMessage(
          message: 'El certificado está vencido',
        ),
        'El certificado está vencido',
      );
      expect(
        friendlyCertificateUploadErrorMessage(statusCode: 500),
        'No se pudo cargar el certificado',
      );
    });

    test('maps POS override key failures precisely', () {
      expect(
        friendlyCertificateUploadErrorMessage(
          errorCode: 'POS_OVERRIDE_KEY_REQUIRED',
          statusCode: 401,
        ),
        'El backend requiere configurar la llave de conexión del POS',
      );

      expect(
        friendlyCertificateUploadErrorMessage(
          errorCode: 'POS_OVERRIDE_KEY_INVALID',
          statusCode: 401,
        ),
        'La llave de conexión del POS no coincide con el backend',
      );
    });

    test('maps DGII certificate signature rejection distinctly', () {
      expect(
        friendlyCertificateUploadErrorMessage(
          errorCode: 'DGII_SEED_VALIDATE_BAD_REQUEST',
          message: 'Firma del certificado inválida',
          statusCode: 400,
        ),
        'DGII rechazó la firma del certificado. Verifique el certificado, contraseña y que el backend esté actualizado',
      );

      expect(
        friendlyCertificateUploadErrorMessage(
          message: 'Firma del certificado invalida',
          statusCode: 400,
        ),
        'DGII rechazó la firma del certificado. Verifique el certificado, contraseña y que el backend esté actualizado',
      );
    });
  });
}
