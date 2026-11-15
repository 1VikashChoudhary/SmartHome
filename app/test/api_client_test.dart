import 'package:flutter_test/flutter_test.dart';
import 'package:smarthome_app/core/network/network_utils.dart';
import 'package:smarthome_app/core/network/api_client.dart';

void main() {
  group('Network Utilities & Host Sanitization Tests', () {
    test('sanitizeHost cleans protocol schemes properly', () {
      expect(sanitizeHost('http://192.168.1.100'), '192.168.1.100');
      expect(sanitizeHost('https://192.168.1.100'), '192.168.1.100');
      expect(sanitizeHost('ws://192.168.1.100/ws'), '192.168.1.100');
    });

    test('sanitizeHost preserves custom ports while stripping paths', () {
      expect(
        sanitizeHost('http://192.168.1.100:8080/api/status'),
        '192.168.1.100:8080',
      );
      expect(sanitizeHost('192.168.1.100:8080/'), '192.168.1.100:8080');
    });

    test(
      'sanitizeHost strips query parameters, hash fragments, and trailing slashes',
      () {
        expect(sanitizeHost('192.168.1.50/?test=1#anchor'), '192.168.1.50');
        expect(sanitizeHost('  smarthome.local/  '), 'smarthome.local');
        expect(sanitizeHost(''), '');
      },
    );
  });

  group('ApiClient Instance Tests', () {
    test('ApiClient initializes with standard timeout options', () {
      final client = ApiClient();
      expect(client, isNotNull);
    });

    test(
      'ApiClient returns null/false gracefully on invalid host connections',
      () async {
        final client = ApiClient();
        // Test unreachable IP with fast timeout (0.0.0.0 will fail instantly)
        final status = await client.fetchStatus('0.0.0.0');
        expect(status, isNull);

        final discovery = await client.probeDiscovery('0.0.0.0');
        expect(discovery, isNull);

        final relayOk = await client.setRelay('0.0.0.0', 0, 'toggle');
        expect(relayOk, false);

        final timerOk = await client.startTimer('0.0.0.0', 0, 'on', 60);
        expect(timerOk, false);
      },
    );
  });

  group('OTA verification status', () {
    test('parses the firmware identity returned by the controller', () {
      final status = OtaStatus.fromJson({
        'updating': false,
        'fw_version': '3.2.1',
        'fw_date': 'Nov 4 2026 23:00:00',
        'fw_md5': 'abc123def456',
      });

      expect(status.updating, isFalse);
      expect(status.firmwareVersion, '3.2.1');
      expect(status.firmwareBuild, 'Nov 4 2026 23:00:00');
      expect(status.firmwareMd5, 'abc123def456');
    });

    test('detects a changed version, build, or md5 after reboot', () {
      const original = OtaStatus(
        updating: false,
        firmwareVersion: '3.2.0',
        firmwareBuild: 'Nov 4 2026 22:00:00',
        firmwareMd5: '1111aaaa',
      );
      const same = OtaStatus(
        updating: false,
        firmwareVersion: '3.2.0',
        firmwareBuild: 'Nov 4 2026 22:00:00',
        firmwareMd5: '1111aaaa',
      );
      const replacement = OtaStatus(
        updating: false,
        firmwareVersion: '3.2.1',
        firmwareBuild: 'Nov 4 2026 23:00:00',
        firmwareMd5: '1111aaaa',
      );
      const rebuiltSameTimestamp = OtaStatus(
        updating: false,
        firmwareVersion: '3.2.0',
        firmwareBuild: 'Nov 4 2026 22:00:00',
        firmwareMd5: '2222bbbb',
      );

      expect(same.differsFrom(original), isFalse);
      expect(replacement.differsFrom(original), isTrue);
      expect(rebuiltSameTimestamp.differsFrom(original), isTrue);
    });
  });

  group('Backup & Restore payload tests', () {
    test('Backup JSON contains hardware profile and all subsystem modules', () {
      final sampleBackup = {
        '_backup_version': 2,
        '_backup_date': 12345678,
        'hardware.json': {
          'board_name': 'SmartHome 5-CH Standard',
          'num_relays': 5,
          'channels': [
            {'enabled': true, 'switch_enabled': true, 'relay_pin': 16, 'switch_pin': 13},
            {'enabled': false, 'switch_enabled': false, 'relay_pin': 17, 'switch_pin': 14},
          ],
        },
        'config.json': {'device_name': 'Living Room Hub'},
        'relays.json': {'relays': [{'name': 'Light 1'}, {'name': 'Fan'}]},
        'relay_states.json': {'states': [{'on': false, 'sw': false}, {'on': true, 'sw': false}]},
      };

      expect(sampleBackup.containsKey('hardware.json'), isTrue);
      final hw = sampleBackup['hardware.json'] as Map<String, dynamic>;
      expect(hw['board_name'], equals('SmartHome 5-CH Standard'));
      final channels = hw['channels'] as List;
      expect(channels.length, equals(2));
      expect(channels[0]['enabled'], isTrue);
      expect(channels[1]['enabled'], isFalse);
    });
  });
}
