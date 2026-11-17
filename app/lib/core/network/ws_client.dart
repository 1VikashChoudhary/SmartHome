import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:web_socket_channel/io.dart';
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
  HttpClient? _httpClient;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _connectTimeoutTimer;
  Timer? _watchdogTimer;
  bool _isDisposed = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  DateTime? _connectStartedAt;
  bool _authFailed = false;
  int _reconnectAttempts = 0;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isActivelyConnecting =>
      _isConnecting &&
      _connectStartedAt != null &&
      DateTime.now().difference(_connectStartedAt!).inMilliseconds < 5000;

  DeviceWebSocketClient({
    required this.ip,
    required this.onData,
    required this.onConnectionChange,
    this.onAuthError,
    this.authPassword,
    this.authUsername,
    this.statusIntervalSeconds = 10,
  });

  void reconnectNow() {
    if (_isDisposed) return;
    _authFailed = false;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    connect();
  }

  void connect() {
    if (_isDisposed || _authFailed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _disconnectInternal();
    _isConnecting = true;
    _connectStartedAt = DateTime.now();

    try {
      final cleanHost = sanitizeHost(ip);
      final hasAuth = authPassword != null && authPassword!.isNotEmpty;
      final user = (authUsername != null && authUsername!.trim().isNotEmpty)
          ? authUsername!.trim()
          : 'admin';
      final hasPasswordlessUser =
          !hasAuth && user.toLowerCase() != 'admin';
      final includeAuth = hasAuth || hasPasswordlessUser;
      final uri = Uri.parse('ws://$cleanHost').replace(path: '/ws');
      if (HttpOverrides.current?.runtimeType.toString() ==
          '_MockHttpOverrides') {
        _handleDisconnect();
        return;
      }
      final httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4)
        ..idleTimeout = Duration.zero;
      _httpClient = httpClient;
      final channel = IOWebSocketChannel.connect(
        uri,
        pingInterval: const Duration(seconds: 5),
        customClient: httpClient,
      );
      _channel = channel;

      // Abort hung TCP SYN / WebSocket handshakes quickly after an AP handoff
      // instead of waiting 60-120s for an OS socket timeout.
      _connectTimeoutTimer = Timer(const Duration(seconds: 5), () {
        if (!_isDisposed && !_isConnected && identical(_channel, channel)) {
          _handleDisconnect();
        }
      });

      final subscribePayload = jsonEncode({
        'type': 'subscribe',
        'stream': 'status',
        'interval_ms': statusIntervalSeconds.clamp(5, 60) * 1000,
        if (includeAuth) 'user': user,
        if (includeAuth) 'pass': authPassword ?? '',
      });

      // The ESP does not stream status until an active screen explicitly asks
      // for it. Send once after handshake completion to avoid duplicate frames.
      channel.ready.then((_) {
        if (!_isDisposed && !_authFailed && identical(_channel, channel)) {
          _isConnecting = false;
          _connectStartedAt = null;
          _connectTimeoutTimer?.cancel();
          _connectTimeoutTimer = null;
          try {
            channel.sink.add(subscribePayload);
          } catch (_) {}
          _resetWatchdog();
        }
      }).catchError((_) {
        if (!_isDisposed && identical(_channel, channel)) {
          _handleDisconnect();
        }
      });

      _subscription = channel.stream.listen(
        (message) {
          if (_isDisposed || !identical(_channel, channel)) return;
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
              _isConnecting = false;
              _connectStartedAt = null;
              _connectTimeoutTimer?.cancel();
              _connectTimeoutTimer = null;
              _reconnectAttempts = 0;
              if (!_isConnected) {
                _isConnected = true;
                onConnectionChange(true);
              }
              _resetWatchdog();
              onData(map);
            }
          } catch (_) {}
        },
        onDone: () {
          if (identical(_channel, channel)) {
            _handleDisconnect();
          }
        },
        onError: (err) {
          if (identical(_channel, channel)) {
            _handleDisconnect();
          }
        },
        cancelOnError: true,
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _resetWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    if (_isDisposed || _authFailed) return;
    final watchdogSec = math.max(12, statusIntervalSeconds + 6);
    _watchdogTimer = Timer(Duration(seconds: watchdogSec), () {
      if (!_isDisposed) {
        _handleDisconnect();
      }
    });
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
      final delaySec = math.min(12, 2 * (1 << _reconnectAttempts.clamp(0, 3)));
      _reconnectAttempts++;
      _reconnectTimer = Timer(Duration(seconds: delaySec), () => connect());
    }
  }

  void _disconnectInternal() {
    final wasConnected = _isConnected;
    _isConnected = false;
    _isConnecting = false;
    _connectStartedAt = null;
    if (wasConnected && !_isDisposed) {
      onConnectionChange(false);
    }
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    try {
      _channel?.sink.add(
        jsonEncode({'type': 'unsubscribe', 'stream': 'status'}),
      );
    } catch (_) {}
    _subscription?.cancel();
    _subscription = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    try {
      _httpClient?.close(force: false);
    } catch (_) {}
    _httpClient = null;
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _disconnectInternal();
  }
}
