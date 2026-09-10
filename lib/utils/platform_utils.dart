import 'dart:io';

class PlatformUtils {
  static String getInstallerExtension() => Platform.isAndroid ? '.apk' : '';
}
