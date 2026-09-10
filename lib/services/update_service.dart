import 'dart:async';
import 'dart:io';
import '../models/update_info.dart';
import '../utils/logger.dart';
import 'download_service.dart';
import 'signature_service.dart';

class UpdateService {
  final DownloadService _downloadService;
  UpdateService(this._downloadService);

  Future<String?> downloadUpdate(UpdateInfo info, StreamController<double> progress) async {
    UpdateLogger.info('Update angefordert: ${info.version} (${info.url})');
    try {
      final path = await _downloadService.downloadFile(
        info.url, DownloadService.generateFileName(info.version), progress);
      if (path == null || !await File(path).exists()) return null;
      final installed = await SignatureService.getInstalledSignature();
      final apk = await SignatureService.getApkSignature(path);
      if (apk == null || apk['packageName'] != 'com.example.musiker_application' ||
          apk['versionName'] != info.version || installed == null ||
          apk['signature'] != installed) {
        UpdateLogger.error('APK-Prüfung fehlgeschlagen: Package, Version oder Signatur stimmt nicht.');
        return null;
      }
      UpdateLogger.info('APK-Prüfung erfolgreich: $path');
      return path;
    } catch (error, stackTrace) {
      UpdateLogger.error('Fehler beim Update-Download', error, stackTrace);
      return null;
    }
  }

  static Future<T> retry<T>(Future<T> Function() operation, int maxRetries, Duration delay) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await operation();
      } catch (_) {
        if (attempt >= maxRetries - 1) rethrow;
        await Future.delayed(delay * (1 << attempt));
      }
    }
  }
}
