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
      expect(outJson['dht_enabled'], true);
      expect(outJson['gas_max'], 4095);
    });

    test('SensorTelemetry preserves dht_enabled: false and ESP8266 gas_max: 1023', () {
      final json = {
        'temperature': 0.0,
        'humidity': 0.0,
        'dht_enabled': false,
        'dht_fault': false,
        'gas_raw': 512,
        'gas_max': 1023,
        'gas_threshold': 100,
      };

      final telemetry = SensorTelemetry.fromJson(json);
      expect(telemetry.dhtEnabled, isFalse);
      expect(telemetry.gasMax, 1023);
      expect(telemetry.gasThreshold, 100);

      final roundtrip = telemetry.toJson();
      expect(roundtrip['dht_enabled'], isFalse);
      expect(roundtrip['gas_max'], 1023);
      expect(roundtrip['gas_threshold'], 100);
    });

    test('SensorTelemetry parses and roundtrips multi-instance sensor arrays cleanly', () {
      final json = {
        'temperature': 24.5,
        'humidity': 55.0,
        'dht_enabled': true,
        'climates': [
          {
            'index': 0,
            'enabled': true,
            'type': 2,
            'type_name': 'DHT22',
            'label': 'Hall',
            'temperature': 24.5,
            'humidity': 55.0,
          },
          {
            'index': 1,
            'enabled': true,
            'type': 3,
            'type_name': 'BME280',
            'label': '',
            'temperature': 28.2,
            'humidity': 42.0,
            'pressure': 1012.4,
            'barometer': true,
          },
        ],
        'lights': [
          {'index': 0, 'enabled': true, 'i2c_addr': 0x23, 'label': 'Window', 'lux': 420.0},
          {'index': 1, 'enabled': true, 'i2c_addr': 0x5C, 'label': '', 'lux': 85.0},
        ],
        'motions': [
          {'index': 0, 'enabled': true, 'type': 1, 'label': 'Entry', 'detected': true, 'age_s': 2},
          {'index': 1, 'enabled': true, 'type': 2, 'label': '', 'detected': false, 'age_s': 120},
        ],
        'probes': [
          {'index': 0, 'enabled': true, 'label': 'Boiler', 'temperature': 58.5, 'fault': false},
        ],
        'tanks': [
          {'index': 0, 'enabled': true, 'type': 1, 'label': 'Roof', 'distance_cm': 45.0, 'level_pct': 78},
        ],
        'mq2s': [
          {'index': 0, 'enabled': true, 'hw_allowed': true, 'label': 'Kitchen', 'raw': 320, 'alarm': false},
          {'index': 1, 'enabled': true, 'hw_allowed': true, 'label': '', 'raw': 910, 'alarm': true},
        ],
      };

      final telemetry = SensorTelemetry.fromJson(json);
      expect(telemetry.climates.length, 2);
      expect(telemetry.climates[0].displayName, 'Hall');
      expect(telemetry.climates[1].displayName, 'Climate #2');
      expect(telemetry.climates[1].pressure, 1012.4);

      expect(telemetry.lights.length, 2);
      expect(telemetry.lights[1].i2cAddr, 0x5C);
      expect(telemetry.lights[1].displayName, 'Light #2');

      expect(telemetry.motions.length, 2);
      expect(telemetry.motions[0].detected, isTrue);
      expect(telemetry.motions[1].displayName, 'Motion #2');

      expect(telemetry.probes.length, 1);
      expect(telemetry.probes[0].temperature, 58.5);

      expect(telemetry.tanks.length, 1);
      expect(telemetry.tanks[0].levelPct, 78);

      expect(telemetry.mq2s.length, 2);
      expect(telemetry.mq2s[1].alarm, isTrue);
      expect(telemetry.mq2s[1].displayName, 'Gas #2');

      final out = telemetry.toJson();
      expect((out['climates'] as List).length, 2);
      expect((out['mq2s'] as List).length, 2);
    });

    test('isCustomSensorLabel ignores blank and firmware default labels', () {
      expect(isCustomSensorLabel('', 'Climate'), isFalse);
      expect(isCustomSensorLabel('   ', 'Light'), isFalse);
      expect(isCustomSensorLabel('Climate 1', 'Climate'), isFalse);
      expect(isCustomSensorLabel('Climate #2', 'Climate'), isFalse);
      expect(isCustomSensorLabel('Light 1', 'Light'), isFalse);
      expect(isCustomSensorLabel('Motion 3', 'Motion'), isFalse);
      expect(isCustomSensorLabel('Probe 1', 'Probe'), isFalse);
      expect(isCustomSensorLabel('Tank 2', 'Tank'), isFalse);
      expect(isCustomSensorLabel('Gas 1', 'Gas'), isFalse);

      expect(isCustomSensorLabel('Server Rack', 'Climate'), isTrue);
      expect(isCustomSensorLabel('Porch Light', 'Light'), isTrue);
      expect(isCustomSensorLabel('Climate 1B', 'Climate'), isTrue);
      expect(isCustomSensorLabel('Overhead Tank Main', 'Tank'), isTrue);
    });

    test('hasCustomLabel works across all reading classes', () {
      expect(const ClimateReading(label: 'Climate 1').hasCustomLabel, isFalse);
      expect(const ClimateReading(label: 'Server Rack').hasCustomLabel, isTrue);
      expect(const LightReading(label: 'Light 1').hasCustomLabel, isFalse);
      expect(const LightReading(label: 'Desk Lux').hasCustomLabel, isTrue);
      expect(const MotionReading(label: 'Motion 1').hasCustomLabel, isFalse);
      expect(const MotionReading(label: 'Hall PIR').hasCustomLabel, isTrue);
      expect(const ProbeReading(label: 'Probe 1').hasCustomLabel, isFalse);
      expect(const ProbeReading(label: 'Pool Temp').hasCustomLabel, isTrue);
      expect(const TankReading(label: 'Tank 1').hasCustomLabel, isFalse);
      expect(const TankReading(label: 'Roof Sump').hasCustomLabel, isTrue);
      expect(const Mq2Reading(label: 'Gas 1').hasCustomLabel, isFalse);
      expect(const Mq2Reading(label: 'Kitchen Gas').hasCustomLabel, isTrue);
    });

    test('parses gas_hw_allowed and reports 0-sensor state cleanly', () {
      final zeroSensors = SensorTelemetry.fromJson({
        'dht_enabled': false,
        'gas_enabled': false,
        'gas_hw_allowed': false,
        'gas_raw': 0,
        'climates': [],
        'mq2s': [],
        'lights': [],
        'motions': [],
        'probes': [],
        'tanks': [],
      });
      expect(zeroSensors.hasActiveClimate, isFalse);
      expect(zeroSensors.hasActiveGas, isFalse);
      expect(zeroSensors.hasActiveLight, isFalse);
      expect(zeroSensors.hasActiveMotion, isFalse);
      expect(zeroSensors.hasActiveProbe, isFalse);
      expect(zeroSensors.hasActiveTank, isFalse);
      expect(zeroSensors.hasAnySensor, isFalse);

      final pausedMq2 = SensorTelemetry.fromJson({
        'dht_enabled': false,
        'gas_enabled': false,
        'gas_hw_allowed': true,
        'gas_raw': 0,
      });
      expect(pausedMq2.gasEnabled, isFalse);
      expect(pausedMq2.gasHwAllowed, isTrue);
      expect(pausedMq2.hasActiveGas, isTrue);
      expect(pausedMq2.hasAnySensor, isTrue);
      expect(pausedMq2.toJson()['gas_hw_allowed'], isTrue);
      expect(pausedMq2.toJson()['gas_enabled'], isFalse);
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
      expect(json['s_idx'], 0);
      expect(json['cond'], 0);
      expect(json['th'], 28.5);

      final restored = AutomationRule.fromJson(json);
      expect(restored.id, 1);
      expect(restored.name, 'Cooling Trigger');
      expect(restored.threshold, 28.5);
      expect(restored.targetRelay, 2);
    });

    test('AutomationRule preserves sensorIndex and supports Motion sensor (6)', () {
      final rule = AutomationRule.fromJson({
        'id': 4,
        'en': true,
        'name': 'Hallway Motion',
        'sensor': 6,
        's_idx': 2,
        'cond': 0,
        'th': 1.0,
        'hyst': 0.0,
        'action': 0,
        'relay': 1,
      });

      expect(rule.sensor, 6);
      expect(rule.sensorIndex, 2);
      expect(rule.unit, '');
      expect(rule.sensorLabel, 'Motion / Occupancy #3');
      expect(rule.toJson()['s_idx'], 2);

      final updated = rule.copyWith(sensorIndex: 3);
      expect(updated.sensorIndex, 3);
      expect(updated.sensorLabel, 'Motion / Occupancy #4');
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
