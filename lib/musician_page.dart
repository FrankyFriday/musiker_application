import 'dart:convert';
import 'dart:io';
import 'dart:async';
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
  final int conductorPort;

  const MusicianPage({
    super.key,
    required this.instrument,
    required this.voice,
    required this.conductorPort,
  });

  @override
  State<MusicianPage> createState() => _MusicianPageState();
}

class _MusicianPageState extends State<MusicianPage> {
  WebSocketChannel? _channel;
  final List<ReceivedPiece> _received = [];
  String _status = 'Suche Dirigenten…';
  late String _clientId;
  String? _localIp;
  bool _isLoading = true;
  RawDatagramSocket? _udpSocket;

  // NavigatorKey, um PDFs gezielt zu schließen
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  Route? _currentPdfRoute;

  @override
  void initState() {
    super.initState();
    _clientId = const Uuid().v4();
    _startDiscovery();
  }

  Future<String?> _getLocalIp() async {
    if (kIsWeb) return null;
    for (var iface in await NetworkInterface.list()) {
      for (var addr in iface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          return addr.address;
        }
      }
    }
    return null;
  }

  Future<void> _startDiscovery() async {
    setState(() {
      _isLoading = true;
      _status = 'Suche lokale IP…';
    });

    _localIp = await _getLocalIp();
    if (!mounted) return;

    setState(() {
      _status = _localIp != null
          ? 'Lokale IP: $_localIp – suche Dirigenten…'
          : 'Keine lokale IP gefunden';
    });

    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 4210);
      _udpSocket!.broadcastEnabled = true;

      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket!.receive();
          if (datagram == null) return;
          try {
            final msg = jsonDecode(String.fromCharCodes(datagram.data));
            if (msg['type'] == 'conductor_discovery') {
              _udpSocket!.close();
              _connectToConductor(msg['ip']);
            }
          } catch (_) {}
        }
      });
    } catch (e) {
      setState(() => _status = 'UDP Discovery fehlgeschlagen: $e');
    }

    setState(() => _isLoading = false);
  }

  Future<void> _connectToConductor(String ip) async {
    setState(() => _status = 'Verbinde mit Dirigent ($ip)…');

    try {
      final uri = "ws://$ip:${widget.conductorPort}";
      if (kIsWeb) {
        _channel = WebSocketChannel.connect(Uri.parse(uri));
      } else {
        _channel = IOWebSocketChannel(await WebSocket.connect(uri));
      }

      _channel!.sink.add(jsonEncode({
        'type': 'register',
        'clientId': _clientId,
        'instrument': widget.instrument,
        'voice': widget.voice,
      }));

      setState(() => _status = 'Verbunden mit Dirigent');

      _channel!.stream.listen(
        _handleMessage,
        onDone: () => setState(() => _status = 'Verbindung beendet'),
        onError: (e) => setState(() => _status = 'Fehler: $e'),
      );
    } catch (e) {
      setState(() => _status = 'Verbindung fehlgeschlagen: $e');
    }
  }

  Future<void> _handleMessage(dynamic message) async {
    final map = jsonDecode(message as String);

    if (map['type'] == 'send_piece') {
      if (map['instrument'] != null && map['instrument'] != widget.instrument) return;
      if (map['voice'] != null && map['voice'] != widget.voice) return;

      final bytes = base64Decode(map['data']);
      final file = await saveBytesAsFile(bytes, map['name']);

      setState(() {
        _received.add(ReceivedPiece(
          name: map['name'],
          path: file.path,
          receivedAt: DateTime.now(),
          active: true,
        ));
      });

      // PDF öffnen und Route speichern
      if (mounted) {
        final route = MaterialPageRoute(
          builder: (_) => PdfViewerScreen(filePath: file.path, title: map['name']),
        );
        _currentPdfRoute = route;
        _navigatorKey.currentState?.push(route);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Neue Noten: ${map['name']}')),
      );
    }

    if (map['type'] == 'end_piece') {
      setState(() {
        for (var piece in _received) {
          if (piece.name.startsWith(map['name'])) {
            piece.active = false;
          }
        }
      });

      // PDF Viewer schließen
      if (_currentPdfRoute != null) {
        _navigatorKey.currentState?.removeRoute(_currentPdfRoute!);
        _currentPdfRoute = null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stück beendet: ${map['name']}')),
      );
    }

    if (map['type'] == 'status') {
      setState(() => _status = map['text']);
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _udpSocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activePieces = _received.where((p) => p.active).toList();

    return MaterialApp(
      navigatorKey: _navigatorKey, // NavigatorKey setzen
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F6FA),
        appBar: AppBar(
          title: const Text('Marschpad – Musiker'),
          centerTitle: true,
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Column(
            children: [
              _InfoHeader(
                instrument: widget.instrument,
                voice: widget.voice,
                status: _status,
                ip: _localIp,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _startDiscovery,
                  icon: const Icon(Icons.wifi),
                  label: const Text('Neu verbinden'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
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
                                borderRadius: BorderRadius.circular(16)),
                            child: ListTile(
                              leading: const Icon(Icons.picture_as_pdf,
                                  size: 36, color: Colors.red),
                              title: Text(p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
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

/* ===================== UI COMPONENTS ===================== */
class _InfoHeader extends StatelessWidget {
  final String instrument;
  final String voice;
  final String status;
  final String? ip;

  const _InfoHeader({
    required this.instrument,
    required this.voice,
    required this.status,
    this.ip,
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
          if (ip != null)
            Text('IP: $ip',
                style: const TextStyle(fontSize: 14, color: Colors.white60)),
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

Future<File> saveBytesAsFile(Uint8List bytes, String filename) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  return file;
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
