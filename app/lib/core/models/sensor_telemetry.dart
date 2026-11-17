double _parseDouble(dynamic v, double fallback) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int _parseInt(dynamic v, int fallback) {
  if (v == null) return fallback;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool _parseBool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes' || s == 'on') return true;
    if (s == 'false' || s == '0' || s == 'no' || s == 'off') return false;
  }
  return fallback;
}

/// Returns true when [label] contains a user-defined name rather than a
/// firmware-generated placeholder such as `"Climate 1"` or `"Tank #2"`.
bool isCustomSensorLabel(String label, String defaultPrefix) {
  final s = label.trim();
  if (s.isEmpty) return false;
  return !RegExp(
    '^${RegExp.escape(defaultPrefix)}(?:\\s*#?\\d+)?\$',
    caseSensitive: false,
  ).hasMatch(s);
}

class ClimateReading {
  final int index;
  final bool enabled;
  final int type;
  final String typeName;
  final String label;
  final double temperature;
  final double humidity;
  final double pressure;
  final bool barometer;
  final bool humidityEnabled;
  final bool fault;
  final bool tempAlarm;
  final double tempOffset;
  final double humOffset;

  const ClimateReading({
    this.index = 0,
    this.enabled = false,
    this.type = 0,
    this.typeName = '',
    this.label = '',
    this.temperature = 0.0,
    this.humidity = 0.0,
    this.pressure = 0.0,
    this.barometer = false,
    this.humidityEnabled = true,
    this.fault = false,
    this.tempAlarm = false,
    this.tempOffset = 0.0,
    this.humOffset = 0.0,
  });

  String get displayName =>
      label.trim().isNotEmpty ? label.trim() : 'Climate #${index + 1}';

  bool get hasCustomLabel => isCustomSensorLabel(label, 'Climate');

  factory ClimateReading.fromJson(Map<String, dynamic> json) {
    final parsedType = _parseInt(json['type'], 0);
    return ClimateReading(
      index: _parseInt(json['index'], 0),
      enabled: _parseBool(json['enabled'], false),
      type: parsedType,
      typeName: json['type_name']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      temperature: _parseDouble(json['temperature'], 0.0),
      humidity: _parseDouble(json['humidity'], 0.0),
      pressure: _parseDouble(json['pressure'], 0.0),
      barometer: _parseBool(json['barometer'], false),
      humidityEnabled: _parseBool(json['humidity_enabled'], parsedType != 7),
      fault: _parseBool(json['fault'], false),
      tempAlarm: _parseBool(json['temp_alarm'], false),
      tempOffset: _parseDouble(json['temp_offset'], 0.0),
      humOffset: _parseDouble(json['hum_offset'], 0.0),
    );
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'enabled': enabled,
    'type': type,
    'type_name': typeName,
    'label': label,
    'temperature': temperature,
    'humidity': humidity,
    'pressure': pressure,
    'barometer': barometer,
    'humidity_enabled': humidityEnabled,
    'fault': fault,
    'temp_alarm': tempAlarm,
    'temp_offset': tempOffset,
    'hum_offset': humOffset,
  };
}

class LightReading {
  final int index;
  final bool enabled;
  final int i2cAddr;
  final String label;
  final double lux;

  const LightReading({
    this.index = 0,
    this.enabled = false,
    this.i2cAddr = 0x23,
    this.label = '',
    this.lux = 0.0,
  });

  String get displayName =>
      label.trim().isNotEmpty ? label.trim() : 'Light #${index + 1}';

  bool get hasCustomLabel => isCustomSensorLabel(label, 'Light');

  factory LightReading.fromJson(Map<String, dynamic> json) => LightReading(
    index: _parseInt(json['index'], 0),
    enabled: _parseBool(json['enabled'], false),
    i2cAddr: _parseInt(json['i2c_addr'], 0x23),
    label: json['label']?.toString() ?? '',
    lux: _parseDouble(json['lux'], 0.0),
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'enabled': enabled,
    'i2c_addr': i2cAddr,
    'label': label,
    'lux': lux,
  };
}

class MotionReading {
  final int index;
  final bool enabled;
  final int type;
  final String label;
  final bool detected;
  final int ageSeconds;

  const MotionReading({
    this.index = 0,
    this.enabled = false,
    this.type = 0,
    this.label = '',
    this.detected = false,
    this.ageSeconds = 99999,
  });

  String get displayName =>
      label.trim().isNotEmpty ? label.trim() : 'Motion #${index + 1}';

  bool get hasCustomLabel => isCustomSensorLabel(label, 'Motion');

  factory MotionReading.fromJson(Map<String, dynamic> json) => MotionReading(
    index: _parseInt(json['index'], 0),
    enabled: _parseBool(json['enabled'], false),
    type: _parseInt(json['type'], 0),
    label: json['label']?.toString() ?? '',
    detected: _parseBool(json['detected'], false),
    ageSeconds: _parseInt(json['age_s'], 99999),
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'enabled': enabled,
    'type': type,
    'label': label,
    'detected': detected,
    'age_s': ageSeconds,
  };
}

class ProbeReading {
  final int index;
  final bool enabled;
  final String label;
  final double temperature;
  final bool fault;

  const ProbeReading({
    this.index = 0,
    this.enabled = false,
    this.label = '',
    this.temperature = -127.0,
    this.fault = false,
  });

  String get displayName =>
      label.trim().isNotEmpty ? label.trim() : 'Probe #${index + 1}';

  bool get hasCustomLabel => isCustomSensorLabel(label, 'Probe');

  factory ProbeReading.fromJson(Map<String, dynamic> json) => ProbeReading(
    index: _parseInt(json['index'], 0),
    enabled: _parseBool(json['enabled'], false),
    label: json['label']?.toString() ?? '',
    temperature: _parseDouble(json['temperature'], -127.0),
    fault: _parseBool(json['fault'], false),
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'enabled': enabled,
    'label': label,
    'temperature': temperature,
    'fault': fault,
  };
}

class TankReading {
  final int index;
  final bool enabled;
  final int type;
  final String label;
  final double distanceCm;
  final int levelPct;

  const TankReading({
    this.index = 0,
    this.enabled = false,
    this.type = 0,
    this.label = '',
    this.distanceCm = 0.0,
    this.levelPct = 0,
  });

  String get displayName =>
      label.trim().isNotEmpty ? label.trim() : 'Tank #${index + 1}';

  bool get hasCustomLabel => isCustomSensorLabel(label, 'Tank');

  factory TankReading.fromJson(Map<String, dynamic> json) => TankReading(
    index: _parseInt(json['index'], 0),
    enabled: _parseBool(json['enabled'], false),
    type: _parseInt(json['type'], 0),
    label: json['label']?.toString() ?? '',
    distanceCm: _parseDouble(json['distance_cm'], 0.0),
    levelPct: _parseInt(json['level_pct'], 0),
  );

  Map<String, dynamic> toJson() => {
    'index': index,
    'enabled': enabled,
    'type': type,
    'label': label,
    'distance_cm': distanceCm,
    'level_pct': levelPct,
  };
}

class Mq2Reading {
  final int index;
  final int type;
  final String typeName;
  final int i2cAddr;
  final bool enabled;
  final bool hwAllowed;
  final String label;
  final String unit;
  final int gasMax;
  final int raw;
  final int percent;
  final int threshold;
  final int baseline;
  final bool alarm;
  final bool digital;
  final bool warming;

  const Mq2Reading({
    this.index = 0,
    this.type = 0,
    this.typeName = 'MQ-2',
    this.i2cAddr = 0,
    this.enabled = false,
    this.hwAllowed = false,
    this.label = '',
    this.unit = 'ADC',
    this.gasMax = 4095,
    this.raw = 0,
    this.percent = 0,
    this.threshold = 400,
    this.baseline = 0,
    this.alarm = false,
    this.digital = false,
    this.warming = false,
  });

  bool get isSgp40 => type == 1 || unit.toUpperCase() == 'VOC';

  String get displayName =>
      label.trim().isNotEmpty ? label.trim() : 'Gas #${index + 1}';

  bool get hasCustomLabel => isCustomSensorLabel(label, 'Gas');

  factory Mq2Reading.fromJson(Map<String, dynamic> json) {
    const typeNames = <int, String>{
      0: 'MQ-2',
      1: 'SGP40',
      2: 'MQ-3',
      3: 'MQ-4',
      4: 'MQ-5',
      5: 'MQ-6',
      6: 'MQ-7',
      7: 'MQ-8',
      8: 'MQ-9',
      9: 'MQ-135',
    };
    final parsedType = _parseInt(json['type'], 0);
    final parsedUnit =
        json['unit']?.toString() ?? (parsedType == 1 ? 'VOC' : 'ADC');
    final parsedGasMax =
        _parseInt(json['gas_max'], parsedType == 1 ? 500 : 4095);
    return Mq2Reading(
      index: _parseInt(json['index'], 0),
      type: parsedType,
      typeName: json['type_name']?.toString() ??
          (typeNames[parsedType] ?? 'MQ-2'),
      i2cAddr: _parseInt(json['i2c_addr'], parsedType == 1 ? 0x59 : 0),
      enabled: _parseBool(json['enabled'], false),
      hwAllowed: _parseBool(json['hw_allowed'], false),
      label: json['label']?.toString() ?? '',
      unit: parsedUnit,
      gasMax: parsedGasMax,
      raw: _parseInt(json['raw'], 0),
      percent: _parseInt(json['percent'], 0),
      threshold: _parseInt(json['threshold'], parsedType == 1 ? 250 : 400),
      baseline: _parseInt(json['baseline'], 0),
      alarm: _parseBool(json['alarm'], false),
      digital: _parseBool(json['digital'], false),
      warming: _parseBool(json['warming'], false),
    );
  }

  Map<String, dynamic> toJson() => {
    'index': index,
    'type': type,
    'type_name': typeName,
    'i2c_addr': i2cAddr,
    'enabled': enabled,
    'hw_allowed': hwAllowed,
    'label': label,
    'unit': unit,
    'gas_max': gasMax,
    'raw': raw,
    'percent': percent,
    'threshold': threshold,
    'baseline': baseline,
    'alarm': alarm,
    'digital': digital,
    'warming': warming,
  };
}

class SensorTelemetry {
  final double temperature;
  final double humidity;
  final bool dhtFault;
  final bool dhtEnabled;
  final bool humidityEnabled;
  bool get dhtError => dhtFault;
  final double tempThreshold;

  // Barometer & Light
  final double pressure;
  final bool pressureEnabled;
  final double lux;
  final bool luxEnabled;

  // Motion / Presence
  final bool motionDetected;
  final int motionAgeSeconds;
  final bool motionEnabled;

  // Submersible Probe
  final double probeTemp;
  final bool probeFault;
  final bool probeEnabled;

  // Ultrasonic Tank Level
  final double distanceCm;
  final int tankLevelPct;
  final bool tankEnabled;

  // Gas & Air Quality (MQ Series / SGP40)
  final int gasRaw;
  final int gasPercent;
  final bool gasAlarm;
  final bool gasWarming;
  final int gasThreshold;
  final int gasMax;
  final String gasUnit;
  final String gasTypeName;
  final bool gasEnabled;
  final bool gasHwAllowed;

  // Multi-instance sensor arrays
  final List<ClimateReading> climates;
  final List<LightReading> lights;
  final List<MotionReading> motions;
  final List<ProbeReading> probes;
  final List<TankReading> tanks;
  final List<Mq2Reading> mq2s;

  bool get hasActiveClimate =>
      climates.isNotEmpty ? climates.any((c) => c.enabled) : dhtEnabled;
  bool get hasActiveGas => mq2s.isNotEmpty
      ? mq2s.any((m) => m.enabled || m.hwAllowed)
      : (gasEnabled || gasHwAllowed);
  bool get hasActiveLight =>
      lights.isNotEmpty ? lights.any((l) => l.enabled) : luxEnabled;
  bool get hasActiveMotion =>
      motions.isNotEmpty ? motions.any((m) => m.enabled) : motionEnabled;
  bool get hasActiveProbe => probes.isNotEmpty
      ? probes.any((p) => p.enabled && (p.temperature > -55 || p.fault))
      : (probeEnabled && (probeTemp > -55 || probeFault));
  bool get hasActiveTank =>
      tanks.isNotEmpty ? tanks.any((u) => u.enabled) : tankEnabled;
  bool get hasAnySensor =>
      hasActiveClimate ||
      (pressureEnabled && pressure > 300) ||
      hasActiveLight ||
      hasActiveMotion ||
      hasActiveProbe ||
      hasActiveTank ||
      hasActiveGas;

  SensorTelemetry({
    this.temperature = 0.0,
    this.humidity = 0.0,
    this.dhtFault = false,
    this.dhtEnabled = true,
    this.humidityEnabled = true,
    this.tempThreshold = 45.0,
    this.pressure = 0.0,
    this.pressureEnabled = false,
    this.lux = 0.0,
    this.luxEnabled = false,
    this.motionDetected = false,
    this.motionAgeSeconds = 99999,
    this.motionEnabled = false,
    this.probeTemp = -127.0,
    this.probeFault = false,
    this.probeEnabled = false,
    this.distanceCm = 0.0,
    this.tankLevelPct = 0,
    this.tankEnabled = false,
    this.gasRaw = 0,
    this.gasPercent = 0,
    this.gasAlarm = false,
    this.gasWarming = false,
    this.gasThreshold = 600,
    this.gasMax = 4095,
    this.gasUnit = 'ADC',
    this.gasTypeName = 'MQ-2',
    this.gasEnabled = false,
    this.gasHwAllowed = false,
    this.climates = const [],
    this.lights = const [],
    this.motions = const [],
    this.probes = const [],
    this.tanks = const [],
    this.mq2s = const [],
  });

  factory SensorTelemetry.fromJson(Map<String, dynamic> json) {
    List<T> parseList<T>(
      dynamic raw,
      T Function(Map<String, dynamic>) builder,
    ) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => builder(Map<String, dynamic>.from(e)))
          .toList();
    }

    final climatesList = parseList(json['climates'], ClimateReading.fromJson);
    final mq2sList = parseList(json['mq2s'], Mq2Reading.fromJson);
    final parsedDhtEnabled = _parseBool(
      json['dht_enabled'],
      climatesList.isNotEmpty
          ? climatesList.any((c) => c.enabled)
          : (json.containsKey('temperature') || json.containsKey('humidity')),
    );
    final parsedHumidityEnabled = _parseBool(
      json['humidity_enabled'],
      climatesList.isNotEmpty ? climatesList.first.humidityEnabled : true,
    );
    final parsedGasUnit = json['gas_unit']?.toString() ??
        (mq2sList.isNotEmpty ? mq2sList.first.unit : 'ADC');
    final parsedGasEnabled = _parseBool(
      json['gas_enabled'],
      mq2sList.isNotEmpty
          ? mq2sList.any((m) => m.enabled)
          : (_parseInt(json['gas_raw'], 0) > 0),
    );
    final parsedGasHwAllowed = _parseBool(
      json['gas_hw_allowed'],
      mq2sList.isNotEmpty
          ? mq2sList.any((m) => m.hwAllowed)
          : parsedGasEnabled,
    );

    return SensorTelemetry(
      temperature: _parseDouble(json['temperature'], 0.0),
      humidity: _parseDouble(json['humidity'], 0.0),
      dhtFault: _parseBool(json['dht_fault'], false),
      dhtEnabled: parsedDhtEnabled,
      humidityEnabled: parsedHumidityEnabled,
      tempThreshold: _parseDouble(json['temp_threshold'], 45.0),
      pressure: _parseDouble(json['pressure'], 0.0),
      pressureEnabled: _parseBool(json['pressure_enabled'], false),
      lux: _parseDouble(json['lux'], 0.0),
      luxEnabled: _parseBool(json['lux_enabled'], false),
      motionDetected: _parseBool(json['motion'], false),
      motionAgeSeconds: _parseInt(json['motion_age_s'], 99999),
      motionEnabled: _parseBool(json['motion_enabled'], false),
      probeTemp: _parseDouble(json['probe_temp'], -127.0),
      probeFault: _parseBool(json['probe_fault'], false),
      probeEnabled: _parseBool(json['probe_enabled'], false),
      distanceCm: _parseDouble(json['distance_cm'], 0.0),
      tankLevelPct: _parseInt(json['tank_level_pct'], 0),
      tankEnabled: _parseBool(json['tank_enabled'], false),
      gasRaw: _parseInt(json['gas_raw'], 0),
      gasPercent: _parseInt(json['gas_percent'], 0),
      gasAlarm: _parseBool(json['gas_alarm'], false),
      gasWarming: _parseBool(json['gas_warming'], false),
      gasThreshold: _parseInt(json['gas_threshold'], 600),
      gasMax: _parseInt(json['gas_max'], parsedGasUnit == 'VOC' ? 500 : 4095),
      gasUnit: parsedGasUnit,
      gasTypeName: json['gas_type_name']?.toString() ??
          (mq2sList.isNotEmpty && mq2sList.first.typeName.isNotEmpty
              ? mq2sList.first.typeName
              : (parsedGasUnit.toUpperCase() == 'VOC' ? 'SGP40' : 'MQ-2')),
      gasEnabled: parsedGasEnabled,
      gasHwAllowed: parsedGasHwAllowed,
      climates: climatesList,
      lights: parseList(json['lights'], LightReading.fromJson),
      motions: parseList(json['motions'], MotionReading.fromJson),
      probes: parseList(json['probes'], ProbeReading.fromJson),
      tanks: parseList(json['tanks'], TankReading.fromJson),
      mq2s: mq2sList,
    );
  }

  Map<String, dynamic> toJson() => {
    'temperature': temperature,
    'humidity': humidity,
    'dht_fault': dhtFault,
    'dht_enabled': dhtEnabled,
    'humidity_enabled': humidityEnabled,
    'temp_threshold': tempThreshold,
    'pressure': pressure,
    'pressure_enabled': pressureEnabled,
    'lux': lux,
    'lux_enabled': luxEnabled,
    'motion': motionDetected,
    'motion_age_s': motionAgeSeconds,
    'motion_enabled': motionEnabled,
    'probe_temp': probeTemp,
    'probe_fault': probeFault,
    'probe_enabled': probeEnabled,
    'distance_cm': distanceCm,
    'tank_level_pct': tankLevelPct,
    'tank_enabled': tankEnabled,
    'gas_raw': gasRaw,
    'gas_percent': gasPercent,
    'gas_alarm': gasAlarm,
    'gas_warming': gasWarming,
    'gas_threshold': gasThreshold,
    'gas_max': gasMax,
    'gas_unit': gasUnit,
    'gas_enabled': gasEnabled,
    'gas_hw_allowed': gasHwAllowed,
    if (climates.isNotEmpty)
      'climates': climates.map((e) => e.toJson()).toList(),
    if (lights.isNotEmpty) 'lights': lights.map((e) => e.toJson()).toList(),
    if (motions.isNotEmpty)
      'motions': motions.map((e) => e.toJson()).toList(),
    if (probes.isNotEmpty) 'probes': probes.map((e) => e.toJson()).toList(),
    if (tanks.isNotEmpty) 'tanks': tanks.map((e) => e.toJson()).toList(),
    if (mq2s.isNotEmpty) 'mq2s': mq2s.map((e) => e.toJson()).toList(),
  };
}
