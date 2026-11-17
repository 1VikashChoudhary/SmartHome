import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:smarthome_app/core/models/smart_device.dart';
import 'package:smarthome_app/services/device_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceStorageService & Credential Migration Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('Loads empty list when no devices are stored', () async {
      final service = DeviceStorageService();
      final devices = await service.loadDevices();
      expect(devices, isEmpty);
    });

    test(
      'Saves credentials outside SharedPreferences and restores them securely',
      () async {
        final service = DeviceStorageService();
        final device = SmartDevice(
          id: 'dev_secure_test',
          mac: 'AA:BB:CC:11:22:33',
          ip: '192.168.1.55',
          hostname: 'smarthome-test',
          name: 'Secure Hub',
          authUsername: 'owner',
          authPassword: 'SecretP@ssw0rd!',
        );

        await service.saveDevices([device]);

        // Check SharedPreferences raw JSON
        final prefs = await SharedPreferences.getInstance();
        final rawJson = prefs.getString('smarthome_registered_devices');
        expect(rawJson, isNotNull);
        final List decoded = jsonDecode(rawJson!);
        expect(decoded.length, 1);
        // Credentials MUST NOT be present in SharedPreferences.
        expect(decoded[0].containsKey('auth_password'), false);
        expect(decoded[0].containsKey('auth_username'), false);

        // Load through service -> credentials MUST be restored from secure storage.
        final loaded = await service.loadDevices();
        expect(loaded.length, 1);
        expect(loaded[0].id, 'dev_secure_test');
        expect(loaded[0].authUsername, 'owner');
        expect(loaded[0].authPassword, 'SecretP@ssw0rd!');
      },
    );

    test(
      'Migrates legacy plaintext password from SharedPreferences to secure storage seamlessly',
      () async {
        // Simulate existing legacy app state before secure storage was introduced
        final legacyDeviceJson = [
          {
            'id': 'legacy_dev_01',
            'mac': '12:34:56:78:9A:BC',
            'ip': '192.168.1.88',
            'hostname': 'smarthome-legacy',
            'name': 'Legacy Hub',
            'room': 'Bedroom',
            'fw_version': '1.0.4',
            'num_relays': 5,
            'auth_required': true,
            'auth_password': 'LegacyPassword123',
            'last_seen': DateTime.now().toIso8601String(),
            'relays': [],
          },
        ];

        SharedPreferences.setMockInitialValues({
          'smarthome_registered_devices': jsonEncode(legacyDeviceJson),
        });

        final service = DeviceStorageService();

        // On first load, it should detect legacy credential, migrate to secure storage, and strip from prefs
        final loaded = await service.loadDevices();
        expect(loaded.length, 1);
        expect(loaded[0].id, 'legacy_dev_01');
        expect(loaded[0].authPassword, 'LegacyPassword123');

        // Verify that SharedPreferences now has the password stripped
        final prefs = await SharedPreferences.getInstance();
        final updatedRaw = prefs.getString('smarthome_registered_devices')!;
        final List updatedDecoded = jsonDecode(updatedRaw);
        expect(updatedDecoded[0].containsKey('auth_password'), false);
      },
    );

    test('Custom rooms load default list and persist updates', () async {
      final service = DeviceStorageService();
      final initialRooms = await service.loadRooms();
      expect(initialRooms, contains('Living Room'));
      expect(initialRooms, contains('Bedroom'));

      final customRooms = ['Living Room', 'Home Cinema', 'Garage', 'Garden'];
      await service.saveRooms(customRooms);

      final loadedRooms = await service.loadRooms();
      expect(loadedRooms, customRooms);
    });

    test(
      'Monitoring selection and live mode persist independently of device credentials',
      () async {
        final service = DeviceStorageService();

        expect(await service.loadMonitoringDeviceId(), isNull);
        expect(await service.loadMonitoringLiveMode(), isTrue);

        await service.saveMonitoringDeviceId('living-room-controller');
        await service.saveMonitoringLiveMode(true);

        expect(
          await service.loadMonitoringDeviceId(),
          'living-room-controller',
        );
        expect(await service.loadMonitoringLiveMode(), isTrue);

        await service.saveMonitoringDeviceId(null);
        expect(await service.loadMonitoringDeviceId(), isNull);
      },
    );

    test(
      'deleteDeviceCredentials serializes after in-flight saveDevices',
      () async {
        final service = DeviceStorageService();
        final secure = FlutterSecureStorage();
        final dev = SmartDevice(
          id: 'race_dev_1',
          ip: '192.168.1.99',
          mac: 'AA:BB:CC:DD:EE:01',
          hostname: 'smarthome',
          name: 'Race Test',
          authRequired: true,
          authRole: 'admin',
          authPassword: 'racePassword123',
        );

        await Future.wait([
          service.saveDevices([dev]),
          service.deleteDeviceCredentials('race_dev_1'),
        ]);

        expect(
          await secure.read(key: 'smarthome_device_pass_race_dev_1'),
          isNull,
        );
      },
    );
  });
}
