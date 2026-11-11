import 'package:flutter_test/flutter_test.dart';
import 'package:smarthome_app/core/models/smart_device.dart';
import 'package:smarthome_app/core/models/relay_channel.dart';
import 'package:smarthome_app/core/models/sensor_telemetry.dart';
import 'package:smarthome_app/core/models/scheduled_alarm.dart';
import 'package:smarthome_app/core/models/automation_rule.dart';
import 'package:smarthome_app/core/models/device_diagnostics.dart';

void main() {
  group('SmartDevice Model Tests', () {
    test('SmartDevice.fromDiscovery creates a valid device instance', () {
      final json = {
        'mac': 'AA:BB:CC:DD:EE:FF',
        'device_id': 'smarthome_aabbccddeeff',
        'device_name': 'Living Room Hub',
        'hostname': 'smarthome-eeff',
        'fw_version': '1.0.5',
        'num_relays': 5,
        'auth_required': true,
        'uptime': '1h 23m',
      };

      final device = SmartDevice.fromDiscovery(json, '192.168.1.50');
      expect(device.id, 'smarthome_aabbccddeeff');
      expect(device.mac, 'AA:BB:CC:DD:EE:FF');
      expect(device.ip, '192.168.1.50');
      expect(device.name, 'Living Room Hub');
      expect(device.hostname, 'smarthome-eeff');
      expect(device.fwVersion, '1.0.5');
      expect(device.numRelays, 5);
      expect(device.authRequired, true);
      expect(device.isOnline, true);
    });

    test('SmartDevice serialization and deserialization preserves all fields', () {
      final original = SmartDevice(
        id: 'dev_test_1',
        mac: '11:22:33:44:55:66',
        ip: '192.168.1.100',
        hostname: 'smarthome-test',
        name: 'Master Controller',
        room: 'Kitchen',
        fwVersion: '1.0.5',
        numRelays: 2,
        authRequired: true,
        authUsername: 'owner',
        authPassword: 'SuperSecretPassword!',
        relays: [
          RelayChannel(index: 0, name: 'Light', state: true, boot: 1),
          RelayChannel(index: 1, name: 'Exhaust', state: false, boot: 2),
        ],
      );

      final json = original.toStorageJson();
      expect(json['id'], 'dev_test_1');
      expect(json['mac'], '11:22:33:44:55:66');
      expect(json['auth_username'], 'owner');
      expect(json['auth_password'], 'SuperSecretPassword!');
      expect(json['relays'].length, 2);

      final restored = SmartDevice.fromStorageJson(json);
      expect(restored.id, original.id);
      expect(restored.mac, original.mac);
      expect(restored.name, original.name);
      expect(restored.room, original.room);
      expect(restored.authUsername, 'owner');
      expect(restored.authPassword, 'SuperSecretPassword!');
      expect(restored.relays.length, 2);
      expect(restored.relays[0].name, 'Light');
      expect(restored.relays[1].boot, 2);
    });

    test('SmartDevice.copyWith overrides specified fields only', () {
      final original = SmartDevice(
        id: 'dev_1',
        mac: '00:11:22:33:44:55',
        ip: '192.168.1.20',
        hostname: 'smarthome',
        name: 'Initial Name',
      );

      final updated = original.copyWith(
        name: 'Updated Name',
        ip: '192.168.1.25',
        isOnline: false,
      );

      expect(updated.name, 'Updated Name');
      expect(updated.ip, '192.168.1.25');
      expect(updated.isOnline, false);
      expect(updated.id, original.id);
      expect(updated.mac, original.mac);
    });

    test('SmartDevice multi-user privilege tiers and logout handling', () {
      final adminDev = SmartDevice(
        id: 'admin_1',
        mac: '00:11:22:33:44:55',
        ip: '192.168.1.50',
        hostname: 'smarthome',
        name: 'Living Room',
        authRequired: true,
        authRole: 'admin',
        authPassword: 'secretPassword',
      );
      expect(adminDev.isAdmin, true);
      expect(adminDev.isGuest, false);
      expect(adminDev.needsAuth, false);

      final guestDev = adminDev.copyWith(authRole: 'guest');
      expect(guestDev.isAdmin, false);
      expect(guestDev.isGuest, true);

      // Simulate logout
      final loggedOutDev = guestDev.copyWith(
        clearAuthPassword: true,
        authLocked: true,
      );
      expect(loggedOutDev.authPassword, isNull);
      expect(loggedOutDev.authLocked, true);
      expect(loggedOutDev.needsAuth, true);
    });
  });

  group('SensorTelemetry Model Tests', () {
    test('SensorTelemetry parses numeric and string values gracefully', () {
      final json = {
        'temperature': '24.5',
        'humidity': 62.0,
        'dht_fault': false,
        'temp_threshold': '50',
        'pressure': '1014.2',
        'lux': 345.5,
        'lux_enabled': true,
        'motion': true,
        'motion_age_s': 12,
        'motion_enabled': true,
        'probe_temp': '28.4',
        'probe_fault': false,
        'probe_enabled': true,
        'distance_cm': '45.0',
        'tank_level_pct': 70,
        'tank_enabled': true,
        'gas_raw': '420',
        'gas_percent': 15,
        'gas_alarm': false,
        'gas_warming': false,
        'gas_threshold': 600,
      };

      final telemetry = SensorTelemetry.fromJson(json);
      expect(telemetry.temperature, 24.5);
      expect(telemetry.humidity, 62.0);
      expect(telemetry.dhtFault, false);
      expect(telemetry.tempThreshold, 50.0);
      expect(telemetry.pressure, 1014.2);
      expect(telemetry.lux, 345.5);
      expect(telemetry.luxEnabled, true);
      expect(telemetry.motionDetected, true);
      expect(telemetry.motionAgeSeconds, 12);
      expect(telemetry.probeTemp, 28.4);
      expect(telemetry.probeFault, false);
      expect(telemetry.distanceCm, 45.0);
      expect(telemetry.tankLevelPct, 70);
      expect(telemetry.tankEnabled, true);
      expect(telemetry.gasRaw, 420);
      expect(telemetry.gasPercent, 15);
      expect(telemetry.gasAlarm, false);

      final outJson = telemetry.toJson();
      expect(outJson['pressure'], 1014.2);
      expect(outJson['lux'], 345.5);
      expect(outJson['motion'], true);
      expect(outJson['probe_temp'], 28.4);
      expect(outJson['tank_level_pct'], 70);
    });
  });

  group('ScheduledAlarm Model Tests', () {
    test('ScheduledAlarm serializes and deserializes correctly', () {
      final alarm = ScheduledAlarm(
        id: 3,
        enabled: true,
        mode: 0,
        type: 1, // Daily
        hour: 7,
        minute: 30,
        action: 0, // Relay ON
        targetRelay: 1,
      );

      final json = alarm.toJson();
      expect(json['id'], 3);
      expect(json['en'], true);
      expect(json['hour'], 7);
      expect(json['min'], 30);
      expect(json['action'], 0);
      expect(json['relay'], 1);

      final restored = ScheduledAlarm.fromJson(json);
      expect(restored.id, 3);
      expect(restored.enabled, true);
      expect(restored.hour, 7);
      expect(restored.minute, 30);
      expect(restored.action, 0);
      expect(restored.targetRelay, 1);
    });
  });

  group('AutomationRule Model Tests', () {
    test('AutomationRule serializes and deserializes correctly', () {
      final rule = AutomationRule(
        id: 1,
        enabled: true,
        name: 'Cooling Trigger',
        sensor: 0, // Temp
        condition: 0,  // >=
        threshold: 28.5,
        hysteresis: 1.0,
        action: 0, // Turn ON
        targetRelay: 2,
      );

      final json = rule.toJson();
      expect(json['id'], 1);
      expect(json['name'], 'Cooling Trigger');
      expect(json['sensor'], 0);
      expect(json['cond'], 0);
      expect(json['th'], 28.5);

      final restored = AutomationRule.fromJson(json);
      expect(restored.id, 1);
      expect(restored.name, 'Cooling Trigger');
      expect(restored.threshold, 28.5);
      expect(restored.targetRelay, 2);
    });
  });

  group('DeviceDiagnostics Model Tests', () {
    test('DeviceDiagnostics parses hardware telemetry accurately', () {
      final json = {
        'chip_model': 'ESP32-D0WDQ6',
        'chip_rev': 3,
        'cpu_freq': 240,
        'flash_size': 4194304,
        'free_heap': 214580,
        'min_heap': 198400,
        'uptime': '1h 00m',
        'reset_reason': 'Power-on Reset',
      };

      final diag = DeviceDiagnostics.fromJson(json);
      expect(diag.chipModel, 'ESP32-D0WDQ6');
      expect(diag.chipRev, 3);
      expect(diag.cpuFreq, 240);
      expect(diag.freeHeap, 214580);
      expect(diag.resetReason, 'Power-on Reset');
    });
  });
}
