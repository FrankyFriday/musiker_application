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

  /// 🔹 Lädt PDF aus Root ODER Unterordner oder nutzt Cache
  Future<File> downloadPdf(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final localFile = File('${dir.path}/$filename');

    // ✅ Cache
    if (await localFile.exists()) {
      print('📦 Cache benutzt: $filename');
      return localFile;
    }

    // 1️⃣ Erst Root probieren
    try {
      return await _downloadFromPath(filename, localFile);
    } catch (_) {
      print('🔍 Nicht im Root – suche in Unterordnern...');
    }

    // 2️⃣ Unterordner durchsuchen
    final path = await _findInSubfolders(filename);
    if (path == null) {
      throw Exception('❌ Datei nicht gefunden: $filename');
    }

    return await _downloadFromPath(path, localFile);
  }

  /// 🔹 Download mit bekanntem Pfad relativ zur Base-URL
  Future<File> _downloadFromPath(String relativePath, File localFile) async {
    // Base-URL sauber ohne doppeltes mwesterh
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    // Pfad korrekt encodieren (Ordner bleiben erhalten)
    final encodedPath = relativePath
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');

    final url = '$cleanBase/$encodedPath';
    print('⬇️ Lade PDF von: $url');

    final request = await HttpClient().getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.authorizationHeader, _authHeader);

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final bytes = await response.fold<List<int>>(
      [],
      (prev, e) => prev..addAll(e),
    );

    await localFile.writeAsBytes(bytes, flush: true);
    print('✅ PDF gespeichert: ${localFile.path}');
    return localFile;
  }

  /// 🔹 Sucht Datei in Unterordnern (Depth: infinity)
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
        // Relative Pfade relativ zur Base-URL
        // z.B. fullPath: /remote.php/dav/files/mwesterh/PreussensGloria/PreussensGloria_Trompete_1.pdf
        // wir schneiden alles vor /files/mwesterh/ ab
        final parts = fullPath.split('/files/mwesterh/');
        if (parts.length == 2) {
          return parts[1]; // relative Pfad für Download
        }
      }
    }
    return null;
  }
}
