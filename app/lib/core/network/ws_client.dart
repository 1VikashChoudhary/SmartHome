import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'network_utils.dart';

class DeviceWebSocketClient {
  final String ip;
  final void Function(Map<String, dynamic> data) onData;
  final void Function(bool isConnected) onConnectionChange;
  final void Function()? onAuthError;
  final String? authPassword;
  final String? authUsername;
  final int statusIntervalSeconds;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _isDisposed = false;
  bool _isConnected = false;
  bool _authFailed = false;

  DeviceWebSocketClient({
    required this.ip,
    required this.onData,
    required this.onConnectionChange,
    this.onAuthError,
    this.authPassword,
    this.authUsername,
    this.statusIntervalSeconds = 10,
  });

  void connect() {
    if (_isDisposed || _authFailed) return;
    _disconnectInternal();

    try {
      final cleanHost = sanitizeHost(ip);
      final hasAuth = authPassword != null && authPassword!.isNotEmpty;
      final user = (authUsername != null && authUsername!.trim().isNotEmpty)
          ? authUsername!.trim()
          : 'admin';
      final endpoint = Uri.parse('ws://$cleanHost');
      // Uri encodes reserved characters in user/password safely. Constructing
      // a ws URL with string interpolation breaks credentials such as `@`.
      final uri = endpoint.replace(
        userInfo: hasAuth ? '$user:${authPassword!}' : '',
        path: '/ws',
      );
      _channel = WebSocketChannel.connect(uri);

      final subscribePayload = jsonEncode({
        'type': 'subscribe',
        'stream': 'status',
        'interval_ms': statusIntervalSeconds.clamp(5, 60) * 1000,
        if (hasAuth) 'user': user,
        if (hasAuth) 'pass': authPassword,
      });

      // The ESP does not stream status until an active screen explicitly asks
      // for it. Include credentials in the subscribe frame so WebSocketManager
      // can verify against WebServerManager's SHA-256 credentials.
      _channel!.sink.add(subscribePayload);
      _channel!.ready.then((_) {
        if (!_isDisposed && !_authFailed && _channel != null) {
          try {
            _channel!.sink.add(subscribePayload);
          } catch (_) {}
        }
      }).catchError((_) {});

      _subscription = _channel!.stream.listen(
        (message) {
          if (_isDisposed) return;
          try {
            final decoded = jsonDecode(message as String);
            if (decoded is Map) {
              final map = Map<String, dynamic>.from(decoded);
              if (map['type'] == 'auth_error') {
                _authFailed = true;
                if (_isConnected) {
                  _isConnected = false;
                  onConnectionChange(false);
                }
                _reconnectTimer?.cancel();
                _disconnectInternal();
                onAuthError?.call();
                return;
              }
              if (!_isConnected) {
                _isConnected = true;
                onConnectionChange(true);
              }
              onData(map);
            }
          } catch (_) {}
        },
        onDone: () => _handleDisconnect(),
        onError: (err) => _handleDisconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    if (_isConnected) {
      _isConnected = false;
      if (!_isDisposed) {
        onConnectionChange(false);
      }
    }
    _disconnectInternal();
    if (!_isDisposed && !_authFailed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(const Duration(seconds: 2), () => connect());
    }
  }

  void _disconnectInternal() {
    try {
      _channel?.sink.add(
        jsonEncode({'type': 'unsubscribe', 'stream': 'status'}),
      );
    } catch (_) {}
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _disconnectInternal();
  }
}
