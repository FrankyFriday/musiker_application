import 'package:version/version.dart';

class VersionChecker {
  static int compareVersions(String version1, String version2) {
    try {
      return Version.parse(version1).compareTo(Version.parse(version2));
    } catch (_) {
      return version1.compareTo(version2);
    }
  }

  static bool isNewerVersion(String currentVersion, String newVersion) =>
      compareVersions(newVersion, currentVersion) > 0;
}
