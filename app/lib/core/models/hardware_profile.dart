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

  bool get isI2c => value >= 3;

  List<int> get allowedI2cAddrs {
    switch (this) {
      case ClimateSensorType.bme280:
        return const [0x76, 0x77];
      case ClimateSensorType.aht20:
        return const [0x38];
      case ClimateSensorType.sht31:
        return const [0x44, 0x45];
      default:
        return const [];
    }
  }

  int get defaultI2cAddr =>
      allowedI2cAddrs.isNotEmpty ? allowedI2cAddrs.first : 0;

  static ClimateSensorType fromValue(int val) {
    return ClimateSensorType.values.firstWhere(
      (m) => m.value == val,
      orElse: () => ClimateSensorType.none,
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

class ClimateSensorSlotConfig {
  final ClimateSensorType type;
  final int pin;
  final int i2cAddr;
  final String label;

  const ClimateSensorSlotConfig({
    this.type = ClimateSensorType.dht22,
    this.pin = 4,
    this.i2cAddr = 0,
    this.label = '',
  });

  factory ClimateSensorSlotConfig.fromJson(Map<String, dynamic> json) {
    final type = ClimateSensorType.fromValue((json['type'] as num?)?.toInt() ?? 0);
    final rawAddr = (json['i2c_addr'] as num?)?.toInt() ?? 0;
    return ClimateSensorSlotConfig(
      type: type,
      pin: (json['pin'] as num?)?.toInt() ?? 255,
      i2cAddr: type.isI2c
          ? (rawAddr > 0 ? rawAddr : type.defaultI2cAddr)
          : 0,
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.value,
    'pin': pin,
    'i2c_addr': type.isI2c ? (i2cAddr > 0 ? i2cAddr : type.defaultI2cAddr) : 0,
    'label': label,
  };

  ClimateSensorSlotConfig copyWith({
    ClimateSensorType? type,
    int? pin,
    int? i2cAddr,
    String? label,
  }) {
    return ClimateSensorSlotConfig(
      type: type ?? this.type,
      pin: pin ?? this.pin,
      i2cAddr: i2cAddr ?? this.i2cAddr,
      label: label ?? this.label,
    );
  }
}

class LightSensorSlotConfig {
  final LightSensorType type;
  final int i2cAddr;
  final String label;

  const LightSensorSlotConfig({
    this.type = LightSensorType.bh1750,
    this.i2cAddr = 0x23,
    this.label = '',
  });

  factory LightSensorSlotConfig.fromJson(Map<String, dynamic> json) {
    final type = LightSensorType.fromValue((json['type'] as num?)?.toInt() ?? 0);
    final rawAddr = (json['i2c_addr'] as num?)?.toInt() ?? 0;
    return LightSensorSlotConfig(
      type: type,
      i2cAddr: rawAddr > 0 ? rawAddr : 0x23,
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.value,
    'i2c_addr': type == LightSensorType.bh1750 ? (i2cAddr > 0 ? i2cAddr : 0x23) : 0,
    'label': label,
  };

  LightSensorSlotConfig copyWith({
    LightSensorType? type,
    int? i2cAddr,
    String? label,
  }) {
    return LightSensorSlotConfig(
      type: type ?? this.type,
      i2cAddr: i2cAddr ?? this.i2cAddr,
      label: label ?? this.label,
    );
  }
}

class MotionSensorSlotConfig {
  final MotionSensorType type;
  final int pin;
  final String label;

  const MotionSensorSlotConfig({
    this.type = MotionSensorType.pir,
    this.pin = 32,
    this.label = '',
  });

  factory MotionSensorSlotConfig.fromJson(Map<String, dynamic> json) {
    return MotionSensorSlotConfig(
      type: MotionSensorType.fromValue((json['type'] as num?)?.toInt() ?? 0),
      pin: (json['pin'] as num?)?.toInt() ?? 255,
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.value,
    'pin': pin,
    'label': label,
  };

  MotionSensorSlotConfig copyWith({
    MotionSensorType? type,
    int? pin,
    String? label,
  }) {
    return MotionSensorSlotConfig(
      type: type ?? this.type,
      pin: pin ?? this.pin,
      label: label ?? this.label,
    );
  }
}

class ProbeSensorSlotConfig {
  final ProbeSensorType type;
  final int pin;
  final String label;

  const ProbeSensorSlotConfig({
    this.type = ProbeSensorType.ds18b20,
    this.pin = 15,
    this.label = '',
  });

  factory ProbeSensorSlotConfig.fromJson(Map<String, dynamic> json) {
    return ProbeSensorSlotConfig(
      type: ProbeSensorType.fromValue((json['type'] as num?)?.toInt() ?? 0),
      pin: (json['pin'] as num?)?.toInt() ?? 255,
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.value,
    'pin': pin,
    'label': label,
  };

  ProbeSensorSlotConfig copyWith({
    ProbeSensorType? type,
    int? pin,
    String? label,
  }) {
    return ProbeSensorSlotConfig(
      type: type ?? this.type,
      pin: pin ?? this.pin,
      label: label ?? this.label,
    );
  }
}

class UltrasonicSensorSlotConfig {
  final UltrasonicSensorType type;
  final int trigPin;
  final int echoPin;
  final int tankDepthCm;
  final int tankAirGapCm;
  final String label;

  const UltrasonicSensorSlotConfig({
    this.type = UltrasonicSensorType.hcsr04p,
    this.trigPin = 15,
    this.echoPin = 35,
    this.tankDepthCm = 150,
    this.tankAirGapCm = 15,
    this.label = '',
  });

  factory UltrasonicSensorSlotConfig.fromJson(Map<String, dynamic> json) {
    return UltrasonicSensorSlotConfig(
      type: UltrasonicSensorType.fromValue((json['type'] as num?)?.toInt() ?? 0),
      trigPin: (json['trig_pin'] as num?)?.toInt() ?? 255,
      echoPin: (json['echo_pin'] as num?)?.toInt() ?? 255,
      tankDepthCm: (json['tank_depth'] as num?)?.toInt() ?? 150,
      tankAirGapCm: (json['air_gap'] as num?)?.toInt() ?? 15,
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.value,
    'trig_pin': trigPin,
    'echo_pin': echoPin,
    'tank_depth': tankDepthCm,
    'air_gap': tankAirGapCm,
    'label': label,
  };

  UltrasonicSensorSlotConfig copyWith({
    UltrasonicSensorType? type,
    int? trigPin,
    int? echoPin,
    int? tankDepthCm,
    int? tankAirGapCm,
    String? label,
  }) {
    return UltrasonicSensorSlotConfig(
      type: type ?? this.type,
      trigPin: trigPin ?? this.trigPin,
      echoPin: echoPin ?? this.echoPin,
      tankDepthCm: tankDepthCm ?? this.tankDepthCm,
      tankAirGapCm: tankAirGapCm ?? this.tankAirGapCm,
      label: label ?? this.label,
    );
  }
}

class Mq2SensorSlotConfig {
  final bool enabled;
  final int analogPin;
  final int digitalPin;
  final String label;

  const Mq2SensorSlotConfig({
    this.enabled = true,
    this.analogPin = 34,
    this.digitalPin = 35,
    this.label = '',
  });

  factory Mq2SensorSlotConfig.fromJson(Map<String, dynamic> json) {
    return Mq2SensorSlotConfig(
      enabled: json['enabled'] as bool? ?? true,
      analogPin: (json['analog_pin'] as num?)?.toInt() ?? 255,
      digitalPin: (json['digital_pin'] as num?)?.toInt() ?? 255,
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'analog_pin': analogPin,
    'digital_pin': digitalPin,
    'label': label,
  };

  Mq2SensorSlotConfig copyWith({
    bool? enabled,
    int? analogPin,
    int? digitalPin,
    String? label,
  }) {
    return Mq2SensorSlotConfig(
      enabled: enabled ?? this.enabled,
      analogPin: analogPin ?? this.analogPin,
      digitalPin: digitalPin ?? this.digitalPin,
      label: label ?? this.label,
    );
  }
}

class SensorLimitsConfig {
  final int relays;
  final int climates;
  final int lights;
  final int motions;
  final int probes;
  final int ultrasonics;
  final int mq2s;

  const SensorLimitsConfig({
    this.relays = 8,
    this.climates = 4,
    this.lights = 2,
    this.motions = 6,
    this.probes = 4,
    this.ultrasonics = 4,
    this.mq2s = 4,
  });

  factory SensorLimitsConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SensorLimitsConfig();
    return SensorLimitsConfig(
      relays: (json['relays'] as num?)?.toInt() ?? 8,
      climates: (json['climates'] as num?)?.toInt() ?? 4,
      lights: (json['lights'] as num?)?.toInt() ?? 2,
      motions: (json['motions'] as num?)?.toInt() ?? 6,
      probes: (json['probes'] as num?)?.toInt() ?? 4,
      ultrasonics: (json['ultrasonics'] as num?)?.toInt() ?? 4,
      mq2s: (json['mq2s'] as num?)?.toInt() ?? 4,
    );
  }
}

class HardwareProfile {
  final String boardName;
  final int numRelays;
  final List<ChannelHardwareConfig> channels;

  final ClimateSensorType _dhtType;
  final int _dhtPin;
  final LightSensorType _lightType;
  final MotionSensorType _motionType;
  final int _motionPin;
  final ProbeSensorType _probeType;
  final int _probePin;
  final UltrasonicSensorType _ultrasonicType;
  final int _trigPin;
  final int _echoPin;
  final int _tankDepthCm;
  final int _tankAirGapCm;
  final bool _mq2Enabled;
  final int _mq2AnalogPin;
  final int _mq2DigitalPin;

  final List<ClimateSensorSlotConfig>? _climates;
  final List<LightSensorSlotConfig>? _lights;
  final List<MotionSensorSlotConfig>? _motions;
  final List<ProbeSensorSlotConfig>? _probes;
  final List<UltrasonicSensorSlotConfig>? _ultrasonics;
  final List<Mq2SensorSlotConfig>? _mq2Sensors;
  final SensorLimitsConfig sensorLimits;

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
    this._dhtType = ClimateSensorType.dht22,
    this._dhtPin = 4,
    this._lightType = LightSensorType.none,
    this._motionType = MotionSensorType.none,
    this._motionPin = 32,
    this._probeType = ProbeSensorType.none,
    this._probePin = 15,
    this._ultrasonicType = UltrasonicSensorType.none,
    this._trigPin = 15,
    this._echoPin = 35,
    this._tankDepthCm = 150,
    this._tankAirGapCm = 15,
    this._mq2Enabled = true,
    this._mq2AnalogPin = 34,
    this._mq2DigitalPin = 35,
    this._climates,
    this._lights,
    this._motions,
    this._probes,
    this._ultrasonics,
    this._mq2Sensors,
    this.sensorLimits = const SensorLimitsConfig(),
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

  List<ClimateSensorSlotConfig> get climates =>
      _climates ??
      (_dhtType == ClimateSensorType.none
          ? const []
          : [
              ClimateSensorSlotConfig(
                type: _dhtType,
                pin: _dhtPin,
                i2cAddr: _dhtType.defaultI2cAddr,
              ),
            ]);

  List<LightSensorSlotConfig> get lights =>
      _lights ??
      (_lightType == LightSensorType.none
          ? const []
          : [LightSensorSlotConfig(type: _lightType, i2cAddr: 0x23)]);

  List<MotionSensorSlotConfig> get motions =>
      _motions ??
      (_motionType == MotionSensorType.none
          ? const []
          : [MotionSensorSlotConfig(type: _motionType, pin: _motionPin)]);

  List<ProbeSensorSlotConfig> get probes =>
      _probes ??
      (_probeType == ProbeSensorType.none
          ? const []
          : [ProbeSensorSlotConfig(type: _probeType, pin: _probePin)]);

  List<UltrasonicSensorSlotConfig> get ultrasonics =>
      _ultrasonics ??
      (_ultrasonicType == UltrasonicSensorType.none
          ? const []
          : [
              UltrasonicSensorSlotConfig(
                type: _ultrasonicType,
                trigPin: _trigPin,
                echoPin: _echoPin,
                tankDepthCm: _tankDepthCm,
                tankAirGapCm: _tankAirGapCm,
              ),
            ]);

  List<Mq2SensorSlotConfig> get mq2Sensors =>
      _mq2Sensors ??
      ((!_mq2Enabled && _mq2AnalogPin == 255 && _mq2DigitalPin == 255)
          ? const []
          : [
              Mq2SensorSlotConfig(
                enabled: _mq2Enabled,
                analogPin: _mq2AnalogPin,
                digitalPin: _mq2DigitalPin,
              ),
            ]);

  ClimateSensorType get dhtType =>
      _climates != null
          ? (_climates.isNotEmpty ? _climates.first.type : ClimateSensorType.none)
          : _dhtType;
  int get dhtPin =>
      _climates != null
          ? (_climates.isNotEmpty ? _climates.first.pin : 255)
          : _dhtPin;

  LightSensorType get lightType =>
      _lights != null
          ? (_lights.isNotEmpty ? _lights.first.type : LightSensorType.none)
          : _lightType;

  MotionSensorType get motionType =>
      _motions != null
          ? (_motions.isNotEmpty ? _motions.first.type : MotionSensorType.none)
          : _motionType;
  int get motionPin =>
      _motions != null
          ? (_motions.isNotEmpty ? _motions.first.pin : 255)
          : _motionPin;

  ProbeSensorType get probeType =>
      _probes != null
          ? (_probes.isNotEmpty ? _probes.first.type : ProbeSensorType.none)
          : _probeType;
  int get probePin =>
      _probes != null
          ? (_probes.isNotEmpty ? _probes.first.pin : 255)
          : _probePin;

  UltrasonicSensorType get ultrasonicType =>
      _ultrasonics != null
          ? (_ultrasonics.isNotEmpty
                ? _ultrasonics.first.type
                : UltrasonicSensorType.none)
          : _ultrasonicType;
  int get trigPin =>
      _ultrasonics != null
          ? (_ultrasonics.isNotEmpty ? _ultrasonics.first.trigPin : 255)
          : _trigPin;
  int get echoPin =>
      _ultrasonics != null
          ? (_ultrasonics.isNotEmpty ? _ultrasonics.first.echoPin : 255)
          : _echoPin;
  int get tankDepthCm =>
      _ultrasonics != null
          ? (_ultrasonics.isNotEmpty ? _ultrasonics.first.tankDepthCm : 150)
          : _tankDepthCm;
  int get tankAirGapCm =>
      _ultrasonics != null
          ? (_ultrasonics.isNotEmpty ? _ultrasonics.first.tankAirGapCm : 15)
          : _tankAirGapCm;

  bool get mq2Enabled =>
      _mq2Sensors != null
          ? _mq2Sensors.any((g) => g.enabled)
          : _mq2Enabled;
  int get mq2AnalogPin =>
      _mq2Sensors != null
          ? (_mq2Sensors.isNotEmpty ? _mq2Sensors.first.analogPin : 255)
          : _mq2AnalogPin;
  int get mq2DigitalPin =>
      _mq2Sensors != null
          ? (_mq2Sensors.isNotEmpty ? _mq2Sensors.first.digitalPin : 255)
          : _mq2DigitalPin;

  bool get hasAnyI2cSensor =>
      climates.any((c) => c.type.isI2c) ||
      lights.any((l) => l.type != LightSensorType.none);

  factory HardwareProfile.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['channels'] as List<dynamic>? ?? [];
    final channels = rawChannels
        .map((c) => ChannelHardwareConfig.fromJson(Map<String, dynamic>.from(c as Map)))
        .toList();

    List<T>? parseSlotList<T>(
      String key,
      T Function(Map<String, dynamic>) builder,
    ) {
      final raw = json[key];
      if (raw is! List) return null;
      return raw
          .whereType<Map>()
          .map((e) => builder(Map<String, dynamic>.from(e)))
          .toList();
    }

    final dht = json['dht'] as Map<String, dynamic>?;
    final light = json['light'] as Map<String, dynamic>?;
    final motion = json['motion'] as Map<String, dynamic>?;
    final probe = json['probe'] as Map<String, dynamic>?;
    final ultrasonic = json['ultrasonic'] as Map<String, dynamic>?;
    final mq2 = json['mq2'] as Map<String, dynamic>?;
    final buzzer = json['buzzer'] as Map<String, dynamic>?;
    final lcd = json['lcd'] as Map<String, dynamic>?;
    final caps = json['pin_capabilities'] as Map<String, dynamic>?;

    final parsedClimates = parseSlotList('climates', ClimateSensorSlotConfig.fromJson);
    final parsedLights = parseSlotList('lights', LightSensorSlotConfig.fromJson);
    final parsedMotions = parseSlotList('motions', MotionSensorSlotConfig.fromJson);
    final parsedProbes = parseSlotList('probes', ProbeSensorSlotConfig.fromJson);
    final parsedUltrasonics = parseSlotList('ultrasonics', UltrasonicSensorSlotConfig.fromJson);
    final parsedMq2s = parseSlotList('mq2_sensors', Mq2SensorSlotConfig.fromJson);

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
      climates: parsedClimates,
      lights: parsedLights,
      motions: parsedMotions,
      probes: parsedProbes,
      ultrasonics: parsedUltrasonics,
      mq2Sensors: parsedMq2s,
      sensorLimits: SensorLimitsConfig.fromJson(
        caps?['sensor_limits'] as Map<String, dynamic>?,
      ),
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

  Map<String, dynamic> toJson() {
    final cList = climates;
    final lList = lights;
    final mList = motions;
    final pList = probes;
    final uList = ultrasonics;
    final gList = mq2Sensors;
    return {
      'board_name': boardName,
      'num_relays': numRelays,
      'channels': channels.map((c) => c.toJson()).toList(),
      'climates': cList.map((e) => e.toJson()).toList(),
      'lights': lList.map((e) => e.toJson()).toList(),
      'motions': mList.map((e) => e.toJson()).toList(),
      'probes': pList.map((e) => e.toJson()).toList(),
      'ultrasonics': uList.map((e) => e.toJson()).toList(),
      'mq2_sensors': gList.map((e) => e.toJson()).toList(),
      'dht': {
        'type': dhtType.value,
        'pin': dhtPin,
        if (cList.isNotEmpty && cList.first.type.isI2c)
          'i2c_addr': cList.first.i2cAddr,
      },
      'light': {
        'type': lightType.value,
        if (lList.isNotEmpty) 'i2c_addr': lList.first.i2cAddr,
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
  }

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
    List<ClimateSensorSlotConfig>? climates,
    List<LightSensorSlotConfig>? lights,
    List<MotionSensorSlotConfig>? motions,
    List<ProbeSensorSlotConfig>? probes,
    List<UltrasonicSensorSlotConfig>? ultrasonics,
    List<Mq2SensorSlotConfig>? mq2Sensors,
    SensorLimitsConfig? sensorLimits,
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
    final curClimates = this.climates;
    final nextClimates = climates ??
        (dhtType != null || dhtPin != null
            ? (curClimates.isEmpty
                ? [
                    ClimateSensorSlotConfig(
                      type: dhtType ?? this.dhtType,
                      pin: dhtPin ?? this.dhtPin,
                      i2cAddr: (dhtType ?? this.dhtType).defaultI2cAddr,
                    ),
                  ]
                : [
                    curClimates.first.copyWith(
                      type: dhtType,
                      pin: dhtPin,
                      i2cAddr: dhtType?.defaultI2cAddr,
                    ),
                    ...curClimates.skip(1),
                  ])
            : curClimates);
    final curLights = this.lights;
    final nextLights = lights ??
        (lightType != null
            ? (curLights.isEmpty
                ? [LightSensorSlotConfig(type: lightType, i2cAddr: 0x23)]
                : [
                    curLights.first.copyWith(type: lightType),
                    ...curLights.skip(1),
                  ])
            : curLights);
    final curMotions = this.motions;
    final nextMotions = motions ??
        (motionType != null || motionPin != null
            ? (curMotions.isEmpty
                ? [
                    MotionSensorSlotConfig(
                      type: motionType ?? this.motionType,
                      pin: motionPin ?? this.motionPin,
                    ),
                  ]
                : [
                    curMotions.first.copyWith(
                      type: motionType,
                      pin: motionPin,
                    ),
                    ...curMotions.skip(1),
                  ])
            : curMotions);
    final curProbes = this.probes;
    final nextProbes = probes ??
        (probeType != null || probePin != null
            ? (curProbes.isEmpty
                ? [
                    ProbeSensorSlotConfig(
                      type: probeType ?? this.probeType,
                      pin: probePin ?? this.probePin,
                    ),
                  ]
                : [
                    curProbes.first.copyWith(
                      type: probeType,
                      pin: probePin,
                    ),
                    ...curProbes.skip(1),
                  ])
            : curProbes);
    final curUltrasonics = this.ultrasonics;
    final nextUltrasonics = ultrasonics ??
        (ultrasonicType != null ||
                trigPin != null ||
                echoPin != null ||
                tankDepthCm != null ||
                tankAirGapCm != null
            ? (curUltrasonics.isEmpty
                ? [
                    UltrasonicSensorSlotConfig(
                      type: ultrasonicType ?? this.ultrasonicType,
                      trigPin: trigPin ?? this.trigPin,
                      echoPin: echoPin ?? this.echoPin,
                      tankDepthCm: tankDepthCm ?? this.tankDepthCm,
                      tankAirGapCm: tankAirGapCm ?? this.tankAirGapCm,
                    ),
                  ]
                : [
                    curUltrasonics.first.copyWith(
                      type: ultrasonicType,
                      trigPin: trigPin,
                      echoPin: echoPin,
                      tankDepthCm: tankDepthCm,
                      tankAirGapCm: tankAirGapCm,
                    ),
                    ...curUltrasonics.skip(1),
                  ])
            : curUltrasonics);
    final curMq2s = this.mq2Sensors;
    final nextMq2s = mq2Sensors ??
        (mq2Enabled != null || mq2AnalogPin != null || mq2DigitalPin != null
            ? (curMq2s.isEmpty
                ? [
                    Mq2SensorSlotConfig(
                      enabled: mq2Enabled ?? this.mq2Enabled,
                      analogPin: mq2AnalogPin ?? this.mq2AnalogPin,
                      digitalPin: mq2DigitalPin ?? this.mq2DigitalPin,
                    ),
                  ]
                : [
                    curMq2s.first.copyWith(
                      enabled: mq2Enabled,
                      analogPin: mq2AnalogPin,
                      digitalPin: mq2DigitalPin,
                    ),
                    ...curMq2s.skip(1),
                  ])
            : curMq2s);

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
      climates: nextClimates,
      lights: nextLights,
      motions: nextMotions,
      probes: nextProbes,
      ultrasonics: nextUltrasonics,
      mq2Sensors: nextMq2s,
      sensorLimits: sensorLimits ?? this.sensorLimits,
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
    0, 2, 4, 5, 12, 13, 14, 15, 16
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
          ? [0, 2, 4, 5, 12, 13, 14, 15, 16, 17]
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
