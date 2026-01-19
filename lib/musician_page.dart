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

        try {
          final pdfName =
              '${map['name']}_${widget.instrument}_${widget.voice}.pdf';

          final file = await _nextcloudService.downloadPdf(pdfName);

          final piece = ReceivedPiece(
            name: map['name'],
            path: file.path,
            receivedAt: DateTime.now(),
            active: true,
          );

          _received
              .where((p) => p.name == map['name'])
              .forEach((p) => p.active = false);

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
        final ended =
            _received.where((p) => p.name == map['name'] && p.active).toList();

        for (final p in ended) {
          p.active = false;
          final file = File(p.path);
          if (await file.exists()) {
            await file.delete();
          }
        }

        if (mounted) {
          while (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _received.where((p) => p.active).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        title: const Text(
          'Marschpad-Musiker',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
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
                ? const _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: active.length,
                    itemBuilder: (_, i) {
                      final p = active[i];
                      return _PieceCard(piece: p);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/* ===================== HEADER ===================== */

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
    IconData icon;
    Color color;

    switch (status.toLowerCase()) {
      case 'verbunden':
        icon = Icons.wifi;
        color = Colors.green;
        break;
      case 'verbindung fehlgeschlagen':
        icon = Icons.wifi_off;
        color = Colors.red;
        break;
      default:
        icon = Icons.sync;
        color = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  instrument,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  voice,
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ===================== EMPTY STATE ===================== */

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.music_off, size: 64, color: Colors.black38),
          SizedBox(height: 16),
          Text(
            'Keine aktiven Noten',
            style: TextStyle(fontSize: 18, color: Colors.black54),
          ),
          SizedBox(height: 6),
          Text(
            'Warte auf das nächste Stück',
            style: TextStyle(color: Colors.black38),
          ),
        ],
      ),
    );
  }
}

/* ===================== PIECE CARD ===================== */

class _PieceCard extends StatelessWidget {
  final ReceivedPiece piece;

  const _PieceCard({required this.piece});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.picture_as_pdf, color: Colors.red),
        ),
        title: Text(
          piece.name,
          style:
              const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Empfangen: ${piece.receivedAt.toLocal().toString().split('.')[0]}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  PdfViewerScreen(filePath: piece.path, title: piece.name),
            ),
          );
        },
      ),
    );
  }
}

/* ===================== MODEL ===================== */

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

/* ===================== PDF VIEWER ===================== */

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
