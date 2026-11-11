class SensorTelemetry {
  final double temperature;
  final double humidity;
  final bool dhtFault;
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

  // Gas MQ-2
  final int gasRaw;
  final int gasPercent;
  final bool gasAlarm;
  final bool gasWarming;
  final int gasThreshold;
  final int gasMax;

  SensorTelemetry({
    this.temperature = 0.0,
    this.humidity = 0.0,
    this.dhtFault = false,
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
  });

  factory SensorTelemetry.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic v, double fallback) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    int parseInt(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return SensorTelemetry(
      temperature: parseDouble(json['temperature'], 0.0),
      humidity: parseDouble(json['humidity'], 0.0),
      dhtFault: json['dht_fault'] as bool? ?? false,
      tempThreshold: parseDouble(json['temp_threshold'], 45.0),
      pressure: parseDouble(json['pressure'], 0.0),
      pressureEnabled: json['pressure_enabled'] as bool? ?? false,
      lux: parseDouble(json['lux'], 0.0),
      luxEnabled: json['lux_enabled'] as bool? ?? false,
      motionDetected: json['motion'] as bool? ?? false,
      motionAgeSeconds: parseInt(json['motion_age_s'], 99999),
      motionEnabled: json['motion_enabled'] as bool? ?? false,
      probeTemp: parseDouble(json['probe_temp'], -127.0),
      probeFault: json['probe_fault'] as bool? ?? false,
      probeEnabled: json['probe_enabled'] as bool? ?? false,
      distanceCm: parseDouble(json['distance_cm'], 0.0),
      tankLevelPct: parseInt(json['tank_level_pct'], 0),
      tankEnabled: json['tank_enabled'] as bool? ?? false,
      gasRaw: parseInt(json['gas_raw'], 0),
      gasPercent: parseInt(json['gas_percent'], 0),
      gasAlarm: json['gas_alarm'] as bool? ?? false,
      gasWarming: json['gas_warming'] as bool? ?? false,
      gasThreshold: parseInt(json['gas_threshold'], 600),
      gasMax: parseInt(json['gas_max'], 4095),
    );
  }

  Map<String, dynamic> toJson() => {
    'temperature': temperature,
    'humidity': humidity,
    'dht_fault': dhtFault,
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
  };
}
