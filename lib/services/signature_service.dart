import 'package:flutter/services.dart';
import '../utils/logger.dart';

class SignatureService {
  static const _channel = MethodChannel('app.signature');

  static Future<String?> getInstalledSignature() async {
    try {
      return await _channel.invokeMethod<String>('getInstalledSignature');
    } catch (error) {
      UpdateLogger.error('Fehler beim Lesen der installierten Signatur', error);
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getApkSignature(String apkPath) async {
    try {
      final result = await _channel.invokeMethod<Map>('getApkSignature', {'path': apkPath});
      return result == null ? null : Map<String, dynamic>.from(result);
    } catch (error) {
      UpdateLogger.error('Fehler beim Lesen der APK-Signatur', error);
      return null;
    }
  }
}
