enum SwitchMode {
  toggle(0, 'Toggle Rocker (Any Edge)'),
  follow(1, 'Follow (Closed = ON)'),
  followInv(2, 'Follow Inverted'),
  pushbutton(3, 'Push-Button (Momentary)'),
  detached(4, 'Detached (Decoupled)');

  final int value;
  final String label;
  const SwitchMode(this.value, this.label);

  static SwitchMode fromValue(int val) {
    return SwitchMode.values.firstWhere(
      (m) => m.value == val,
      orElse: () => SwitchMode.toggle,
    );
  }
}

enum ClimateSensorType {
  none(0, 'Disabled (None)'),
  dht11(1, 'DHT11'),
  dht22(2, 'DHT22 / AM2302'),
  bme280(3, 'BME280 (I2C Temp/Hum/Baro)'),
  aht20(4, 'AHT20 (I2C Temp/Hum)'),
  sht31(5, 'SHT31 / SHT3x (I2C High Accuracy)');

  final int value;
  final String label;
  const ClimateSensorType(this.value, this.label);

  static ClimateSensorType fromValue(int val) {
    return ClimateSensorType.values.firstWhere(
      (m) => m.value == val,
      orElse: () => ClimateSensorType.dht22,
    );
  }
}

enum LightSensorType {
  none(0, 'Disabled'),
  bh1750(1, 'BH1750 (I2C 0x23 / Lux)');

  final int value;
  final String label;
  const LightSensorType(this.value, this.label);

  static LightSensorType fromValue(int val) {
    return LightSensorType.values.firstWhere(
      (m) => m.value == val,
      orElse: () => LightSensorType.none,
    );
  }
}

enum MotionSensorType {
  none(0, 'Disabled'),
  pir(1, 'PIR Motion Sensor'),
  radar(2, 'mmWave Radar (LD2410)');

  final int value;
  final String label;
  const MotionSensorType(this.value, this.label);

  static MotionSensorType fromValue(int val) {
    return MotionSensorType.values.firstWhere(
      (m) => m.value == val,
      orElse: () => MotionSensorType.none,
    );
  }
}

enum ProbeSensorType {
  none(0, 'Disabled'),
  ds18b20(1, 'DS18B20 (1-Wire Waterproof)');

  final int value;
  final String label;
  const ProbeSensorType(this.value, this.label);

  static ProbeSensorType fromValue(int val) {
    return ProbeSensorType.values.firstWhere(
      (m) => m.value == val,
      orElse: () => ProbeSensorType.none,
    );
  }
}

enum UltrasonicSensorType {
  none(0, 'Disabled'),
  hcsr04p(1, 'HC-SR04P (3.3V Native - Recommended)'),
  hcsr04(2, 'HC-SR04 (5V Legacy - Needs Divider)'),
  jsnsr04t(3, 'JSN-SR04T (Waterproof Transceiver)');

  final int value;
  final String label;
  const UltrasonicSensorType(this.value, this.label);

  static UltrasonicSensorType fromValue(int val) {
    return UltrasonicSensorType.values.firstWhere(
      (m) => m.value == val,
      orElse: () => UltrasonicSensorType.none,
    );
  }
}

class ChannelHardwareConfig {
  final bool enabled;
  final bool switchEnabled;
  final int relayPin;
  final int switchPin;
  final SwitchMode switchMode;
  final int triggerMode; // 0 = Active LOW, 1 = Active HIGH

  const ChannelHardwareConfig({
    this.enabled = true,
    this.switchEnabled = true,
    required this.relayPin,
    required this.switchPin,
    this.switchMode = SwitchMode.toggle,
    this.triggerMode = 0,
  });

  factory ChannelHardwareConfig.fromJson(Map<String, dynamic> json) {
    return ChannelHardwareConfig(
      enabled: json['enabled'] as bool? ?? true,
      switchEnabled: json['switch_enabled'] as bool? ?? true,
      relayPin: (json['relay_pin'] as num?)?.toInt() ?? 255,
      switchPin: (json['switch_pin'] as num?)?.toInt() ?? 255,
      switchMode: SwitchMode.fromValue((json['switch_mode'] as num?)?.toInt() ?? 0),
      triggerMode: (json['trigger'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'switch_enabled': switchEnabled,
    'relay_pin': relayPin,
    'switch_pin': switchPin,
    'switch_mode': switchMode.value,
    'trigger': triggerMode,
  };

  ChannelHardwareConfig copyWith({
    bool? enabled,
    bool? switchEnabled,
    int? relayPin,
    int? switchPin,
    SwitchMode? switchMode,
    int? triggerMode,
  }) {
    return ChannelHardwareConfig(
      enabled: enabled ?? this.enabled,
      switchEnabled: switchEnabled ?? this.switchEnabled,
      relayPin: relayPin ?? this.relayPin,
      switchPin: switchPin ?? this.switchPin,
      switchMode: switchMode ?? this.switchMode,
      triggerMode: triggerMode ?? this.triggerMode,
    );
  }
}

class HardwareProfile {
  final String boardName;
  final int numRelays;
  final List<ChannelHardwareConfig> channels;

  final ClimateSensorType dhtType;
  final int dhtPin;

  final LightSensorType lightType;

  final MotionSensorType motionType;
  final int motionPin;

  final ProbeSensorType probeType;
  final int probePin;

  final UltrasonicSensorType ultrasonicType;
  final int trigPin;
  final int echoPin;
  final int tankDepthCm;
  final int tankAirGapCm;

  final bool mq2Enabled;
  final int mq2AnalogPin;
  final int mq2DigitalPin;

  final bool buzzerEnabled;
  final int buzzerPin;

  final bool lcdEnabled;
  final int lcdI2cAddr;
  final int lcdCols;
  final int lcdRows;
  final int i2cSdaPin;
  final int i2cSclPin;

  final int btnMultiPin;

  const HardwareProfile({
    required this.boardName,
    required this.numRelays,
    required this.channels,
    this.dhtType = ClimateSensorType.dht22,
    this.dhtPin = 4,
    this.lightType = LightSensorType.none,
    this.motionType = MotionSensorType.none,
    this.motionPin = 32,
    this.probeType = ProbeSensorType.none,
    this.probePin = 15,
    this.ultrasonicType = UltrasonicSensorType.none,
    this.trigPin = 15,
    this.echoPin = 35,
    this.tankDepthCm = 150,
    this.tankAirGapCm = 15,
    this.mq2Enabled = true,
    this.mq2AnalogPin = 34,
    this.mq2DigitalPin = 35,
    this.buzzerEnabled = true,
    this.buzzerPin = 5,
    this.lcdEnabled = true,
    this.lcdI2cAddr = 39,
    this.lcdCols = 16,
    this.lcdRows = 2,
    this.i2cSdaPin = 21,
    this.i2cSclPin = 22,
    this.btnMultiPin = 33,
  });

  factory HardwareProfile.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'] as List<dynamic>? ?? [];
    final channels = rawChannels
        .map((c) => ChannelHardwareConfig.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();

    final dht = json['dht'] as Map<String, dynamic>?;
    final light = json['light'] as Map<String, dynamic>?;
    final motion = json['motion'] as Map<String, dynamic>?;
    final probe = json['probe'] as Map<String, dynamic>?;
    final ultrasonic = json['ultrasonic'] as Map<String, dynamic>?;
    final mq2 = json['mq2'] as Map<String, dynamic>?;
    final buzzer = json['buzzer'] as Map<String, dynamic>?;
    final lcd = json['lcd'] as Map<String, dynamic>?;

    return HardwareProfile(
      boardName: json['board_name'] as String? ?? 'Custom',
      numRelays: (json['num_relays'] as num?)?.toInt() ?? channels.length,
      channels: channels,
      dhtType: ClimateSensorType.fromValue((dht?['type'] as num?)?.toInt() ?? 2),
      dhtPin: (dht?['pin'] as num?)?.toInt() ?? 4,
      lightType: LightSensorType.fromValue((light?['type'] as num?)?.toInt() ?? 0),
      motionType: MotionSensorType.fromValue((motion?['type'] as num?)?.toInt() ?? 0),
      motionPin: (motion?['pin'] as num?)?.toInt() ?? 32,
      probeType: ProbeSensorType.fromValue((probe?['type'] as num?)?.toInt() ?? 0),
      probePin: (probe?['pin'] as num?)?.toInt() ?? 15,
      ultrasonicType: UltrasonicSensorType.fromValue((ultrasonic?['type'] as num?)?.toInt() ?? 0),
      trigPin: (ultrasonic?['trig_pin'] as num?)?.toInt() ?? 15,
      echoPin: (ultrasonic?['echo_pin'] as num?)?.toInt() ?? 35,
      tankDepthCm: (ultrasonic?['tank_depth'] as num?)?.toInt() ?? 150,
      tankAirGapCm: (ultrasonic?['air_gap'] as num?)?.toInt() ?? 15,
      mq2Enabled: mq2?['enabled'] as bool? ?? true,
      mq2AnalogPin: (mq2?['analog_pin'] as num?)?.toInt() ?? 34,
      mq2DigitalPin: (mq2?['digital_pin'] as num?)?.toInt() ?? 35,
      buzzerEnabled: buzzer?['enabled'] as bool? ?? true,
      buzzerPin: (buzzer?['pin'] as num?)?.toInt() ?? 5,
      lcdEnabled: lcd?['enabled'] as bool? ?? true,
      lcdI2cAddr: (lcd?['i2c_addr'] as num?)?.toInt() ?? 39,
      lcdCols: (lcd?['cols'] as num?)?.toInt() ?? 16,
      lcdRows: (lcd?['rows'] as num?)?.toInt() ?? 2,
      i2cSdaPin: (lcd?['sda_pin'] as num?)?.toInt() ?? 21,
      i2cSclPin: (lcd?['scl_pin'] as num?)?.toInt() ?? 22,
      btnMultiPin: (json['btn_multi_pin'] as num?)?.toInt() ?? 33,
    );
  }

  Map<String, dynamic> toJson() => {
    'board_name': boardName,
    'num_relays': numRelays,
    'channels': channels.map((c) => c.toJson()).toList(),
    'dht': {
      'type': dhtType.value,
      'pin': dhtPin,
    },
    'light': {
      'type': lightType.value,
    },
    'motion': {
      'type': motionType.value,
      'pin': motionPin,
    },
    'probe': {
      'type': probeType.value,
      'pin': probePin,
    },
    'ultrasonic': {
      'type': ultrasonicType.value,
      'trig_pin': trigPin,
      'echo_pin': echoPin,
      'tank_depth': tankDepthCm,
      'air_gap': tankAirGapCm,
    },
    'mq2': {
      'enabled': mq2Enabled,
      'analog_pin': mq2AnalogPin,
      'digital_pin': mq2DigitalPin,
    },
    'buzzer': {
      'enabled': buzzerEnabled,
      'pin': buzzerPin,
    },
    'lcd': {
      'enabled': lcdEnabled,
      'i2c_addr': lcdI2cAddr,
      'cols': lcdCols,
      'rows': lcdRows,
      'sda_pin': i2cSdaPin,
      'scl_pin': i2cSclPin,
    },
    'btn_multi_pin': btnMultiPin,
  };

  HardwareProfile copyWith({
    String? boardName,
    int? numRelays,
    List<ChannelHardwareConfig>? channels,
    ClimateSensorType? dhtType,
    int? dhtPin,
    LightSensorType? lightType,
    MotionSensorType? motionType,
    int? motionPin,
    ProbeSensorType? probeType,
    int? probePin,
    UltrasonicSensorType? ultrasonicType,
    int? trigPin,
    int? echoPin,
    int? tankDepthCm,
    int? tankAirGapCm,
    bool? mq2Enabled,
    int? mq2AnalogPin,
    int? mq2DigitalPin,
    bool? buzzerEnabled,
    int? buzzerPin,
    bool? lcdEnabled,
    int? lcdI2cAddr,
    int? lcdCols,
    int? lcdRows,
    int? i2cSdaPin,
    int? i2cSclPin,
    int? btnMultiPin,
  }) {
    return HardwareProfile(
      boardName: boardName ?? this.boardName,
      numRelays: numRelays ?? this.numRelays,
      channels: channels ?? this.channels,
      dhtType: dhtType ?? this.dhtType,
      dhtPin: dhtPin ?? this.dhtPin,
      lightType: lightType ?? this.lightType,
      motionType: motionType ?? this.motionType,
      motionPin: motionPin ?? this.motionPin,
      probeType: probeType ?? this.probeType,
      probePin: probePin ?? this.probePin,
      ultrasonicType: ultrasonicType ?? this.ultrasonicType,
      trigPin: trigPin ?? this.trigPin,
      echoPin: echoPin ?? this.echoPin,
      tankDepthCm: tankDepthCm ?? this.tankDepthCm,
      tankAirGapCm: tankAirGapCm ?? this.tankAirGapCm,
      mq2Enabled: mq2Enabled ?? this.mq2Enabled,
      mq2AnalogPin: mq2AnalogPin ?? this.mq2AnalogPin,
      mq2DigitalPin: mq2DigitalPin ?? this.mq2DigitalPin,
      buzzerEnabled: buzzerEnabled ?? this.buzzerEnabled,
      buzzerPin: buzzerPin ?? this.buzzerPin,
      lcdEnabled: lcdEnabled ?? this.lcdEnabled,
      lcdI2cAddr: lcdI2cAddr ?? this.lcdI2cAddr,
      lcdCols: lcdCols ?? this.lcdCols,
      lcdRows: lcdRows ?? this.lcdRows,
      i2cSdaPin: i2cSdaPin ?? this.i2cSdaPin,
      i2cSclPin: i2cSclPin ?? this.i2cSclPin,
      btnMultiPin: btnMultiPin ?? this.btnMultiPin,
    );
  }

  static const List<String> availablePresets = [
    'SmartHome 5-CH Standard',
    'SmartHome 1-CH Mini',
    'SmartHome 2-CH Dual',
    'SmartHome 4-CH Pro',
    'SmartHome 8-CH Max',
    'SmartHome Sensor Node',
  ];

  static const List<String> availablePresetsESP32 = [
    'SmartHome 5-CH Standard',
    'SmartHome 1-CH Mini',
    'SmartHome 2-CH Dual',
    'SmartHome 4-CH Pro',
    'SmartHome 8-CH Max',
    'SmartHome Sensor Node',
  ];

  static const List<String> availablePresetsESP8266 = [
    'SmartHome ESP8266 2-CH Dual',
    'SmartHome ESP8266 1-CH Mini',
    'SmartHome ESP8266 3-CH Pro',
    'SmartHome ESP8266 4-CH Quad',
    'SmartHome ESP8266 8-CH Max',
    'SmartHome ESP8266 Sensor Node',
  ];

  static const List<int> safeOutputPins = [
    2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33
  ];

  static const List<int> safeOutputPinsESP8266 = [
    0, 2, 4, 5, 12, 13, 14, 15, 16
  ];

  static const List<int> safeInputPins = [
    0, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35, 36, 39
  ];

  static const List<int> safeInputPinsESP8266 = [
    0, 2, 4, 5, 12, 13, 14, 15, 16, 17
  ];

  static const List<int> strappingPinsESP32 = [0, 2, 12, 15];
  static const List<int> strappingPinsESP8266 = [0, 2, 15];

  static const List<int> inputOnlyPinsESP32 = [34, 35, 36, 39];
  static const List<int> inputOnlyPinsESP8266 = [17]; // A0

  static const List<int> adc1Pins = [32, 33, 34, 35, 36, 39];
  static const List<int> adc1PinsESP8266 = [17]; // A0

  static List<String> presetsFor(bool isEsp8266) =>
      isEsp8266 ? availablePresetsESP8266 : availablePresetsESP32;

  static List<int> outputPinsFor(bool isEsp8266) =>
      isEsp8266 ? safeOutputPinsESP8266 : safeOutputPins;

  static List<int> inputPinsFor(bool isEsp8266) =>
      isEsp8266 ? safeInputPinsESP8266 : safeInputPins;

  static List<int> adc1PinsFor(bool isEsp8266) =>
      isEsp8266 ? adc1PinsESP8266 : adc1Pins;

  static List<int> strappingPinsFor(bool isEsp8266) =>
      isEsp8266 ? strappingPinsESP8266 : strappingPinsESP32;

  static List<int> inputOnlyPinsFor(bool isEsp8266) =>
      isEsp8266 ? inputOnlyPinsESP8266 : inputOnlyPinsESP32;

  static List<int> allPhysicalPinsFor(bool isEsp8266) =>
      isEsp8266
          ? [0, 1, 2, 3, 4, 5, 12, 13, 14, 15, 16, 17]
          : [0, 2, 4, 5, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 25, 26, 27, 32, 33, 34, 35, 36, 39];

  static String pinLabel(int pin, bool isEsp8266) {
    if (pin == 255) return 'None / Disabled';
    if (!isEsp8266) {
      String label = 'GPIO $pin';
      if (pin == 34 || pin == 35 || pin == 36 || pin == 39) label += ' (In)';
      if (pin == 0 || pin == 2 || pin == 12 || pin == 15) label += ' (Boot)';
      return label;
    }
    switch (pin) {
      case 0:
        return 'GPIO 0 (D3 / FLASH)';
      case 1:
        return 'GPIO 1 (TX0)';
      case 2:
        return 'GPIO 2 (D4 / LED)';
      case 3:
        return 'GPIO 3 (RX0)';
      case 4:
        return 'GPIO 4 (D2 / SDA)';
      case 5:
        return 'GPIO 5 (D1 / SCL)';
      case 12:
        return 'GPIO 12 (D6)';
      case 13:
        return 'GPIO 13 (D7)';
      case 14:
        return 'GPIO 14 (D5)';
      case 15:
        return 'GPIO 15 (D8)';
      case 16:
        return 'GPIO 16 (D0 / WAKE)';
      case 17:
        return 'A0 (ADC0)';
      default:
        return 'GPIO $pin';
    }
  }
}
