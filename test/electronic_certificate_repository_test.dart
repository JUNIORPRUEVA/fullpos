import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/facturacion_electronica/data/electronic_certificate_repository.dart';

void main() {
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
}
