import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalSessionDiscovery {
  static const int _discoveryPort = 8766;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;

  Future<void> start(void Function(Uri host) onHostFound) async {
    await stop();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      _discoveryPort,
      reuseAddress: true,
    );
    _socket = socket;
    _subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      try {
        final message = jsonDecode(utf8.decode(datagram.data));
        if (message is! Map<String, dynamic> ||
            message['type'] != 'marschpad_local_session') {
          return;
        }
        final host = message['host'];
        final port = message['port'];
        if (host is! String || port is! int) return;
        onHostFound(Uri(scheme: 'ws', host: host, port: port));
      } on FormatException {
        // Ignore unrelated datagrams on the discovery port.
      }
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }
}
