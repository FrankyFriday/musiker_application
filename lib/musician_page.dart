import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/update_info.dart';
import '../services/nextcloud_service.dart';
import '../services/notification_service.dart';
import '../services/version_checker.dart';
import '../ui/update_dialog.dart';
import '../utils/logger.dart';
import '../theme/app_theme.dart';
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

class _MusicianPageState extends State<MusicianPage>
    with WidgetsBindingObserver {
  final NextcloudService _nextcloudService = NextcloudService();
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  final Duration _pingInterval = const Duration(seconds: 10);

  final List<ReceivedPiece> _received = [];
  String _status = 'Verbindung wird aufgebaut…';
  late final String _clientId;
  late String _instrument;
  late String _voice;
  late bool _darkMode;
  bool _updateDialogShown = false;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _instrument = widget.instrument;
    _voice = widget.voice;
    _darkMode = widget.darkMode;
    _clientId = const Uuid().v4();
    _connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconnectIfNeeded();
    }
  }

  void _reconnectIfNeeded() {
    if (!mounted || _connecting || _channel != null) return;
    _connect();
  }

  void _scheduleReconnect() {
    if (!mounted || _reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 2), _reconnectIfNeeded);
  }

  // =========================
  // WEBSOCKET CONNECT
  // =========================
  Future<void> _connect() async {
    if (_connecting || !mounted) return;
    _connecting = true;
    _channel?.sink.close();
    const domain = 'ws.notenserver.duckdns.org';

    try {
      final uri = Uri.parse('wss://$domain');
      final channel = kIsWeb
          ? WebSocketChannel.connect(uri)
          : IOWebSocketChannel.connect(uri.toString());
      _channel = channel;

      channel.sink.add(jsonEncode({
        'type': 'register',
        'clientId': _clientId,
        'role': 'musician',
        'app': AppConfig.appId,
        'instrument': _instrument,
        'voice': _voice,
      }));

      channel.stream.listen(
        _handleMessage,
        onDone: _onDisconnected,
        onError: _onError,
      );

      if (!mounted) return;
      setState(() => _status = 'Verbunden');
      _startPing();
    } catch (e) {
      _channel = null;
      if (!mounted) return;
      setState(() => _status = 'Verbindung fehlgeschlagen');
      debugPrint('WebSocket-Verbindungsfehler: $e');
      _scheduleReconnect();
    } finally {
      _connecting = false;
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
    _channel = null;
    if (!mounted) return;
    setState(() => _status = 'Getrennt');
    _scheduleReconnect();
  }

  void _onError(dynamic e) {
    debugPrint('[WS] Fehler: $e');
    _pingTimer?.cancel();
    _channel = null;
    if (!mounted) return;
    setState(() => _status = 'Fehler');
    _scheduleReconnect();
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

      case 'release_announce':
        await _handleReleaseAnnounce(map);
        return;

      case 'maintenance_status':
        final enabled = map['enabled'] == true;
        UpdateLogger.info('[WS] Wartungsmodus: $enabled');
        if (mounted && enabled) {
          _showSnackBar('Server-Wartungsmodus ist aktiv.');
        }
        return;

      case 'send_piece_signal':
        if (map['instrument'] != _instrument || map['voice'] != _voice) return;

        try {
          final pdfName = '${map['name']}_${_instrument}_$_voice.pdf';
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
                builder: (_) => PdfViewerScreen(
                    filePath: piece.path,
                    title: piece.name,
                    darkMode: _darkMode),
              ),
            );
          }

          _showSnackBar('Neue Noten: $piece.name');
          if (mounted) setState(() {});
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
          if (await file.exists()) await file.delete();
        }

        if (mounted) {
          while (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }

        _showSnackBar('Stück beendet: ${map['name']}');
        if (mounted) setState(() {});
        break;

      case 'status':
        if (mounted) setState(() => _status = map['text']);
        break;

      default:
        debugPrint('[WS] Unbekannter Nachrichtentyp: ${map['type']}');
    }
  }

  Future<void> _handleReleaseAnnounce(Map<String, dynamic> message) async {
    UpdateLogger.info('[UPDATE] release_announce empfangen');
    if (!AppConfig.matchesServerAppId(message['app'])) {
      UpdateLogger.warning('[UPDATE] Falsche App-ID: ${message['app']}');
      return;
    }

    final release = message['release'];
    if (release is! Map) {
      UpdateLogger.warning('[UPDATE] Release-Daten fehlen');
      return;
    }
    final releaseMap = Map<String, dynamic>.from(release);
    final serverVersion = releaseMap['version'] as String?;
    final apkUrl = releaseMap['apkUrl'] as String?;
    if (serverVersion == null || apkUrl == null) {
      UpdateLogger.warning('[UPDATE] Version oder APK-URL fehlt');
      return;
    }

    final currentVersion = (await PackageInfo.fromPlatform()).version;
    if (!VersionChecker.isNewerVersion(currentVersion, serverVersion) ||
        _updateDialogShown ||
        !mounted) {
      return;
    }

    _updateDialogShown = true;
    await notificationService.showUpdateAvailable(serverVersion);
    if (!mounted) return;
    try {
      await showDialog<bool>(
        context: context,
        builder: (_) => UpdateDialog(
          updateInfo: UpdateInfo(
            version: serverVersion,
            mandatory: false,
            notes: 'Neues Release verfügbar.',
            url: apkUrl,
          ),
        ),
      );
    } finally {
      _updateDialogShown = false;
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _received.where((p) => p.active).toList();
    final themeData = _darkMode ? AppTheme.dark : AppTheme.light;

    return Theme(
      data: themeData,
      child: Scaffold(
        appBar: AppBar(
          title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Marschpad'),
              Text(
                'MUSIKERPULT',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Offline-Noten',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OfflinePracticePage(
                    instrument: _instrument,
                    voice: _voice,
                    darkMode: _darkMode,
                  ),
                ),
              ),
              icon: const Icon(Icons.library_music_outlined),
            ),
            IconButton(
              tooltip: 'Einstellungen',
              onPressed: _openSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
            const SizedBox(width: 5),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InfoHeader(
                instrument: _instrument,
                voice: _voice,
                status: _status,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Auf deinem Pult',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        '${active.length}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: active.isEmpty
                    ? const _EmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: active.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, index) =>
                            _PieceCard(piece: active[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          instrument: _instrument,
          voice: _voice,
          darkMode: _darkMode,
        ),
      ),
    );
    if (result == null || !mounted) return;

    final instrument = result['instrument'] as String;
    final voice = result['voice'] as String;
    final darkMode = result['darkMode'] as bool;
    final changedConnection = instrument != _instrument || voice != _voice;
    setState(() {
      _instrument = instrument;
      _voice = voice;
      _darkMode = darkMode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('instrument', instrument);
    await prefs.setString('voice', voice);
    await prefs.setBool('darkMode', darkMode);
    widget.onSettingsChanged?.call({
      'instrument': instrument,
      'voice': voice,
      'darkMode': darkMode,
    });
    if (changedConnection) _connect();
  }
}

// =========================
// WIDGETS
// =========================
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
    final connected = status.toLowerCase() == 'verbunden';
    final statusColor = connected ? const Color(0xFF8DE3C0) : AppTheme.amber;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 5, 20, 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.midnight, Color(0xFF0B5961)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppTheme.midnight.withValues(alpha: 0.17),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.music_note_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(instrument,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    )),
                const SizedBox(height: 3),
                Text(
                  '$voice. Stimme · Musikverein Scharrel',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  connected ? 'Live' : 'Wartet',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Icon(Icons.music_off_rounded,
                size: 34, color: colors.secondary),
          ),
          const SizedBox(height: 18),
          Text(
            'Dein Pult ist bereit',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Text(
            'Sobald der Dirigent Noten sendet,\nerscheinen sie hier.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _PieceCard extends StatelessWidget {
  final ReceivedPiece piece;
  const _PieceCard({required this.piece});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfViewerScreen(
              filePath: piece.path,
              title: piece.name,
              darkMode: Theme.of(context).brightness == Brightness.dark,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFB43C4B).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.picture_as_pdf_rounded,
                    color: Color(0xFFB43C4B)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      piece.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Empfangen ${piece.receivedAt.toLocal().toString().substring(0, 16)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.open_in_new_rounded, color: colors.secondary),
            ],
          ),
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
  ReceivedPiece(
      {required this.name,
      required this.path,
      required this.receivedAt,
      this.active = true});
}

// =========================
// PDF VIEWER
// =========================
class PdfViewerScreen extends StatelessWidget {
  final String filePath;
  final String title;
  final bool darkMode;
  const PdfViewerScreen(
      {super.key,
      required this.filePath,
      required this.title,
      this.darkMode = false});

  @override
  Widget build(BuildContext context) {
    final theme = darkMode ? AppTheme.dark : AppTheme.light;
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: const [
            Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        body: SfPdfViewer.file(File(filePath)),
      ),
    );
  }
}
