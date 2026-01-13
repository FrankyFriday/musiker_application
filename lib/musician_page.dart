import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class MusicianPage extends StatefulWidget {
  final String instrument;
  final String voice;

  const MusicianPage({
    super.key,
    required this.instrument,
    required this.voice,
  });

  @override
  State<MusicianPage> createState() => _MusicianPageState();
}

class _MusicianPageState extends State<MusicianPage> {
  WebSocketChannel? _channel;
  final List<ReceivedPiece> _received = [];
  String _status = 'Verbindung wird aufgebaut…';
  late final String _clientId;
  bool _isConnected = false;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  Route? _currentPdfRoute;

  @override
  void initState() {
    super.initState();
    _clientId = const Uuid().v4();
    _autoConnect();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _autoConnect() async {
    const serverDomain = 'ws.notenserver.duckdns.org';
    await _connectToConductor(serverDomain);
  }

  Future<void> _connectToConductor(String domain) async {
    setState(() => _status = 'Verbinde mit Dirigent ($domain)…');

    try {
      // WebSocket URI (wss:// ohne Port, Proxy übernimmt Port 443)
      final uri = Uri.parse('wss://$domain');

      _channel = kIsWeb
          ? WebSocketChannel.connect(uri)
          : IOWebSocketChannel.connect(uri.toString());

      // Musiker beim Server registrieren
      _channel!.sink.add(jsonEncode({
        'type': 'register',
        'clientId': _clientId,
        'role': 'musician',
        'instrument': widget.instrument,
        'voice': widget.voice,
      }));

      setState(() {
        _status = 'Verbunden mit Dirigent';
        _isConnected = true;
      });

      _channel!.stream.listen(
        _handleMessage,
        onDone: () => setState(() {
          _status = 'Verbindung beendet';
          _isConnected = false;
        }),
        onError: (e) => setState(() {
          _status = 'Fehler: $e';
          _isConnected = false;
        }),
      );
    } catch (e) {
      setState(() {
        _status = 'Verbindung fehlgeschlagen: $e';
        _isConnected = false;
      });
    }
  }

  Future<void> _handleMessage(dynamic message) async {
    final map = jsonDecode(message as String);

    switch (map['type']) {
      case 'send_piece':
        if ((map['instrument'] != null && map['instrument'] != widget.instrument) ||
            (map['voice'] != null && map['voice'] != widget.voice)) return;

        final bytes = base64Decode(map['data']);
        final file = await _saveBytesAsFile(bytes, map['name']);

        _received.add(ReceivedPiece(
          name: map['name'],
          path: file.path,
          receivedAt: DateTime.now(),
          active: true,
        ));

        if (mounted) {
          final route = MaterialPageRoute(
            builder: (_) => PdfViewerScreen(filePath: file.path, title: map['name']),
          );
          _currentPdfRoute = route;
          _navigatorKey.currentState?.push(route);
        }

        _showSnackBar('Neue Noten: ${map['name']}');
        setState(() {});
        break;

      case 'end_piece':
        for (var piece in _received) {
          if (piece.name.startsWith(map['name'])) piece.active = false;
        }

        if (_currentPdfRoute != null) {
          _navigatorKey.currentState?.removeRoute(_currentPdfRoute!);
          _currentPdfRoute = null;
        }

        _showSnackBar('Stück beendet: ${map['name']}');
        setState(() {});
        break;

      case 'status':
        setState(() => _status = map['text']);
        break;

      case 'error':
        _showSnackBar('Server-Fehler: ${map['message']}');
        setState(() => _status = 'Server-Fehler: ${map['message']}');
        break;

      default:
        debugPrint('Unbekannter Nachrichtentyp: ${map['type']}');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<File> _saveBytesAsFile(Uint8List bytes, String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    final activePieces = _received.where((p) => p.active).toList();

    return MaterialApp(
      navigatorKey: _navigatorKey,
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          title: const Text('Marschpad – Musiker'),
          centerTitle: true,
          backgroundColor: const Color(0xFF0D47A1),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _InfoHeader(
                instrument: widget.instrument,
                voice: widget.voice,
                status: _status,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: activePieces.isEmpty
                    ? const Center(
                        child: Text(
                          'Keine aktiven Noten',
                          style: TextStyle(fontSize: 18, color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: activePieces.length,
                        itemBuilder: (_, i) {
                          final p = activePieces[i];
                          return Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              leading: const Icon(Icons.picture_as_pdf,
                                  size: 36, color: Colors.red),
                              title: Text(p.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                  'Empfangen: ${p.receivedAt.toLocal().toString().split('.')[0]}'),
                              trailing: const Icon(Icons.open_in_new),
                              onTap: () {
                                final route = MaterialPageRoute(
                                  builder: (_) =>
                                      PdfViewerScreen(filePath: p.path, title: p.name),
                                );
                                _currentPdfRoute = route;
                                _navigatorKey.currentState?.push(route);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ===================== UI COMPONENT ===================== */
class _InfoHeader extends StatelessWidget {
  final String instrument;
  final String voice;
  final String status;

  const _InfoHeader({
    required this.instrument,
    required this.voice,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1565C0)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(instrument,
              style: const TextStyle(
                  fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
          Text(voice,
              style: const TextStyle(fontSize: 18, color: Colors.white70)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(status,
                style: const TextStyle(
                    fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/* ===================== MODELS ===================== */
class ReceivedPiece {
  final String name;
  final String path;
  final DateTime receivedAt;
  bool active;

  ReceivedPiece({
    required this.name,
    required this.path,
    required this.receivedAt,
    this.active = true,
  });
}

class PdfViewerScreen extends StatelessWidget {
  final String filePath;
  final String title;

  const PdfViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SfPdfViewer.file(File(filePath)),
    );
  }
}
