import 'app_version.dart';

enum UpdateDecision { none, optional, mandatory }

class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.latest,
    required this.minimumSupported,
    required this.mandatory,
    required this.enabled,
    required this.installerUrl,
    required this.installerFilename,
    required this.installerSizeBytes,
    required this.sha256,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.publishedAt,
  });

  static const approvedHosts = <String>{
    'github.com',
    'objects.githubusercontent.com',
    'github-releases.githubusercontent.com',
    'release-assets.githubusercontent.com',
  };

  final AppVersion latest;
  final AppVersion minimumSupported;
  final bool mandatory;
  final bool enabled;
  final Uri installerUrl;
  final String installerFilename;
  final int? installerSizeBytes;
  final String? sha256;
  final String releaseTitle;
  final List<String> releaseNotes;
  final DateTime publishedAt;

  factory AppUpdatePolicy.fromJson(Map<String, dynamic> json) {
    final url = Uri.parse(_requiredString(json, 'installerUrl'));
    validateInstallerUri(url);
    final filename = _requiredString(json, 'installerFilename');
    if (filename != 'FullPOS-Setup.exe') {
      throw const FormatException('Unexpected installer filename');
    }
    final rawHash = json['sha256']?.toString().trim().toLowerCase() ?? '';
    String? hash;
    if (rawHash.isNotEmpty) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(rawHash)) {
        throw const FormatException('Invalid SHA-256');
      }
      hash = rawHash;
    }
    final latestBuild = _positiveInt(json['latestBuild'], 'latestBuild');
    final minimumBuild = _positiveInt(
      json['minimumSupportedBuild'],
      'minimumSupportedBuild',
    );
    final size = json['installerSizeBytes'] == null
        ? null
        : _positiveInt(json['installerSizeBytes'], 'installerSizeBytes');
    final notesValue = json['releaseNotes'];
    if (notesValue is! List) {
      throw const FormatException('Invalid release notes');
    }
    final notes = notesValue
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final publishedAt = DateTime.tryParse(_requiredString(json, 'publishedAt'));
    if (publishedAt == null) {
      throw const FormatException('Invalid published date');
    }
    if (json['projectCode'] != 'fullpos' ||
        json['platform'] != 'windows' ||
        json['enabled'] != true) {
      throw const FormatException('Policy is not enabled for FullPOS Windows');
    }

    return AppUpdatePolicy(
      latest: AppVersion.parse(
        _requiredString(json, 'latestVersion'),
        buildNumber: latestBuild,
      ),
      minimumSupported: AppVersion.parse(
        _requiredString(json, 'minimumSupportedVersion'),
        buildNumber: minimumBuild,
      ),
      mandatory: json['mandatory'] == true,
      enabled: true,
      installerUrl: url,
      installerFilename: filename,
      installerSizeBytes: size,
      sha256: hash,
      releaseTitle: _requiredString(json, 'releaseTitle'),
      releaseNotes: notes,
      publishedAt: publishedAt.toUtc(),
    );
  }

  UpdateDecision decide(AppVersion installed) {
    if (installed.compareTo(latest) >= 0) return UpdateDecision.none;
    if (installed.compareTo(minimumSupported) < 0 || mandatory) {
      return UpdateDecision.mandatory;
    }
    return UpdateDecision.optional;
  }

  String get localInstallerFilename =>
      'FullPOS-Setup-v${latest.semantic}-build${latest.build}.exe';

  Map<String, dynamic> toJson() => {
    'projectCode': 'fullpos',
    'platform': 'windows',
    'latestVersion': latest.semantic,
    'latestBuild': latest.build,
    'minimumSupportedVersion': minimumSupported.semantic,
    'minimumSupportedBuild': minimumSupported.build,
    'mandatory': mandatory,
    'enabled': enabled,
    'installerUrl': installerUrl.toString(),
    'installerFilename': installerFilename,
    'installerSizeBytes': installerSizeBytes,
    if (sha256 != null) 'sha256': sha256,
    'releaseTitle': releaseTitle,
    'releaseNotes': releaseNotes,
    'publishedAt': publishedAt.toIso8601String(),
  };

  static void validateInstallerUri(Uri uri) {
    if (uri.scheme != 'https' ||
        !approvedHosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.host.isEmpty) {
      throw const FormatException('Unapproved installer URL');
    }
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key]?.toString().trim() ?? '';
    if (value.isEmpty) throw FormatException('Missing $key');
    return value;
  }

  static int _positiveInt(dynamic value, String key) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null || parsed <= 0) throw FormatException('Invalid $key');
    return parsed;
  }
}
