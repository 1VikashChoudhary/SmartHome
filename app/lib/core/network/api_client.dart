import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import '../models/smart_device.dart';
import '../models/hardware_profile.dart';
import 'network_utils.dart';

/// The controller accepted or rejected an OTA upload.
///
/// This confirms the ESP32 finished [Update.end] successfully.  It does not
/// claim that the controller has subsequently rebooted into that image; use
/// [OtaStatus] for that second, separate verification step.
class FirmwareUploadResult {
  final bool accepted;
  final String message;

  const FirmwareUploadResult({required this.accepted, required this.message});
}

/// The small, stable part of `/api/ota/status` used to verify an OTA reboot.
class OtaStatus {
  final bool updating;
  final String firmwareVersion;
  final String firmwareBuild;
  final String firmwareMd5;

  const OtaStatus({
    required this.updating,
    required this.firmwareVersion,
    required this.firmwareBuild,
    this.firmwareMd5 = '',
  });

  factory OtaStatus.fromJson(Map<String, dynamic> json) => OtaStatus(
    updating: json['updating'] == true,
    firmwareVersion: json['fw_version']?.toString() ?? '',
    firmwareBuild: json['fw_date']?.toString() ?? '',
    firmwareMd5: json['fw_md5']?.toString() ?? '',
  );

  bool differsFrom(OtaStatus other) =>
      firmwareVersion != other.firmwareVersion ||
      firmwareBuild != other.firmwareBuild ||
      (firmwareMd5.isNotEmpty &&
          other.firmwareMd5.isNotEmpty &&
          firmwareMd5 != other.firmwareMd5);
}

class ApiClient {
  static final Map<String, String> _usernameByHost = {};
  static void Function(String host)? onUnauthorized;
  final Dio _dio;
  final String? defaultUsername;
  DateTime? _lastConnectionResetAt;

  ApiClient({this.defaultUsername})
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(milliseconds: 3500),
          receiveTimeout: const Duration(milliseconds: 4500),
          persistentConnection: false,
          headers: {'Accept': 'application/json', 'Connection': 'close'},
        ),
      ) {
    _configureHttpClientAdapter();
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final password =
              options.extra.remove('smarthome_auth_password') as String?;
          final requestedUser =
              options.extra.remove('smarthome_auth_username') as String?;
          final knownUser =
              _usernameByHost[_hostKey(options.uri.host, options.uri.port)];
          final user = (requestedUser != null && requestedUser.isNotEmpty)
              ? requestedUser
              : ((defaultUsername != null && defaultUsername!.trim().isNotEmpty)
                    ? defaultUsername!.trim()
                    : knownUser);
          final hasPassword = password != null && password.isNotEmpty;
          final hasCustomUser =
              user != null &&
              user.isNotEmpty &&
              user.toLowerCase() != 'admin';
          if (hasPassword || hasCustomUser) {
            final effectiveUser = (user != null && user.isNotEmpty)
                ? user
                : 'admin';
            options.headers['Authorization'] =
                'Basic ${base64Encode(utf8.encode('$effectiveUser:${password ?? ''}'))}';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          final skipReset =
              error.requestOptions.extra['smarthome_skip_connection_reset'] ==
              true;
          if (!skipReset &&
              (error.type == DioExceptionType.connectionError ||
                  error.type == DioExceptionType.connectionTimeout ||
                  error.type == DioExceptionType.receiveTimeout)) {
            final now = DateTime.now();
            if (_lastConnectionResetAt == null ||
                now.difference(_lastConnectionResetAt!).inSeconds >= 3) {
              _lastConnectionResetAt = now;
              // Discard stale pooled sockets after AP-bridge roaming so retries
              // open a fresh socket with updated ARP/L2 routing.
              resetConnections();
            }
          }
          final skipUnauthorized =
              error.requestOptions.extra['smarthome_skip_unauthorized'] == true;
          if (!skipUnauthorized && error.response?.statusCode == 401) {
            onUnauthorized?.call(error.requestOptions.uri.host);
          }
          handler.next(error);
        },
      ),
    );
  }

  void _configureHttpClientAdapter() {
    if (_dio.httpClientAdapter is IOHttpClientAdapter) {
      _dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpClient()
          ..connectionTimeout = const Duration(milliseconds: 3500)
          ..idleTimeout = Duration.zero
          ..maxConnectionsPerHost = 4,
      );
    }
  }

  /// Replaces the underlying [IOHttpClientAdapter] so subsequent requests never
  /// reuse stale OS sockets after an AP handoff, while closing idle sockets
  /// gracefully so concurrent requests for other controllers can finish.
  void resetConnections() {
    final current = _dio.httpClientAdapter;
    if (current is IOHttpClientAdapter) {
      _configureHttpClientAdapter();
      current.close(force: false);
    }
  }

  void dispose() {
    _dio.close(force: true);
  }

  static (String host, int port) _parseHostAndPort(String ipOrHost) {
    final host = sanitizeHost(ipOrHost);
    if (host.isEmpty) return ('', 80);
    final parsed = Uri.tryParse('http://$host');
    if (parsed != null && parsed.host.isNotEmpty) {
      final port = parsed.hasPort ? parsed.port : 80;
      return (parsed.host, port);
    }
    return (host, 80);
  }

  static void registerDeviceUsername(String ipOrHost, String? username) {
    final (host, port) = _parseHostAndPort(ipOrHost);
    if (host.isEmpty) return;
    _usernameByHost[_hostKey(
      host,
      port,
    )] = (username == null || username.trim().isEmpty)
        ? 'admin'
        : username.trim();
  }

  static void unregisterDevice(String ipOrHost) {
    final (host, port) = _parseHostAndPort(ipOrHost);
    if (host.isEmpty) return;
    _usernameByHost.remove(_hostKey(host, port));
  }

  @visibleForTesting
  static bool hasRegisteredUsername(String ipOrHost) {
    final (host, port) = _parseHostAndPort(ipOrHost);
    if (host.isEmpty) return false;
    return _usernameByHost.containsKey(_hostKey(host, port));
  }

  static String _hostKey(String host, int port) =>
      '${host.toLowerCase()}:$port';

  String _url(String ip, String path) => 'http://${sanitizeHost(ip)}$path';

  Options _authOptions(
    String? password, {
    String? username,
    Duration? timeout,
    bool skipUnauthorizedCallback = false,
  }) {
    final headers = <String, dynamic>{
      'Accept': 'application/json',
      'X-Requested-With': 'SmartHome',
      'Connection': 'close',
    };
    final extra = <String, dynamic>{};
    if (password != null && password.isNotEmpty) {
      extra['smarthome_auth_password'] = password;
    }
    if (username != null && username.trim().isNotEmpty) {
      extra['smarthome_auth_username'] = username.trim();
    } else if (defaultUsername != null && defaultUsername!.trim().isNotEmpty) {
      extra['smarthome_auth_username'] = defaultUsername!.trim();
    }
    if (skipUnauthorizedCallback) {
      extra['smarthome_skip_unauthorized'] = true;
    }
    return Options(
      headers: headers,
      receiveTimeout: timeout,
      persistentConnection: false,
      extra: extra.isEmpty ? null : extra,
    );
  }

  /// Fast discovery probe (unauthenticated)
  Future<SmartDevice?> probeDiscovery(
    String ip, {
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/discovery'),
        cancelToken: cancelToken,
        options: Options(
          connectTimeout: const Duration(milliseconds: 1800),
          receiveTimeout: const Duration(milliseconds: 2500),
          persistentConnection: false,
          headers: const {'Accept': 'application/json', 'Connection': 'close'},
          extra: {'smarthome_skip_connection_reset': true},
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          final isSmartHomePayload =
              map['service'] == 'smarthome' ||
              map.containsKey('device_id') ||
              (map.containsKey('mac') && map.containsKey('num_relays'));
          if (isSmartHomePayload) {
            return SmartDevice.fromDiscovery(map, sanitizeHost(ip));
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Full status fetch with explicit 401 unauthorized reporting
  Future<({Map<String, dynamic>? data, bool unauthorized})> fetchStatusDetailed(
    String ip, {
    String? password,
    String? username,
    bool skipUnauthorizedCallback = false,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/status'),
        options: _authOptions(
          password,
          username: username,
          skipUnauthorizedCallback: skipUnauthorizedCallback,
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map) {
          return (data: Map<String, dynamic>.from(data), unauthorized: false);
        }
      }
    } on DioException catch (e) {
      return (data: null, unauthorized: e.response?.statusCode == 401);
    } catch (_) {}
    return (data: null, unauthorized: false);
  }

  /// Full status fetch
  Future<Map<String, dynamic>?> fetchStatus(
    String ip, {
    String? password,
    String? username,
    bool skipUnauthorizedCallback = false,
  }) async {
    final res = await fetchStatusDetailed(
      ip,
      password: password,
      username: username,
      skipUnauthorizedCallback: skipUnauthorizedCallback,
    );
    return res.data;
  }

  /// Relay control: action = 'toggle', 'on', 'off'
  Future<bool> setRelay(
    String ip,
    int relayIndex,
    String action, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay'),
        data: {'id': relayIndex, 'action': action},
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Master Relay control: 'on', 'off'
  Future<bool> setAllRelays(
    String ip,
    String action, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay/all'),
        data: {'action': action},
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Start quick countdown timer
  Future<bool> startTimer(
    String ip,
    int relayIndex,
    String action,
    int durationSec, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay/timer'),
        data: {'id': relayIndex, 'action': action, 'duration': durationSec},
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Cancel active timer
  Future<bool> cancelTimer(
    String ip,
    int relayIndex, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay/timer'),
        data: {'id': relayIndex, 'action': 'cancel'},
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch Automation Rules
  Future<List<Map<String, dynamic>>?> fetchRules(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/rules'),
        options: _authOptions(password, username: username),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is List) {
          return data.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Save / Update Automation Rule
  Future<bool> saveRule(
    String ip,
    Map<String, dynamic> ruleData, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/rule'),
        data: ruleData,
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Toggle Automation Rule Enabled State
  Future<bool> setRuleEnabled(
    String ip,
    int ruleId,
    bool enabled, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/rule'),
        data: {'id': ruleId, 'en': enabled},
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Delete Automation Rule
  Future<bool> deleteRule(
    String ip,
    int ruleId, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/rule'),
        data: {'id': ruleId, 'delete': true},
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Upload an application or filesystem image using the same multipart contract as `/update`.
  ///
  /// A successful result only means the ESP32 validated and committed the
  /// inactive OTA partition or LittleFS slot. Call [fetchOtaStatus] after the scheduled reboot
  /// before presenting the update as verified.
  Future<FirmwareUploadResult> uploadFirmware(
    String ip,
    List<int> fileBytes,
    String filename, {
    void Function(int sent, int total)? onProgress,
    String? password,
    String? username,
    bool isFilesystem = false,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: filename),
      });

      final opts = _authOptions(
        password,
        username: username,
        timeout: const Duration(minutes: 2),
      );
      opts.sendTimeout = const Duration(minutes: 2);
      final typeParam = isFilesystem ? 'fs' : 'firmware';
      final res = await _dio.post(
        _url(ip, '/api/ota/upload?type=$typeParam'),
        data: formData,
        options: opts,
        onSendProgress: onProgress,
      );
      final message = _responseMessage(
        res.data,
        'Controller did not confirm the firmware write.',
      );
      return FirmwareUploadResult(
        accepted: res.statusCode == 200,
        message: message,
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final fallback = status == null
          ? 'Connection lost before the controller confirmed the flash.'
          : 'OTA upload failed (HTTP $status).';
      return FirmwareUploadResult(
        accepted: false,
        message: _responseMessage(error.response?.data, fallback),
      );
    } catch (_) {
      return const FirmwareUploadResult(
        accepted: false,
        message: 'The OTA upload could not be started.',
      );
    }
  }

  /// Reads the controller's post-reboot firmware identity without using a
  /// cached response. A null value means that the controller has not yet
  /// returned (or cannot be reached/authenticated), never a successful update.
  Future<OtaStatus?> fetchOtaStatus(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final res = await _dio.get(
        _url(ip, '/api/ota/status?_=$nonce'),
        options: _authOptions(
          password,
          username: username,
          timeout: const Duration(seconds: 4),
        ),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map) {
          return OtaStatus.fromJson(Map<String, dynamic>.from(data));
        }
      }
    } catch (_) {}
    return null;
  }

  static String _responseMessage(dynamic data, String fallback) {
    try {
      dynamic decoded = data;
      if (decoded is String) decoded = jsonDecode(decoded);
      if (decoded is Map) {
        final message = decoded['message'] ?? decoded['error'];
        if (message != null && message.toString().trim().isNotEmpty) {
          return message.toString();
        }
      }
    } catch (_) {
      // An invalid error body must not hide the useful fallback message.
    }
    return fallback;
  }

  /// Reboot device
  Future<bool> reboot(String ip, {String? password, String? username}) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/reboot'),
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch Scheduled Alarms / Timers
  Future<List<Map<String, dynamic>>?> fetchAlarms(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/alarms'),
        options: _authOptions(password, username: username),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is List) {
          return data.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Save or update alarm schedule
  Future<bool> saveAlarm(
    String ip,
    Map<String, dynamic> alarmData, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/alarm'),
        data: alarmData,
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Toggle alarm enabled state
  Future<bool> setAlarmEnabled(
    String ip,
    int alarmId,
    bool enabled, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/alarm'),
        data: {'id': alarmId, 'en': enabled},
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Delete alarm schedule
  Future<bool> deleteAlarm(
    String ip,
    int alarmId, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/alarm'),
        data: {'id': alarmId, 'delete': true},
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch System Event Logs
  Future<List<Map<String, dynamic>>?> fetchLogs(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/logs'),
        options: _authOptions(password, username: username),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map<String, dynamic> && data['logs'] is List) {
          return (data['logs'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
        } else if (data is List) {
          return data.map((e) => e as Map<String, dynamic>).toList();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Clear System Event Logs
  Future<bool> clearLogs(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/logs/clear'),
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch System Diagnostics & Hardware Health
  Future<Map<String, dynamic>?> fetchDiagnostics(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/diagnostics'),
        options: _authOptions(password, username: username),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map<String, dynamic>) return data;
      }
    } catch (_) {}
    return null;
  }

  /// Fetch Relays full configuration
  Future<List<Map<String, dynamic>>?> fetchRelays(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/relays'),
        options: _authOptions(password, username: username),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetch complete system & hardware configuration (LCD, Sensor, MQTT, Buzzer)
  Future<Map<String, dynamic>?> fetchConfig(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/config'),
        options: _authOptions(password, username: username),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map) {
          return Map<String, dynamic>.from(data);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Save core system & network configuration
  Future<bool> saveDeviceConfig(
    String ip,
    Map<String, dynamic> configData, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/config'),
        data: configData,
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Save Wi-Fi credentials. The controller intentionally reconnects after a
  /// successful call, so callers must treat the current IP as transient.
  Future<bool> saveWifiConfig(
    String ip,
    String ssid,
    String password, {
    String? authPassword,
    String? authUsername,
    String? deviceName,
    bool? webAuth,
    String? webUser,
    String? webPass,
  }) async {
    try {
      final payload = <String, dynamic>{'ssid': ssid, 'pass': password};
      if (deviceName != null && deviceName.trim().isNotEmpty) {
        payload['device_name'] = deviceName.trim();
      }
      if (webAuth != null) payload['web_auth'] = webAuth;
      if (webUser != null && webUser.trim().isNotEmpty) {
        payload['web_user'] = webUser.trim();
      }
      if (webPass != null && webPass.isNotEmpty) {
        payload['web_pass'] = webPass;
      }
      final res = await _dio.post(
        _url(ip, '/api/config/wifi'),
        data: payload,
        options: _authOptions(authPassword, username: authUsername),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Scan nearby 2.4 GHz Wi-Fi networks from the ESP32 (/api/wifi/scan).
  /// Automatically polls until the async scan completes.
  Future<List<Map<String, dynamic>>?> scanWifiNetworks(
    String ip, {
    bool forceRefresh = false,
    String? authPassword,
    String? authUsername,
  }) async {
    for (int attempt = 0; attempt < 6; attempt++) {
      try {
        final query = (forceRefresh && attempt == 0) ? '?refresh=1' : '';
        final res = await _dio.get(
          _url(ip, '/api/wifi/scan$query'),
          options: _authOptions(
            authPassword,
            username: authUsername,
            timeout: const Duration(seconds: 5),
          ),
        );
        if (res.statusCode == 200 && res.data != null) {
          dynamic data = res.data;
          if (data is String) data = jsonDecode(data);
          if (data is Map) {
            final scanning = data['scanning'] == true;
            if (scanning) {
              if (attempt < 5) {
                await Future.delayed(const Duration(milliseconds: 1400));
              }
              continue;
            }
            final rawNets = data['networks'];
            if (rawNets is List) {
              final list = rawNets
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList();
              list.sort(
                (a, b) => ((b['rssi'] as num?)?.toInt() ?? -100).compareTo(
                  (a['rssi'] as num?)?.toInt() ?? -100,
                ),
              );
              return list;
            }
          }
        }
      } catch (_) {
        break;
      }
    }
    return null;
  }

  /// Save the controller's persisted MQTT broker configuration.
  Future<bool> saveMqttConfig(
    String ip,
    Map<String, dynamic> config, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/config/mqtt'),
        data: config,
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Save per-relay hardware configuration
  Future<bool> saveRelayConfig(
    String ip,
    Map<String, dynamic> relayConfig, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay/config'),
        data: relayConfig,
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Save sensor calibration & threshold settings
  Future<bool> saveSensorCalibration(
    String ip,
    Map<String, dynamic> sensorData, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/config/sensor'),
        data: sensorData,
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Control buzzer: action = 'test', 'mute', 'unmute', 'stop', or enabled/volume
  Future<bool> controlBuzzer(
    String ip,
    Map<String, dynamic> buzzerData, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/buzzer'),
        data: buzzerData,
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Save LCD configuration
  Future<bool> saveLcdConfig(
    String ip,
    Map<String, dynamic> lcdData, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/config/lcd'),
        data: lcdData,
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Send a test remote push webhook/ntfy alert from the controller.
  /// Returns null on success or a human-readable error message on failure.
  Future<String?> testRemoteAlert(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/alert/test'),
        data: const <String, dynamic>{},
        options: _authOptions(password, username: username),
      );
      if (res.statusCode == 200) return null;
      return 'Controller returned HTTP ${res.statusCode}';
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) {
        final msg = data['message'] ?? data['error'];
        if (msg != null && msg.toString().isNotEmpty) {
          return msg.toString();
        }
      }
      return e.message ?? 'Remote alert test failed';
    } catch (e) {
      return e.toString();
    }
  }

  /// Factory reset ESP32 controller
  Future<bool> factoryReset(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/factory-reset'),
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch complete configuration backup JSON
  Future<String?> fetchBackup(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final opts = _authOptions(password, username: username);
      opts.responseType = ResponseType.plain;
      final res = await _dio.get<String>(
        _url(ip, '/api/backup'),
        options: opts,
      );
      return res.data;
    } catch (_) {
      return null;
    }
  }

  /// Restore configuration backup JSON
  Future<bool> restoreConfig(
    String ip,
    String configJson, {
    String? password,
    String? username,
  }) async {
    try {
      dynamic payload;
      try {
        payload = jsonDecode(configJson);
      } catch (_) {
        payload = {'config': configJson};
      }
      final res = await _dio.post(
        _url(ip, '/api/restore'),
        data: payload,
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch Hardware Profile & GPIO Template configuration
  Future<HardwareProfile?> fetchHardwareProfile(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/hardware'),
        options: _authOptions(password, username: username),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map<String, dynamic>) {
          return HardwareProfile.fromJson(data);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Save Hardware Profile & GPIO Template configuration
  Future<bool> saveHardwareProfile(
    String ip,
    HardwareProfile profile, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/hardware'),
        data: profile.toJson(),
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Apply predefined hardware template preset
  Future<bool> applyHardwarePreset(
    String ip,
    String templateName, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/hardware/template'),
        data: {'template': templateName},
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Reset hardware configuration to default 5-CH profile
  Future<bool> resetHardwareProfile(
    String ip, {
    String? password,
    String? username,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/hardware/reset'),
        options: _authOptions(password, username: username),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
