import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/models/smart_device.dart';
import '../core/network/network_utils.dart';
import 'native_controls_service.dart';

class DeviceStorageService {
  static const String _keyDevices = 'smarthome_registered_devices';
  static const String _keyRooms = 'smarthome_custom_rooms';
  static const String _keyPassPrefix = 'smarthome_device_pass_';
  static const String _keyUserPrefix = 'smarthome_device_user_';
  static const String _keyMonitoringDevice = 'smarthome_monitoring_device';
  static const String _keyMonitoringLive = 'smarthome_monitoring_live';

  // Secure storage for sensitive credentials (AES-256 on Android, Keychain on iOS)
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static Future<void> _saveQueue = Future<void>.value();

  Future<void> _enqueueWrite(Future<void> Function() op) {
    final next = _saveQueue.catchError((_) {}).then((_) => op());
    _saveQueue = next;
    return next;
  }

  Future<List<SmartDevice>> loadDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyDevices);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is! List) return [];
      final devices = decoded
          .whereType<Map>()
          .map((e) => SmartDevice.fromStorageJson(Map<String, dynamic>.from(e)))
          .toList();

      bool needsMigrationResave = false;

      // Restore passwords and usernames from secure storage (supports passwordless guest logins)
      for (int i = 0; i < devices.length; i++) {
        String? securePass;
        String? secureUser;
        try {
          securePass = await _secureStorage.read(
            key: _keyPassPrefix + devices[i].id,
          );
          secureUser = await _secureStorage.read(
            key: _keyUserPrefix + devices[i].id,
          );
        } catch (_) {
          // Preserve device entry if Android Keystore experiences a transient read error
          continue;
        }
        final effectiveUser = (secureUser != null && secureUser.isNotEmpty)
            ? secureUser
            : devices[i].authUsername;

        if (securePass != null && securePass.isNotEmpty) {
          devices[i] = devices[i].copyWith(
            authPassword: securePass,
            authUsername: effectiveUser ?? 'admin',
          );
        } else {
          if (effectiveUser != null && effectiveUser.isNotEmpty) {
            devices[i] = devices[i].copyWith(authUsername: effectiveUser);
          }
          if (devices[i].authPassword != null &&
              devices[i].authPassword!.isNotEmpty) {
            try {
              // Legacy migration: password existed in SharedPreferences JSON, migrate to secure storage
              await _secureStorage.write(
                key: _keyPassPrefix + devices[i].id,
                value: devices[i].authPassword!,
              );
              needsMigrationResave = true;
            } catch (_) {}
          }
        }
      }

      // If any legacy credentials were migrated, re-save stripped JSON to SharedPreferences
      if (needsMigrationResave) {
        await saveDevices(devices);
      }

      return devices;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDevices(List<SmartDevice> devices) {
    return _enqueueWrite(() async {
      final prefs = await SharedPreferences.getInstance();

      // Save or clear credentials in secure storage, strip from plaintext JSON
      for (final device in devices) {
        if (device.authPassword != null && device.authPassword!.isNotEmpty) {
          await _secureStorage.write(
            key: _keyPassPrefix + device.id,
            value: device.authPassword!,
          );
        } else {
          await _secureStorage.delete(key: _keyPassPrefix + device.id);
        }
        if (device.authUsername != null &&
            device.authUsername!.trim().isNotEmpty) {
          await _secureStorage.write(
            key: _keyUserPrefix + device.id,
            value: device.authUsername!.trim(),
          );
        } else {
          await _secureStorage.delete(key: _keyUserPrefix + device.id);
        }
      }

      // Store device metadata WITHOUT passwords in SharedPreferences
      final list = devices.map((d) {
        final json = d.toStorageJson();
        json.remove('auth_password'); // Strip password from plaintext storage
        json.remove('auth_username');
        return json;
      }).toList();
      await prefs.setString(_keyDevices, jsonEncode(list));
      await NativeControlsService.instance.syncDevices(devices);
    });
  }

  Future<List<String>> loadRooms() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyRooms) ??
        ['Living Room', 'Bedroom', 'Kitchen', 'Office', 'Outdoor'];
  }

  Future<void> saveRooms(List<String> rooms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyRooms, rooms);
  }

  Future<String?> loadMonitoringDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyMonitoringDevice);
  }

  Future<void> saveMonitoringDeviceId(String? deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    if (deviceId == null) {
      await prefs.remove(_keyMonitoringDevice);
    } else {
      await prefs.setString(_keyMonitoringDevice, deviceId);
    }
  }

  Future<bool> loadMonitoringLiveMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyMonitoringLive) ?? true;
  }

  Future<void> saveMonitoringLiveMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMonitoringLive, enabled);
  }

  /// Remove a device's secure credentials when unregistered
  Future<void> deleteDeviceCredentials(String deviceId) {
    return _enqueueWrite(() async {
      await _secureStorage.delete(key: _keyPassPrefix + deviceId);
      await _secureStorage.delete(key: _keyUserPrefix + deviceId);
    });
  }

  /// Export the entire Multi-Controller Hub configuration (paired controllers,
  /// room assignments, custom icons, custom rooms, and preferences) to a single JSON string.
  Future<String> exportHubBackupJson(
    List<SmartDevice> currentDevices, {
    bool includeCredentials = false,
  }) async {
    final rooms = await loadRooms();
    final monitoringDevice = await loadMonitoringDeviceId();
    final monitoringLive = await loadMonitoringLiveMode();

    final devicesList = currentDevices.map((d) {
      final json = d.toStorageJson();
      if (!includeCredentials) {
        json.remove('auth_password');
        json.remove('auth_username');
      }
      return json;
    }).toList();

    final payload = <String, dynamic>{
      'type': 'smarthome_pro_hub_backup',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'rooms': rooms,
      'monitoring_device_id': monitoringDevice,
      'monitoring_live_mode': monitoringLive,
      'devices': devicesList,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Import and persist a Multi-Controller Hub backup JSON string.
  /// Returns the restored list of [SmartDevice] on success, or null if invalid.
  Future<List<SmartDevice>?> importHubBackupJson(String rawJson) async {
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map.containsKey('type') && map['type'] != 'smarthome_pro_hub_backup') {
        return null;
      }

      final rawDevices = map['devices'];
      if (rawDevices is! List) return null;

      final existingDevices = await loadDevices();
      final existingById = <String, SmartDevice>{
        for (final d in existingDevices) d.id: d,
      };
      final existingByMac = <String, SmartDevice>{
        for (final d in existingDevices)
          if (d.mac.isNotEmpty) d.mac: d,
      };

      final restoredDevices = <SmartDevice>[];
      for (final item in rawDevices) {
        if (item is Map) {
          final devMap = Map<String, dynamic>.from(item);
          final rawIp = devMap['ip']?.toString() ?? '';
          final cleanIp = sanitizeHost(rawIp);
          if (cleanIp.isEmpty ||
              RegExp(r'[\s\x00-\x1F\x7F@#?\\]').hasMatch(cleanIp)) {
            continue;
          }
          devMap['ip'] = cleanIp;

          final rawHostname = devMap['hostname']?.toString() ?? '';
          final cleanHostname = sanitizeHost(rawHostname);
          devMap['hostname'] = cleanHostname.isNotEmpty
              ? cleanHostname
              : 'smarthome';

          var dev = SmartDevice.fromStorageJson(devMap);
          if (dev.id.trim().isEmpty ||
              dev.numRelays < 0 ||
              dev.numRelays > 16) {
            continue;
          }
          final prior = existingById[dev.id] ??
              (dev.mac.isNotEmpty ? existingByMac[dev.mac] : null);
          if (prior != null &&
              (dev.authPassword == null || dev.authPassword!.isEmpty) &&
              prior.authPassword != null &&
              prior.authPassword!.isNotEmpty) {
            dev = dev.copyWith(
              authPassword: prior.authPassword,
              authUsername: dev.authUsername ?? prior.authUsername,
            );
          }
          restoredDevices.add(dev);
        }
      }

      final restoredIds = restoredDevices.map((d) => d.id).toSet();
      for (final oldDev in existingDevices) {
        if (!restoredIds.contains(oldDev.id)) {
          await deleteDeviceCredentials(oldDev.id);
        }
      }

      if (map['rooms'] is List) {
        final rooms = (map['rooms'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (rooms.isNotEmpty) {
          await saveRooms(rooms);
        }
      }

      if (map.containsKey('monitoring_device_id')) {
        await saveMonitoringDeviceId(map['monitoring_device_id']?.toString());
      }
      if (map['monitoring_live_mode'] is bool) {
        await saveMonitoringLiveMode(map['monitoring_live_mode'] as bool);
      }

      await saveDevices(restoredDevices);
      return restoredDevices;
    } catch (_) {
      return null;
    }
  }
}
