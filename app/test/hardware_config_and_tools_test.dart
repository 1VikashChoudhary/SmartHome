import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smarthome_app/core/models/device_diagnostics.dart';
import 'package:smarthome_app/core/models/hardware_profile.dart';
import 'package:smarthome_app/core/models/relay_channel.dart';
import 'package:smarthome_app/core/models/sensor_telemetry.dart';
import 'package:smarthome_app/core/models/smart_device.dart';
import 'package:smarthome_app/core/models/system_log_entry.dart';
import 'package:smarthome_app/core/network/api_client.dart';
import 'package:smarthome_app/core/theme/app_theme.dart';
import 'package:smarthome_app/presentation/screens/home_screen.dart';
import 'package:smarthome_app/presentation/widgets/device_tools_sheet.dart';
import 'package:smarthome_app/presentation/widgets/hardware_config_sheet.dart';
import 'package:smarthome_app/presentation/widgets/relay_config_sheet.dart';
import 'package:smarthome_app/services/device_manager.dart';
import 'package:smarthome_app/services/device_storage_service.dart';

class _FakeApiClient extends ApiClient {
  HardwareProfile? profileToReturn;
  HardwareProfile? lastSavedProfile;

  @override
  Future<HardwareProfile?> fetchHardwareProfile(
    String ip, {
    String? password,
    String? username,
  }) async {
    return profileToReturn;
  }

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

class _TestDeviceManager extends DeviceManager {
  final List<SmartDevice> _initialDevices;
  final _FakeApiClient _fakeApi;
  List<RelayChannel>? relaysToReturn;
  Map<String, dynamic>? configToReturn;
  DeviceDiagnostics? diagToReturn;
  List<SystemLogEntry> logsToReturn;
  String? loggedOutDeviceId;
  Map<String, dynamic>? lastSavedLcdPayload;
  Map<String, dynamic>? lastSavedDeviceConfig;
  int testRemoteAlertCalls = 0;

  _TestDeviceManager(
    this._initialDevices,
    this._fakeApi, {
    this.relaysToReturn,
    this.configToReturn,
    this.diagToReturn,
    this.logsToReturn = const [],
  });

  @override
  Future<bool> saveDeviceConfig(
    String deviceId,
    Map<String, dynamic> config,
  ) async {
    lastSavedDeviceConfig = Map<String, dynamic>.from(config);
    return true;
  }

  @override
  Future<String?> testRemoteAlert(String deviceId) async {
    testRemoteAlertCalls++;
    return null;
  }

  @override
  Future<bool> saveLcdSettings(
    String deviceId, {
    bool? enabled,
    bool? backlight,
    int? rotation,
    int? brightness,
    String? displayMode,
    bool? autoDim,
    String? dimStart,
    String? dimEnd,
    int? dimBrightness,
    List<String>? pages,
    List<String>? lines,
  }) async {
    lastSavedLcdPayload = {
      'enabled': ?enabled,
      'backlight': ?backlight,
      'rotation': ?rotation,
      'brightness': ?brightness,
      'display_mode': ?displayMode,
      'auto_dim': ?autoDim,
      'dim_start': ?dimStart,
      'dim_end': ?dimEnd,
      'dim_brightness': ?dimBrightness,
      'pages': ?pages,
      'lines': ?lines,
    };
    return true;
  }

  @override
  List<SmartDevice> build() => _initialDevices;

  @override
  ApiClient get apiClient => _fakeApi;

  @override
  Future<List<RelayChannel>?> fetchDeviceRelays(String deviceId) async =>
      relaysToReturn;

  @override
  Future<Map<String, dynamic>?> fetchDeviceConfig(String deviceId) async =>
      configToReturn;

  @override
  Future<DeviceDiagnostics?> fetchDeviceDiagnostics(String deviceId) async =>
      diagToReturn;

  @override
  Future<List<SystemLogEntry>> fetchDeviceLogs(String deviceId) async =>
      logsToReturn;

  @override
  Future<bool> saveRelayHardwareConfig(
    String deviceId,
    int relayIndex,
    Map<String, dynamic> config,
  ) async =>
      true;

  @override
  Future<void> logoutDevice(String deviceId) async {
    loggedOutDeviceId = deviceId;
  }
}

DeviceManager _createTestManager({
  required List<SmartDevice> devices,
  required _FakeApiClient apiClient,
  List<RelayChannel>? relays,
  Map<String, dynamic>? config,
  DeviceDiagnostics? diag,
  List<SystemLogEntry> logs = const [],
}) {
  final provider = NotifierProvider<DeviceManager, List<SmartDevice>>(
    () => _TestDeviceManager(
      devices,
      apiClient,
      relaysToReturn: relays,
      configToReturn: config,
      diagToReturn: diag,
      logsToReturn: logs,
    ),
  );
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container.read(provider.notifier);
}

SmartDevice _sampleDevice({
  String id = 'dev_esp32',
  String ip = '192.168.1.50',
  String platform = 'ESP32',
  String authRole = 'admin',
  int numRelays = 5,
  int gasThreshold = 400,
  int gasMax = 4095,
}) {
  return SmartDevice(
    id: id,
    mac: 'AA:BB:CC:11:22:33',
    ip: ip,
    hostname: 'smarthome-test',
    name: 'Test Controller',
    platform: platform,
    numRelays: numRelays,
    authRequired: true,
    authRole: authRole,
    authUsername: authRole == 'guest' ? 'guest' : 'admin',
    authPassword: 'secret',
    telemetry: SensorTelemetry(
      gasThreshold: gasThreshold,
      gasMax: gasMax,
    ),
    relays: [
      RelayChannel(
        index: 0,
        name: 'Ceiling Light',
        state: false,
        autoOff: 10,
        autoOn: 5,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceManager Credential & Session Lifecycle Regressions', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
    });

    test('logoutDevice clears stored password, unregisters host, and locks device', () async {
      final initial = SmartDevice(
        id: 'dev_logout_1',
        mac: 'AA:BB:CC:DD:EE:01',
        ip: '127.0.0.1:59991',
        hostname: 'smarthome-01',
        name: 'Living Room Hub',
        authRequired: true,
        authRole: 'admin',
        authUsername: 'owner',
        authPassword: 'SecretPassword!',
      );
      await DeviceStorageService().saveDevices([initial]);
      ApiClient.registerDeviceUsername(initial.ip, initial.authUsername);
      expect(ApiClient.hasRegisteredUsername(initial.ip), isTrue);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(deviceManagerProvider);
      // Let _init() loadDevices complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final manager = container.read(deviceManagerProvider.notifier);
      await manager.logoutDevice(initial.id);

      final devices = container.read(deviceManagerProvider);
      expect(devices.length, 1);
      expect(devices.first.authPassword, isNull);
      expect(devices.first.authLocked, isTrue);
      expect(devices.first.needsAuth, isTrue);
      expect(ApiClient.hasRegisteredUsername(initial.ip), isFalse);

      final reloaded = await DeviceStorageService().loadDevices();
      expect(reloaded.first.authPassword, isNull);
    });

    test('removeDevice deletes credentials, unregisters host, and removes from storage', () async {
      final initial = SmartDevice(
        id: 'dev_remove_1',
        mac: 'AA:BB:CC:DD:EE:02',
        ip: '127.0.0.1:59992',
        hostname: 'smarthome-02',
        name: 'Bedroom Hub',
        authRequired: true,
        authUsername: 'owner',
        authPassword: 'RemovePassword!',
      );
      await DeviceStorageService().saveDevices([initial]);
      ApiClient.registerDeviceUsername(initial.ip, initial.authUsername);
      expect(ApiClient.hasRegisteredUsername(initial.ip), isTrue);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(deviceManagerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final manager = container.read(deviceManagerProvider.notifier);
      await manager.removeDevice(initial.id);

      expect(container.read(deviceManagerProvider), isEmpty);
      expect(ApiClient.hasRegisteredUsername(initial.ip), isFalse);

      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString('smarthome_registered_devices')!);
      expect(decoded, isEmpty);
    });

    test('immediate ProviderContainer dispose during in-flight init/sync causes no post-dispose Ref exception', () async {
      final initial = SmartDevice(
        id: 'dev_dispose_race_1',
        mac: 'AA:BB:CC:DD:EE:03',
        ip: '127.0.0.1:59993',
        hostname: 'smarthome-03',
        name: 'Dispose Race Hub',
      );
      await DeviceStorageService().saveDevices([initial]);

      final container = ProviderContainer();
      container.read(deviceManagerProvider);
      // Wait just long enough for _init() loadDevices() -> startForegroundSync() to start HTTP probes,
      // then dispose while probes are in flight or completing.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      container.dispose();
      // Give any in-flight socket connection errors time to settle without throwing
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
  });

  group('RelayConfigSheet Regressions', () {
    testWidgets('Handles non-preset autoOff=10 without Dropdown crash and enforces Guest RBAC', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      final guestDev = _sampleDevice(authRole: 'guest');
      final manager = _createTestManager(
        devices: [guestDev],
        apiClient: fakeApi,
        relays: [guestDev.relays.first],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: RelayConfigSheet(
              device: guestDev,
              relay: guestDev.relays.first,
              manager: manager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Non-preset value 10 renders cleanly without DropdownButton assertion failure
      expect(find.text('10 min'), findsOneWidget);

      // Guest tier sees read-only lock and cannot save
      expect(find.text('Admin Credentials Required'), findsOneWidget);
      final saveBtn = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Admin Credentials Required'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(saveBtn.onPressed, isNull);
    });
  });

  group('DeviceToolsSheet Regressions', () {
    testWidgets('ESP8266 mq2Threshold=100 (<200) renders Slider safely and respects Guest RBAC & Log Out', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      final esp8266Guest = _sampleDevice(
        id: 'dev_8266_guest',
        platform: 'ESP8266',
        authRole: 'guest',
        numRelays: 2,
        gasThreshold: 100,
        gasMax: 1023,
      );
      final manager = _createTestManager(
        devices: [esp8266Guest],
        apiClient: fakeApi,
        config: {
          'sensor': {
            'temp_offset': 0.0,
            'hum_offset': 0.0,
            'mq2_threshold': 100,
            'gas_max': 1023,
            'temp_alarm': 45.0,
            'mq2_enabled': true,
            'mq2_hw_allowed': true,
          },
          'lcd': {'enabled': true, 'hw_allowed': true, 'backlight': true},
          'buzzer': {'enabled': true, 'hw_allowed': true, 'volume': 128},
          'mqtt': {'enabled': false},
          'device_name': '8266 Node',
          'hostname': 'smarthome-8266',
          'arduino_ota': false,
        },
        diag: DeviceDiagnostics(
          chipModel: 'ESP8266',
          freeHeap: 24000,
          minHeap: 18000,
          totalHeap: 81920,
          heapFrag: 8,
          uptime: '0d 01:00',
          resetReason: 'Power on',
          chipRev: 0,
          cpuFreq: 80,
          flashSize: 4194304,
          sdkVersion: 'NONOS-SDK',
          fwVersion: '3.2.0',
          fwBuild: 'test',
          fsUsed: 65536,
          fsTotal: 1048576,
          otaStatus: 'Idle',
        ),
        logs: [
          SystemLogEntry(
            timestamp: 1700000000,
            level: 0,
            source: 'Relay',
            message: 'Boot OK',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: DeviceToolsSheet(
              device: esp8266Guest,
              manager: manager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Hardware Tuning tab: mq2Threshold = 100 works cleanly with min=10, max=1023
      await tester.tap(find.text('Hardware Tuning'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Mute 5 Min'),
        200,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Mute 5 Min'), findsOneWidget);

      // Mute 5 Min remains enabled for Guest when buzzer hardware is allowed
      final muteBtn = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Mute 5 Min'),
          matching: find.bySubtype<OutlinedButton>(),
        ),
      );
      expect(muteBtn.onPressed, isNotNull);

      // Controller Settings tab: scroll TabBar horizontally so tab is onscreen before tapping
      await tester.ensureVisible(find.text('Controller Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Controller Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Log Out / Switch Account'),
        200,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ).first,
      );
      await tester.pumpAndSettle();
      final logoutBtn = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Log Out / Switch Account'),
          matching: find.bySubtype<OutlinedButton>(),
        ),
      );
      expect(logoutBtn.onPressed, isNotNull);

      // Maintenance tab: Admin controls disabled for Guest
      await tester.ensureVisible(find.text('Maintenance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance'));
      await tester.pumpAndSettle();
      final exportBtn = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Export Config JSON Backup'),
          matching: find.bySubtype<ElevatedButton>(),
        ),
      );
      expect(exportBtn.onPressed, isNull);

      final restoreBtn = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Restore Config Backup'),
          matching: find.bySubtype<OutlinedButton>(),
        ),
      );
      expect(restoreBtn.onPressed, isNull);

      await tester.scrollUntilVisible(
        find.text('Factory Reset'),
        250,
        scrollable: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ).first,
      );
      await tester.pumpAndSettle();
      final factoryResetBtn = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Factory Reset'),
          matching: find.bySubtype<ElevatedButton>(),
        ),
      );
      expect(factoryResetBtn.onPressed, isNull);
    });

    testWidgets('Hardware profile disabled flags lock LCD, Buzzer, and MQ-2 tuning controls', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      final adminDev = _sampleDevice(id: 'dev_hw_disabled', authRole: 'admin');
      final manager = _createTestManager(
        devices: [adminDev],
        apiClient: fakeApi,
        config: {
          'sensor': {
            'mq2_threshold': 400,
            'gas_max': 4095,
            'mq2_enabled': false,
            'mq2_hw_allowed': false,
          },
          'lcd': {'enabled': false, 'hw_allowed': false, 'backlight': false},
          'buzzer': {'enabled': false, 'hw_allowed': false, 'volume': 128},
          'mqtt': {'enabled': false},
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: DeviceToolsSheet(
              device: adminDev,
              manager: manager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hardware Tuning'));
      await tester.pumpAndSettle();

      final vertScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ).first;

      await tester.scrollUntilVisible(
        find.text('Alarm Buzzer is disabled or GPIO pin unassigned in Hardware Profile.'),
        200,
        scrollable: vertScroll,
      );
      expect(
        find.text('Alarm Buzzer is disabled or GPIO pin unassigned in Hardware Profile.'),
        findsOneWidget,
      );
      final muteBtn = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Mute 5 Min'),
          matching: find.bySubtype<OutlinedButton>(),
        ),
      );
      expect(muteBtn.onPressed, isNull);

      await tester.scrollUntilVisible(
        find.text('I2C LCD Display is disabled or pins unassigned in Hardware Profile.'),
        200,
        scrollable: vertScroll,
      );
      expect(
        find.text('I2C LCD Display is disabled or pins unassigned in Hardware Profile.'),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.text('MQ-2 Gas Sensor is disabled or pins unassigned in Hardware Profile.'),
        200,
        scrollable: vertScroll,
      );
      expect(
        find.text('MQ-2 Gas Sensor is disabled or pins unassigned in Hardware Profile.'),
        findsOneWidget,
      );
    });
  });

  group('HardwareConfigSheet Custom DIY & Validation Regressions', () {
    testWidgets('Custom DIY Mode adds relays up to 8 with free pins & validates ultrasonic depth > air gap', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      fakeApi.profileToReturn = HardwareProfile(
        boardName: 'SmartHome 5-CH Standard',
        numRelays: 5,
        channels: const [
          ChannelHardwareConfig(relayPin: 16, switchPin: 13),
          ChannelHardwareConfig(relayPin: 17, switchPin: 14),
          ChannelHardwareConfig(relayPin: 18, switchPin: 27),
          ChannelHardwareConfig(relayPin: 19, switchPin: 26),
          ChannelHardwareConfig(relayPin: 23, switchPin: 25),
        ],
        dhtType: ClimateSensorType.dht22,
        dhtPin: 4,
        mq2Enabled: true,
        mq2AnalogPin: 34,
        mq2DigitalPin: 35,
        buzzerEnabled: true,
        buzzerPin: 5,
        lcdEnabled: true,
        i2cSdaPin: 21,
        i2cSclPin: 22,
        btnMultiPin: 33,
      );

      final esp32Dev = _sampleDevice();
      final manager = _createTestManager(devices: [esp32Dev], apiClient: fakeApi);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: HardwareConfigSheet(
              device: esp32Dev,
              manager: manager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Custom DIY Mode and add 3 more relay channels (5 -> 8)
      await tester.tap(find.text('Custom DIY Mode'));
      await tester.pumpAndSettle();
      final vertScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ).first;
      await tester.scrollUntilVisible(find.text('5 / 8'), 200, scrollable: vertScroll);
      await tester.pumpAndSettle();
      expect(find.text('5 / 8'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('8 / 8'), findsOneWidget);

      // Add Ultrasonic sensor slot and enter invalid Tank Depth <= Air Gap
      final addUsBtn = find.byKey(const ValueKey('add_ultrasonics_btn'));
      await tester.scrollUntilVisible(addUsBtn, 250, scrollable: vertScroll);
      await tester.pumpAndSettle();
      await tester.tap(addUsBtn);
      await tester.pumpAndSettle();

      final usDropdown = find.byKey(const ValueKey('ultrasonic_type_0_1'));
      await tester.scrollUntilVisible(usDropdown, 250, scrollable: vertScroll);
      await tester.pumpAndSettle();
      await tester.tap(usDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text(UltrasonicSensorType.hcsr04p.label).last);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Tank Total Depth (cm)'),
        200,
        scrollable: vertScroll,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Tank Total Depth (cm)'),
        '25',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Sensor Air Gap (cm)'),
        '30',
      );
      await tester.pumpAndSettle();

      // Conflict banner should appear and Save button must be disabled
      expect(
        find.text('Ultrasonic 1 Tank Depth (20–500 cm) must be greater than Air Gap (5–100 cm)'),
        findsOneWidget,
      );
      final saveBtn = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Save & Reboot Controller'),
          matching: find.bySubtype<ElevatedButton>(),
        ),
      );
      expect(saveBtn.onPressed, isNull);
    });

    testWidgets('ESP8266 Custom DIY rejects A0 (GPIO 17) as digital channel pin', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      fakeApi.profileToReturn = HardwareProfile(
        boardName: 'SmartHome ESP8266 Custom DIY',
        numRelays: 1,
        channels: const [
          // Intentionally invalid A0 (17) assigned as switchPin from corrupted data
          ChannelHardwareConfig(enabled: true, switchEnabled: true, relayPin: 12, switchPin: 17),
        ],
        mq2Enabled: true,
        mq2AnalogPin: 17,
        buzzerEnabled: true,
        buzzerPin: 2,
        lcdEnabled: true,
        i2cSdaPin: 4,
        i2cSclPin: 5,
        btnMultiPin: 0,
      );

      final esp8266Dev = _sampleDevice(
        id: 'dev_8266_a0',
        platform: 'ESP8266',
        numRelays: 1,
      );
      final manager = _createTestManager(devices: [esp8266Dev], apiClient: fakeApi);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: HardwareConfigSheet(
              device: esp8266Dev,
              manager: manager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Live A0 analog-only rule prevents GPIO 17 from appearing in digital dropdowns and catches any digital claim
      expect(HardwareProfile.outputPinsFor(true), isNot(contains(17)));
      expect(HardwareProfile.inputPinsFor(true), isNot(contains(17)));
      expect(
        find.text('A0 (GPIO 17) on ESP8266 is analog-only and cannot be used for digital I/O (Switch 1)'),
        findsOneWidget,
      );
      final saveBtn = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Save & Reboot Controller'),
          matching: find.bySubtype<ElevatedButton>(),
        ),
      );
      expect(saveBtn.onPressed, isNull);
    });

    testWidgets('Shared I2C SDA/SCL pin dropdowns stay accessible when LCD is OFF and BME280 is active', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      fakeApi.profileToReturn = const HardwareProfile(
        boardName: 'SmartHome Custom I2C Climate',
        numRelays: 1,
        channels: [
          ChannelHardwareConfig(enabled: true, switchEnabled: false, relayPin: 16, switchPin: 255),
        ],
        dhtType: ClimateSensorType.bme280,
        dhtPin: 255,
        mq2Enabled: false,
        mq2AnalogPin: 255,
        mq2DigitalPin: 255,
        buzzerEnabled: false,
        buzzerPin: 255,
        lcdEnabled: false,
        i2cSdaPin: 21,
        i2cSclPin: 22,
        btnMultiPin: 33,
      );

      final esp32Dev = _sampleDevice(id: 'dev_i2c_nolcd', numRelays: 1);
      final manager = _createTestManager(devices: [esp32Dev], apiClient: fakeApi);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: HardwareConfigSheet(
              device: esp32Dev,
              manager: manager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final vertScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ).first;
      await tester.scrollUntilVisible(
        find.text('Shared I2C Bus Pins (Active for Climate/Light Sensors)'),
        250,
        scrollable: vertScroll,
      );
      await tester.pumpAndSettle();

      expect(find.text('Shared I2C Bus Pins (Active for Climate/Light Sensors)'), findsOneWidget);
      expect(find.text('SDA Pin'), findsOneWidget);
      expect(find.text('SCL Pin'), findsOneWidget);
    });

    testWidgets('Dynamic multi-sensor controls add and remove slots across sensor groups', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      fakeApi.profileToReturn = const HardwareProfile(
        boardName: 'SmartHome 5-CH Standard',
        numRelays: 1,
        channels: [ChannelHardwareConfig(relayPin: 16, switchPin: 13)],
        climates: [ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4)],
        mq2Sensors: [],
        buzzerEnabled: true,
        buzzerPin: 5,
        lcdEnabled: true,
        i2cSdaPin: 21,
        i2cSclPin: 22,
        btnMultiPin: 33,
      );

      final esp32Dev = _sampleDevice(numRelays: 1);
      final manager = _createTestManager(devices: [esp32Dev], apiClient: fakeApi);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: HardwareConfigSheet(device: esp32Dev, manager: manager),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final vertScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ).first;

      // Add a 2nd Climate sensor (1 / 4 -> 2 / 4)
      final addClimate = find.byKey(const ValueKey('add_climates_btn'));
      await tester.scrollUntilVisible(addClimate, 250, scrollable: vertScroll);
      await tester.pumpAndSettle();
      expect(find.text('1 / 4'), findsOneWidget);
      await tester.tap(addClimate);
      await tester.pumpAndSettle();
      expect(find.text('2 / 4'), findsOneWidget);

      // Add 2 Motion sensors (0 / 6 -> 2 / 6) then remove one (2 / 6 -> 1 / 6)
      final addMotion = find.byKey(const ValueKey('add_motions_btn'));
      await tester.scrollUntilVisible(addMotion, 250, scrollable: vertScroll);
      await tester.pumpAndSettle();
      expect(find.text('0 / 6'), findsOneWidget);
      await tester.tap(addMotion);
      await tester.pumpAndSettle();
      await tester.tap(addMotion);
      await tester.pumpAndSettle();
      expect(find.text('2 / 6'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('remove_motions_1')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 6'), findsOneWidget);
    });

    testWidgets('I2C 7-bit address conflict detection catches duplicate BME280 addresses and clears when resolved', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      fakeApi.profileToReturn = const HardwareProfile(
        boardName: 'SmartHome Dual I2C',
        numRelays: 1,
        channels: [ChannelHardwareConfig(enabled: true, switchEnabled: false, relayPin: 16, switchPin: 255)],
        climates: [
          ClimateSensorSlotConfig(type: ClimateSensorType.bme280, pin: 255, i2cAddr: 0x76),
          ClimateSensorSlotConfig(type: ClimateSensorType.bme280, pin: 255, i2cAddr: 0x76),
        ],
        mq2Sensors: [],
        buzzerEnabled: false,
        buzzerPin: 255,
        lcdEnabled: true,
        lcdI2cAddr: 0x27,
        i2cSdaPin: 21,
        i2cSclPin: 22,
        btnMultiPin: 33,
      );

      final esp32Dev = _sampleDevice(numRelays: 1);
      final manager = _createTestManager(devices: [esp32Dev], apiClient: fakeApi);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: HardwareConfigSheet(device: esp32Dev, manager: manager),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('I2C address 0x76 is assigned to both "Climate Sensor 1" and "Climate Sensor 2"'),
        findsOneWidget,
      );
      ElevatedButton saveBtn() => tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Save & Reboot Controller'),
          matching: find.bySubtype<ElevatedButton>(),
        ),
      );
      expect(saveBtn().onPressed, isNull);

      // Change Climate Sensor 2 address from 0x76 (118) to 0x77
      final vertScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ).first;
      final addrDropdown = find.byKey(const ValueKey('climate_addr_1_118'));
      await tester.scrollUntilVisible(addrDropdown, 250, scrollable: vertScroll);
      await tester.pumpAndSettle();
      await tester.tap(addrDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('0x77').last);
      await tester.pumpAndSettle();

      expect(
        find.text('I2C address 0x76 is assigned to both "Climate Sensor 1" and "Climate Sensor 2"'),
        findsNothing,
      );
      expect(saveBtn().onPressed, isNotNull);
    });

    testWidgets('ESP8266 second MQ-2 slot defaults away from occupied A0 analog pin without conflict', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      fakeApi.profileToReturn = const HardwareProfile(
        boardName: 'SmartHome ESP8266 Dual MQ2',
        numRelays: 2,
        channels: [
          ChannelHardwareConfig(enabled: true, switchEnabled: false, relayPin: 12, switchPin: 255),
          ChannelHardwareConfig(enabled: true, switchEnabled: false, relayPin: 14, switchPin: 255),
        ],
        climates: [],
        mq2Sensors: [
          Mq2SensorSlotConfig(enabled: true, analogPin: 17, digitalPin: 255),
        ],
        buzzerEnabled: true,
        buzzerPin: 2,
        lcdEnabled: true,
        i2cSdaPin: 4,
        i2cSclPin: 5,
        btnMultiPin: 0,
      );

      final esp8266Dev = _sampleDevice(id: 'dev_8266_mq2', platform: 'ESP8266', numRelays: 2);
      final manager = _createTestManager(devices: [esp8266Dev], apiClient: fakeApi);

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
      final addMq2 = find.byKey(const ValueKey('add_mq2s_btn'));
      await tester.scrollUntilVisible(addMq2, 250, scrollable: vertScroll);
      await tester.pumpAndSettle();
      await tester.tap(addMq2);
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Digital D0 mode active (ESP8266 A0 analog pin is allocated elsewhere).'),
        200,
        scrollable: vertScroll,
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Digital D0 mode active (ESP8266 A0 analog pin is allocated elsewhere).'),
        findsOneWidget,
      );
      final saveBtn = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Save & Reboot Controller'),
          matching: find.bySubtype<ElevatedButton>(),
        ),
      );
      expect(saveBtn.onPressed, isNotNull);
    });
  });

  group('RelayConfigSheet Custom Minutes Dialog & HomeScreen Sensor Node Regressions', () {
    testWidgets('Custom minutes dialog applies value cleanly without TextEditingController dispose errors', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      final dev = _sampleDevice();
      final manager = _createTestManager(
        devices: [dev],
        apiClient: fakeApi,
        relays: [dev.relays.first],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: RelayConfigSheet(
              device: dev,
              relay: dev.relays.first,
              manager: manager,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final vertScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ).first;
      await tester.scrollUntilVisible(find.text('10 min'), 200, scrollable: vertScroll);
      await tester.pumpAndSettle();

      await tester.tap(find.text('10 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Custom (1–1440 min)...').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '45');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(find.text('45 min'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('HomeScreen displays Sensor Node empty state and sub-zero climate reading accurately', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      final sensorNode = SmartDevice(
        id: 'dev_sensor_node',
        mac: 'AA:BB:CC:44:55:66',
        ip: '192.168.1.99',
        hostname: 'smarthome-sensor',
        name: 'Freezer Sensor Node',
        platform: 'ESP8266',
        numRelays: 0,
        isOnline: true,
        authRequired: false,
        telemetry: SensorTelemetry(
          dhtEnabled: true,
          dhtFault: false,
          temperature: -2.5,
          humidity: 48.0,
        ),
        relays: const [],
      );

      final container = ProviderContainer(
        overrides: [
          deviceManagerProvider.overrideWith(
            () => _TestDeviceManager([sensorNode], fakeApi),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Sensor Node active (0 relay channels configured). Tap to inspect telemetry & profile.'),
        findsOneWidget,
      );
      expect(find.text('Loading channels...'), findsNothing);
      expect(find.text('-2.5°'), findsWidgets);
    });

    testWidgets('Sensor slot labels cap at 15 chars and editing sensor model enters Custom DIY mode', (tester) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final fakeApi = _FakeApiClient();
      fakeApi.profileToReturn = const HardwareProfile(
        boardName: 'SmartHome 5-CH Standard',
        numRelays: 1,
        channels: [ChannelHardwareConfig(enabled: true, switchEnabled: false, relayPin: 16, switchPin: 255)],
        climates: [ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4)],
        ultrasonics: [UltrasonicSensorSlotConfig(type: UltrasonicSensorType.hcsr04p, trigPin: 15, echoPin: 35)],
        mq2Sensors: [],
        buzzerEnabled: false,
        buzzerPin: 255,
        lcdEnabled: false,
        i2cSdaPin: 255,
        i2cSclPin: 255,
        btnMultiPin: 33,
      );

      final esp32Dev = _sampleDevice(numRelays: 1);
      final manager = _createTestManager(devices: [esp32Dev], apiClient: fakeApi);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: HardwareConfigSheet(device: esp32Dev, manager: manager),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final vertScroll = find.byWidgetPredicate(
        (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ).first;

      // Switch climate slot 0 model from DHT22 (2) to BME280 (3) -> switches preset to Custom DIY
      final cliType = find.byKey(const ValueKey('climate_type_0_2'));
      await tester.scrollUntilVisible(cliType, 200, scrollable: vertScroll);
      await tester.pumpAndSettle();
      await tester.tap(cliType);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ClimateSensorType.bme280.label).last);
      await tester.pumpAndSettle();

      // Label TextFormField enforces maxLength: 15 (matching firmware char label[16])
      final labelField = find.byKey(const ValueKey('climates_label_0_1'));
      await tester.scrollUntilVisible(labelField, 150, scrollable: vertScroll);
      await tester.pumpAndSettle();
      await tester.enterText(labelField, 'VeryLongClimateLabel1234');
      await tester.pumpAndSettle();

      // Switch ultrasonic slot 0 model key (value-keyed) -> HC-SR04 (2)
      final usType = find.byKey(const ValueKey('ultrasonic_type_0_1'));
      await tester.scrollUntilVisible(usType, 250, scrollable: vertScroll);
      await tester.pumpAndSettle();
      await tester.tap(usType);
      await tester.pumpAndSettle();
      await tester.tap(find.text(UltrasonicSensorType.hcsr04.label).last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ultrasonic_type_0_2')), findsOneWidget);

      await tester.tap(find.text('Save & Reboot Controller'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save & Reboot'));
      await tester.pumpAndSettle();

      expect(fakeApi.lastSavedProfile, isNotNull);
      expect(fakeApi.lastSavedProfile!.boardName, 'SmartHome Custom DIY Controller');
      expect(fakeApi.lastSavedProfile!.climates.first.label, 'VeryLongClimate');
      expect(fakeApi.lastSavedProfile!.climates.first.label.length, 15);
    });

    testWidgets(
      'DeviceToolsSheet supports Auto-Rotate page toggling/reordering and Custom per-row layout',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeApi = _FakeApiClient();
        final dev = _sampleDevice(id: 'dev_lcd_custom');
        final testMgr = _createTestManager(
          devices: [dev],
          apiClient: fakeApi,
          config: {
            'sensor': {
              'temp_offset': 0.0,
              'hum_offset': 0.0,
              'mq2_threshold': 400,
              'gas_max': 4095,
              'temp_alarm': 40.0,
              'mq2_enabled': true,
              'mq2_hw_allowed': true,
            },
            'lcd': {
              'enabled': true,
              'hw_allowed': true,
              'cols': 16,
              'rows': 2,
              'backlight': true,
              'display_mode': 'rotate',
              'rotation': 5,
              'brightness': 100,
              'auto_dim': false,
              'dim_start': '22:00',
              'dim_end': '06:00',
              'dim_brightness': 0,
              'pages': ['climate', 'tank'],
              'lines': ['climate:0', 'tank:0'],
              'catalog': {
                'pages': [
                  {'id': 'climate', 'label': 'Climate', 'available': true},
                  {'id': 'tank', 'label': 'Tank Level', 'available': true},
                  {'id': 'gas', 'label': 'Gas / VOC', 'available': false},
                ],
                'widgets': [
                  {'id': 'climate:0', 'label': 'Climate #1'},
                  {'id': 'tank:0', 'label': 'Rooftop Tank'},
                  {'id': 'relays', 'label': 'Relay States'},
                  {'id': 'none', 'label': '(Blank Row)'},
                ],
              },
            },
            'buzzer': {'enabled': true, 'hw_allowed': true, 'volume': 128},
            'mqtt': {'enabled': false},
            'device_name': 'Controller',
            'hostname': 'smarthome-1',
          },
          diag: DeviceDiagnostics(
            chipModel: 'ESP32',
            freeHeap: 120000,
            minHeap: 90000,
            totalHeap: 320000,
            heapFrag: 4,
            uptime: '0d 01:00',
            resetReason: 'Power on',
            chipRev: 1,
            cpuFreq: 240,
            flashSize: 4194304,
            sdkVersion: 'IDF',
            fwVersion: '1.1.0',
            fwBuild: 'test',
            fsUsed: 65536,
            fsTotal: 1048576,
            otaStatus: 'Idle',
          ),
        ) as _TestDeviceManager;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(body: DeviceToolsSheet(device: dev, manager: testMgr)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Controller Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Controller Settings'));
        await tester.pumpAndSettle();

        final vertScroll = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ).first;

        // Scroll to LCD pages section and move "Tank Level" (index 1) up to first
        await tester.scrollUntilVisible(
          find.text('Active Pages & Display Order (Top Shows First)'),
          200,
          scrollable: vertScroll,
        );
        await tester.pumpAndSettle();
        expect(find.text('2. Tank Level'), findsOneWidget);
        expect(find.text('3. Gas / VOC (Off in HW)'), findsOneWidget);

        // Move "Tank Level" up (second Move up icon on page list -> row 1)
        await tester.tap(find.byTooltip('Move up').at(1));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Save LCD Settings'),
          150,
          scrollable: vertScroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save LCD Settings'));
        await tester.pumpAndSettle();

        expect(testMgr.lastSavedLcdPayload?['display_mode'], 'rotate');
        expect(testMgr.lastSavedLcdPayload?['pages'], ['tank', 'climate']);

        // Switch Display Mode to Custom Per-Row Layout and swap Line 2 up to Line 1
        final modeDropdown = find.byKey(const ValueKey('lcd_mode_rotate_false_true'));
        await tester.scrollUntilVisible(modeDropdown, -200, scrollable: vertScroll);
        await tester.pumpAndSettle();
        await tester.tap(modeDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom per-row layout').last);
        await tester.pumpAndSettle();

        expect(find.text('Pinned Row Layout (16x2 — Line 1 Shows First)'), findsOneWidget);
        await tester.tap(find.byTooltip('Move line up').at(1));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Save LCD Settings'),
          150,
          scrollable: vertScroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save LCD Settings'));
        await tester.pumpAndSettle();

        expect(testMgr.lastSavedLcdPayload?['display_mode'], 'custom');
        expect(testMgr.lastSavedLcdPayload?['lines'], ['tank:0', 'climate:0']);
      },
    );

    testWidgets(
      'DeviceToolsSheet saves Optional Remote Push Alerts (4G/5G) config and dispatches test alert',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeApi = _FakeApiClient();
        final dev = _sampleDevice(id: 'dev_remote_alert', platform: 'ESP32');
        final testMgr = _createTestManager(
          devices: [dev],
          apiClient: fakeApi,
          config: {
            'sensor': {
              'temp_offset': 0.0,
              'hum_offset': 0.0,
              'mq2_threshold': 400,
              'gas_max': 4095,
              'temp_alarm': 40.0,
              'mq2_enabled': true,
              'mq2_hw_allowed': true,
            },
            'lcd': {'enabled': true, 'hw_allowed': true},
            'buzzer': {'enabled': true, 'hw_allowed': true, 'volume': 128},
            'mqtt': {'enabled': false},
            'device_name': 'Controller',
            'hostname': 'smarthome-1',
            'alert_webhook_en': false,
            'alert_webhook_url': '',
            'alert_webhook_token_set': false,
            'alert_https_supported': true,
          },
          diag: DeviceDiagnostics(
            chipModel: 'ESP32',
            freeHeap: 120000,
            minHeap: 90000,
            totalHeap: 320000,
            heapFrag: 4,
            uptime: '0d 01:00',
            resetReason: 'Power on',
            chipRev: 1,
            cpuFreq: 240,
            flashSize: 4194304,
            sdkVersion: 'IDF',
            fwVersion: '1.1.0',
            fwBuild: 'test',
            fsUsed: 65536,
            fsTotal: 1048576,
            otaStatus: 'Idle',
          ),
        ) as _TestDeviceManager;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(body: DeviceToolsSheet(device: dev, manager: testMgr)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Controller Settings'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Controller Settings'));
        await tester.pumpAndSettle();

        final vertScroll = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ).first;

        final remoteSwitch = find.text('Optional Remote Push Alerts (4G/5G)');
        await tester.scrollUntilVisible(remoteSwitch, 250, scrollable: vertScroll);
        await tester.pumpAndSettle();
        await tester.tap(remoteSwitch);
        await tester.pumpAndSettle();

        final urlField = find.widgetWithText(TextField, 'Webhook / ntfy URL');
        await tester.scrollUntilVisible(urlField, 150, scrollable: vertScroll);
        await tester.pumpAndSettle();
        await tester.enterText(urlField, 'https://ntfy.sh/test-room-alarm');

        final tokenField = find.widgetWithText(TextField, 'Bearer token (optional)');
        await tester.enterText(tokenField, 'tk_secret_123');
        await tester.pumpAndSettle();

        final saveBtn = find.text('Save Device Settings');
        await tester.scrollUntilVisible(saveBtn, 150, scrollable: vertScroll);
        await tester.pumpAndSettle();
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(testMgr.lastSavedDeviceConfig?['alert_webhook_en'], isTrue);
        expect(
          testMgr.lastSavedDeviceConfig?['alert_webhook_url'],
          'https://ntfy.sh/test-room-alarm',
        );
        expect(
          testMgr.lastSavedDeviceConfig?['alert_webhook_token'],
          'tk_secret_123',
        );

        final testBtn = find.text('Test Remote Alert');
        await tester.scrollUntilVisible(testBtn, -150, scrollable: vertScroll);
        await tester.pumpAndSettle();
        await tester.tap(testBtn);
        await tester.pumpAndSettle();
        expect(testMgr.testRemoteAlertCalls, 1);
      },
    );
  });
}
