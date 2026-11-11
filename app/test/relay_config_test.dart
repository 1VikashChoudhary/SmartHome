import 'package:flutter_test/flutter_test.dart';
import 'package:smarthome_app/core/models/relay_channel.dart';
import 'package:smarthome_app/core/models/smart_device.dart';

void main() {
  group('RelayChannel & SmartDevice hardware configuration tests', () {
    test('RelayChannel.fromJson handles mixed data types robustly', () {
      final json = {
        'id': '2',
        'enabled': false,
        'switch_enabled': false,
        'name': 'Living Room Light',
        'state': 1,
        'trigger': '1',
        'boot': 2,
        'autoOff': '45',
        'autoOn': 0,
        'failsafe': 'true',
      };

      final relay = RelayChannel.fromJson(2, json);
      expect(relay.index, 2);
      expect(relay.enabled, false);
      expect(relay.switchEnabled, false);
      expect(relay.name, 'Living Room Light');
      expect(relay.state, true);
      expect(relay.trigger, 1);
      expect(relay.boot, 2);
      expect(relay.autoOff, 45);
      expect(relay.autoOn, 0);
      expect(relay.failsafe, true);
    });

    test('SmartDevice.fromStatus preserves all relay configurations', () {
      final statusJson = {
        'device_name': 'ESP32 Controller',
        'mac': '3C:8A:1F:81:21:60',
        'ip': '192.168.29.103',
        'num_relays': 2,
        'relays': [
          {
            'id': 0,
            'enabled': true,
            'switch_enabled': true,
            'name': 'Socket 1',
            'state': false,
            'trigger': 0,
            'boot': 1,
            'autoOff': 30,
            'autoOn': 0,
            'failsafe': false,
          },
          {
            'id': 1,
            'enabled': false,
            'switch_enabled': false,
            'name': 'Fan',
            'state': true,
            'trigger': 1,
            'boot': 2,
            'autoOff': 0,
            'autoOn': 15,
            'failsafe': true,
          }
        ],
      };

      final dev = SmartDevice.fromStatus(statusJson, '192.168.29.103');
      expect(dev.relays.length, 2);
      expect(dev.relays[0].enabled, true);
      expect(dev.relays[0].switchEnabled, true);
      expect(dev.relays[0].name, 'Socket 1');
      expect(dev.relays[0].boot, 1);
      expect(dev.relays[0].autoOff, 30);
      expect(dev.relays[1].enabled, false);
      expect(dev.relays[1].switchEnabled, false);
      expect(dev.relays[1].name, 'Fan');
      expect(dev.relays[1].trigger, 1);
      expect(dev.relays[1].failsafe, true);

      // Verify persistence roundtrip
      final storageJson = dev.toStorageJson();
      final restored = SmartDevice.fromStorageJson(storageJson);
      expect(restored.relays.length, 2);
      expect(restored.relays[0].enabled, true);
      expect(restored.relays[0].switchEnabled, true);
      expect(restored.relays[0].name, 'Socket 1');
      expect(restored.relays[1].enabled, false);
      expect(restored.relays[1].switchEnabled, false);
      expect(restored.relays[1].name, 'Fan');
      expect(restored.relays[1].failsafe, true);
      expect(restored.relays[1].trigger, 1);
    });
  });
}
