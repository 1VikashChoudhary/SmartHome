import 'package:flutter_test/flutter_test.dart';
import 'package:smarthome_app/core/models/hardware_profile.dart';

void main() {
  group('HardwareProfile & ChannelHardwareConfig Unit Tests', () {
    test('ChannelHardwareConfig serialization and deserialization preserves all values', () {
      final config = const ChannelHardwareConfig(
        enabled: false,
        switchEnabled: true,
        relayPin: 18,
        switchPin: 27,
        switchMode: SwitchMode.follow,
        triggerMode: 1,
      );

      final json = config.toJson();
      expect(json['enabled'], isFalse);
      expect(json['switch_enabled'], isTrue);
      expect(json['relay_pin'], equals(18));
      expect(json['switch_pin'], equals(27));
      expect(json['switch_mode'], equals(SwitchMode.follow.value));
      expect(json['trigger'], equals(1));

      final restored = ChannelHardwareConfig.fromJson(json);
      expect(restored.enabled, isFalse);
      expect(restored.switchEnabled, isTrue);
      expect(restored.relayPin, equals(18));
      expect(restored.switchPin, equals(27));
      expect(restored.switchMode, equals(SwitchMode.follow));
      expect(restored.triggerMode, equals(1));
    });

    test('HardwareProfile JSON serialization roundtrip preserves complete state', () {
      final profile = HardwareProfile(
        boardName: 'SmartHome 5-CH Standard',
        numRelays: 5,
        channels: [
          const ChannelHardwareConfig(relayPin: 16, switchPin: 13, switchMode: SwitchMode.toggle, triggerMode: 0),
          const ChannelHardwareConfig(relayPin: 17, switchPin: 14, switchMode: SwitchMode.toggle, triggerMode: 0),
          const ChannelHardwareConfig(relayPin: 18, switchPin: 27, switchMode: SwitchMode.toggle, triggerMode: 0),
          const ChannelHardwareConfig(relayPin: 19, switchPin: 26, switchMode: SwitchMode.toggle, triggerMode: 0),
          const ChannelHardwareConfig(relayPin: 23, switchPin: 25, switchMode: SwitchMode.toggle, triggerMode: 0),
        ],
        dhtType: ClimateSensorType.bme280,
        dhtPin: 4,
        lightType: LightSensorType.bh1750,
        motionType: MotionSensorType.radar,
        motionPin: 32,
        probeType: ProbeSensorType.ds18b20,
        probePin: 15,
        ultrasonicType: UltrasonicSensorType.hcsr04p,
        trigPin: 15,
        echoPin: 35,
        tankDepthCm: 200,
        tankAirGapCm: 20,
        mq2Enabled: true,
        mq2AnalogPin: 34,
        mq2DigitalPin: 35,
        buzzerEnabled: true,
        buzzerPin: 5,
        lcdEnabled: true,
        lcdI2cAddr: 39,
        lcdCols: 16,
        lcdRows: 2,
        i2cSdaPin: 21,
        i2cSclPin: 22,
        btnMultiPin: 33,
      );

      final json = profile.toJson();
      final restored = HardwareProfile.fromJson(json);

      expect(restored.boardName, equals('SmartHome 5-CH Standard'));
      expect(restored.numRelays, equals(5));
      expect(restored.channels.length, equals(5));
      expect(restored.channels[0].relayPin, equals(16));
      expect(restored.channels[0].switchPin, equals(13));
      expect(restored.dhtType, equals(ClimateSensorType.bme280));
      expect(restored.dhtPin, equals(4));
      expect(restored.lightType, equals(LightSensorType.bh1750));
      expect(restored.motionType, equals(MotionSensorType.radar));
      expect(restored.motionPin, equals(32));
      expect(restored.probeType, equals(ProbeSensorType.ds18b20));
      expect(restored.probePin, equals(15));
      expect(restored.ultrasonicType, equals(UltrasonicSensorType.hcsr04p));
      expect(restored.trigPin, equals(15));
      expect(restored.echoPin, equals(35));
      expect(restored.tankDepthCm, equals(200));
      expect(restored.tankAirGapCm, equals(20));
      expect(restored.mq2Enabled, isTrue);
      expect(restored.mq2AnalogPin, equals(34));
      expect(restored.buzzerEnabled, isTrue);
      expect(restored.buzzerPin, equals(5));
      expect(restored.lcdEnabled, isTrue);
      expect(restored.lcdI2cAddr, equals(39));
      expect(restored.i2cSdaPin, equals(21));
      expect(restored.i2cSclPin, equals(22));
      expect(restored.btnMultiPin, equals(33));
    });

    test('HardwareProfile static pin safety catalogs and presets are valid', () {
      expect(HardwareProfile.availablePresets, contains('SmartHome 5-CH Standard'));
      expect(HardwareProfile.availablePresets, contains('SmartHome 8-CH Max'));
      expect(HardwareProfile.availablePresets, contains('SmartHome Sensor Node'));

      // Check safe output pins
      expect(HardwareProfile.safeOutputPins, contains(16));
      expect(HardwareProfile.safeOutputPins, contains(17));
      expect(HardwareProfile.safeOutputPins, contains(18));
      // Pins 34-39 must NOT be in safeOutputPins
      expect(HardwareProfile.safeOutputPins, isNot(contains(34)));
      expect(HardwareProfile.safeOutputPins, isNot(contains(35)));

      // Check safe input pins
      expect(HardwareProfile.safeInputPins, contains(34));
      expect(HardwareProfile.safeInputPins, contains(35));
      expect(HardwareProfile.safeInputPins, contains(36));
      expect(HardwareProfile.safeInputPins, contains(39));

      // Check ADC1 pins (safe with Wi-Fi)
      expect(HardwareProfile.adc1Pins, contains(34));
      expect(HardwareProfile.adc1Pins, contains(35));
    });

    test('Conflict detection catches duplicate GPIO pin allocations', () {
      final Map<int, String> used = {};
      String? conflict;

      void claim(int pin, String name) {
        if (pin == 255) return;
        if (used.containsKey(pin)) {
          conflict = 'GPIO $pin is assigned to both "${used[pin]}" and "$name"';
          throw Exception(conflict);
        }
        used[pin] = name;
      }

      claim(16, 'Relay 1');
      claim(13, 'Switch 1');
      claim(4, 'DHT Climate');

      expect(conflict, isNull);

      // Attempt duplicate assignment on GPIO 16
      try {
        claim(16, 'Buzzer');
      } catch (_) {}

      expect(conflict, equals('GPIO 16 is assigned to both "Relay 1" and "Buzzer"'));
    });

    test('ESP8266 presets, pin catalogs, and pin labels are correct', () {
      final presets8266 = HardwareProfile.presetsFor(true);
      expect(presets8266, contains('SmartHome ESP8266 2-CH Dual'));
      expect(presets8266, contains('SmartHome ESP8266 1-CH Mini'));
      expect(presets8266, contains('SmartHome ESP8266 3-CH Pro'));
      expect(presets8266, contains('SmartHome ESP8266 4-CH Quad'));
      expect(presets8266, contains('SmartHome ESP8266 8-CH Max'));
      expect(presets8266, contains('SmartHome ESP8266 Sensor Node'));

      final out8266 = HardwareProfile.outputPinsFor(true);
      expect(out8266, contains(12));
      expect(out8266, contains(14));
      expect(out8266, isNot(contains(17))); // A0 is analog only

      final in8266 = HardwareProfile.inputPinsFor(true);
      expect(in8266, contains(13));
      expect(in8266, contains(16));
      expect(in8266, isNot(contains(17))); // A0 is analog-only, not digital GPIO

      final adc8266 = HardwareProfile.adc1PinsFor(true);
      expect(adc8266, equals([17]));

      expect(HardwareProfile.strappingPinsFor(true), equals([0, 2, 15]));
      expect(HardwareProfile.strappingPinsFor(false), equals([0, 2, 12, 15]));

      expect(HardwareProfile.inputOnlyPinsFor(true), equals([17]));
      expect(HardwareProfile.inputOnlyPinsFor(false), equals([34, 35, 36, 39]));

      expect(HardwareProfile.allPhysicalPinsFor(true).length, equals(10));
      expect(HardwareProfile.allPhysicalPinsFor(true), isNot(contains(1)));
      expect(HardwareProfile.allPhysicalPinsFor(true), isNot(contains(3)));
      expect(HardwareProfile.allPhysicalPinsFor(false).length, equals(24));

      expect(HardwareProfile.pinLabel(12, true), contains('D6'));
      expect(HardwareProfile.pinLabel(14, true), contains('D5'));
      expect(HardwareProfile.pinLabel(17, true), contains('A0'));
      expect(HardwareProfile.pinLabel(255, true), equals('None / Disabled'));
    });

    test('Multi-instance HardwareProfile JSON serialization roundtrip preserves all slots and I2C addresses', () {
      const profile = HardwareProfile(
        boardName: 'SmartHome Custom Multi',
        numRelays: 2,
        channels: [
          ChannelHardwareConfig(relayPin: 16, switchPin: 13),
          ChannelHardwareConfig(relayPin: 17, switchPin: 14),
        ],
        climates: [
          ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4, label: 'Hall'),
          ClimateSensorSlotConfig(type: ClimateSensorType.bme280, pin: 255, i2cAddr: 0x77, label: 'Attic'),
          ClimateSensorSlotConfig(type: ClimateSensorType.sht31, pin: 255, i2cAddr: 0x45, label: 'Outdoor'),
        ],
        lights: [
          LightSensorSlotConfig(type: LightSensorType.bh1750, i2cAddr: 0x23, label: 'Window'),
          LightSensorSlotConfig(type: LightSensorType.bh1750, i2cAddr: 0x5C, label: 'Porch'),
        ],
        motions: [
          MotionSensorSlotConfig(type: MotionSensorType.pir, pin: 32, label: 'Door'),
          MotionSensorSlotConfig(type: MotionSensorType.radar, pin: 33, label: 'Lobby'),
        ],
        probes: [
          ProbeSensorSlotConfig(type: ProbeSensorType.ds18b20, pin: 15, label: 'Solar'),
          ProbeSensorSlotConfig(type: ProbeSensorType.ds18b20, pin: 19, label: 'Sump'),
        ],
        ultrasonics: [
          UltrasonicSensorSlotConfig(type: UltrasonicSensorType.hcsr04p, trigPin: 18, echoPin: 36, tankDepthCm: 200, tankAirGapCm: 15, label: 'Main Tank'),
          UltrasonicSensorSlotConfig(type: UltrasonicSensorType.jsnsr04t, trigPin: 23, echoPin: 39, tankDepthCm: 120, tankAirGapCm: 10, label: 'Sump Tank'),
        ],
        mq2Sensors: [
          Mq2SensorSlotConfig(enabled: true, analogPin: 34, digitalPin: 35, label: 'Kitchen'),
          Mq2SensorSlotConfig(enabled: true, analogPin: 255, digitalPin: 25, label: 'Garage'),
        ],
        sensorLimits: SensorLimitsConfig(
          relays: 8,
          climates: 4,
          lights: 2,
          motions: 6,
          probes: 4,
          ultrasonics: 4,
          mq2s: 4,
        ),
        lcdEnabled: true,
        lcdI2cAddr: 0x27,
        i2cSdaPin: 21,
        i2cSclPin: 22,
        btnMultiPin: 0,
      );

      expect(profile.hasAnyI2cSensor, isTrue);
      expect(profile.dhtType, equals(ClimateSensorType.dht22));
      expect(profile.dhtPin, equals(4));

      final restored = HardwareProfile.fromJson(profile.toJson());
      expect(restored.climates.length, equals(3));
      expect(restored.climates[1].type, equals(ClimateSensorType.bme280));
      expect(restored.climates[1].i2cAddr, equals(0x77));
      expect(restored.climates[2].label, equals('Outdoor'));

      expect(restored.lights.length, equals(2));
      expect(restored.lights[1].i2cAddr, equals(0x5C));
      expect(restored.lights[1].label, equals('Porch'));

      expect(restored.motions.length, equals(2));
      expect(restored.motions[1].type, equals(MotionSensorType.radar));
      expect(restored.motions[1].pin, equals(33));

      expect(restored.probes.length, equals(2));
      expect(restored.probes[1].pin, equals(19));

      expect(restored.ultrasonics.length, equals(2));
      expect(restored.ultrasonics[1].type, equals(UltrasonicSensorType.jsnsr04t));
      expect(restored.ultrasonics[1].tankDepthCm, equals(120));

      expect(restored.mq2Sensors.length, equals(2));
      expect(restored.mq2Sensors[1].analogPin, equals(255));
      expect(restored.mq2Sensors[1].digitalPin, equals(25));
      expect(restored.mq2Sensors[1].label, equals('Garage'));
    });

    test('Legacy scalar JSON profile hydrates multi-sensor slots cleanly and respects disabled sensors', () {
      final legacy = HardwareProfile.fromJson({
        'board_name': 'Legacy Node',
        'num_relays': 0,
        'channels': [],
        'dht': {'type': 0, 'pin': 255},
        'light': {'type': 1},
        'motion': {'type': 1, 'pin': 14},
        'probe': {'type': 0, 'pin': 255},
        'ultrasonic': {'type': 1, 'trig_pin': 12, 'echo_pin': 13, 'tank_depth': 180, 'air_gap': 20},
        'mq2': {'enabled': false, 'analog_pin': 255, 'digital_pin': 255},
      });

      expect(legacy.climates, isEmpty);
      expect(legacy.lights.length, equals(1));
      expect(legacy.lights.first.type, equals(LightSensorType.bh1750));
      expect(legacy.lights.first.i2cAddr, equals(0x23));
      expect(legacy.motions.length, equals(1));
      expect(legacy.motions.first.pin, equals(14));
      expect(legacy.probes, isEmpty);
      expect(legacy.ultrasonics.length, equals(1));
      expect(legacy.ultrasonics.first.tankDepthCm, equals(180));
      expect(legacy.mq2Sensors, isEmpty);
    });

    test('copyWith(dhtType: ClimateSensorType.none) removes primary climate slot cleanly', () {
      const initial = HardwareProfile(
        boardName: 'Test Board',
        numRelays: 1,
        channels: [ChannelHardwareConfig(relayPin: 16, switchPin: 13)],
        climates: [
          ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4),
          ClimateSensorSlotConfig(type: ClimateSensorType.bme280, i2cAddr: 0x76),
        ],
      );
      final profile = initial.copyWith(dhtType: ClimateSensorType.none);
      expect(profile.climates.length, equals(1));
      expect(profile.climates.first.type, equals(ClimateSensorType.bme280));

      final empty = const HardwareProfile(
        boardName: 'Test Board',
        numRelays: 1,
        channels: [ChannelHardwareConfig(relayPin: 16, switchPin: 13)],
        climates: [ClimateSensorSlotConfig(type: ClimateSensorType.dht22, pin: 4)],
      ).copyWith(dhtType: ClimateSensorType.none);
      expect(empty.climates, isEmpty);
      expect(empty.dhtType, equals(ClimateSensorType.none));
    });
  });
}
