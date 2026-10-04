import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

class NextcloudService {
  Uri _apiUri([String? relativePath]) {
    final path = relativePath == null || relativePath.isEmpty
        ? '/api/notes'
        : '/api/notes/$relativePath';
    return Uri.https(AppConfig.wsDomain, path);
  }

  Future<List<String>> _listAllPdfs() async {
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(_apiUri()))
          .close()
          .timeout(const Duration(seconds: 30));
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Notenserver antwortete mit HTTP ${response.statusCode}.',
          uri: _apiUri(),
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['files'] is! List) {
        throw const FormatException('Ungültige Notenliste vom Notenserver.');
      }

      return (decoded['files'] as List)
          .whereType<String>()
          .where((path) => path.toLowerCase().endsWith('.pdf'))
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  Future<File> downloadPdf(String filename) async {
    String? path;
    for (final candidate in await _listAllPdfs()) {
      if (candidate.split('/').last == filename) {
        path = candidate;
        break;
      }
    }
    if (path == null) {
      throw FileSystemException('Noten-PDF nicht gefunden', filename);
    }

    final dir = await getApplicationDocumentsDirectory();
    final localFile = File(
      '${dir.path}${Platform.pathSeparator}'
      '${path.split('/').join(Platform.pathSeparator)}',
    );
    if (await localFile.exists()) return localFile;

    return _downloadFromPath(path, localFile);
  }

  Future<List<File>> listAndDownloadPdfs(String instrument, String voice) async {
    final allFiles = await _listAllPdfs();
    final filtered = allFiles
        .where((path) => path.endsWith('_${instrument}_$voice.pdf'))
        .toList();

    final downloadedFiles = <File>[];
    for (final relativePath in filtered) {
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File(
        '${dir.path}${Platform.pathSeparator}'
        '${relativePath.split('/').join(Platform.pathSeparator)}',
      );
      downloadedFiles.add(
        await localFile.exists()
            ? localFile
            : await _downloadFromPath(relativePath, localFile),
      );
    }

    return downloadedFiles;
  }

  Future<File> _downloadFromPath(String relativePath, File localFile) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(_apiUri(relativePath));
      final response = await request.close().timeout(
            const Duration(seconds: 60),
          );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'Notenserver antwortete mit HTTP ${response.statusCode}.',
          uri: _apiUri(relativePath),
        );
      }

      await localFile.parent.create(recursive: true);
      final sink = localFile.openWrite();
      try {
        await sink.addStream(response).timeout(const Duration(minutes: 2));
        await sink.flush();
      } finally {
        await sink.close();
      }
      debugPrint('Noten-PDF gespeichert: ${localFile.path}');
      return localFile;
    } finally {
      client.close(force: true);
    }
  }
}
