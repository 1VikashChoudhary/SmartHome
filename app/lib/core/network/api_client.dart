import 'dart:convert';
import 'package:dio/dio.dart';
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

  const OtaStatus({
    required this.updating,
    required this.firmwareVersion,
    required this.firmwareBuild,
  });

  factory OtaStatus.fromJson(Map<String, dynamic> json) => OtaStatus(
    updating: json['updating'] == true,
    firmwareVersion: json['fw_version']?.toString() ?? '',
    firmwareBuild: json['fw_date']?.toString() ?? '',
  );

  bool differsFrom(OtaStatus other) =>
      firmwareVersion != other.firmwareVersion ||
      firmwareBuild != other.firmwareBuild;
}

class ApiClient {
  static final Map<String, String> _usernameByHost = {};
  static void Function(String host)? onUnauthorized;
  final Dio _dio;
  final String? defaultUsername;

  ApiClient({this.defaultUsername})
    : _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(milliseconds: 5000),
          receiveTimeout: const Duration(milliseconds: 6000),
          headers: {'Accept': 'application/json'},
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final password =
              options.extra.remove('smarthome_auth_password') as String?;
          if (password != null && password.isNotEmpty) {
            final requestedUser =
                options.extra.remove('smarthome_auth_username') as String?;
            final knownUser =
                _usernameByHost[_hostKey(options.uri.host, options.uri.port)];
            final user = (requestedUser != null && requestedUser.isNotEmpty)
                ? requestedUser
                : (knownUser ?? 'admin');
            options.headers['Authorization'] =
                'Basic ${base64Encode(utf8.encode('$user:$password'))}';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            onUnauthorized?.call(error.requestOptions.uri.host);
          }
          handler.next(error);
        },
      ),
    );
  }

  static void registerDeviceUsername(String ipOrHost, String? username) {
    final host = sanitizeHost(ipOrHost);
    if (host.isEmpty) return;
    final parts = host.split(':');
    final port = parts.length > 1 ? int.tryParse(parts.last) ?? 80 : 80;
    _usernameByHost[_hostKey(
      parts.first,
      port,
    )] = (username == null || username.trim().isEmpty)
        ? 'admin'
        : username.trim();
  }

  static void unregisterDevice(String ipOrHost) {
    final host = sanitizeHost(ipOrHost);
    if (host.isEmpty) return;
    final parts = host.split(':');
    final port = parts.length > 1 ? int.tryParse(parts.last) ?? 80 : 80;
    _usernameByHost.remove(_hostKey(parts.first, port));
  }

  @visibleForTesting
  static bool hasRegisteredUsername(String ipOrHost) {
    final host = sanitizeHost(ipOrHost);
    if (host.isEmpty) return false;
    final parts = host.split(':');
    final port = parts.length > 1 ? int.tryParse(parts.last) ?? 80 : 80;
    return _usernameByHost.containsKey(_hostKey(parts.first, port));
  }

  static String _hostKey(String host, int port) =>
      '${host.toLowerCase()}:$port';

  String _url(String ip, String path) => 'http://${sanitizeHost(ip)}$path';

  Options _authOptions(
    String? password, {
    String? username,
    Duration? timeout,
  }) {
    final headers = <String, dynamic>{
      'Accept': 'application/json',
      'X-Requested-With': 'SmartHome',
    };
    if (password != null && password.isNotEmpty) {
      return Options(
        headers: headers,
        receiveTimeout: timeout,
        extra: {
          'smarthome_auth_password': password,
          'smarthome_auth_username': username ?? defaultUsername,
        },
      );
    }
    return Options(headers: headers, receiveTimeout: timeout);
  }

  /// Fast discovery probe (unauthenticated)
  Future<SmartDevice?> probeDiscovery(String ip) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/discovery'),
        options: Options(receiveTimeout: const Duration(milliseconds: 3000)),
      );
      if (res.statusCode == 200 && res.data != null) {
        dynamic data = res.data;
        if (data is String) data = jsonDecode(data);
        if (data is Map<String, dynamic>) {
          return SmartDevice.fromDiscovery(data, sanitizeHost(ip));
        }
      }
    } catch (_) {}
    return null;
  }

  /// Full status fetch
  Future<Map<String, dynamic>?> fetchStatus(
    String ip, {
    String? password,
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/status'),
        options: _authOptions(password),
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

  /// Relay control: action = 'toggle', 'on', 'off'
  Future<bool> setRelay(
    String ip,
    int relayIndex,
    String action, {
    String? password,
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay'),
        data: {'id': relayIndex, 'action': action},
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay/all'),
        data: {'action': action},
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay/timer'),
        data: {'id': relayIndex, 'action': action, 'duration': durationSec},
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay/timer'),
        data: {'id': relayIndex, 'action': 'cancel'},
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/rules'),
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/rule'),
        data: ruleData,
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/rule'),
        data: {'id': ruleId, 'en': enabled},
        options: _authOptions(password),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Delete Automation Rule
  Future<bool> deleteRule(String ip, int ruleId, {String? password}) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/rule'),
        data: {'id': ruleId, 'delete': true},
        options: _authOptions(password),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Upload an application image using the same multipart contract as `/update`.
  ///
  /// A successful result only means the ESP32 validated and committed the
  /// inactive OTA partition. Call [fetchOtaStatus] after the scheduled reboot
  /// before presenting the update as verified.
  Future<FirmwareUploadResult> uploadFirmware(
    String ip,
    List<int> fileBytes,
    String filename, {
    void Function(int sent, int total)? onProgress,
    String? password,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: filename),
      });

      final opts = _authOptions(password, timeout: const Duration(minutes: 2));
      opts.sendTimeout = const Duration(minutes: 2);
      final res = await _dio.post(
        _url(ip, '/api/ota/upload?type=firmware'),
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
  Future<OtaStatus?> fetchOtaStatus(String ip, {String? password}) async {
    try {
      final nonce = DateTime.now().microsecondsSinceEpoch;
      final res = await _dio.get(
        _url(ip, '/api/ota/status?_=$nonce'),
        options: _authOptions(password, timeout: const Duration(seconds: 4)),
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
  Future<bool> reboot(String ip, {String? password}) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/reboot'),
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/alarms'),
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/alarm'),
        data: alarmData,
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/alarm'),
        data: {'id': alarmId, 'en': enabled},
        options: _authOptions(password),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Delete alarm schedule
  Future<bool> deleteAlarm(String ip, int alarmId, {String? password}) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/alarm'),
        data: {'id': alarmId, 'delete': true},
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/logs'),
        options: _authOptions(password),
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
  Future<bool> clearLogs(String ip, {String? password}) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/logs/clear'),
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/diagnostics'),
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/relays'),
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.get(
        _url(ip, '/api/config'),
        options: _authOptions(password),
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
        options: _authOptions(authPassword),
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
  }) async {
    for (int attempt = 0; attempt < 6; attempt++) {
      try {
        final query = (forceRefresh && attempt == 0) ? '?refresh=1' : '';
        final res = await _dio.get(
          _url(ip, '/api/wifi/scan$query'),
          options: _authOptions(
            authPassword,
            timeout: const Duration(seconds: 5),
          ),
        );
        if (res.statusCode == 200 && res.data != null) {
          dynamic data = res.data;
          if (data is String) data = jsonDecode(data);
          if (data is Map) {
            final scanning = data['scanning'] == true;
            if (scanning) {
              await Future.delayed(const Duration(milliseconds: 1400));
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/config/mqtt'),
        data: config,
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/relay/config'),
        data: relayConfig,
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/config/sensor'),
        data: sensorData,
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/buzzer'),
        data: buzzerData,
        options: _authOptions(password),
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
  }) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/config/lcd'),
        data: lcdData,
        options: _authOptions(password),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Factory reset ESP32 controller
  Future<bool> factoryReset(String ip, {String? password}) async {
    try {
      final res = await _dio.post(
        _url(ip, '/api/factory-reset'),
        options: _authOptions(password),
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
