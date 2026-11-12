import 'relay_channel.dart';
import 'sensor_telemetry.dart';

class SmartDevice {
  final String id;
  final String mac;
  final String ip;
  final String hostname;
  final String name;
  final String room;
  final String fwVersion;
  final int numRelays;
  final bool authRequired;
  final bool authLocked;
  final String authRole;
  final String? authUsername;
  final String? authPassword;
  final bool isOnline;
  final int rssi;
  final int signalPercent;
  final String uptime;
  final int freeHeap;
  final List<RelayChannel> relays;
  final SensorTelemetry telemetry;
  final DateTime lastSeen;
  final String platform;
  final String model;

  bool get isEsp8266 => platform.toUpperCase().contains('ESP8266') || model.toUpperCase().contains('ESP8266');
  bool get isEsp32 => !isEsp8266;

  bool get needsAuth =>
      authLocked ||
      (authRequired && (authPassword == null || authPassword!.isEmpty));

  bool get isAdmin => authRole.toLowerCase() == 'admin';
  bool get isGuest => authRole.toLowerCase() == 'guest';

  SmartDevice({
    required this.id,
    required this.mac,
    required this.ip,
    required this.hostname,
    required this.name,
    this.room = 'Unassigned',
    this.fwVersion = '3.2.0',
    this.numRelays = 5,
    this.authRequired = false,
    this.authLocked = false,
    this.authRole = 'admin',
    this.authUsername,
    this.authPassword,
    this.isOnline = true,
    this.rssi = -60,
    this.signalPercent = 80,
    this.uptime = '0m',
    this.freeHeap = 0,
    this.platform = 'ESP32',
    this.model = 'ESP32-SmartHome',
    List<RelayChannel>? relays,
    SensorTelemetry? telemetry,
    DateTime? lastSeen,
  }) : relays = relays ?? [],
       telemetry = telemetry ?? SensorTelemetry(),
       lastSeen = lastSeen ?? DateTime.now();

  factory SmartDevice.fromDiscovery(Map<String, dynamic> json, String hostIp) {
    final mac = json['mac'] as String? ?? '00:00:00:00:00:00';
    final id =
        json['device_id'] as String? ??
        'smarthome_${mac.replaceAll(':', '').toLowerCase()}';
    final name = json['device_name'] as String? ?? 'SmartHome Device';
    final hostname = json['hostname'] as String? ?? 'smarthome';
    final fw = json['fw_version'] as String? ?? '3.2.0';
    final relaysCount = (json['num_relays'] as num?)?.toInt() ?? 5;
    final auth = json['auth_required'] as bool? ?? false;
    final role = json['auth_role'] as String? ?? 'admin';
    final up = json['uptime'] as String? ?? '';
    final platform = json['platform'] as String? ??
        (json['model']?.toString().toUpperCase().contains('ESP8266') == true ? 'ESP8266' : 'ESP32');
    final model = json['model'] as String? ?? '$platform-SmartHome';

    return SmartDevice(
      id: id,
      mac: mac,
      ip: hostIp,
      hostname: hostname,
      name: name,
      fwVersion: fw,
      numRelays: relaysCount,
      authRequired: auth,
      authRole: role,
      uptime: up,
      platform: platform,
      model: model,
      isOnline: true,
      lastSeen: DateTime.now(),
    );
  }

  factory SmartDevice.fromStatus(
    Map<String, dynamic> json,
    String hostIp, {
    String? existingRoom,
  }) {
    final mac = json['mac'] as String? ?? '';
    final id =
        json['device_id'] as String? ??
        (mac.isNotEmpty
            ? 'smarthome_${mac.replaceAll(':', '').toLowerCase()}'
            : hostIp);
    final name = json['device_name'] as String? ?? 'SmartHome Controller';
    final hostname = json['hostname'] as String? ?? 'smarthome';
    final fw = json['fw_version'] as String? ?? '3.2.0';
    final relaysCount = (json['num_relays'] as num?)?.toInt() ?? 5;
    final auth = json['auth_required'] as bool? ?? false;
    final role = json['auth_role'] as String? ?? 'admin';
    final rssi = (json['rssi'] as num?)?.toInt() ?? -60;
    final signal = (json['signal'] as num?)?.toInt() ?? 75;
    final up = json['uptime'] as String? ?? '';
    final heap = (json['free_heap'] as num?)?.toInt() ?? 0;
    final platform = json['platform'] as String? ??
        (json['model']?.toString().toUpperCase().contains('ESP8266') == true ? 'ESP8266' : 'ESP32');
    final model = json['model'] as String? ?? '$platform-SmartHome';

    List<RelayChannel> rList = [];
    if (json['relays'] is List) {
      final rawList = json['relays'] as List;
      for (int i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        if (item is Map) {
          rList.add(RelayChannel.fromJson(i, Map<String, dynamic>.from(item)));
        }
      }
    }

    final telemetry = SensorTelemetry.fromJson(json);

    return SmartDevice(
      id: id,
      mac: mac,
      ip: hostIp,
      hostname: hostname,
      name: name,
      room: existingRoom ?? 'Living Room',
      fwVersion: fw,
      numRelays: relaysCount,
      authRequired: auth,
      authLocked: false,
      authRole: role,
      isOnline: true,
      rssi: rssi,
      signalPercent: signal,
      uptime: up,
      freeHeap: heap,
      platform: platform,
      model: model,
      relays: rList,
      telemetry: telemetry,
      lastSeen: DateTime.now(),
    );
  }

  SmartDevice copyWith({
    String? id,
    String? mac,
    String? ip,
    String? hostname,
    String? name,
    String? room,
    int? numRelays,
    bool? authRequired,
    bool? authLocked,
    String? authRole,
    bool? isOnline,
    int? rssi,
    int? signalPercent,
    String? uptime,
    int? freeHeap,
    String? platform,
    String? model,
    List<RelayChannel>? relays,
    SensorTelemetry? telemetry,
    DateTime? lastSeen,
    String? authPassword,
    String? authUsername,
    bool clearAuthPassword = false,
  }) {
    return SmartDevice(
      id: id ?? this.id,
      mac: mac ?? this.mac,
      ip: ip ?? this.ip,
      hostname: hostname ?? this.hostname,
      name: name ?? this.name,
      room: room ?? this.room,
      fwVersion: fwVersion,
      numRelays: numRelays ?? this.numRelays,
      authRequired: authRequired ?? this.authRequired,
      authLocked: authLocked ?? this.authLocked,
      authRole: authRole ?? this.authRole,
      authUsername: authUsername ?? this.authUsername,
      authPassword: clearAuthPassword
          ? null
          : (authPassword ?? this.authPassword),
      isOnline: isOnline ?? this.isOnline,
      rssi: rssi ?? this.rssi,
      signalPercent: signalPercent ?? this.signalPercent,
      uptime: uptime ?? this.uptime,
      freeHeap: freeHeap ?? this.freeHeap,
      platform: platform ?? this.platform,
      model: model ?? this.model,
      relays: relays ?? this.relays,
      telemetry: telemetry ?? this.telemetry,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toStorageJson() => {
    'id': id,
    'mac': mac,
    'ip': ip,
    'hostname': hostname,
    'name': name,
    'room': room,
    'fw_version': fwVersion,
    'num_relays': numRelays,
    'auth_required': authRequired,
    'auth_role': authRole,
    'auth_username': authUsername,
    'auth_password': authPassword,
    'platform': platform,
    'model': model,
    'last_seen': lastSeen.toIso8601String(),
    'relays': relays.map((r) => r.toJson()).toList(),
  };

  factory SmartDevice.fromStorageJson(Map<String, dynamic> json) {
    List<RelayChannel> rList = [];
    if (json['relays'] is List) {
      final rawList = json['relays'] as List;
      for (int i = 0; i < rawList.length; i++) {
        final item = rawList[i];
        if (item is Map) {
          rList.add(RelayChannel.fromJson(i, Map<String, dynamic>.from(item)));
        }
      }
    }

    return SmartDevice(
      id: json['id'] as String,
      mac: json['mac'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      hostname: json['hostname'] as String? ?? 'smarthome',
      name: json['name'] as String? ?? 'SmartHome',
      room: json['room'] as String? ?? 'Living Room',
      fwVersion: json['fw_version'] as String? ?? '3.2.0',
      numRelays: (json['num_relays'] as num?)?.toInt() ?? 5,
      authRequired: json['auth_required'] as bool? ?? false,
      authRole: json['auth_role'] as String? ?? 'admin',
      authUsername: json['auth_username'] as String?,
      authPassword: json['auth_password'] as String?,
      platform: json['platform'] as String? ?? 'ESP32',
      model: json['model'] as String? ?? 'ESP32-SmartHome',
      relays: rList,
      isOnline: false,
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
