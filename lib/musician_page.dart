import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/update_info.dart';
import '../services/nextcloud_service.dart';
import '../services/local_session_discovery.dart';
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
  static const _localNetworkChannel = MethodChannel('marschpad/local_network');
  final NextcloudService _nextcloudService = NextcloudService();
  final LocalSessionDiscovery _localDiscovery = LocalSessionDiscovery();
  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _cloudProbeTimer;
  final Duration _pingInterval = const Duration(seconds: 10);

  final List<ReceivedPiece> _received = [];
  String _status = 'Verbindung wird aufgebaut…';
  late final String _clientId;
  late String _instrument;
  late String _voice;
  late bool _darkMode;
  bool _updateDialogShown = false;
  bool _connecting = false;
  bool _offlineFallbackEnabled = false;
  bool _usingLocalSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _instrument = widget.instrument;
    _voice = widget.voice;
    _darkMode = widget.darkMode;
    _clientId = const Uuid().v4();
    _loadOfflineFallback();
    _connect();
  }

  Future<void> _loadOfflineFallback() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || !(prefs.getBool('offlineBackupEnabled') ?? false)) return;
    setState(() => _offlineFallbackEnabled = true);
    await _startLocalDiscovery();
    await _syncOfflineScores();
  }

  Future<void> _toggleOfflineFallback() async {
    final enabled = !_offlineFallbackEnabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('offlineBackupEnabled', enabled);
    if (!mounted) return;
    setState(() => _offlineFallbackEnabled = enabled);
    if (enabled) {
      await _startLocalDiscovery();
      if (mounted) {
        _showSnackBar(
          'Offline-Fallback aktiv. Verbinde dieses Handy mit dem '
          'Hotspot des Dirigenten.',
        );
      }
      unawaited(_syncOfflineScores(showFeedback: true));

      return;
    }

    await _localDiscovery.stop();
    _cloudProbeTimer?.cancel();
    if (_usingLocalSession) {
      final localChannel = _channel;
      _channel = null;
      _usingLocalSession = false;
      await localChannel?.sink.close();
      if (mounted) setState(() => _status = 'Verbinde…');
      _connect();
    }
    if (mounted) _showSnackBar('Offline-Fallback ausgeschaltet.');
  }

  Future<void> _openWifiSettings() async {
    try {
      await _localNetworkChannel.invokeMethod<void>('openWifiSettings');
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showSnackBar(
        'WLAN-Einstellungen konnten nicht geöffnet werden: ${error.message}',
      );
    }
  }

  Future<void> _connectToLocalServerManually() async {
    if (!_offlineFallbackEnabled || !mounted) {
      _showSnackBar('Aktiviere zuerst den Offline-Fallback.');
      return;
    }
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lokalen Dirigenten verbinden'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'IP-Adresse',
            hintText: '192.168.43.1',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Verbinden'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || !mounted) return;

    final value = input.trim();
    final uri = Uri.tryParse(
      value.contains('://')
          ? value
          : 'ws://$value${value.contains(':') ? '' : ':8765'}',
    );
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'ws' && uri.scheme != 'wss')) {
      _showSnackBar('Bitte eine gültige IP-Adresse eingeben.');
      return;
    }

    final previousChannel = _channel;
    _channel = null;
    _usingLocalSession = false;
    await previousChannel?.sink.close();
    if (mounted) _connectLocal(uri);
  }

  Future<void> _startLocalDiscovery() async {
    try {
      await _localDiscovery.start((host) {
        if (_offlineFallbackEnabled && _channel == null) {
          _connectLocal(host);
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _offlineFallbackEnabled = false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('offlineBackupEnabled', false);
      _showSnackBar('Lokale Suche konnte nicht gestartet werden: $error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _cloudProbeTimer?.cancel();
    _localDiscovery.stop();
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
      await channel.ready.timeout(const Duration(seconds: 8));
      if (!mounted) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _usingLocalSession = false;
      _register(channel);
      _listen(channel);
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

  void _register(WebSocketChannel channel) {
    channel.sink.add(jsonEncode({
      'type': 'register',
      'clientId': _clientId,
      'role': 'musician',
      'app': AppConfig.appId,
      'instrument': _instrument,
      'voice': _voice,
    }));
  }

  void _listen(WebSocketChannel channel) {
    channel.stream.listen(
      (message) => _handleMessage(message, channel),
      onDone: () => _onDisconnected(channel),
      onError: (error) => _onError(channel, error),
    );
  }

  Future<void> _connectLocal(Uri host) async {
    if (_connecting || _channel != null || !mounted) return;
    _connecting = true;
    WebSocketChannel? channel;
    try {
      channel = IOWebSocketChannel.connect(host);
      await channel.ready.timeout(const Duration(seconds: 4));
      if (!mounted || !_offlineFallbackEnabled || _channel != null) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _usingLocalSession = true;
      _register(channel);
      _listen(channel);
      _startPing();
      _cloudProbeTimer?.cancel();
      _cloudProbeTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _probeCloudConnection(),
      );
      setState(() => _status = 'Lokal verbunden');
      _showSnackBar(
          'Server nicht erreichbar – lokal mit dem Dirigenten verbunden.');
    } catch (error) {
      await channel?.sink.close();
      debugPrint('Lokale Verbindung fehlgeschlagen: $error');
    } finally {
      _connecting = false;
    }
  }

  Future<void> _probeCloudConnection() async {
    if (!mounted || !_usingLocalSession || _connecting) return;
    WebSocketChannel? cloudChannel;
    try {
      final uri = Uri.parse('wss://ws.notenserver.duckdns.org');
      cloudChannel = kIsWeb
          ? WebSocketChannel.connect(uri)
          : IOWebSocketChannel.connect(uri.toString());
      await cloudChannel.ready.timeout(const Duration(seconds: 5));
      if (!mounted || !_usingLocalSession) {
        await cloudChannel.sink.close();
        return;
      }
      final localChannel = _channel;
      _channel = cloudChannel;
      _usingLocalSession = false;
      _register(cloudChannel);
      _listen(cloudChannel);
      _cloudProbeTimer?.cancel();
      _cloudProbeTimer = null;
      _startPing();
      await localChannel?.sink.close();
      setState(() => _status = 'Verbunden');
      _showSnackBar(
          'Internetverbindung wiederhergestellt – zurück zum Server.');
    } catch (_) {
      await cloudChannel?.sink.close();
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

  void _onDisconnected(WebSocketChannel channel) {
    if (!identical(_channel, channel)) return;
    debugPrint('[WS] Verbindung getrennt');
    _pingTimer?.cancel();
    _channel = null;
    _usingLocalSession = false;
    _cloudProbeTimer?.cancel();
    _cloudProbeTimer = null;
    if (!mounted) return;
    setState(() => _status = 'Getrennt');
    _scheduleReconnect();
  }

  void _onError(WebSocketChannel channel, dynamic e) {
    if (!identical(_channel, channel)) return;
    debugPrint('[WS] Fehler: $e');
    _pingTimer?.cancel();
    _channel = null;
    _usingLocalSession = false;
    _cloudProbeTimer?.cancel();
    _cloudProbeTimer = null;
    if (!mounted) return;
    setState(() => _status = 'Fehler');
    _scheduleReconnect();
  }

  // =========================
  // WEBSOCKET MESSAGE HANDLER
  // =========================
  Future<void> _handleMessage(
    dynamic message,
    WebSocketChannel sourceChannel,
  ) async {
    final map = jsonDecode(message as String);

    switch (map['type']) {
      case 'ping':
        sourceChannel.sink.add(jsonEncode({'type': 'pong'}));
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
          _showSnackBar(
            'Noten für ${map['name']} ($_instrument, Stimme $_voice) '
            'konnten nicht geladen werden. Synchronisiere die Offline-Noten '
            'und prüfe den Dateinamen auf dem Notenserver.',
          );
        }
        break;

      case 'end_piece_signal':
        final ended =
            _received.where((p) => p.name == map['name'] && p.active).toList();

        for (final p in ended) {
          p.active = false;
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
        if (mounted && map['text'] is String) {
          setState(() => _status = map['text'] as String);
        }
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
              tooltip: _offlineFallbackEnabled
                  ? 'Offline-Fallback ausschalten'
                  : 'Offline-Fallback einschalten',
              onPressed: _toggleOfflineFallback,
              icon: Icon(
                _offlineFallbackEnabled
                    ? Icons.wifi_tethering_rounded
                    : Icons.wifi_tethering_off_rounded,
              ),
            ),
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
              Card(
                margin: const EdgeInsets.fromLTRB(20, -10, 20, 14),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _offlineFallbackEnabled,
                      onChanged: (_) => _toggleOfflineFallback(),
                      secondary: IconButton(
                        tooltip: 'WLAN-Einstellungen öffnen',
                        onPressed: _openWifiSettings,
                        icon: const Icon(Icons.wifi_tethering_rounded),
                      ),
                      title: const Text('Automatisch lokal verbinden'),
                      subtitle: Text(
                        _usingLocalSession
                            ? 'Mit dem Dirigenten-Hotspot verbunden'
                            : 'Hotspot verbinden; schaltet bei Serverausfall lokal um',
                      ),
                    ),
                    if (_offlineFallbackEnabled)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _connectToLocalServerManually,
                          icon: const Icon(Icons.link_rounded),
                          label: const Text('IP manuell eingeben'),
                        ),
                      ),
                  ],
                ),
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
    if (changedConnection && _offlineFallbackEnabled) {
      await _syncOfflineScores();
    }
  }

  Future<void> _syncOfflineScores({bool showFeedback = false}) async {
    try {
      final files = await _nextcloudService.listAndDownloadPdfs(
        _instrument,
        _voice,
      );
      if (!showFeedback || !mounted) return;
      if (files.isEmpty) {
        _showSnackBar(
          'Keine Noten für $_instrument, Stimme $_voice auf dem Notenserver. '
          'Die Dateinamen müssen auf _${_instrument}_$_voice.pdf enden.',
        );
      } else {
        _showSnackBar(
          '${files.length} passende Noten für $_instrument, Stimme $_voice '
          'sind offline verfügbar.',
        );
      }
    } catch (error) {
      debugPrint('Offline-Noten konnten nicht synchronisiert werden: $error');
      if (showFeedback && mounted) {
        _showSnackBar(
          'Noten konnten nicht synchronisiert werden. Verbinde dich mit dem '
          'Notenserver und versuche es erneut.',
        );
      }
    }
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
    final connected = status.toLowerCase().contains('verbunden');
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
