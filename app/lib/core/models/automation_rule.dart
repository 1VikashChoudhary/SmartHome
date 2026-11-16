import 'sensor_telemetry.dart';

class AutomationRule {
  final int id;
  final bool enabled;
  final String name;
  final int sensor; // 0: Temp, 1: Hum, 2: Gas, 3: Lux, 4: Probe, 5: Tank, 6: Motion
  final int sensorIndex; // 0-based index within the sensor group (s_idx)
  final int condition; // 0: Above (>=), 1: Below (<=)
  final double threshold;
  final double hysteresis;
  final int targetRelay; // 0..7 or 255 (All)
  final int action; // 0: ON, 1: OFF
  final bool triggered;

  AutomationRule({
    required this.id,
    required this.enabled,
    required this.name,
    required this.sensor,
    this.sensorIndex = 0,
    required this.condition,
    required this.threshold,
    required this.hysteresis,
    required this.targetRelay,
    required this.action,
    this.triggered = false,
  });

  factory AutomationRule.fromJson(Map<String, dynamic> json) {
    return AutomationRule(
      id: (json['id'] as num?)?.toInt() ?? 0,
      enabled: json['en'] as bool? ?? true,
      name: json['name'] as String? ?? 'Rule',
      sensor: (json['sensor'] as num?)?.toInt() ?? 0,
      sensorIndex:
          (json['s_idx'] as num?)?.toInt() ??
          (json['sensor_index'] as num?)?.toInt() ??
          0,
      condition: (json['cond'] as num?)?.toInt() ?? 0,
      threshold: (json['th'] as num?)?.toDouble() ?? 0.0,
      hysteresis: (json['hyst'] as num?)?.toDouble() ?? 0.5,
      targetRelay: (json['relay'] as num?)?.toInt() ?? 0,
      action: (json['act'] as num?)?.toInt() ?? 0,
      triggered: json['trig'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'en': enabled,
    'name': name,
    'sensor': sensor,
    's_idx': sensorIndex,
    'cond': condition,
    'th': threshold,
    'hyst': hysteresis,
    'relay': targetRelay,
    'act': action,
  };

  String get sensorLabel {
    final idxSuffix = sensorIndex > 0 ? ' #${sensorIndex + 1}' : '';
    switch (sensor) {
      case 0:
        return 'Temperature$idxSuffix';
      case 1:
        return 'Humidity$idxSuffix';
      case 2:
        return 'Gas Sensor$idxSuffix';
      case 3:
        return 'Ambient Light$idxSuffix';
      case 4:
        return 'Water Temp Probe$idxSuffix';
      case 5:
        return 'Water Tank Level$idxSuffix';
      case 6:
        return 'Motion / Occupancy$idxSuffix';
      default:
        return 'Unknown$idxSuffix';
    }
  }

  String get conditionSymbol => condition == 0 ? '≥' : '≤';

  String get unit {
    switch (sensor) {
      case 0:
      case 4:
        return '°C';
      case 1:
      case 5:
        return '%';
      case 2:
        return 'ADC';
      case 3:
        return 'lx';
      case 6:
        return '';
      default:
        return '';
    }
  }

  /// Resolves the unit (`VOC` vs `ADC`), ceiling, and defaults for Gas slot [slotIndex].
  static ({
    String unit,
    bool isSgp40,
    double maxVal,
    double defaultThreshold,
    String defaultHyst,
  }) gasSpecFor(
    SensorTelemetry? telemetry,
    int slotIndex, {
    bool isEsp8266 = false,
  }) {
    bool isSgp = false;
    int rawMax = 0;
    if (telemetry != null) {
      if (slotIndex >= 0 && slotIndex < telemetry.mq2s.length) {
        final slot = telemetry.mq2s[slotIndex];
        isSgp = slot.isSgp40;
        rawMax = slot.gasMax;
      } else if (slotIndex == 0 && telemetry.mq2s.isEmpty) {
        isSgp = telemetry.gasUnit.toUpperCase() == 'VOC';
        rawMax = telemetry.gasMax;
      }
    }
    final maxVal = isSgp
        ? (rawMax > 0 ? rawMax.toDouble() : 500.0)
        : (rawMax > 0 ? rawMax.toDouble() : (isEsp8266 ? 1023.0 : 4095.0));
    return (
      unit: isSgp ? 'VOC' : 'ADC',
      isSgp40: isSgp,
      maxVal: maxVal,
      defaultThreshold: isSgp ? 250.0 : (isEsp8266 ? 400.0 : 800.0),
      defaultHyst: isSgp ? '25' : '30',
    );
  }

  String sensorLabelFor(SensorTelemetry? telemetry) {
    if (sensor == 2 && telemetry != null) {
      final spec = gasSpecFor(telemetry, sensorIndex);
      final idxSuffix = sensorIndex > 0 ? ' #${sensorIndex + 1}' : '';
      return '${spec.isSgp40 ? 'SGP40 VOC' : 'Gas Sensor'}$idxSuffix';
    }
    return sensorLabel;
  }

  String unitFor(SensorTelemetry? telemetry) {
    if (sensor == 2) {
      return gasSpecFor(telemetry, sensorIndex).unit;
    }
    return unit;
  }

  String get actionLabel => action == 0 ? 'Turn ON' : 'Turn OFF';

  AutomationRule copyWith({
    int? id,
    bool? enabled,
    String? name,
    int? sensor,
    int? sensorIndex,
    int? condition,
    double? threshold,
    double? hysteresis,
    int? targetRelay,
    int? action,
    bool? triggered,
  }) {
    return AutomationRule(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      name: name ?? this.name,
      sensor: sensor ?? this.sensor,
      sensorIndex: sensorIndex ?? this.sensorIndex,
      condition: condition ?? this.condition,
      threshold: threshold ?? this.threshold,
      hysteresis: hysteresis ?? this.hysteresis,
      targetRelay: targetRelay ?? this.targetRelay,
      action: action ?? this.action,
      triggered: triggered ?? this.triggered,
    );
  }
}
