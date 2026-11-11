class AutomationRule {
  final int id;
  final bool enabled;
  final String name;
  final int sensor; // 0: Temp, 1: Hum, 2: Gas
  final int condition; // 0: Above (>=), 1: Below (<=)
  final double threshold;
  final double hysteresis;
  final int targetRelay; // 0..4
  final int action; // 0: ON, 1: OFF
  final bool triggered;

  AutomationRule({
    required this.id,
    required this.enabled,
    required this.name,
    required this.sensor,
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
    'cond': condition,
    'th': threshold,
    'hyst': hysteresis,
    'relay': targetRelay,
    'act': action,
  };

  String get sensorLabel {
    switch (sensor) {
      case 0:
        return 'Temperature';
      case 1:
        return 'Humidity';
      case 2:
        return 'Gas Sensor';
      case 3:
        return 'Ambient Light';
      case 4:
        return 'Water Temp Probe';
      case 5:
        return 'Water Tank Level';
      default:
        return 'Unknown';
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
      default:
        return '';
    }
  }

  String get actionLabel => action == 0 ? 'Turn ON' : 'Turn OFF';

  AutomationRule copyWith({
    int? id,
    bool? enabled,
    String? name,
    int? sensor,
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
      condition: condition ?? this.condition,
      threshold: threshold ?? this.threshold,
      hysteresis: hysteresis ?? this.hysteresis,
      targetRelay: targetRelay ?? this.targetRelay,
      action: action ?? this.action,
      triggered: triggered ?? this.triggered,
    );
  }
}
