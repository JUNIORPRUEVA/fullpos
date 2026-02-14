import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';

class LicenseSupportMessage {
  static String build({
    required String supportCode,
    required String? businessId,
    required String? deviceId,
    required String? licenseKey,
    required String projectCode,
    required String? status,
  }) {
    final now = DateTime.now();
    final ts = DateFormat('yyyy-MM-dd HH:mm').format(now);

    final lines = <String>[
      'Hola soporte, necesito ayuda con FULLPOS.',
      '',
      'Código soporte: $supportCode',
      'Proyecto: $projectCode',
      'Versión app: ${AppConfig.appVersion}',
      'Fecha/hora: $ts',
      if (businessId != null && businessId.trim().isNotEmpty)
        'Business ID: ${businessId.trim()}',
      if (deviceId != null && deviceId.trim().isNotEmpty)
        'Device ID: ${deviceId.trim()}',
      if (licenseKey != null && licenseKey.trim().isNotEmpty)
        'Licencia: ${licenseKey.trim()}',
      if (status != null && status.trim().isNotEmpty)
        'Estado: ${status.trim()}',
    ];

    return lines.join('\n');
  }
}
