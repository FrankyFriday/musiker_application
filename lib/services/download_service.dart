import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger.dart';
import '../utils/platform_utils.dart';

class DownloadService {
  final Dio _dio;
  DownloadService(this._dio);

  Uri _resolveUri(String value) {
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null || parsed.toString().isEmpty) throw FormatException('Ungültige Download-URL.');
    if (parsed.hasScheme) return parsed;
    final base = Uri.tryParse(dotenv.env['NEXTCLOUD_BASE_URL'] ?? '');
    if (base == null || !base.hasAuthority) throw StateError('NEXTCLOUD_BASE_URL ist ungültig.');
    return base.resolve(value);
  }

  Future<String?> downloadFile(String url, String fileName, StreamController<double> progress) async {
    try {
      final directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      await directory.create(recursive: true);
      final path = '${directory.path}/$fileName';
      final user = dotenv.env['NEXTCLOUD_USER'] ?? '';
      final password = dotenv.env['NEXTCLOUD_PASSWORD'] ?? '';
      if (user.isEmpty || password.isEmpty) throw StateError('Nextcloud-Zugangsdaten fehlen.');
      final auth = base64Encode(utf8.encode('$user:$password'));
      UpdateLogger.info('APK-Download gestartet: ${_resolveUri(url).replace(userInfo: '')}');
      await _dio.download(_resolveUri(url).toString(), path,
          options: Options(headers: {'Authorization': 'Basic $auth'}),
          onReceiveProgress: (received, total) {
            if (total > 0) progress.add(received / total);
          });
      final file = await File(path).stat();
      if (file.size == 0) throw StateError('APK ist leer.');
      progress.add(1);
      return path;
    } catch (error, stackTrace) {
      UpdateLogger.error('APK-Download fehlgeschlagen', error, stackTrace);
      progress.addError(error, stackTrace);
      return null;
    }
  }

  static String generateFileName(String version) =>
      'musiker_application-$version${PlatformUtils.getInstallerExtension()}';
}
