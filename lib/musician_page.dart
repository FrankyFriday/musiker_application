import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../services/nextcloud_service.dart';

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
  final NextcloudService _nextcloudService = NextcloudService();
  WebSocketChannel? _channel;

  final List<ReceivedPiece> _received = [];
  String _status = 'Verbindung wird aufgebaut…';
  late final String _clientId;

  @override
  void initState() {
    super.initState();
    _clientId = const Uuid().v4();
    _connect();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _connect() async {
    const domain = 'ws.notenserver.duckdns.org';

    try {
      final uri = Uri.parse('wss://$domain');
      _channel = kIsWeb
          ? WebSocketChannel.connect(uri)
          : IOWebSocketChannel.connect(uri.toString());

      _channel!.sink.add(jsonEncode({
        'type': 'register',
        'clientId': _clientId,
        'role': 'musician',
        'instrument': widget.instrument,
        'voice': widget.voice,
      }));

      _channel!.stream.listen(_handleMessage);
      setState(() => _status = 'Verbunden');
    } catch (_) {
      setState(() => _status = 'Verbindung fehlgeschlagen');
    }
  }

  Future<void> _handleMessage(dynamic message) async {
    final map = jsonDecode(message as String);

    switch (map['type']) {
      case 'ping':
        _channel?.sink.add(jsonEncode({'type': 'pong'}));
        return;

      case 'send_piece_signal':
        if (map['instrument'] != widget.instrument ||
            map['voice'] != widget.voice) return;

        if (_received.any((p) => p.name == map['name'])) return;

        try {
          final pdfName =
              '${map['name']}_${widget.instrument}_${widget.voice}.pdf';

          final file = await _nextcloudService.downloadPdf(pdfName);

          final piece = ReceivedPiece(
            name: map['name'],
            path: file.path,
            receivedAt: DateTime.now(),
          );

          _received.add(piece);

          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    PdfViewerScreen(filePath: piece.path, title: piece.name),
              ),
            );
          }

          _showSnackBar('Neue Noten: ${piece.name}');
          setState(() {});
        } catch (e) {
          debugPrint('PDF-Download-Fehler: $e');
          _showSnackBar('Fehler beim Laden der Noten');
        }
        break;

      case 'end_piece_signal':
        final ended = _received.where((p) => p.name == map['name']).toList();

        for (final p in ended) {
          p.active = false;

          // 🧹 CACHE LÖSCHEN
          final file = File(p.path);
          if (await file.exists()) {
            await file.delete();
            debugPrint('🗑️ Cache gelöscht: ${file.path}');
          }
        }

        // 📄 PDF schließen
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }

        _showSnackBar('Stück beendet: ${map['name']}');
        setState(() {});
        break;

      case 'status':
        setState(() => _status = map['text']);
        break;
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final active = _received.where((p) => p.active).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Marschpad – Musiker'),
        backgroundColor: const Color(0xFF0D47A1),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _InfoHeader(
            instrument: widget.instrument,
            voice: widget.voice,
            status: _status,
          ),
          Expanded(
            child: active.isEmpty
                ? const Center(
                    child: Text(
                      'Keine aktiven Noten',
                      style: TextStyle(fontSize: 18, color: Colors.black54),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: active.length,
                    itemBuilder: (_, i) {
                      final p = active[i];
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: const Icon(Icons.picture_as_pdf,
                              color: Colors.red),
                          title: Text(p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              'Empfangen: ${p.receivedAt.toLocal().toString().split('.')[0]}'),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PdfViewerScreen(
                                  filePath: p.path,
                                  title: p.name,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/* ===================== UI ===================== */

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
        gradient:
            LinearGradient(colors: [Color(0xFF0D47A1), Color(0xFF1565C0)]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(instrument,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
          Text(voice,
              style: const TextStyle(fontSize: 18, color: Colors.white70)),
          const SizedBox(height: 12),
          Text(status,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
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
