import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

class NextcloudService {
  final Uri _apiBaseUri;
  final Future<Directory> Function() _documentsDirectoryProvider;

  NextcloudService({
    Uri? apiBaseUri,
    Future<Directory> Function()? documentsDirectoryProvider,
  })  : _apiBaseUri = apiBaseUri ?? Uri.https(AppConfig.wsDomain, '/'),
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  Uri _apiUri([String? relativePath]) {
    return _apiBaseUri.replace(
      path: relativePath == null || relativePath.isEmpty
          ? '/api/notes'
          : '/api/notes/$relativePath',
      query: null,
      fragment: null,
    );
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
    final cached = await _findCachedPdf(filename);
    if (cached != null) return cached;

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

    final localFile = await _localFileForPath(path);
    return _downloadFromPath(path, localFile);
  }

  Future<List<File>> listAndDownloadPdfs(
      String instrument, String voice) async {
    List<String> allFiles;
    try {
      allFiles = await _listAllPdfs();
    } on TimeoutException {
      final cached = await listCachedPdfs(instrument, voice);
      if (cached.isNotEmpty) return cached;
      rethrow;
    } on IOException {
      final cached = await listCachedPdfs(instrument, voice);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
    final filtered = allFiles
        .where((path) => _matchesProfile(path, instrument, voice))
        .toList();

    final downloadedFiles = <File>[];
    for (final relativePath in filtered) {
      final localFile = await _localFileForPath(relativePath);
      final cached = await _validCachedFile(localFile);
      downloadedFiles.add(
        cached ?? await _downloadFromPath(relativePath, localFile),
      );
    }

    return downloadedFiles;
  }

  Future<List<File>> listCachedPdfs(String instrument, String voice) async {
    final dir = await _documentsDirectoryProvider();
    if (!await dir.exists()) return [];
    final files = <File>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || !_matchesProfile(entity.path, instrument, voice)) {
        continue;
      }
      final cached = await _validCachedFile(entity);
      if (cached != null) files.add(cached);
    }
    return files;
  }

  Future<File?> _findCachedPdf(String filename) async {
    final dir = await _documentsDirectoryProvider();
    if (!await dir.exists()) return null;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File &&
          entity.path.split(Platform.pathSeparator).last == filename) {
        final cached = await _validCachedFile(entity);
        if (cached != null) return cached;
      }
    }
    return null;
  }

  Future<File> _downloadFromPath(String relativePath, File localFile) async {
    final client = HttpClient();
    final temporaryFile = File(
      '${localFile.path}.part-${DateTime.now().microsecondsSinceEpoch}',
    );
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
      final sink = temporaryFile.openWrite();
      try {
        await sink.addStream(response).timeout(const Duration(minutes: 2));
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (!await _isValidPdf(temporaryFile)) {
        throw FileSystemException(
          'Der Notenserver hat keine gültige PDF-Datei geliefert.',
          relativePath,
        );
      }
      if (await localFile.exists()) await localFile.delete();
      final downloadedFile = await temporaryFile.rename(localFile.path);
      debugPrint('Noten-PDF gespeichert: ${downloadedFile.path}');
      return downloadedFile;
    } catch (_) {
      if (await temporaryFile.exists()) await temporaryFile.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _localFileForPath(String relativePath) async {
    final dir = await _documentsDirectoryProvider();
    return File(
      '${dir.path}${Platform.pathSeparator}'
      '${relativePath.split('/').join(Platform.pathSeparator)}',
    );
  }

  Future<File?> _validCachedFile(File file) async {
    if (!await file.exists()) return null;
    if (await _isValidPdf(file)) return file;
    await file.delete();
    return null;
  }

  Future<bool> _isValidPdf(File file) async {
    if (!await file.exists() || await file.length() < 5) return false;
    final handle = await file.open();
    try {
      return ascii.decode(await handle.read(5), allowInvalid: true) == '%PDF-';
    } finally {
      await handle.close();
    }
  }

  bool _matchesProfile(String path, String instrument, String voice) {
    final filename = path.split(Platform.pathSeparator).last.split('/').last;
    return filename.toLowerCase().endsWith(
          '_${instrument.trim()}_${voice.trim()}.pdf'.toLowerCase(),
        );
  }
}
