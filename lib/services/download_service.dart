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
    final raw = value.trim();
    final parsed = Uri.tryParse(raw);
    if (parsed == null || raw.isEmpty) {
      throw const FormatException('Ungültige Download-URL.');
    }
    if (parsed.hasScheme) {
      if (!parsed.hasAuthority ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        throw FormatException('Ungültige Download-URL: $value');
      }
      return parsed;
    }

    final baseValue = dotenv.env['NEXTCLOUD_BASE_URL']?.trim() ?? '';
    final base = Uri.tryParse(baseValue);
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'http' && base.scheme != 'https')) {
      throw StateError('NEXTCLOUD_BASE_URL ist ungültig.');
    }
    final resolved = raw.startsWith('/')
        ? base.replace(
            path: parsed.path, query: parsed.query, fragment: parsed.fragment)
        : base.resolve(raw);
    if (!resolved.hasAuthority ||
        (resolved.scheme != 'http' && resolved.scheme != 'https')) {
      throw FormatException('Ungültige Download-URL: $value');
    }
    return resolved;
  }

  String _safeUri(Uri uri) => uri.origin;

  Future<String?> downloadFile(
      String url, String fileName, StreamController<double> progress) async {
    try {
      final directory = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      await directory.create(recursive: true);
      final path = '${directory.path}/$fileName';
      final downloadUri = _resolveUri(url);
      final user =
          (dotenv.env['NC_USER'] ?? dotenv.env['NEXTCLOUD_USER'] ?? '').trim();
      final password =
          dotenv.env['NC_PASS'] ?? dotenv.env['NEXTCLOUD_PASSWORD'] ?? '';
      if (user.isEmpty != password.isEmpty) {
        throw StateError(
            'Nextcloud-Benutzername und Passwort müssen gemeinsam gesetzt sein.');
      }

      final headers = <String, String>{'Accept': '*/*'};
      final baseUri =
          Uri.tryParse(dotenv.env['NEXTCLOUD_BASE_URL']?.trim() ?? '');
      if (user.isNotEmpty &&
          baseUri != null &&
          baseUri.hasAuthority &&
          (baseUri.scheme == 'http' || baseUri.scheme == 'https') &&
          baseUri.origin == downloadUri.origin) {
        headers[HttpHeaders.authorizationHeader] =
            'Basic ${base64Encode(utf8.encode('$user:$password'))}';
      }

      UpdateLogger.info('APK-Download gestartet: ${_safeUri(downloadUri)}');
      await _dio.download(downloadUri.toString(), path,
          options: Options(headers: headers),
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
