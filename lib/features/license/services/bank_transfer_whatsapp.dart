const bankTransferWhatsappNumber = '18494314070';
const dominicanBanks = <String>['Banreservas', 'BHD', 'Popular'];

Uri buildBankTransferWhatsappUri({
  required String programName,
  required String bankName,
  required int months,
  required double amount,
  required String currency,
  String? businessName,
  String? deviceId,
}) {
  final message = [
    'Hola, deseo comprar una licencia de $programName mediante transferencia bancaria.',
    'Banco seleccionado: $bankName.',
    'Plan: $months ${months == 1 ? 'mes' : 'meses'}.',
    'Monto: $currency ${amount.toStringAsFixed(2)}.',
    if ((businessName ?? '').trim().isNotEmpty)
      'Negocio: ${businessName!.trim()}.',
    if ((deviceId ?? '').trim().isNotEmpty) 'Dispositivo: ${deviceId!.trim()}.',
    'Estoy en República Dominicana. Por favor, envíenme los datos para realizar la transferencia y activar mi licencia.',
  ].join('\n');

  return Uri.https('wa.me', '/$bankTransferWhatsappNumber', {'text': message});
}
