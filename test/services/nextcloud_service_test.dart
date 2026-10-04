import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:marschpad/services/nextcloud_service.dart';

void main() {
  late HttpServer server;
  late Directory documentsDirectory;
  late List<String> requestedPaths;
  var serveValidPdf = true;

  setUp(() async {
    requestedPaths = [];
    serveValidPdf = true;
    documentsDirectory = await Directory.systemTemp.createTemp(
      'marschpad-notes-test-',
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      unawaited(() async {
        if (request.uri.path == '/api/notes') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'files': [
                'Marsch/Marsch_Trompete_1.pdf',
                'Marsch/Marsch_Trompete_2.pdf',
                'Marsch/Marsch_Flöte_1.pdf',
              ],
            }),
          );
        } else {
          requestedPaths.add(request.uri.path);
          request.response.headers.contentType = ContentType.binary;
          request.response.add(
            ascii.encode(
                serveValidPdf ? '%PDF-1.7\nfixture' : '<html>error</html>'),
          );
        }
        await request.response.close();
      }());
    });
  });

  tearDown(() async {
    await server.close(force: true);
    await documentsDirectory.delete(recursive: true);
  });

  NextcloudService createService() => NextcloudService(
        apiBaseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        documentsDirectoryProvider: () async => documentsDirectory,
      );

  test('downloads only PDFs for the selected instrument and voice', () async {
    final files = await createService().listAndDownloadPdfs('Trompete', '1');

    expect(files, hasLength(1));
    expect(files.single.path, endsWith('Marsch_Trompete_1.pdf'));
    expect(await files.single.readAsString(), startsWith('%PDF-'));
    expect(requestedPaths, ['/api/notes/Marsch/Marsch_Trompete_1.pdf']);
  });

  test('replaces a partial cached PDF before making it available offline',
      () async {
    final partialFile = File(
      '${documentsDirectory.path}${Platform.pathSeparator}'
      'Marsch${Platform.pathSeparator}Marsch_Trompete_1.pdf',
    );
    await partialFile.parent.create(recursive: true);
    await partialFile.writeAsString('partial download');

    final files = await createService().listAndDownloadPdfs('Trompete', '1');

    expect(files, hasLength(1));
    expect(await files.single.readAsString(), startsWith('%PDF-'));
    expect(requestedPaths, ['/api/notes/Marsch/Marsch_Trompete_1.pdf']);
  });

  test('does not cache a response that is not a PDF', () async {
    serveValidPdf = false;

    await expectLater(
      createService().listAndDownloadPdfs('Trompete', '1'),
      throwsA(isA<FileSystemException>()),
    );
    expect(await createService().listCachedPdfs('Trompete', '1'), isEmpty);
  });
}
