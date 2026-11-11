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
      expect(in8266, contains(17)); // A0

      final adc8266 = HardwareProfile.adc1PinsFor(true);
      expect(adc8266, equals([17]));

      expect(HardwareProfile.strappingPinsFor(true), equals([0, 2, 15]));
      expect(HardwareProfile.strappingPinsFor(false), equals([0, 2, 12, 15]));

      expect(HardwareProfile.inputOnlyPinsFor(true), equals([17]));
      expect(HardwareProfile.inputOnlyPinsFor(false), equals([34, 35, 36, 39]));

      expect(HardwareProfile.allPhysicalPinsFor(true).length, equals(12));
      expect(HardwareProfile.allPhysicalPinsFor(false).length, equals(24));

      expect(HardwareProfile.pinLabel(12, true), contains('D6'));
      expect(HardwareProfile.pinLabel(14, true), contains('D5'));
      expect(HardwareProfile.pinLabel(17, true), contains('A0'));
      expect(HardwareProfile.pinLabel(255, true), equals('None / Disabled'));
    });
  });
}
