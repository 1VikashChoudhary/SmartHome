import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthome_app/core/models/relay_channel.dart';
import 'package:smarthome_app/core/models/sensor_telemetry.dart';
import 'package:smarthome_app/core/models/smart_device.dart';
import 'package:smarthome_app/core/models/hardware_profile.dart';
import 'package:smarthome_app/core/models/scheduled_alarm.dart';
import 'package:smarthome_app/core/network/ws_client.dart';
import 'package:smarthome_app/core/theme/app_theme.dart';
import 'package:smarthome_app/presentation/screens/device_screen.dart';
import 'package:smarthome_app/presentation/widgets/emergency_alarm_dialog.dart';
import 'package:smarthome_app/services/device_manager.dart';
import 'package:smarthome_app/services/device_storage_service.dart';

class _AlarmDialogTestDeviceManager extends DeviceManager {
  final List<SmartDevice> _devices;

  _AlarmDialogTestDeviceManager(this._devices);

  @override
  List<SmartDevice> build() => _devices;
}

Future<void> _pumpEmergencyDialog(
  WidgetTester tester,
  SmartDevice device,
  String alarmType,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        deviceManagerProvider.overrideWith(
          () => _AlarmDialogTestDeviceManager([device]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: EmergencyAlarmDialog(
            deviceId: device.id,
            alarmType: alarmType,
          ),
        ),
      ),
    ),
  );
  // Advance past initState audible/haptic Future.delayed timers
  await tester.pump(const Duration(seconds: 1));
}

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

    test('Re-arming a completed Delay Countdown alarm clears fired flag and transitions to armed', () {
      final completedAlarm = ScheduledAlarm(
        id: 3,
        enabled: false,
        mode: 1,
        delayMinutes: 1,
        action: 1,
        targetRelay: 0,
        fired: true,
      );

      expect(completedAlarm.nextRunBadge, 'Paused');

      // If toggled ON without clearing fired flag, nextRunBadge wrongly stays 'Completed'
      final buggyArm = completedAlarm.copyWith(enabled: true);
      expect(buggyArm.nextRunBadge, 'Completed');

      // With proper re-arming logic, fired flag is reset to false
      final rearmed = completedAlarm.copyWith(
        enabled: true,
        fired: false,
      );
      expect(rearmed.enabled, true);
      expect(rearmed.fired, false);
      expect(rearmed.nextRunBadge, 'Runs within 1m');
    });
  });

  group('EmergencyAlarmDialog Alert Type Differentiation Regressions', () {
    final testDevice = SmartDevice(
      id: 'dev_alarm_test',
      mac: 'AA:BB:CC:11:22:33',
      ip: '192.168.1.42',
      hostname: 'smarthome-test',
      name: 'Living Room Hub',
      room: 'Living Room',
      isOnline: true,
      telemetry: SensorTelemetry(
        temperature: 48.5,
        tempThreshold: 45.0,
        gasRaw: 620,
        gasPercent: 52,
        gasThreshold: 400,
      ),
    );

    testWidgets('Displays SENSOR HARDWARE FAULT DETECTED for sensor_fault alarm', (
      WidgetTester tester,
    ) async {
      await _pumpEmergencyDialog(tester, testDevice, 'sensor_fault');

      expect(find.text('SENSOR HARDWARE FAULT DETECTED'), findsOneWidget);
      expect(find.textContaining('Climate sensor failed to respond'), findsOneWidget);
      expect(find.byIcon(Icons.sensors_off_rounded), findsOneWidget);
      expect(find.text('HIGH TEMPERATURE ALARM'), findsNothing);
    });

    testWidgets('Displays GAS / SMOKE HAZARD DETECTED for gas alarm', (
      WidgetTester tester,
    ) async {
      await _pumpEmergencyDialog(tester, testDevice, 'gas');

      expect(find.text('GAS / SMOKE HAZARD DETECTED'), findsOneWidget);
      expect(find.textContaining('MQ-2 Gas Sensor: 620 ADC'), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsOneWidget);
    });

    testWidgets('Displays HIGH TEMPERATURE ALARM for temperature alarm', (
      WidgetTester tester,
    ) async {
      await _pumpEmergencyDialog(tester, testDevice, 'temperature');

      expect(find.text('HIGH TEMPERATURE ALARM'), findsOneWidget);
      expect(find.textContaining('Temperature: 48.5°C'), findsOneWidget);
      expect(find.byIcon(Icons.thermostat_rounded), findsOneWidget);
    });
  });

  group('DeviceScreen Dynamic Telemetry Card Tests', () {
    Future<void> pumpDeviceScreen(
      WidgetTester tester,
      SmartDevice device,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deviceManagerProvider.overrideWith(
              () => _TelemetryCardTestDeviceManager(device),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: DeviceScreen(deviceId: device.id),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets(
      'Shows empty state and hides Temp/Humidity/Gas placeholders when 0 sensors configured',
      (WidgetTester tester) async {
        final device = SmartDevice(
          id: 'dev-empty',
          name: 'Office Node',
          hostname: 'smarthome-office',
          ip: '192.168.1.50',
          mac: 'AA:BB:CC:DD:EE:01',
          isOnline: true,
          relays: const [],
          telemetry: SensorTelemetry(
            dhtEnabled: false,
            gasEnabled: false,
            gasHwAllowed: false,
          ),
        );

        await pumpDeviceScreen(tester, device);

        expect(
          find.text('No environmental sensors configured in Hardware Profile.'),
          findsOneWidget,
        );
        expect(find.text('Configure in Hardware Profile'), findsOneWidget);
        expect(find.text('TEMPERATURE'), findsNothing);
        expect(find.text('HUMIDITY'), findsNothing);
        expect(find.text('AIR / GAS'), findsNothing);
      },
    );

    testWidgets(
      'Shows Motion PIR and Overhead Water Tank only when Climate and Gas are absent',
      (WidgetTester tester) async {
        final device = SmartDevice(
          id: 'dev-motion-tank',
          name: 'Basement Node',
          hostname: 'smarthome-basement',
          ip: '192.168.1.51',
          mac: 'AA:BB:CC:DD:EE:02',
          isOnline: true,
          relays: const [],
          telemetry: SensorTelemetry(
            dhtEnabled: false,
            gasEnabled: false,
            gasHwAllowed: false,
            motions: const [
              MotionReading(
                enabled: true,
                label: 'Motion 1',
                detected: true,
              ),
            ],
            tanks: const [
              TankReading(
                enabled: true,
                label: 'Tank 1',
                levelPct: 68,
                distanceCm: 42.5,
              ),
            ],
          ),
        );

        await pumpDeviceScreen(tester, device);

        expect(find.text('MOTION PIR'), findsOneWidget);
        expect(find.text('Overhead Water Tank'), findsOneWidget);
        expect(find.text('68% (42.5 cm)'), findsOneWidget);
        expect(find.text('TEMPERATURE'), findsNothing);
        expect(find.text('HUMIDITY'), findsNothing);
        expect(find.text('AIR / GAS'), findsNothing);
      },
    );

    testWidgets(
      'Displays custom label on single Climate sensor and paused Gas when gasHwAllowed is true',
      (WidgetTester tester) async {
        final device = SmartDevice(
          id: 'dev-custom-climate',
          name: 'Rack Node',
          hostname: 'smarthome-rack',
          ip: '192.168.1.52',
          mac: 'AA:BB:CC:DD:EE:03',
          isOnline: true,
          relays: const [],
          telemetry: SensorTelemetry(
            dhtEnabled: true,
            gasEnabled: false,
            gasHwAllowed: true,
            climates: const [
              ClimateReading(
                enabled: true,
                label: 'Server Rack',
                temperature: 24.5,
                humidity: 48,
              ),
            ],
          ),
        );

        await pumpDeviceScreen(tester, device);

        expect(find.text('SERVER RACK TEMP'), findsOneWidget);
        expect(find.text('SERVER RACK HUMIDITY'), findsOneWidget);
        expect(find.text('AIR / GAS'), findsOneWidget);
        expect(find.text('DISABLED'), findsOneWidget);
        expect(find.text('TEMPERATURE'), findsNothing);
      },
    );

    testWidgets(
      'Renders both active and paused MQ-2 slots when mixed hardware-allowed mq2s exist',
      (WidgetTester tester) async {
        final device = SmartDevice(
          id: 'dev-multi-mq2',
          name: 'Multi Gas Node',
          hostname: 'smarthome-multigas',
          ip: '192.168.1.53',
          mac: 'AA:BB:CC:DD:EE:04',
          isOnline: true,
          relays: const [],
          telemetry: SensorTelemetry(
            dhtEnabled: false,
            gasEnabled: true,
            gasHwAllowed: true,
            mq2s: const [
              Mq2Reading(
                index: 0,
                enabled: true,
                hwAllowed: true,
                label: 'Kitchen Gas',
                raw: 180,
                threshold: 400,
              ),
              Mq2Reading(
                index: 1,
                enabled: false,
                hwAllowed: true,
                label: 'Garage Gas',
                raw: 0,
                threshold: 400,
              ),
            ],
          ),
        );

        await pumpDeviceScreen(tester, device);

        expect(find.text('KITCHEN GAS'), findsOneWidget);
        expect(find.text('SAFE'), findsOneWidget);
        expect(find.text('GARAGE GAS'), findsOneWidget);
        expect(find.text('DISABLED'), findsOneWidget);
        expect(find.text('OFF'), findsOneWidget);
        expect(find.text('TEMPERATURE'), findsNothing);
        expect(find.text('HUMIDITY'), findsNothing);
      },
    );
  });

  group('AP Roaming Recovery & Connection Resilience Regressions', () {
    HttpOverrides? previousHttpOverrides;

    setUp(() {
      previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    tearDown(() {
      HttpOverrides.global = previousHttpOverrides;
    });

    test(
      'refreshAllDevices(skipHealthyWs: true) polls offline device, retries transient failure, and sends Connection: close',
      () async {
        var statusAttempts = 0;
        final connectionHeaders = <String?>[];
        var wsUpgrades = 0;

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final sockets = <WebSocket>[];
        server.listen((request) async {
          if (request.uri.path == '/ws' &&
              WebSocketTransformer.isUpgradeRequest(request)) {
            wsUpgrades++;
            final ws = await WebSocketTransformer.upgrade(request);
            sockets.add(ws);
            ws.listen((msg) {
              if (ws.closeCode != null) return;
              final decoded = jsonDecode(msg as String);
              if (decoded is Map && decoded['type'] == 'subscribe') {
                ws.add(
                  jsonEncode({
                    'type': 'status',
                    'device_name': 'Bedroom',
                    'mac': 'AA:BB:CC:DD:EE:99',
                    'relays': const [],
                  }),
                );
              }
            });
            return;
          }

          if (request.uri.path == '/api/status') {
            statusAttempts++;
            connectionHeaders.add(request.headers.value('connection'));
            if (statusAttempts == 1) {
              // Simulate a transient first-packet failure during AP handoff
              request.response.statusCode = HttpStatus.serviceUnavailable;
              await request.response.close();
              return;
            }
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'device_name': 'Bedroom',
                'mac': 'AA:BB:CC:DD:EE:99',
                'fw_version': '1.1.0',
                'relays': const [],
              }),
            );
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        final offlineDevice = SmartDevice(
          id: 'AA:BB:CC:DD:EE:99',
          mac: 'AA:BB:CC:DD:EE:99',
          ip: '127.0.0.1:${server.port}',
          hostname: 'smarthome-bedroom',
          name: 'Bedroom',
          isOnline: false,
          lastSeen: DateTime.now(),
        );

        final container = ProviderContainer(
          overrides: [
            deviceManagerProvider.overrideWith(
              () => _RoamingTestDeviceManager([offlineDevice]),
            ),
          ],
        );
        addTearDown(() async {
          container.read(deviceManagerProvider.notifier).stopForegroundSync();
          for (final ws in sockets) {
            await ws.close();
          }
          container.dispose();
        });

        final manager = container.read(deviceManagerProvider.notifier);
        await manager.refreshAllDevices(skipHealthyWs: true);

        final recovered = container.read(deviceManagerProvider).single;
        expect(statusAttempts, 2);
        expect(connectionHeaders, everyElement('close'));
        expect(recovered.isOnline, isTrue);

        // Verify refreshDevice recovers live WebSocket telemetry promptly.
        await manager.refreshDevice(recovered.id);
        final deadline = DateTime.now().add(const Duration(seconds: 2));
        while (wsUpgrades == 0 && DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 20));
        }
        expect(wsUpgrades, greaterThanOrEqualTo(1));
      },
    );

    test(
      'DeviceWebSocketClient.reconnectNow resets backoff and reconnects cleanly',
      () async {
        var wsConnectCount = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final sockets = <WebSocket>[];
        server.listen((request) async {
          if (request.uri.path == '/ws' &&
              WebSocketTransformer.isUpgradeRequest(request)) {
            wsConnectCount++;
            final ws = await WebSocketTransformer.upgrade(request);
            sockets.add(ws);
            ws.listen((msg) {
              if (ws.closeCode != null) return;
              final decoded = jsonDecode(msg as String);
              if (decoded is Map && decoded['type'] == 'subscribe') {
                ws.add(
                  jsonEncode({
                    'type': 'status',
                    'device_name': 'Bedroom',
                    'mac': 'AA:BB:CC:DD:EE:88',
                    'relays': const [],
                  }),
                );
              }
            });
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        });

        final connectedCompleter1 = Completer<void>();
        final connectedCompleter2 = Completer<void>();
        late DeviceWebSocketClient client;

        client = DeviceWebSocketClient(
          ip: '127.0.0.1:${server.port}',
          onData: (_) {},
          onConnectionChange: (isConnected) {
            if (isConnected) {
              if (!connectedCompleter1.isCompleted) {
                connectedCompleter1.complete();
              } else if (wsConnectCount >= 2 &&
                  !connectedCompleter2.isCompleted) {
                connectedCompleter2.complete();
              }
            }
          },
        );
        addTearDown(() async {
          client.dispose();
          for (final ws in sockets) {
            await ws.close();
          }
        });

        client.connect();
        await connectedCompleter1.future.timeout(const Duration(seconds: 3));
        expect(client.isConnected, isTrue);
        expect(wsConnectCount, 1);

        client.reconnectNow();
        await connectedCompleter2.future.timeout(const Duration(seconds: 3));
        expect(wsConnectCount, 2);
        expect(client.isConnected, isTrue);
      },
    );

    test(
      'startForegroundSync and refreshDevice preserve healthy WebSocket without tearing down handshake',
      () async {
        var wsUpgrades = 0;
        final firstWsFrameServed = Completer<void>();

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final sockets = <WebSocket>[];
        server.listen((request) async {
          if (request.uri.path == '/ws' &&
              WebSocketTransformer.isUpgradeRequest(request)) {
            wsUpgrades++;
            final ws = await WebSocketTransformer.upgrade(request);
            sockets.add(ws);
            ws.listen((msg) {
              if (ws.closeCode != null) return;
              final decoded = jsonDecode(msg as String);
              if (decoded is Map && decoded['type'] == 'subscribe') {
                ws.add(
                  jsonEncode({
                    'type': 'status',
                    'device_name': 'Bedroom',
                    'mac': 'AA:BB:CC:DD:EE:77',
                    'relays': const [],
                  }),
                );
                if (!firstWsFrameServed.isCompleted) {
                  firstWsFrameServed.complete();
                }
              }
            });
            return;
          }

          if (request.uri.path == '/api/status') {
            await Future.delayed(const Duration(milliseconds: 60));
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'device_name': 'Bedroom',
                'mac': 'AA:BB:CC:DD:EE:77',
                'fw_version': '1.1.0',
                'relays': const [],
              }),
            );
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        });

        final initialOffline = SmartDevice(
          id: 'AA:BB:CC:DD:EE:77',
          mac: 'AA:BB:CC:DD:EE:77',
          ip: '127.0.0.1:${server.port}',
          hostname: 'smarthome-bedroom',
          name: 'Bedroom',
          isOnline: false,
          lastSeen: DateTime.now(),
        );

        final container = ProviderContainer(
          overrides: [
            deviceManagerProvider.overrideWith(
              () => _RoamingTestDeviceManager([initialOffline]),
            ),
          ],
        );
        addTearDown(() async {
          container.read(deviceManagerProvider.notifier).stopForegroundSync();
          for (final ws in sockets) {
            await ws.close();
          }
          container.dispose();
        });

        final manager = container.read(deviceManagerProvider.notifier);
        await manager.startForegroundSync();
        await firstWsFrameServed.future.timeout(const Duration(seconds: 3));
        await Future.delayed(const Duration(milliseconds: 50));

        expect(wsUpgrades, 1);
        expect(container.read(deviceManagerProvider).single.isOnline, isTrue);

        // Calling refreshDevice / refreshAllDevices must not kill the healthy WS.
        await manager.refreshDevice(initialOffline.id);
        await manager.refreshAllDevices();
        await Future.delayed(const Duration(milliseconds: 50));
        expect(wsUpgrades, 1);
      },
    );
  });
}

class _RoamingTestDeviceManager extends DeviceManager {
  final List<SmartDevice> _initial;
  _RoamingTestDeviceManager(this._initial);

  @override
  List<SmartDevice> build() => _initial;
}

class _TelemetryCardTestDeviceManager extends DeviceManager {
  final SmartDevice initialDevice;
  _TelemetryCardTestDeviceManager(this.initialDevice);

  @override
  List<SmartDevice> build() => [initialDevice];

  @override
  Future<List<RelayChannel>?> fetchDeviceRelays(String deviceId) async => null;

  @override
  Future<Map<String, dynamic>?> fetchDeviceConfig(String deviceId) async =>
      null;
}
