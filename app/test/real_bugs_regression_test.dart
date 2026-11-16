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
import 'package:smarthome_app/core/models/automation_rule.dart';
import 'package:smarthome_app/core/models/hardware_profile.dart';
import 'package:smarthome_app/core/models/scheduled_alarm.dart';
import 'package:smarthome_app/core/network/api_client.dart';
import 'package:smarthome_app/core/network/ws_client.dart';
import 'package:smarthome_app/core/theme/app_theme.dart';
import 'package:smarthome_app/presentation/screens/device_screen.dart';
import 'package:smarthome_app/presentation/screens/home_screen.dart';
import 'package:smarthome_app/presentation/widgets/emergency_alarm_dialog.dart';
import 'package:smarthome_app/presentation/widgets/hardware_config_sheet.dart';
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

    test('parses rem_sec and computes live second-by-second countdown and progress', () {
      final t0 = DateTime(2026, 11, 15, 18, 0, 0);
      final parsed = ScheduledAlarm.fromJson({
        'id': 9,
        'en': true,
        'mode': 1,
        'delay': 10,
        'action': 0,
        'relay': 0,
        'fired': false,
        'rem_sec': 595,
      });
      expect(parsed.remainingSeconds, 595);

      final anchored = parsed.copyWith(fetchedAt: t0);
      expect(anchored.liveRemainingAt(t0), 595);
      expect(anchored.liveRemainingAt(t0.add(const Duration(seconds: 25))), 570);
      expect(anchored.liveRemainingAt(t0.add(const Duration(seconds: 700))), 0);
      expect(anchored.liveRemainingAt(t0.subtract(const Duration(seconds: 5))), 595);
      expect(anchored.formattedCountdownAt(t0), '9m 55s');
      expect(anchored.countdownProgressAt(t0), closeTo(595 / 600, 0.001));

      // Disabled or fired delay timers stop counting down
      expect(anchored.copyWith(enabled: false).liveRemainingAt(t0), 0);
      expect(anchored.copyWith(fired: true).liveRemainingAt(t0), 0);
      expect(anchored.copyWith(enabled: false).countdownProgressAt(t0), isNull);
    });

    test('supports rem_sec live countdown for clock schedules and formats Xh Ym Zs', () {
      final t0 = DateTime(2026, 11, 15, 18, 0, 0);
      final clockFromEsp = ScheduledAlarm(
        id: 10,
        enabled: true,
        mode: 0,
        type: 1,
        hour: 19,
        minute: 2,
        remainingSeconds: 3725, // 1h 2m 5s
        fetchedAt: t0,
      );
      expect(clockFromEsp.liveRemainingAt(t0), 3725);
      expect(clockFromEsp.liveRemainingAt(t0.add(const Duration(seconds: 10))), 3715);
      expect(clockFromEsp.formattedCountdownAt(t0), '1h 2m 5s');
      expect(ScheduledAlarm.formatDurationSeconds(0), '0s');
      expect(ScheduledAlarm.formatDurationSeconds(45), '45s');
      expect(ScheduledAlarm.formatDurationSeconds(595), '9m 55s');
      expect(ScheduledAlarm.formatDurationSeconds(3725), '1h 2m 5s');

      // Legacy clock fallback without rem_sec computes remaining seconds locally
      final legacyClock = ScheduledAlarm(
        id: 11,
        enabled: true,
        mode: 0,
        type: 1,
        hour: 18,
        minute: 1,
      );
      expect(legacyClock.liveRemainingAt(t0), 60);

      // Existing nextRunBadge behavior preserved
      final delayBadge = ScheduledAlarm(
        id: 12,
        enabled: true,
        mode: 1,
        delayMinutes: 75,
        remainingSeconds: 4500,
      );
      expect(delayBadge.nextRunBadge, 'Runs within 1h 15m');
      expect(delayBadge.copyWith(enabled: false).nextRunBadge, 'Paused');
      expect(delayBadge.copyWith(fired: true).nextRunBadge, 'Completed');
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

    testWidgets('Displays VOC AIR QUALITY HAZARD DETECTED for SGP40 VOC alarm', (
      WidgetTester tester,
    ) async {
      final vocDevice = SmartDevice(
        id: 'dev_voc_alarm',
        mac: 'AA:BB:CC:11:22:99',
        ip: '192.168.1.43',
        hostname: 'smarthome-voc',
        name: 'Bedroom Hub',
        room: 'Bedroom',
        isOnline: true,
        telemetry: SensorTelemetry(
          gasRaw: 340,
          gasPercent: 68,
          gasThreshold: 250,
          gasMax: 500,
          gasUnit: 'VOC',
          gasEnabled: true,
          gasAlarm: true,
        ),
      );
      await _pumpEmergencyDialog(tester, vocDevice, 'gas');

      expect(find.text('VOC AIR QUALITY HAZARD DETECTED'), findsOneWidget);
      expect(find.textContaining('SGP40 VOC Sensor: 340 VOC'), findsOneWidget);
      expect(find.textContaining('Limit: 250 VOC'), findsOneWidget);
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

  group('Additional Sensors (SHT40/SHT45, DS18B20 Climate, SGP40 VOC) Regressions', () {
    test(
      'ClimateSensorType enum & slot serialization support SHT40/SHT45 and DS18B20',
      () {
        final sht4x = ClimateSensorType.fromValue(6);
        expect(sht4x, ClimateSensorType.sht4x);
        expect(sht4x.isI2c, isTrue);
        expect(sht4x.isOneWire, isFalse);
        expect(sht4x.hasHumidity, isTrue);
        expect(sht4x.allowedI2cAddrs, [0x44, 0x45]);
        expect(sht4x.defaultI2cAddr, 0x44);

        final ds = ClimateSensorType.fromValue(7);
        expect(ds, ClimateSensorType.ds18b20);
        expect(ds.isI2c, isFalse);
        expect(ds.isOneWire, isTrue);
        expect(ds.hasHumidity, isFalse);
        expect(ds.allowedI2cAddrs, isEmpty);

        const shtSlot = ClimateSensorSlotConfig(
          type: ClimateSensorType.sht4x,
          pin: 255,
          i2cAddr: 0x45,
          label: 'Office',
        );
        final shtJson = shtSlot.toJson();
        expect(shtJson['type'], 6);
        expect(shtJson['pin'], 255);
        expect(shtJson['i2c_addr'], 0x45);
        expect(ClimateSensorSlotConfig.fromJson(shtJson).type, ClimateSensorType.sht4x);

        const dsSlot = ClimateSensorSlotConfig(
          type: ClimateSensorType.ds18b20,
          pin: 14,
          i2cAddr: 0x44,
          label: 'Ambient',
        );
        final dsJson = dsSlot.toJson();
        expect(dsJson['type'], 7);
        expect(dsJson['pin'], 14);
        expect(dsJson['i2c_addr'], 0);
        expect(ClimateSensorSlotConfig.fromJson(dsJson).type, ClimateSensorType.ds18b20);
      },
    );

    test(
      'GasSensorType SGP40 triggers hasAnyI2cSensor and strips analog/digital pins',
      () {
        final sgp = GasSensorType.fromValue(1);
        expect(sgp, GasSensorType.sgp40);
        expect(sgp.isI2c, isTrue);

        final parsedSgp = Mq2SensorSlotConfig.fromJson({
          'type': 1,
          'enabled': true,
          'analog_pin': 34,
          'digital_pin': 35,
          'label': 'VOC',
        });
        expect(parsedSgp.type, GasSensorType.sgp40);
        expect(parsedSgp.analogPin, 255);
        expect(parsedSgp.digitalPin, 255);
        expect(parsedSgp.i2cAddr, 0x59);
        expect(parsedSgp.toJson()['i2c_addr'], 0x59);

        final profileEnabled = HardwareProfile(
          boardName: 'Test',
          numRelays: 1,
          channels: const [
            ChannelHardwareConfig(enabled: true, switchEnabled: false, relayPin: 16, switchPin: 255),
          ],
          climates: const [
            ClimateSensorSlotConfig(type: ClimateSensorType.ds18b20, pin: 4),
          ],
          mq2Sensors: [parsedSgp],
          lcdEnabled: false,
        );
        expect(profileEnabled.hasAnyI2cSensor, isTrue);

        final profileDisabled = profileEnabled.copyWith(
          mq2Sensors: [parsedSgp.copyWith(enabled: false)],
        );
        expect(profileDisabled.hasAnyI2cSensor, isFalse);
      },
    );

    test(
      'SensorTelemetry parses DS18B20 humidity_enabled=false and SGP40 VOC telemetry',
      () {
        final telemetry = SensorTelemetry.fromJson({
          'temperature': 26.5,
          'humidity': 0,
          'dht_enabled': true,
          'humidity_enabled': false,
          'gas_raw': 135,
          'gas_percent': 27,
          'gas_threshold': 250,
          'gas_max': 500,
          'gas_unit': 'VOC',
          'gas_enabled': true,
          'gas_hw_allowed': true,
          'climates': [
            {
              'index': 0,
              'enabled': true,
              'type': 7,
              'type_name': 'DS18B20',
              'temperature': 26.5,
              'humidity': 0,
              'humidity_enabled': false,
              'fault': false,
            },
          ],
          'mq2s': [
            {
              'index': 0,
              'type': 1,
              'type_name': 'SGP40',
              'i2c_addr': 89,
              'enabled': true,
              'hw_allowed': true,
              'unit': 'VOC',
              'gas_max': 500,
              'raw': 135,
              'percent': 27,
              'threshold': 250,
              'alarm': false,
              'warming': false,
            },
          ],
        });

        expect(telemetry.humidityEnabled, isFalse);
        expect(telemetry.climates.single.humidityEnabled, isFalse);
        expect(telemetry.gasUnit, 'VOC');
        expect(telemetry.gasMax, 500);
        expect(telemetry.mq2s.single.isSgp40, isTrue);
        expect(telemetry.mq2s.single.typeName, 'SGP40');
        expect(telemetry.mq2s.single.unit, 'VOC');
        expect(telemetry.mq2s.single.gasMax, 500);
        expect(telemetry.mq2s.single.threshold, 250);
      },
    );
  });

  group('HardwareConfigSheet I2C Auto-Assignment Regressions', () {
    testWidgets(
      'Switching Slot #2 to SHT3x auto-selects 0x45 when Slot #1 uses SHT40 at 0x44 and moves I2C SDA/SCL off occupied Relay GPIOs 4 & 5',
      (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final fakeApi = _HwSheetFakeApiClient(
          const HardwareProfile(
            boardName: 'SmartHome ESP8266 Custom DIY',
            numRelays: 2,
            channels: [
              ChannelHardwareConfig(
                enabled: true,
                switchEnabled: true,
                relayPin: 5,
                switchPin: 13,
              ),
              ChannelHardwareConfig(
                enabled: true,
                switchEnabled: true,
                relayPin: 4,
                switchPin: 16,
              ),
            ],
            climates: [
              ClimateSensorSlotConfig(
                type: ClimateSensorType.sht4x,
                pin: 255,
                i2cAddr: 0x44,
              ),
              ClimateSensorSlotConfig(
                type: ClimateSensorType.dht22,
                pin: 12,
                i2cAddr: 0,
              ),
            ],
            mq2Sensors: [],
            buzzerEnabled: true,
            buzzerPin: 2,
            lcdEnabled: false,
            i2cSdaPin: 4,
            i2cSclPin: 5,
            btnMultiPin: 0,
          ),
        );

        final esp8266Dev = SmartDevice(
          id: 'dev_8266_i2c_auto',
          mac: 'AA:BB:CC:11:22:99',
          ip: '192.168.29.143',
          hostname: 'smarthome-1848',
          name: 'Office',
          platform: 'ESP8266',
          numRelays: 2,
          authRequired: true,
          authRole: 'admin',
          authUsername: 'admin',
          authPassword: 'secret',
        );

        final container = ProviderContainer();
        addTearDown(container.dispose);
        final provider = NotifierProvider<DeviceManager, List<SmartDevice>>(
          () => _HwSheetTestDeviceManager([esp8266Dev], fakeApi),
        );
        final manager = container.read(provider.notifier);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: HardwareConfigSheet(device: esp8266Dev, manager: manager),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final vertScroll = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ).first;

        // Switch Slot #2 (index 1) from DHT22 (2) to SHT31 / SHT3x (5)
        final slot2Type = find.byKey(const ValueKey('climate_type_1_2'));
        await tester.scrollUntilVisible(slot2Type, 200, scrollable: vertScroll);
        await tester.pumpAndSettle();
        await tester.tap(slot2Type);
        await tester.pumpAndSettle();
        await tester.tap(find.text(ClimateSensorType.sht31.label).last);
        await tester.pumpAndSettle();

        // Slot #2 auto-selected unused 0x45 instead of colliding with Slot #1's 0x44
        expect(find.byKey(const ValueKey('climate_addr_1_69')), findsOneWidget);

        // Shared I2C SDA & SCL dropdowns appear directly inside both I2C climate sensor cards
        final sdaInCard = find.text('I2C SDA Pin (Shared)');
        final sclInCard = find.text('I2C SCL Pin (Shared)');
        await tester.scrollUntilVisible(sdaInCard.last, 150, scrollable: vertScroll);
        await tester.pumpAndSettle();
        expect(sdaInCard, findsNWidgets(2));
        expect(sclInCard, findsNWidgets(2));

        // Customize shared bus pins directly from inside the I2C sensor card (SDA -> GPIO 14, SCL -> GPIO 12)
        await tester.tap(
          find.ancestor(
            of: sdaInCard.last,
            matching: find.bySubtype<DropdownButtonFormField<int>>(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('GPIO 14 (D5)').last);
        await tester.pumpAndSettle();

        await tester.tap(
          find.ancestor(
            of: sclInCard.last,
            matching: find.bySubtype<DropdownButtonFormField<int>>(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('GPIO 12 (D6)').last);
        await tester.pumpAndSettle();

        // Save button is enabled because I2C SDA/SCL are free and non-conflicting
        await tester.tap(find.text('Save & Reboot Controller'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save & Reboot'));
        await tester.pumpAndSettle();

        final saved = fakeApi.lastSavedProfile;
        expect(saved, isNotNull);
        expect(saved!.climates[0].type, ClimateSensorType.sht4x);
        expect(saved.climates[0].i2cAddr, 0x44);
        expect(saved.climates[1].type, ClimateSensorType.sht31);
        expect(saved.climates[1].i2cAddr, 0x45);
        expect(saved.i2cSdaPin, 14);
        expect(saved.i2cSclPin, 12);
      },
    );

    testWidgets(
      'Re-enabling Light Sensor #2 (BH1750) auto-selects 0x5C when Light Sensor #1 uses 0x23',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(480, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final fakeApi = _HwSheetFakeApiClient(
          const HardwareProfile(
            boardName: 'SmartHome Light Test',
            numRelays: 1,
            channels: [
              ChannelHardwareConfig(
                enabled: true,
                switchEnabled: false,
                relayPin: 16,
                switchPin: 255,
              ),
            ],
            climates: [],
            lights: [
              LightSensorSlotConfig(
                type: LightSensorType.bh1750,
                i2cAddr: 0x23,
              ),
              LightSensorSlotConfig(
                type: LightSensorType.none,
                i2cAddr: 0,
              ),
            ],
            lcdEnabled: false,
            buzzerEnabled: false,
            i2cSdaPin: 21,
            i2cSclPin: 22,
            btnMultiPin: 33,
          ),
        );
        final device = SmartDevice(
          id: 'dev_lgt_auto',
          mac: 'AA:BB:CC:22:33:55',
          ip: '192.168.1.90',
          hostname: 'smarthome-lgt',
          name: 'Porch Node',
          platform: 'ESP32',
          numRelays: 1,
          isOnline: true,
        );
        final manager = _HwSheetTestDeviceManager([device], fakeApi);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: HardwareConfigSheet(device: device, manager: manager),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final vertScroll = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first;

        final lightModel2 = find.byKey(const ValueKey('light_type_1_0'));
        await tester.scrollUntilVisible(
          lightModel2,
          200,
          scrollable: vertScroll,
        );
        await tester.pumpAndSettle();

        await tester.tap(lightModel2);
        await tester.pumpAndSettle();
        await tester.tap(find.text(LightSensorType.bh1750.label).last);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('light_addr_1_92')), findsOneWidget);

        await tester.tap(find.text('Save & Reboot Controller'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save & Reboot'));
        await tester.pumpAndSettle();

        final saved = fakeApi.lastSavedProfile;
        expect(saved, isNotNull);
        expect(saved!.lights.length, 2);
        expect(saved.lights[0].i2cAddr, 0x23);
        expect(saved.lights[1].type, LightSensorType.bh1750);
        expect(saved.lights[1].i2cAddr, 0x5C);
      },
    );

    testWidgets(
      'HomeScreen hides humidity pill for DS18B20 and displays SGP40 VOC reading in gas banner',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final device = SmartDevice(
          id: 'dev_ds_sgp_home',
          mac: 'AA:BB:CC:22:33:66',
          ip: '192.168.1.91',
          hostname: 'smarthome-home',
          name: 'Utility Room',
          platform: 'ESP32',
          numRelays: 1,
          isOnline: true,
          telemetry: SensorTelemetry(
            dhtEnabled: true,
            dhtFault: false,
            humidityEnabled: false,
            temperature: 24.5,
            humidity: 0.0,
            climates: const [
              ClimateReading(
                index: 0,
                enabled: true,
                type: 7,
                typeName: 'DS18B20',
                temperature: 24.5,
                humidity: 0.0,
                humidityEnabled: false,
              ),
            ],
            gasRaw: 340,
            gasPercent: 68,
            gasThreshold: 250,
            gasMax: 500,
            gasUnit: 'VOC',
            gasEnabled: true,
            gasAlarm: true,
          ),
        );

        final manager = _AlarmDialogTestDeviceManager([device]);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              deviceManagerProvider.overrideWith(() => manager),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: const HomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('24.5°'), findsWidgets);
        expect(find.text('0%'), findsNothing);
        expect(
          find.textContaining('SGP40 VOC Reading: 340 VOC'),
          findsOneWidget,
        );
      },
    );
  });

  group('Backup & Restore Regressions', () {
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
      'Hub exportHubBackupJson and importHubBackupJson round-trip devices, rooms, icons, and secure credentials',
      () async {
        final storage = DeviceStorageService();
        final secure = const FlutterSecureStorage();

        await storage.saveRooms(['Bedroom', 'Office', 'Terrace']);
        await storage.saveMonitoringDeviceId('dev_hub_1');
        await storage.saveMonitoringLiveMode(false);

        final device = SmartDevice(
          id: 'dev_hub_1',
          mac: 'AA:BB:CC:11:22:33',
          ip: '192.168.29.105',
          hostname: 'smarthome-bedroom',
          name: 'Bedroom',
          room: 'Bedroom',
          fwVersion: '1.1.0',
          numRelays: 2,
          authRequired: true,
          authRole: 'admin',
          authUsername: 'admin',
          authPassword: 'hub_secret_password',
          relays: [
            RelayChannel(index: 0, name: 'Fan', state: false, iconType: 'fan'),
            RelayChannel(
              index: 1,
              name: 'Ceiling Light',
              state: true,
              iconType: 'light',
            ),
          ],
        );

        final exported = await storage.exportHubBackupJson([device]);
        final decoded = jsonDecode(exported) as Map<String, dynamic>;
        expect(decoded['type'], 'smarthome_pro_hub_backup');

        // Wipe local storage to simulate restoring on a fresh device
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});

        // Reject controller backup in Hub restore
        final invalid = await storage.importHubBackupJson(
          jsonEncode({
            '_backup_version': 1,
            'config.json': {'device_name': 'Bedroom'},
          }),
        );
        expect(invalid, isNull);

        final restored = await storage.importHubBackupJson(exported);
        expect(restored, isNotNull);
        expect(restored!.length, 1);
        expect(restored.first.name, 'Bedroom');
        expect(restored.first.relays[0].iconType, 'fan');
        expect(await storage.loadRooms(), ['Bedroom', 'Office', 'Terrace']);
        expect(await storage.loadMonitoringDeviceId(), 'dev_hub_1');
        expect(await storage.loadMonitoringLiveMode(), isFalse);
        expect(
          await secure.read(key: 'smarthome_device_pass_dev_hub_1'),
          'hub_secret_password',
        );

        final reloaded = await storage.loadDevices();
        expect(reloaded.length, 1);
        expect(reloaded.first.authPassword, 'hub_secret_password');
      },
    );

    test(
      'restoreBackup sends full controller payload and syncs device_name locally without redundant POST /api/config',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        final requestedPaths = <String>[];
        Map<String, dynamic>? receivedRestoreBody;

        server.listen((request) async {
          requestedPaths.add('${request.method} ${request.uri.path}');
          final raw = await utf8.decoder.bind(request).join();
          if (request.uri.path == '/api/restore') {
            receivedRestoreBody = jsonDecode(raw) as Map<String, dynamic>;
            request.response.statusCode = HttpStatus.ok;
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'status': 'ok'}));
          } else {
            request.response.statusCode = HttpStatus.notFound;
          }
          await request.response.close();
        });

        final initialDev = SmartDevice(
          id: 'dev_restore_1',
          mac: 'AA:BB:CC:44:55:66',
          ip: '127.0.0.1:${server.port}',
          hostname: 'smarthome',
          name: 'Old Name',
          platform: 'ESP32',
        );

        final container = ProviderContainer();
        addTearDown(container.dispose);
        final provider = NotifierProvider<DeviceManager, List<SmartDevice>>(
          () => _RoamingTestDeviceManager([initialDev]),
        );
        final manager = container.read(provider.notifier);

        final backupPayload = jsonEncode({
          '_backup_version': 2,
          'config.json': {'device_name': 'Restored Bedroom'},
          'hardware.json': {
            'climates': [
              {'type': 6, 'i2c_addr': 0x44, 'label': 'SHT40'},
              {'type': 7, 'pin': 4, 'label': 'DS18B20'},
            ],
            'mq2_sensors': [
              {'enabled': true, 'type': 1, 'i2c_addr': 0x59, 'label': 'SGP40'},
            ],
            'lcd': {'enabled': false, 'sda_pin': 21, 'scl_pin': 22},
          },
          'alarms.json': {
            'alarms': [
              {
                'id': 1,
                'en': true,
                'mode': 1,
                'delay': 10,
                'created': 1794744000,
                'act': 0,
                'relay': 0,
                'fired': false,
              },
            ],
          },
        });

        final ok = await manager.restoreBackup(initialDev.id, backupPayload);
        expect(ok, isTrue);
        expect(requestedPaths, ['POST /api/restore']);
        expect(receivedRestoreBody, isNotNull);
        expect(
          (receivedRestoreBody!['hardware.json'] as Map)['mq2_sensors'],
          hasLength(1),
        );
        expect(container.read(provider).first.name, 'Restored Bedroom');
      },
    );

    test(
      'AutomationRule resolves SGP40 VOC unit and ceiling per gas slot instead of hardcoding ADC',
      () {
        final telemetry = SensorTelemetry.fromJson({
          'mq2s': [
            {
              'index': 0,
              'type': 0,
              'type_name': 'MQ-2',
              'unit': 'ADC',
              'gas_max': 4095,
              'enabled': true,
              'hw_allowed': true,
              'raw': 180,
            },
            {
              'index': 1,
              'type': 1,
              'type_name': 'SGP40',
              'unit': 'VOC',
              'gas_max': 500,
              'enabled': true,
              'hw_allowed': true,
              'raw': 210,
            },
          ],
        });

        final mq2Spec = AutomationRule.gasSpecFor(telemetry, 0);
        final sgpSpec = AutomationRule.gasSpecFor(telemetry, 1);
        expect(mq2Spec.unit, 'ADC');
        expect(mq2Spec.maxVal, 4095.0);
        expect(sgpSpec.unit, 'VOC');
        expect(sgpSpec.maxVal, 500.0);
        expect(sgpSpec.defaultThreshold, 250.0);

        final sgpRule = AutomationRule(
          id: 1,
          enabled: true,
          name: 'High VOC',
          sensor: 2,
          sensorIndex: 1,
          condition: 0,
          threshold: 250,
          hysteresis: 25,
          targetRelay: 0,
          action: 0,
        );
        expect(sgpRule.unitFor(telemetry), 'VOC');
        expect(sgpRule.sensorLabelFor(telemetry), 'SGP40 VOC #2');
      },
    );
  });
}

class _HwSheetFakeApiClient extends ApiClient {
  final HardwareProfile profileToReturn;
  HardwareProfile? lastSavedProfile;

  _HwSheetFakeApiClient(this.profileToReturn);

  @override
  Future<HardwareProfile?> fetchHardwareProfile(
    String ip, {
    String? password,
    String? username,
  }) async =>
      profileToReturn;

  @override
  Future<bool> saveHardwareProfile(
    String ip,
    HardwareProfile profile, {
    String? password,
    String? username,
  }) async {
    lastSavedProfile = profile;
    return true;
  }
}

class _HwSheetTestDeviceManager extends DeviceManager {
  final List<SmartDevice> _devices;
  final ApiClient _api;

  _HwSheetTestDeviceManager(this._devices, this._api);

  @override
  List<SmartDevice> build() => _devices;

  @override
  ApiClient get apiClient => _api;
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
