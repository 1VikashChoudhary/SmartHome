import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthome_app/core/models/smart_device.dart';
import 'package:smarthome_app/core/models/hardware_profile.dart';
import 'package:smarthome_app/core/models/scheduled_alarm.dart';
import 'package:smarthome_app/services/device_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 1 & 2 Regressions: Auth, Models, WebSocket Integrity', () {
    test('SmartDevice.copyWith preserves and updates fwVersion properly', () {
      final original = SmartDevice(
        id: 'dev_1',
        mac: '11:22:33:44:55:66',
        ip: '192.168.1.50',
        hostname: 'smarthome',
        name: 'Device 1',
        fwVersion: '1.0.0',
      );

      final updated = original.copyWith(fwVersion: '2.0.0');
      expect(updated.fwVersion, '2.0.0');

      final preserved = updated.copyWith(name: 'Device 1 Updated');
      expect(preserved.fwVersion, '2.0.0');
      expect(preserved.name, 'Device 1 Updated');
    });

    test('SmartDevice.fromStorageJson handles missing id and preserves authLocked', () {
      final json = {
        'ip': '192.168.1.100',
        'mac': 'AA:BB:CC:DD:EE:FF',
        'auth_required': true,
        'auth_locked': true,
      };

      final dev = SmartDevice.fromStorageJson(json);
      expect(dev.id, 'AA:BB:CC:DD:EE:FF');
      expect(dev.authLocked, true);
      expect(dev.needsAuth, true);
    });

    test('Passwordless guest user has valid credentials and does not needAuth when unlocked', () {
      final guestDev = SmartDevice(
        id: 'dev_guest',
        mac: '11:22:33:44:55:77',
        ip: '192.168.1.60',
        hostname: 'smarthome-guest',
        name: 'Guest Controller',
        authRequired: true,
        authLocked: false,
        authRole: 'guest',
        authUsername: 'family',
        authPassword: null,
      );

      expect(guestDev.isGuest, true);
      expect(guestDev.hasCredentials, true);
      expect(guestDev.needsAuth, false);
    });

    test('Admin user with empty password needsAuth when authRequired is true', () {
      final adminDev = SmartDevice(
        id: 'dev_admin',
        mac: '11:22:33:44:55:88',
        ip: '192.168.1.65',
        hostname: 'smarthome-admin',
        name: 'Admin Controller',
        authRequired: true,
        authLocked: false,
        authRole: 'admin',
        authUsername: 'admin',
        authPassword: null,
      );

      expect(adminDev.isAdmin, true);
      expect(adminDev.hasCredentials, false);
      expect(adminDev.needsAuth, true);
    });
  });

  group('DeviceStorageService Credential Cleanup Regressions', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('saveDevices clears removed password from secure storage', () async {
      final storage = DeviceStorageService();
      final secure = const FlutterSecureStorage();

      final devWithPass = SmartDevice(
        id: 'dev_clear_test',
        mac: '22:33:44:55:66:77',
        ip: '192.168.1.120',
        hostname: 'smarthome',
        name: 'Clear Test',
        authPassword: 'SecretPassword123',
        authUsername: 'admin',
      );

      await storage.saveDevices([devWithPass]);
      final savedPass = await secure.read(key: 'smarthome_device_pass_dev_clear_test');
      expect(savedPass, 'SecretPassword123');

      // Now clear password and re-save
      final devWithoutPass = devWithPass.copyWith(
        authPassword: null,
        clearAuthPassword: true,
      );
      await storage.saveDevices([devWithoutPass]);

      final clearedPass = await secure.read(key: 'smarthome_device_pass_dev_clear_test');
      expect(clearedPass, isNull);
    });
  });

  group('HardwareProfile & Sensor Enum Fallback Regressions', () {
    test('ClimateSensorType.fromValue returns none for unknown or invalid value', () {
      expect(ClimateSensorType.fromValue(0), ClimateSensorType.none);
      expect(ClimateSensorType.fromValue(99), ClimateSensorType.none);
      expect(ClimateSensorType.fromValue(-1), ClimateSensorType.none);
      expect(ClimateSensorType.fromValue(2), ClimateSensorType.dht22);
      expect(ClimateSensorType.fromValue(3), ClimateSensorType.bme280);
    });

    test('HardwareProfile.copyWith updates primary sensor without blowing away multi-instance slots', () {
      const profile = HardwareProfile(
        boardName: 'Custom Multi-Node',
        numRelays: 2,
        channels: [],
        climates: [
          ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4),
          ClimateSensorSlotConfig(type: ClimateSensorType.bme280, pin: 255, i2cAddr: 0x76),
        ],
        ultrasonics: [
          UltrasonicSensorSlotConfig(type: UltrasonicSensorType.hcsr04p, trigPin: 15, echoPin: 35, tankDepthCm: 200, tankAirGapCm: 20),
          UltrasonicSensorSlotConfig(type: UltrasonicSensorType.hcsr04p, trigPin: 16, echoPin: 36, tankDepthCm: 300, tankAirGapCm: 25),
        ],
      );

      expect(profile.climates.length, 2);
      expect(profile.ultrasonics.length, 2);

      // Update primary climate pin via legacy helper argument
      final updatedClimates = profile.copyWith(dhtPin: 14);
      expect(updatedClimates.climates.length, 2);
      expect(updatedClimates.climates[0].pin, 14);
      expect(updatedClimates.climates[1].type, ClimateSensorType.bme280);
      expect(updatedClimates.climates[1].i2cAddr, 0x76);

      // Update primary ultrasonic depth via legacy helper argument
      final updatedUltrasonics = profile.copyWith(tankDepthCm: 250);
      expect(updatedUltrasonics.ultrasonics.length, 2);
      expect(updatedUltrasonics.ultrasonics[0].tankDepthCm, 250);
      expect(updatedUltrasonics.ultrasonics[1].tankDepthCm, 300);
      expect(updatedUltrasonics.ultrasonics[1].echoPin, 36);
    });
  });

  group('Hardware Automations & Timer Serialization Regressions', () {
    test('ScheduledAlarm in Fixed Clock mode serializes and formats correctly', () {
      final alarm = ScheduledAlarm(
        id: 1,
        enabled: true,
        mode: 0,
        type: 1, // Daily
        hour: 8,
        minute: 30,
        action: 0, // Turn ON
        targetRelay: 0,
      );

      final json = alarm.toJson();
      expect(json['id'], 1);
      expect(json['mode'], 0);
      expect(json['type'], 1);
      expect(json['hour'], 8);
      expect(json['min'], 30);
      expect(json['action'], 0);
      expect(json['relay'], 0);

      expect(alarm.timeString, '08:30');
      expect(alarm.typeLabel, 'Daily');
      expect(alarm.actionLabel, 'Turn ON');
    });

    test('ScheduledAlarm in Delay Countdown mode calculates duration and labels', () {
      final delayAlarm = ScheduledAlarm(
        id: 2,
        enabled: true,
        mode: 1,
        delayMinutes: 75,
        action: 1, // Turn OFF
        targetRelay: 1,
      );

      final json = delayAlarm.toJson();
      expect(json['mode'], 1);
      expect(json['delay'], 75);
      expect(json['action'], 1);
      expect(json['relay'], 1);

      expect(delayAlarm.nextRunBadge, 'Runs within 1h 15m');
      expect(delayAlarm.actionLabel, 'Turn OFF');
    });
  });
}
