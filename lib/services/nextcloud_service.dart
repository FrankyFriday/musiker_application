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

  /// 🔹 Lädt PDF aus Nextcloud oder nutzt Cache
  Future<File> downloadPdf(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final localFile = File('${dir.path}/$filename');

    // ✅ CACHE
    if (await localFile.exists()) {
      print('📦 Cache benutzt: $filename');
      return localFile;
    }

    // ✅ URL korrekt zusammensetzen
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final encodedFilename = Uri.encodeComponent(filename);
    final url = '$cleanBase/$encodedFilename';

    print('⬇️ Lade PDF von: $url');

    final uri = Uri.parse(url);
    final request = await HttpClient().getUrl(uri);
    request.headers.set(HttpHeaders.authorizationHeader, _authHeader);

    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception('Nextcloud HTTP ${response.statusCode}');
    }

    final bytes = await response.fold<List<int>>(
      [],
      (prev, e) => prev..addAll(e),
    );

    await localFile.writeAsBytes(bytes, flush: true);
    print('✅ PDF gespeichert: ${localFile.path}');

    return localFile;
  }
}
