import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/license/services/bank_transfer_whatsapp.dart';

void main() {
  test('builds the FullPOS bank transfer WhatsApp request', () {
    final uri = buildBankTransferWhatsappUri(
      programName: 'FullPOS',
      bankName: 'Popular',
      months: 6,
      amount: 90,
      currency: 'USD',
      businessName: 'Comercial Demo',
      deviceId: 'terminal-123',
    );

    expect(uri.host, 'wa.me');
    expect(uri.path, '/18494314070');
    expect(uri.queryParameters['text'], contains('FullPOS'));
    expect(uri.queryParameters['text'], contains('Popular'));
    expect(uri.queryParameters['text'], contains('República Dominicana'));
  });
}
