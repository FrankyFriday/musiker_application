import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

class NextcloudService {
  final String baseUrl = dotenv.env['NEXTCLOUD_BASE_URL']!;
  final String username = dotenv.env['NEXTCLOUD_USER']!;
  final String password = dotenv.env['NEXTCLOUD_PASSWORD']!;

  String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  /* ===================== LIVE ===================== */

  /// 🔹 Lädt eine einzelne PDF für Live-Stücke (wie bisher)
  Future<File> downloadPdf(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final localFile = File('${dir.path}/$filename');

    if (await localFile.exists()) {
      print('📦 Cache benutzt: $filename');
      return localFile;
    }

    try {
      return await _downloadFromPath(filename, localFile);
    } catch (_) {
      print('🔍 Nicht im Root – suche in Unterordnern...');
    }

    final path = await _findInSubfolders(filename);
    if (path == null) {
      throw Exception('❌ Datei nicht gefunden: $filename');
    }

    return await _downloadFromPath(path, localFile);
  }

  /* ===================== OFFLINE ===================== */

  /// 🔹 Listet alle PDFs auf und lädt die herunter, die zu Instrument+Stimme passen.
  /// Falls keine gefunden wird, wird das nächste verfügbare Instrument/Stimme genommen.
  Future<List<File>> listAndDownloadPdfs(String instrument, String voice) async {
    final allFiles = await _listAllPdfs();

    // Filter für gewünschtes Instrument + Stimme
    List<String> filtered = allFiles
        .where((f) => f.endsWith('_${instrument}_${voice}.pdf'))
        .toList();

    // Falls nichts gefunden: nächstes verfügbares Instrument/Stimme
    if (filtered.isEmpty && allFiles.isNotEmpty) {
      print('⚠️ Keine Dateien für $instrument / $voice gefunden, nehme nächstes verfügbares.');
      filtered = [allFiles.first];
    }

    final List<File> downloadedFiles = [];
    for (final fileName in filtered) {
      try {
        final file = await downloadPdf(fileName); // Nutzt weiterhin die Live-Methode
        downloadedFiles.add(file);
      } catch (e) {
        print('Fehler beim Herunterladen von $fileName: $e');
      }
    }

    return downloadedFiles;
  }

  /* ===================== HELPER ===================== */

  /// 🔹 Download mit bekanntem Pfad
  Future<File> _downloadFromPath(String relativePath, File localFile) async {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final encodedPath = relativePath.split('/').map(Uri.encodeComponent).join('/');
    final url = '$cleanBase/$encodedPath';
    print('⬇️ Lade PDF von: $url');

    final request = await HttpClient().getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.authorizationHeader, _authHeader);

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final bytes = await response.fold<List<int>>([], (prev, e) => prev..addAll(e));

    // ⚡ Ordnerstruktur erstellen, falls noch nicht vorhanden
    await localFile.parent.create(recursive: true);
    await localFile.writeAsBytes(bytes, flush: true);

    print('✅ PDF gespeichert: ${localFile.path}');
    return localFile;
  }

  /// 🔹 Sucht Datei in Unterordnern
  Future<String?> _findInSubfolders(String filename) async {
    final uri = Uri.parse(baseUrl);
    final request = await HttpClient().openUrl('PROPFIND', uri);
    request.headers.set(HttpHeaders.authorizationHeader, _authHeader);
    request.headers.set('Depth', 'infinity');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    final regex = RegExp(r'<d:href>([^<]+)</d:href>');
    for (final m in regex.allMatches(body)) {
      final fullPath = Uri.decodeFull(m.group(1)!);
      if (fullPath.endsWith('/$filename')) {
        final parts = fullPath.split('/files/mwesterh/');
        if (parts.length == 2) return parts[1];
      }
    }
    return null;
  }

  /// 🔹 Listet alle PDFs auf (für OfflinePractice)
  Future<List<String>> _listAllPdfs() async {
    final uri = Uri.parse(baseUrl);
    final request = await HttpClient().openUrl('PROPFIND', uri);
    request.headers.set(HttpHeaders.authorizationHeader, _authHeader);
    request.headers.set('Depth', 'infinity');

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    final regex = RegExp(r'<d:href>([^<]+)</d:href>');
    final List<String> files = [];

    for (final m in regex.allMatches(body)) {
      final fullPath = Uri.decodeFull(m.group(1)!);
      if (fullPath.endsWith('.pdf')) {
        final parts = fullPath.split('/files/mwesterh/');
        if (parts.length == 2) files.add(parts[1]);
      }
    }

    return files;
  }
}
