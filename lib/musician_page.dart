import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../services/nextcloud_service.dart';
import 'offline_practice_page.dart';
import 'settings_page.dart';

// =========================
// MUSICIAN PAGE
// =========================
class MusicianPage extends StatefulWidget {
  final String instrument;
  final String voice;
  final bool darkMode;
  final Function(Map<String, dynamic>)? onSettingsChanged;

  const MusicianPage({
    super.key,
    required this.instrument,
    required this.voice,
    this.darkMode = false,
    this.onSettingsChanged,
  });

  @override
  State<MusicianPage> createState() => _MusicianPageState();
}

class _MusicianPageState extends State<MusicianPage> {
  final NextcloudService _nextcloudService = NextcloudService();
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  final Duration _pingInterval = const Duration(seconds: 10);

  final List<ReceivedPiece> _received = [];
  String _status = 'Verbindung wird aufgebaut…';
  late final String _clientId;
  late String _instrument;
  late String _voice;
  late bool _darkMode;

  @override
  void initState() {
    super.initState();
    _instrument = widget.instrument;
    _voice = widget.voice;
    _darkMode = widget.darkMode;
    _clientId = const Uuid().v4();
    _connect();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  // =========================
  // WEBSOCKET CONNECT
  // =========================
  Future<void> _connect() async {
    _channel?.sink.close();
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
        'instrument': _instrument,
        'voice': _voice,
      }));

      _channel!.stream.listen(
        _handleMessage,
        onDone: _onDisconnected,
        onError: _onError,
      );

      setState(() => _status = 'Verbunden');
      _startPing();
    } catch (e) {
      setState(() => _status = 'Verbindung fehlgeschlagen');
      debugPrint('WebSocket-Verbindungsfehler: $e');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_channel != null) {
        try {
          _channel!.sink.add(jsonEncode({'type': 'ping'}));
        } catch (e) {
          debugPrint('[PING] Fehler beim Senden: $e');
        }
      }
    });
  }

  void _onDisconnected() {
    debugPrint('[WS] Verbindung getrennt');
    _pingTimer?.cancel();
    setState(() => _status = 'Getrennt');
  }

  void _onError(dynamic e) {
    debugPrint('[WS] Fehler: $e');
    _pingTimer?.cancel();
    setState(() => _status = 'Fehler');
  }

  // =========================
  // WEBSOCKET MESSAGE HANDLER
  // =========================
  Future<void> _handleMessage(dynamic message) async {
    final map = jsonDecode(message as String);

    switch (map['type']) {
      case 'ping':
        _channel?.sink.add(jsonEncode({'type': 'pong'}));
        return;

      case 'pong':
        return;

      case 'send_piece_signal':
        if (map['instrument'] != _instrument || map['voice'] != _voice) return;

        try {
          final pdfName = '${map['name']}_${_instrument}_${_voice}.pdf';
          final file = await _nextcloudService.downloadPdf(pdfName);

          final piece = ReceivedPiece(
            name: map['name'],
            path: file.path,
            receivedAt: DateTime.now(),
            active: true,
          );

          _received.where((p) => p.name == map['name']).forEach((p) => p.active = false);
          _received.add(piece);

          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PdfViewerScreen(
                    filePath: piece.path, title: piece.name, darkMode: _darkMode),
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
        final ended = _received.where((p) => p.name == map['name'] && p.active).toList();

        for (final p in ended) {
          p.active = false;
          final file = File(p.path);
          if (await file.exists()) await file.delete();
        }

        if (mounted) {
          while (Navigator.of(context).canPop()) Navigator.of(context).pop();
        }

        _showSnackBar('Stück beendet: ${map['name']}');
        setState(() {});
        break;

      case 'status':
        setState(() => _status = map['text']);
        break;

      default:
        debugPrint('[WS] Unbekannter Nachrichtentyp: ${map['type']}');
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _received.where((p) => p.active).toList();
    final themeData = _darkMode ? ThemeData.dark() : ThemeData.light();
    final bgColor = _darkMode ? Colors.grey[900]! : const Color(0xFFF7F8FC);
    final appBarColor = _darkMode ? Colors.grey[850]! : Colors.blue.shade900;

    return Theme(
      data: themeData,
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: appBarColor,
          foregroundColor: Colors.white,
          title: const Text('Marschpad-Musiker', style: TextStyle(fontWeight: FontWeight.w600)),
          centerTitle: true,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(color: appBarColor),
                child: const Text(
                  'Menü',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.music_note),
                title: const Text('Offline üben'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OfflinePracticePage(
                        instrument: _instrument,
                        voice: _voice,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Einstellungen'),
                onTap: () async {
                  Navigator.of(context).pop();
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(
                        instrument: _instrument,
                        voice: _voice,
                      ),
                    ),
                  );
                  if (result != null && mounted) {
                    setState(() {
                      _instrument = result['instrument'];
                      _voice = result['voice'];
                      _darkMode = result['darkMode'] ?? _darkMode;
                    });

                    // Callback, um Dark Mode global zurückzugeben
                    if (widget.onSettingsChanged != null) {
                      widget.onSettingsChanged!({
                        'instrument': _instrument,
                        'voice': _voice,
                        'darkMode': _darkMode,
                      });
                    }

                    _connect();
                  }
                },
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            _InfoHeader(
                instrument: _instrument,
                voice: _voice,
                status: _status,
                darkMode: _darkMode),
            Expanded(
              child: active.isEmpty
                  ? _EmptyState(darkMode: _darkMode)
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: active.length,
                      itemBuilder: (_, i) => _PieceCard(piece: active[i], darkMode: _darkMode),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================
// WIDGETS
// =========================
class _InfoHeader extends StatelessWidget {
  final String instrument;
  final String voice;
  final String status;
  final bool darkMode;

  const _InfoHeader({required this.instrument, required this.voice, required this.status, required this.darkMode});

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

    final bgColor = darkMode ? Colors.grey[850] : Colors.white;

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(instrument,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: darkMode ? Colors.white : Colors.black)),
                Text(voice, style: TextStyle(color: darkMode ? Colors.white70 : Colors.black54)),
                const SizedBox(height: 6),
                Text(status, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool darkMode;
  const _EmptyState({this.darkMode = false});

  @override
  Widget build(BuildContext context) {
    final color = darkMode ? Colors.white38 : Colors.black38;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_off, size: 64, color: color),
          const SizedBox(height: 16),
          Text('Keine aktiven Noten', style: TextStyle(fontSize: 18, color: color)),
          const SizedBox(height: 6),
          Text('Warte auf das nächste Stück', style: TextStyle(color: color.withOpacity(0.7))),
        ],
      ),
    );
  }
}

class _PieceCard extends StatelessWidget {
  final ReceivedPiece piece;
  final bool darkMode;
  const _PieceCard({required this.piece, this.darkMode = false});

  @override
  Widget build(BuildContext context) {
    final bgColor = darkMode ? Colors.grey[800] : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0, 6))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.picture_as_pdf, color: Colors.red),
        ),
        title: Text(piece.name,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: darkMode ? Colors.white : Colors.black)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Empfangen: ${piece.receivedAt.toLocal().toString().split('.')[0]}',
              style: TextStyle(fontSize: 13, color: darkMode ? Colors.white70 : Colors.black54)),
        ),
        trailing: Icon(Icons.chevron_right, color: darkMode ? Colors.white70 : Colors.black45),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PdfViewerScreen(filePath: piece.path, title: piece.name, darkMode: darkMode)),
        ),
      ),
    );
  }
}

// =========================
// MODEL
// =========================
class ReceivedPiece {
  final String name;
  final String path;
  final DateTime receivedAt;
  bool active;
  ReceivedPiece({required this.name, required this.path, required this.receivedAt, this.active = true});
}

// =========================
// PDF VIEWER
// =========================
class PdfViewerScreen extends StatelessWidget {
  final String filePath;
  final String title;
  final bool darkMode;
  const PdfViewerScreen({super.key, required this.filePath, required this.title, this.darkMode = false});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: darkMode ? ThemeData.dark() : ThemeData.light(),
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SfPdfViewer.file(File(filePath)),
      ),
    );
  }
}
