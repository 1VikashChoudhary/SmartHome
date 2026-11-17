import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models/smart_device.dart';

class QuickTileSlotConfig {
  final int slot;
  final String? deviceId;
  final int? relayId; // -1 = All Relays Master
  final String? customLabel;

  const QuickTileSlotConfig({
    required this.slot,
    this.deviceId,
    this.relayId,
    this.customLabel,
  });

  bool get isAssigned => deviceId != null && deviceId!.isNotEmpty && relayId != null;

  factory QuickTileSlotConfig.fromMap(Map<dynamic, dynamic> map) {
    return QuickTileSlotConfig(
      slot: (map['slot'] as num?)?.toInt() ?? 0,
      deviceId: map['deviceId']?.toString(),
      relayId: (map['relayId'] as num?)?.toInt(),
      customLabel: map['customLabel']?.toString(),
    );
  }
}

class NativePlatformCapabilities {
  final bool supportsQuickTiles;
  final bool supportsDeviceControls;
  final int apiLevel;
  final int maxTileSlots;

  const NativePlatformCapabilities({
    this.supportsQuickTiles = false,
    this.supportsDeviceControls = false,
    this.apiLevel = 0,
    this.maxTileSlots = 12,
  });
}

class NativeLaunchAction {
  final int? tileSlot;
  final String? deviceId;
  final String? alarmType;

  const NativeLaunchAction({this.tileSlot, this.deviceId, this.alarmType});
}

class SafetyMonitorState {
  final bool monitorEnabled;
  final bool sirenEnabled;
  final bool notificationPermissionGranted;
  final bool isSirenPlaying;
  final bool ignoringBatteryOptimizations;
  final bool monitorChannelHidden;

  const SafetyMonitorState({
    this.monitorEnabled = true,
    this.sirenEnabled = true,
    this.notificationPermissionGranted = true,
    this.isSirenPlaying = false,
    this.ignoringBatteryOptimizations = true,
    this.monitorChannelHidden = false,
  });
}

class NativeControlsService {
  NativeControlsService._();

  static final NativeControlsService instance = NativeControlsService._();

  static const MethodChannel _channel = MethodChannel(
    'com.smarthome.smarthome_app/native_controls',
  );

  String _lastSyncSignature = '';
  bool _handlerRegistered = false;
  void Function(NativeLaunchAction action)? _onLaunchAction;

  bool get _isAndroidNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void setLaunchActionListener(void Function(NativeLaunchAction action)? listener) {
    _onLaunchAction = listener;
    if (!_handlerRegistered && _isAndroidNative) {
      _handlerRegistered = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onLaunchAction' && call.arguments is Map) {
          final map = Map<dynamic, dynamic>.from(call.arguments as Map);
          final slot = (map['tileSlot'] as num?)?.toInt();
          final devId = map['deviceId']?.toString();
          final alarmType = map['alarmType']?.toString();
          if (slot != null || (devId != null && devId.isNotEmpty)) {
            _onLaunchAction?.call(
              NativeLaunchAction(
                tileSlot: slot,
                deviceId: devId,
                alarmType: alarmType,
              ),
            );
          }
        }
      });
    }
  }

  Future<NativeLaunchAction?> consumeLaunchAction() async {
    if (!_isAndroidNative) return null;
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'consumeLaunchAction',
      );
      if (res == null) return null;
      final slot = (res['tileSlot'] as num?)?.toInt();
      final devId = res['deviceId']?.toString();
      final alarmType = res['alarmType']?.toString();
      if (slot == null && (devId == null || devId.isEmpty)) return null;
      return NativeLaunchAction(
        tileSlot: slot,
        deviceId: devId,
        alarmType: alarmType,
      );
    } catch (_) {
      return null;
    }
  }

  Future<NativePlatformCapabilities> getPlatformCapabilities() async {
    if (!_isAndroidNative) return const NativePlatformCapabilities();
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getPlatformCapabilities',
      );
      if (res == null) return const NativePlatformCapabilities();
      return NativePlatformCapabilities(
        supportsQuickTiles: res['supportsQuickTiles'] == true,
        supportsDeviceControls: res['supportsDeviceControls'] == true,
        apiLevel: (res['apiLevel'] as num?)?.toInt() ?? 0,
        maxTileSlots: (res['maxTileSlots'] as num?)?.toInt() ?? 12,
      );
    } catch (_) {
      return const NativePlatformCapabilities();
    }
  }

  static List<Map<String, dynamic>> serializeDevices(List<SmartDevice> devices) {
    return devices
        .map(
          (d) => {
            'id': d.id,
            'name': d.name,
            'room': d.room,
            'ip': d.ip,
            'authRequired': d.authRequired,
            'authLocked': d.needsAuth,
            'isOnline': d.isOnline,
            'numRelays': d.numRelays,
            'authUsername': d.authUsername,
            'authPassword': d.authPassword,
            'relays': d.relays
                .map(
                  (r) => {
                    'id': r.id,
                    'name': r.name,
                    'state': r.state,
                    'enabled': r.enabled,
                    'icon': r.iconType,
                  },
                )
                .toList(),
          },
        )
        .toList();
  }

  static String buildSyncSignature(List<SmartDevice> devices) {
    final buf = StringBuffer();
    for (final d in devices) {
      buf.write('${d.id}|${d.ip}|${d.name}|${d.room}|${d.isOnline}|'
          '${d.authRequired}|${d.needsAuth}|${d.authUsername ?? ''}|${d.authPassword ?? ''}|');
      for (final r in d.relays) {
        buf.write('${r.id}:${r.enabled}:${r.state}:${r.name}:${r.iconType},');
      }
      buf.write(';');
    }
    return buf.toString();
  }

  Future<void> syncDevices(
    List<SmartDevice> devices, {
    bool force = false,
  }) async {
    if (!_isAndroidNative) return;
    final sig = buildSyncSignature(devices);
    if (!force && sig == _lastSyncSignature) return;
    _lastSyncSignature = sig;
    try {
      await _channel.invokeMethod('syncDevices', {
        'devices': serializeDevices(devices),
      });
    } catch (_) {}
  }

  Future<List<QuickTileSlotConfig>> getTileSlots() async {
    if (!_isAndroidNative) {
      return List.generate(
        12,
        (i) => QuickTileSlotConfig(slot: i + 1),
      );
    }
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('getTileSlots');
      if (raw == null) return [];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(QuickTileSlotConfig.fromMap)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> setTileSlot({
    required int slot,
    required String deviceId,
    required int relayId,
    String? customLabel,
  }) async {
    if (!_isAndroidNative) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setTileSlot', {
        'slot': slot,
        'deviceId': deviceId,
        'relayId': relayId,
        'customLabel': customLabel,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearTileSlot(int slot) async {
    if (!_isAndroidNative) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('clearTileSlot', {
        'slot': slot,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<int> autoAssignTileSlots() async {
    if (!_isAndroidNative) return 0;
    try {
      final count = await _channel.invokeMethod<int>('autoAssignTileSlots');
      return count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<bool> getAllowLockscreenControls() async {
    if (!_isAndroidNative) return false;
    try {
      final allow = await _channel.invokeMethod<bool>('getAllowLockscreenControls');
      return allow == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setAllowLockscreenControls(bool allow) async {
    if (!_isAndroidNative) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setAllowLockscreenControls', {
        'allow': allow,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static const String _prefSirenEnabled = 'alarm_siren_enabled';

  Future<SafetyMonitorState> getSafetyMonitorState() async {
    if (!_isAndroidNative) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return SafetyMonitorState(
          monitorEnabled: false,
          sirenEnabled: prefs.getBool(_prefSirenEnabled) ?? true,
        );
      } catch (_) {
        return const SafetyMonitorState();
      }
    }
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getSafetyMonitorState',
      );
      if (res == null) return const SafetyMonitorState();
      return SafetyMonitorState(
        monitorEnabled: res['monitorEnabled'] != false,
        sirenEnabled: res['sirenEnabled'] != false,
        notificationPermissionGranted:
            res['notificationPermissionGranted'] != false,
        isSirenPlaying: res['isSirenPlaying'] == true,
        ignoringBatteryOptimizations:
            res['ignoringBatteryOptimizations'] != false,
        monitorChannelHidden: res['monitorChannelHidden'] == true,
      );
    } catch (_) {
      return const SafetyMonitorState();
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (!_isAndroidNative) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openMonitorChannelSettings() async {
    if (!_isAndroidNative) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openMonitorChannelSettings');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openNotificationSettings() async {
    if (!_isAndroidNative) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openNotificationSettings');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openAppDetailsSettings() async {
    if (!_isAndroidNative) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openAppDetailsSettings');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setSafetyMonitorEnabled(bool enabled) async {
    if (!_isAndroidNative) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setSafetyMonitorEnabled', {
        'enabled': enabled,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setAlarmSirenEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefSirenEnabled, enabled);
    } catch (_) {}
    if (!_isAndroidNative) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('setAlarmSirenEnabled', {
        'enabled': enabled,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isAlarmSirenEnabled() async {
    final st = await getSafetyMonitorState();
    return st.sirenEnabled;
  }

  Future<void> startInAppSiren({bool force = false}) async {
    if (!_isAndroidNative) return;
    try {
      await _channel.invokeMethod('startInAppSiren', {'force': force});
    } catch (_) {}
  }

  Future<void> stopInAppSiren() async {
    if (!_isAndroidNative) return;
    try {
      await _channel.invokeMethod('stopInAppSiren');
    } catch (_) {}
  }

  Future<void> silenceAlarmEpisode(String deviceId, String alarmType) async {
    if (!_isAndroidNative) return;
    try {
      await _channel.invokeMethod('silenceAlarmEpisode', {
        'deviceId': deviceId,
        'alarmType': alarmType,
      });
    } catch (_) {}
  }
}
