import 'package:package_info_plus/package_info_plus.dart';

class AppVersion implements Comparable<AppVersion> {
  const AppVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  static final RegExp _pattern = RegExp(
    r'^\s*v?(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*$',
    caseSensitive: false,
  );

  factory AppVersion.parse(String input, {int? buildNumber}) {
    final match = _pattern.firstMatch(input);
    if (match == null) {
      throw const FormatException('Invalid semantic version');
    }
    final embeddedBuild = int.tryParse(match.group(4) ?? '');
    return AppVersion(
      major: int.parse(match.group(1)!),
      minor: int.parse(match.group(2)!),
      patch: int.parse(match.group(3)!),
      build: buildNumber ?? embeddedBuild ?? 0,
    );
  }

  static Future<AppVersion> installed() async {
    final info = await PackageInfo.fromPlatform();
    return AppVersion.parse(
      info.version,
      buildNumber: int.tryParse(info.buildNumber.trim()) ?? 0,
    );
  }

  String get semantic => '$major.$minor.$patch';

  @override
  int compareTo(AppVersion other) {
    for (final pair in <(int, int)>[
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (build, other.build),
    ]) {
      final compared = pair.$1.compareTo(pair.$2);
      if (compared != 0) return compared;
    }
    return 0;
  }

  @override
  String toString() => '$semantic+$build';

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);
}
