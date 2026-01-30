import 'dart:io';

import '../../features/settings/data/business_settings_repository.dart';
import '../config/backend_config.dart';
import '../logging/app_logger.dart';

class CloudStatus {
  CloudStatus({
    required this.isCloudEnabled,
    required this.isInternetAvailable,
    required this.canUseCloudBackup,
    required this.baseUrl,
    this.reason,
  });

  final bool isCloudEnabled;
  final bool isInternetAvailable;
  final bool canUseCloudBackup;
  final String baseUrl;
  final String? reason;
}

class CloudStatusService {
  CloudStatusService._();

  static final CloudStatusService instance = CloudStatusService._();

  Future<CloudStatus> checkStatus() async {
    final settings = await BusinessSettingsRepository().loadSettings();
    final baseUrl =
        (settings.cloudEndpoint?.trim().isNotEmpty ?? false)
            ? settings.cloudEndpoint!.trim()
            : backendBaseUrl;

    if (!settings.cloudEnabled) {
      return CloudStatus(
        isCloudEnabled: false,
        isInternetAvailable: false,
        canUseCloudBackup: false,
        baseUrl: baseUrl,
        reason: 'Nube desactivada',
      );
    }

    final online = await _checkInternet(baseUrl);
    if (!online) {
      return CloudStatus(
        isCloudEnabled: true,
        isInternetAvailable: false,
        canUseCloudBackup: false,
        baseUrl: baseUrl,
        reason: 'Sin conexiÃ³n a Internet',
      );
    }

    final cloudKey = settings.cloudApiKey?.trim();
    if (cloudKey == null || cloudKey.isEmpty) {
      return CloudStatus(
        isCloudEnabled: true,
        isInternetAvailable: true,
        canUseCloudBackup: false,
        baseUrl: baseUrl,
        reason: 'API key faltante',
      );
    }

    return CloudStatus(
      isCloudEnabled: true,
      isInternetAvailable: true,
      canUseCloudBackup: true,
      baseUrl: baseUrl,
    );
  }

  Future<bool> _checkInternet(String baseUrl) async {
    try {
      final uri = Uri.parse(baseUrl);
      final host = uri.host;
      if (host.isEmpty) return false;
      final result = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (e) {
      await AppLogger.instance.logWarn(
        'CloudStatus sin Internet: $e',
        module: 'backup_cloud',
      );
      return false;
    }
  }
}
