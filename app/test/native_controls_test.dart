import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthome_app/core/models/relay_channel.dart';
import 'package:smarthome_app/core/models/smart_device.dart';
import 'package:smarthome_app/presentation/widgets/quick_controls_sheet.dart';
import 'package:smarthome_app/presentation/widgets/relay_tile.dart';
import 'package:smarthome_app/services/device_manager.dart';
import 'package:smarthome_app/services/native_controls_service.dart';

class _StubDeviceManager extends DeviceManager {
  final List<SmartDevice> seedDevices;
  _StubDeviceManager(this.seedDevices);

  @override
  List<SmartDevice> build() => seedDevices;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeControlsService & QuickControlsSheet', () {
    test('serializeDevices and buildSyncSignature track relay & credential changes', () {
      final devA = SmartDevice(
        id: 'dev_1',
        mac: 'AA:BB:CC:DD:EE:01',
        ip: '192.168.1.50',
        hostname: 'bedroom',
        name: 'Bedroom',
        room: 'Bedroom Room',
        authUsername: 'admin',
        authPassword: 'secret',
        relays: [
          RelayChannel(index: 0, name: 'Light', state: false, iconType: 'light'),
          RelayChannel(index: 1, name: 'Fan', state: true, iconType: 'fan'),
        ],
      );

      final map = NativeControlsService.serializeDevices([devA]).single;
      expect(map['id'], 'dev_1');
      expect(map['room'], 'Bedroom Room');
      expect(map['authPassword'], 'secret');
      expect(map['authLocked'], false);
      final relays = map['relays'] as List;
      expect(relays.length, 2);
      expect(relays[1]['icon'], 'fan');
      expect(relays[1]['state'], true);

      final sig1 = NativeControlsService.buildSyncSignature([devA]);
      final devB = devA.copyWith(
        relays: [
          devA.relays[0].copyWith(state: true),
          devA.relays[1],
        ],
      );
      final sig2 = NativeControlsService.buildSyncSignature([devB]);
      expect(sig1, isNot(equals(sig2)));
    });

    testWidgets('QuickControlsSheet lists 12 tiles and assigns/auto-assigns via MethodChannel', (tester) async {
      SharedPreferences.setMockInitialValues({});
      const channel = MethodChannel('com.smarthome.smarthome_app/native_controls');
      final Map<int, Map<String, dynamic>> storedSlots = {};
      final List<String> calls = [];

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'getPlatformCapabilities':
            return {
              'supportsQuickTiles': true,
              'supportsDeviceControls': true,
              'apiLevel': 34,
              'maxTileSlots': 12,
            };
          case 'getTileSlots':
            return List.generate(12, (i) {
              final s = i + 1;
              final item = storedSlots[s];
              return {
                'slot': s,
                'deviceId': item?['deviceId'],
                'relayId': item?['relayId'],
                'customLabel': item?['customLabel'],
              };
            });
          case 'setTileSlot':
            final args = Map<dynamic, dynamic>.from(call.arguments as Map);
            final slot = (args['slot'] as num).toInt();
            storedSlots[slot] = {
              'deviceId': args['deviceId'],
              'relayId': args['relayId'],
              'customLabel': args['customLabel'],
            };
            return true;
          case 'autoAssignTileSlots':
            storedSlots[1] = {'deviceId': 'dev_1', 'relayId': 0, 'customLabel': null};
            storedSlots[2] = {'deviceId': 'dev_1', 'relayId': 1, 'customLabel': null};
            return 2;
          default:
            return true;
        }
      });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final seeded = [
        SmartDevice(
          id: 'dev_1',
          mac: 'AA:BB:CC:DD:EE:01',
          ip: '192.168.1.50',
          hostname: 'bedroom',
          name: 'Bedroom',
          room: 'Bedroom',
          relays: [
            RelayChannel(index: 0, name: 'Light', state: false, iconType: 'light'),
            RelayChannel(index: 1, name: 'Fan', state: true, iconType: 'fan'),
          ],
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceManagerProvider.overrideWith(() => _StubDeviceManager(seeded)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () => QuickControlsSheet.show(
                    ctx,
                    prefillDeviceId: 'dev_1',
                    prefillRelayId: 1,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Pin "Fan" to Tile'), findsOneWidget);
      expect(find.text('Tile 1 (Unassigned)'), findsOneWidget);

      await tester.tap(find.text('Tile 1 (Unassigned)'));
      await tester.pumpAndSettle();

      expect(storedSlots[1]?['relayId'], 1);
      expect(find.textContaining('Pinned "Fan" to Quick Settings Tile 1.'), findsOneWidget);
    });

    testWidgets('RelayTile options sheet exposes Pin to Quick Settings Tile action', (tester) async {
      bool pinned = false;
      final relay = RelayChannel(index: 0, name: 'Ceiling Light', state: true, iconType: 'light');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                height: 180,
                child: RelayTile(
                  relay: relay,
                  deviceName: 'Bedroom',
                  onToggle: () {},
                  onStartTimer: (_, _) {},
                  onCancelTimer: () {},
                  onSettings: () {},
                  onPinToQuickTile: () => pinned = true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.longPress(find.byType(RelayTile));
      await tester.pumpAndSettle();

      expect(find.text('Pin to Quick Settings Tile'), findsOneWidget);
      await tester.tap(find.text('Pin to Quick Settings Tile'));
      await tester.pumpAndSettle();
      expect(pinned, isTrue);
    });
  });
}
