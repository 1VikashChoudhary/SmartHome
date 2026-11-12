import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/smart_device.dart';
import '../core/models/relay_channel.dart';
import '../core/models/scheduled_alarm.dart';
import '../core/models/system_log_entry.dart';
import '../core/models/device_diagnostics.dart';
import '../core/network/api_client.dart';
import '../core/network/ws_client.dart';
import '../core/network/network_utils.dart';
import 'discovery_service.dart';
import 'device_storage_service.dart';

class IsScanningNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void setScanning(bool val) => state = val;
}

final isScanningProvider = NotifierProvider<IsScanningNotifier, bool>(
  IsScanningNotifier.new,
);

class AuthPromptRequest {
  final String deviceId;
  final int timestamp;
  const AuthPromptRequest({required this.deviceId, required this.timestamp});
}

class AuthPromptNotifier extends Notifier<AuthPromptRequest?> {
  @override
  AuthPromptRequest? build() => null;

  void prompt(String deviceId) {
    state = AuthPromptRequest(
      deviceId: deviceId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void clear() {
    state = null;
  }
}

final authPromptProvider =
    NotifierProvider<AuthPromptNotifier, AuthPromptRequest?>(
      AuthPromptNotifier.new,
    );

class EmergencyAlarmEvent {
  final String deviceId;
  final String alarmType; // 'gas' or 'temperature'
  final int timestamp;

  const EmergencyAlarmEvent({
    required this.deviceId,
    required this.alarmType,
    required this.timestamp,
  });
}

class EmergencyAlarmNotifier extends Notifier<EmergencyAlarmEvent?> {
  @override
  EmergencyAlarmEvent? build() => null;

  void trigger(String deviceId, String alarmType) {
    state = EmergencyAlarmEvent(
      deviceId: deviceId,
      alarmType: alarmType,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void clear() {
    state = null;
  }
}

final emergencyAlarmProvider =
    NotifierProvider<EmergencyAlarmNotifier, EmergencyAlarmEvent?>(
      EmergencyAlarmNotifier.new,
    );

final deviceManagerProvider =
    NotifierProvider<DeviceManager, List<SmartDevice>>(DeviceManager.new);

class DeviceManager extends Notifier<List<SmartDevice>> {
  final ApiClient _api = ApiClient();
  final DiscoveryService _discovery = DiscoveryService();
  final DeviceStorageService _storage = DeviceStorageService();
  ApiClient get apiClient => _api;

  final Map<String, DeviceWebSocketClient> _wsClients = {};
  final Set<String> _refreshingDeviceIds = {};
  final Set<String> _activeAlertKeys = {};
  Timer? _periodicSyncTimer;
  Timer? _countdownTickerTimer;
  bool _foregroundSyncEnabled = true;
  bool _disposed = false;

  bool get _isAlive => !_disposed && ref.mounted;

  @override
  List<SmartDevice> build() {
    _disposed = false;
    ApiClient.onUnauthorized = _handleUnauthorizedHost;
    ref.onDispose(() {
      _disposed = true;
      _periodicSyncTimer?.cancel();
      _periodicSyncTimer = null;
      _countdownTickerTimer?.cancel();
      _countdownTickerTimer = null;
      if (ApiClient.onUnauthorized == _handleUnauthorizedHost) {
        ApiClient.onUnauthorized = null;
      }
      for (final client in _wsClients.values) {
        client.dispose();
      }
      _wsClients.clear();
    });

    _init();
    return [];
  }

  void _handleUnauthorizedHost(String host) {
    if (!_isAlive) return;
    final clean = sanitizeHost(host).toLowerCase();
    final idx = state.indexWhere((d) {
      final devHost = sanitizeHost(d.ip).split(':').first.toLowerCase();
      return devHost == clean || sanitizeHost(d.ip).toLowerCase() == clean;
    });
    if (idx >= 0) {
      _handleDeviceAuthError(state[idx].id, promptUser: true);
    }
  }

  void _handleDeviceAuthError(String deviceId, {bool promptUser = true}) {
    if (!_isAlive) return;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return;

    // Stop the WebSocket loop immediately so repeated unauthorized attempts
    // cannot trigger the ESP32 5-attempt rate-limit lockout.
    _wsClients.remove(deviceId)?.dispose();

    final current = state[idx];
    final wasAlreadyLocked = current.authLocked;
    if (!current.authLocked || !current.authRequired) {
      final updated = current.copyWith(authRequired: true, authLocked: true);
      final newList = List<SmartDevice>.from(state);
      newList[idx] = updated;
      state = newList;
      _storage.saveDevices(newList);
    }

    if (promptUser || !wasAlreadyLocked) {
      ref.read(authPromptProvider.notifier).prompt(deviceId);
    }
  }

  void requestLoginPrompt(String deviceId) {
    if (!_isAlive) return;
    ref.read(authPromptProvider.notifier).prompt(deviceId);
  }

  Future<void> _init() async {
    final saved = await _storage.loadDevices();
    if (!_isAlive) return;
    for (final device in saved) {
      ApiClient.registerDeviceUsername(device.ip, device.authUsername);
    }
    state = saved;

    // The app is a companion: while it is visible, every registered controller
    // stays synchronised at a restrained 10-second cadence. This preserves
    // live Dashboard/Controllers data without the former 1-second flood.
    if (_foregroundSyncEnabled && saved.isNotEmpty) {
      await startForegroundSync();
      if (!_isAlive) return;
    }

    // Perform auto-discovery only if no devices exist yet.
    if (saved.isEmpty) {
      await scanForDevices();
    }
  }

  /// Run network scan on demand to discover new ESPs or update IPs
  Future<void> scanForDevices() async {
    if (!_isAlive) return;
    if (ref.read(isScanningProvider)) return;
    ref.read(isScanningProvider.notifier).setScanning(true);

    try {
      await _discovery.discoverAll(
        onDeviceFound: (discovered) {
          if (_isAlive) _handleDiscoveredDevice(discovered);
        },
      );
    } finally {
      if (_isAlive) {
        ref.read(isScanningProvider.notifier).setScanning(false);
      }
    }
  }

  /// Refresh all devices once. `/api/status` is authoritative and already
  /// contains relay state, so this deliberately avoids a second `/api/relays`
  /// request per device.
  Future<void> refreshAllDevices({
    bool skipHealthyWs = false,
    int staleSeconds = 25,
  }) async {
    if (!_isAlive) return;
    final now = DateTime.now();
    final devices = state.where((dev) {
      if (dev.ip.isEmpty) return false;
      if (!skipHealthyWs) return true;
      final wsConnected = _wsClients[dev.id]?.isConnected ?? false;
      if (!wsConnected) return true;
      return now.difference(dev.lastSeen).inSeconds >= staleSeconds;
    }).toList();
    // Two requests at a time keeps a large installation responsive without
    // creating a Wi-Fi burst or overwhelming the phone radio.
    for (var start = 0; start < devices.length; start += 2) {
      if (!_isAlive) return;
      final end = (start + 2).clamp(0, devices.length).toInt();
      await Future.wait(devices.sublist(start, end).map(_refreshDeviceStatus));
    }
  }

  /// Add device manually by IP or Hostname
  Future<bool> addDeviceByIp(
    String rawIp, {
    String? username,
    String? password,
  }) async {
    if (!_isAlive) return false;
    final ip = sanitizeHost(rawIp);
    if (ip.isEmpty) return false;

    final client = ApiClient(defaultUsername: username);
    final statusJson = await client.fetchStatus(ip, password: password);
    if (!_isAlive) return false;
    if (statusJson != null) {
      final dev = SmartDevice.fromStatus(statusJson, ip);
      _handleDiscoveredDevice(dev, username: username, password: password);
      return true;
    }
    final discoveryDev = await client.probeDiscovery(ip);
    if (!_isAlive) return false;
    if (discoveryDev != null) {
      _handleDiscoveredDevice(
        discoveryDev,
        username: username,
        password: password,
      );
      return true;
    }
    return false;
  }

  void _handleDiscoveredDevice(
    SmartDevice discovered, {
    String? username,
    String? password,
  }) {
    if (!_isAlive) return;
    final existingIdx = state.indexWhere(
      (d) =>
          (d.mac.isNotEmpty && d.mac == discovered.mac) ||
          d.id == discovered.id,
    );

    if (existingIdx >= 0) {
      // Existing device: update IP (self-healing migration) and online status
      final old = state[existingIdx];
      if (old.ip.isNotEmpty && old.ip != discovered.ip) {
        ApiClient.unregisterDevice(old.ip);
      }
      final cleanProvidedPass =
          (password != null && password.isNotEmpty) ? password : null;
      final effectivePass = cleanProvidedPass ?? old.authPassword;
      final effectiveUser =
          (username != null && username.trim().isNotEmpty)
              ? username.trim()
              : (old.authUsername ?? 'admin');
      final hasUsablePass = effectivePass != null && effectivePass.isNotEmpty;
      final explicitGuestNoPass =
          username != null &&
          username.trim().isNotEmpty &&
          username.trim().toLowerCase() != 'admin';
      final isStoredGuestNoPass =
          !old.authLocked &&
          old.isGuest &&
          effectiveUser.toLowerCase() != 'admin';
      final missingCredentials =
          discovered.authRequired &&
          !hasUsablePass &&
          !explicitGuestNoPass &&
          !isStoredGuestNoPass;
      final shouldUnlock =
          !discovered.authRequired ||
          cleanProvidedPass != null ||
          explicitGuestNoPass;
      final updated = old.copyWith(
        ip: discovered.ip,
        isOnline: true,
        lastSeen: DateTime.now(),
        authRequired: discovered.authRequired,
        authLocked: missingCredentials
            ? true
            : (shouldUnlock ? false : old.authLocked),
        authPassword: effectivePass,
        authUsername: effectiveUser,
      );

      final newList = List<SmartDevice>.from(state);
      newList[existingIdx] = updated;
      state = newList;
      ApiClient.registerDeviceUsername(updated.ip, updated.authUsername);

      _storage.saveDevices(newList);
      if (missingCredentials) {
        _wsClients.remove(updated.id)?.dispose();
        ref.read(authPromptProvider.notifier).prompt(updated.id);
      } else if (_foregroundSyncEnabled) {
        _replaceForegroundStream(updated);
        _refreshDeviceStatus(updated);
      }
    } else {
      // New device: add to list
      final cleanPass =
          (password != null && password.isNotEmpty) ? password : null;
      final effectiveUser =
          (username != null && username.trim().isNotEmpty)
              ? username.trim()
              : 'admin';
      final isGuestNoPass =
          cleanPass == null && effectiveUser.toLowerCase() != 'admin';
      final missingCredentials =
          discovered.authRequired && cleanPass == null && !isGuestNoPass;
      final devToAdd = discovered.copyWith(
        authRequired: discovered.authRequired,
        authLocked: missingCredentials,
        authPassword: cleanPass,
        authUsername: effectiveUser,
        authRole: isGuestNoPass ? 'guest' : discovered.authRole,
        room: 'Living Room',
      );
      final newList = [...state, devToAdd];
      state = newList;
      ApiClient.registerDeviceUsername(devToAdd.ip, devToAdd.authUsername);

      _storage.saveDevices(newList);
      if (missingCredentials) {
        ref.read(authPromptProvider.notifier).prompt(devToAdd.id);
      } else if (_foregroundSyncEnabled) {
        _startStatusStream(devToAdd);
        _refreshDeviceStatus(devToAdd);
      }
    }
  }

  /// Starts low-rate live status for every registered controller while the
  /// app is in the foreground. The ESP remains the automation authority; this
  /// stream only keeps the companion UI current.
  Future<void> startForegroundSync({int intervalSeconds = 10}) async {
    if (!_isAlive) return;
    _foregroundSyncEnabled = true;
    final interval = intervalSeconds.clamp(5, 60).toInt();
    _checkAndStartCountdownTicker();
    for (final dev in state) {
      if (dev.ip.isNotEmpty &&
          !dev.needsAuth &&
          !_wsClients.containsKey(dev.id)) {
        _startStatusStream(dev, intervalSeconds: interval);
      }
    }
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(Duration(seconds: interval), (_) {
      if (!_isAlive || !_foregroundSyncEnabled) return;
      for (final dev in state) {
        if (dev.ip.isNotEmpty &&
            !dev.needsAuth &&
            !_wsClients.containsKey(dev.id)) {
          _startStatusStream(dev, intervalSeconds: interval);
        }
      }
      refreshAllDevices(
        skipHealthyWs: true,
        staleSeconds: interval * 2 + 5,
      );
    });
    await refreshAllDevices();
  }

  void _replaceForegroundStream(SmartDevice dev) {
    if (!_isAlive) return;
    _wsClients.remove(dev.id)?.dispose();
    if (!dev.needsAuth) {
      _startStatusStream(dev);
    }
  }

  void _startStatusStream(SmartDevice dev, {int intervalSeconds = 10}) {
    if (!_isAlive ||
        dev.ip.isEmpty ||
        dev.needsAuth ||
        _wsClients.containsKey(dev.id)) {
      return;
    }

    final client = DeviceWebSocketClient(
      ip: dev.ip,
      authPassword: dev.authPassword,
      authUsername: dev.authUsername,
      statusIntervalSeconds: intervalSeconds,
      onData: (data) => _handleWsData(dev.id, data),
      onConnectionChange: (connected) =>
          _handleConnectionChange(dev.id, connected),
      onAuthError: () => _handleDeviceAuthError(dev.id, promptUser: true),
    );

    _wsClients[dev.id] = client;
    client.connect();
  }

  /// Stops all network activity while the companion app is backgrounded.
  void stopForegroundSync() {
    _foregroundSyncEnabled = false;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
    _countdownTickerTimer?.cancel();
    _countdownTickerTimer = null;
    for (final client in _wsClients.values) {
      client.dispose();
    }
    _wsClients.clear();
  }

  void _handleConnectionChange(String deviceId, bool connected) {
    if (!_isAlive) return;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return;

    if (connected) {
      if (!state[idx].isOnline) {
        final updated = state[idx].copyWith(isOnline: true);
        final newList = List<SmartDevice>.from(state);
        newList[idx] = updated;
        state = newList;
      }
    } else {
      // Do not immediately flip the controller to offline on a transient
      // WebSocket disconnect; verify via HTTP /api/status first so the UI
      // never flashes "Controller offline" while the ESP32 is still reachable.
      _refreshDeviceStatus(state[idx]);
    }
  }

  void _setDeviceOnlineState(String deviceId, bool isOnline) {
    if (!_isAlive) return;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx >= 0 && state[idx].isOnline != isOnline) {
      final updated = state[idx].copyWith(isOnline: isOnline);
      final newList = List<SmartDevice>.from(state);
      newList[idx] = updated;
      state = newList;
    }
  }

  void _handleWsData(String deviceId, Map<String, dynamic> data) {
    if (!_isAlive) return;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return;

    final current = state[idx];

    // Event frames are not status frames. Never parse an alarm/toast as a
    // partial status response because that would erase the last real reading.
    if (data['type'] != null) {
      if (data['type'] == 'alarm') {
        final alarmName = data['alarm']?.toString() ?? 'gas';
        final isActive = data['active'] == true;
        final alertKey = '${current.id}:$alarmName';
        if (isActive &&
            (alarmName == 'gas' || alarmName == 'temperature') &&
            _activeAlertKeys.add(alertKey)) {
          ref
              .read(emergencyAlarmProvider.notifier)
              .trigger(current.id, alarmName);
        } else if (!isActive) {
          _activeAlertKeys.remove(alertKey);
        }
        // An alarm frame contains no telemetry payload. Fetch one authoritative
        // snapshot immediately so the active companion view reflects the new
        // ESP-controlled safety state without waiting for its next interval.
        _refreshDeviceStatus(current);
        return;
      }
      // Single relay broadcast: {type: 'relay', id: index, state: bool}
      if (data['type'] == 'relay') {
        final rId = (data['id'] as num?)?.toInt();
        final rState = data['state'] as bool?;
        if (rId != null && rState != null && rId >= 0 && rId < current.relays.length) {
          final rList = List<RelayChannel>.from(current.relays);
          final relay = rList[rId];
          final bool shouldCancelTimer = relay.timerActive && (
            rState == relay.timerTarget ||
            (!relay.timerTarget && !rState)
          );
          rList[rId] = relay.copyWith(
            state: rState,
            timerActive: shouldCancelTimer ? false : relay.timerActive,
            timerRemaining: shouldCancelTimer ? 0 : relay.timerRemaining,
          );
          final updated = current.copyWith(relays: rList, isOnline: true);
          final newList = List<SmartDevice>.from(state);
          newList[idx] = updated;
          state = newList;
          _checkAndStartCountdownTicker();
        }
        return;
      }

      // Single relay timer broadcast: {type: 'relay_timer', id: index, timer_active: bool, ...}
      if (data['type'] == 'relay_timer') {
        final rId = (data['id'] as num?)?.toInt();
        final tActive = data['timer_active'] as bool? ?? false;
        final tTarget = data['timer_target'] as bool? ?? false;
        final tRemaining = (data['timer_remaining'] as num?)?.toInt() ?? 0;
        if (rId != null && rId >= 0 && rId < current.relays.length) {
          final rList = List<RelayChannel>.from(current.relays);
          rList[rId] = rList[rId].copyWith(
            timerActive: tActive,
            timerTarget: tTarget,
            timerRemaining: tRemaining,
          );
          final updated = current.copyWith(relays: rList, isOnline: true);
          final newList = List<SmartDevice>.from(state);
          newList[idx] = updated;
          state = newList;
          _checkAndStartCountdownTicker();
        }
        return;
      }

      // Non-status typed frames (e.g. toast, pong) must not fall through
      // into SmartDevice.fromStatus, which would overwrite telemetry/relays.
      if (data['type'] != 'status') {
        return;
      }
    }

    // Full status broadcast
    final updated = SmartDevice.fromStatus(
      data,
      current.ip,
      existingRoom: current.room,
    );

    // Preserve any locally known icon if firmware didn't send one
    final mergedRelays = List<RelayChannel>.from(updated.relays);
    for (
      int i = 0;
      i < mergedRelays.length && i < current.relays.length;
      i++
    ) {
      if (mergedRelays[i].iconType == 'light' &&
          current.relays[i].iconType != 'light' &&
          (data['relays'] is List &&
              i < (data['relays'] as List).length &&
              ((data['relays'] as List)[i] is Map) &&
              !((data['relays'] as List)[i] as Map).containsKey('icon'))) {
        mergedRelays[i] = mergedRelays[i].copyWith(
          iconType: current.relays[i].iconType,
        );
      }
    }

    final hasExplicitRole =
        data['auth_role'] != null &&
        data['auth_role'].toString().trim().isNotEmpty;
    final finalDev = updated.copyWith(
      id: current.id,
      mac: current.mac.isNotEmpty ? current.mac : updated.mac,
      authRequired: updated.authRequired,
      authLocked: false,
      authRole: hasExplicitRole ? updated.authRole : current.authRole,
      authPassword: current.authPassword,
      authUsername: current.authUsername,
      relays: mergedRelays,
      isOnline: true,
    );

    // Check for newly active gas or high-temperature emergency alarms
    final gasKey = '${finalDev.id}:gas';
    if (finalDev.telemetry.gasAlarm) {
      if (_activeAlertKeys.add(gasKey)) {
        ref.read(emergencyAlarmProvider.notifier).trigger(finalDev.id, 'gas');
      }
    } else {
      _activeAlertKeys.remove(gasKey);
    }

    final tempKey = '${finalDev.id}:temperature';
    final isHighTemp =
        finalDev.telemetry.dhtEnabled &&
        !finalDev.telemetry.dhtFault &&
        finalDev.telemetry.tempThreshold > 0 &&
        finalDev.telemetry.temperature >= finalDev.telemetry.tempThreshold;
    if (isHighTemp) {
      if (_activeAlertKeys.add(tempKey)) {
        ref
            .read(emergencyAlarmProvider.notifier)
            .trigger(finalDev.id, 'temperature');
      }
    } else {
      _activeAlertKeys.remove(tempKey);
    }

    final newList = List<SmartDevice>.from(state);
    newList[idx] = finalDev;
    state = newList;
    _checkAndStartCountdownTicker();
  }

  Future<void> _refreshDeviceStatus(SmartDevice dev) async {
    if (!_isAlive) return;
    if (!_refreshingDeviceIds.add(dev.id)) return;
    try {
      if (dev.needsAuth) {
        final disc = await _api.probeDiscovery(dev.ip);
        if (!_isAlive) return;
        if (disc != null && !disc.authRequired) {
          final json = await _api.fetchStatus(
            dev.ip,
            password: dev.authPassword,
            username: dev.authUsername,
          );
          if (!_isAlive) return;
          if (json != null) {
            final curIdx = state.indexWhere((d) => d.id == dev.id);
            if (curIdx < 0) return;
            _handleWsData(dev.id, json);
            final latestIdx = state.indexWhere((d) => d.id == dev.id);
            if (_foregroundSyncEnabled && latestIdx >= 0) {
              _replaceForegroundStream(state[latestIdx]);
            }
          }
        }
        return;
      }

      final json = await _api.fetchStatus(
        dev.ip,
        password: dev.authPassword,
        username: dev.authUsername,
      );
      if (!_isAlive) return;
      final postStatusIdx = state.indexWhere((d) => d.id == dev.id);
      if (postStatusIdx < 0 || state[postStatusIdx].needsAuth) {
        return;
      }
      if (json != null) {
        _handleWsData(dev.id, json);
      } else {
        // Check if device is still reachable via /api/discovery
        final disc = await _api.probeDiscovery(dev.ip);
        if (!_isAlive) return;
        final postDiscIdx = state.indexWhere((d) => d.id == dev.id);
        if (postDiscIdx < 0 || state[postDiscIdx].needsAuth) {
          return;
        }
        if (disc != null) {
          if (disc.authRequired) {
            _handleDeviceAuthError(dev.id, promptUser: true);
          } else {
            // Controller is alive on LAN; keep online and retry status once
            _setDeviceOnlineState(dev.id, true);
            final retryJson = await _api.fetchStatus(
              dev.ip,
              password: dev.authPassword,
              username: dev.authUsername,
            );
            if (!_isAlive) return;
            final postRetryIdx = state.indexWhere((d) => d.id == dev.id);
            if (postRetryIdx < 0 || state[postRetryIdx].needsAuth) {
              return;
            }
            if (retryJson != null) {
              _handleWsData(dev.id, retryJson);
            }
          }
        } else {
          _setDeviceOnlineState(dev.id, false);
        }
      }
    } finally {
      _refreshingDeviceIds.remove(dev.id);
    }
  }

  // --- Actions ---

  /// Optimistic Relay Toggle
  Future<void> toggleRelay(String deviceId, int relayIndex) async {
    if (!_isAlive) return;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return;

    final dev = state[idx];
    if (dev.needsAuth) {
      _handleDeviceAuthError(dev.id, promptUser: true);
      return;
    }
    if (relayIndex < 0 || relayIndex >= dev.relays.length) return;

    final oldState = dev.relays[relayIndex].state;
    final newState = !oldState;

    // Optimistic UI update
    final rList = List<RelayChannel>.from(dev.relays);
    final targetRelay = rList[relayIndex];
    final bool cancelTimer = targetRelay.timerActive && (
      newState == targetRelay.timerTarget ||
      (!targetRelay.timerTarget && !newState)
    );
    rList[relayIndex] = targetRelay.copyWith(
      state: newState,
      timerActive: cancelTimer ? false : targetRelay.timerActive,
      timerRemaining: cancelTimer ? 0 : targetRelay.timerRemaining,
    );
    final updated = dev.copyWith(relays: rList, isOnline: true);
    final newList = List<SmartDevice>.from(state);
    newList[idx] = updated;
    state = newList;
    _checkAndStartCountdownTicker();

    // Execute API
    final ok = await _api.setRelay(
      dev.ip,
      relayIndex,
      newState ? 'on' : 'off',
      password: dev.authPassword,
    );
    if (!_isAlive) return;
    if (!ok) {
      // Revert if API call fails (preserving any authLocked state updated during the call)
      final currentIdx = state.indexWhere((d) => d.id == deviceId);
      if (currentIdx >= 0) {
        final latest = state[currentIdx];
        final revRelays = List<RelayChannel>.from(latest.relays);
        if (relayIndex >= 0 && relayIndex < revRelays.length) {
        revRelays[relayIndex] = revRelays[relayIndex].copyWith(
          state: oldState,
          timerActive: targetRelay.timerActive,
          timerTarget: targetRelay.timerTarget,
          timerRemaining: targetRelay.timerRemaining,
        );
        }
        final revList = List<SmartDevice>.from(state);
        revList[currentIdx] = latest.copyWith(relays: revRelays);
        state = revList;
      }
    }
  }

  /// Start quick one-shot countdown timer
  Future<bool> startTimer(
    String deviceId,
    int relayIndex,
    String action,
    int durationSeconds,
  ) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;

    final dev = state[idx];
    if (dev.needsAuth) {
      _handleDeviceAuthError(dev.id, promptUser: true);
      return false;
    }

    final ok = await _api.startTimer(
      dev.ip,
      relayIndex,
      action,
      durationSeconds,
      password: dev.authPassword,
    );
    if (!_isAlive) return ok;
    if (ok) {
      final currentIdx = state.indexWhere((d) => d.id == deviceId);
      if (currentIdx >= 0) {
        final currentDev = state[currentIdx];
        final rList = List<RelayChannel>.from(currentDev.relays);
        if (relayIndex >= 0 && relayIndex < rList.length) {
          rList[relayIndex] = rList[relayIndex].copyWith(
            timerActive: true,
            timerTarget: action == 'on',
            timerRemaining: durationSeconds,
          );
          final updated = currentDev.copyWith(relays: rList, isOnline: true);
          final newList = List<SmartDevice>.from(state);
          newList[currentIdx] = updated;
          state = newList;
        }
      }
      _checkAndStartCountdownTicker();
    }
    return ok;
  }

  /// Cancel quick timer
  Future<bool> cancelTimer(String deviceId, int relayIndex) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;

    final dev = state[idx];
    if (dev.needsAuth) {
      _handleDeviceAuthError(dev.id, promptUser: true);
      return false;
    }
    final ok = await _api.cancelTimer(
      dev.ip,
      relayIndex,
      password: dev.authPassword,
    );
    if (!_isAlive) return ok;
    if (ok) {
      final currentIdx = state.indexWhere((d) => d.id == deviceId);
      if (currentIdx >= 0) {
        final currentDev = state[currentIdx];
        final rList = List<RelayChannel>.from(currentDev.relays);
        if (relayIndex >= 0 && relayIndex < rList.length) {
          rList[relayIndex] = rList[relayIndex].copyWith(
            timerActive: false,
            timerRemaining: 0,
          );
          final updated = currentDev.copyWith(relays: rList);
          final newList = List<SmartDevice>.from(state);
          newList[currentIdx] = updated;
          state = newList;
        }
      }
      _checkAndStartCountdownTicker();
    }
    return ok;
  }

  void _checkAndStartCountdownTicker() {
    if (!_isAlive) return;
    final hasActiveTimers = state.any((d) => d.relays.any((r) => r.timerActive && r.timerRemaining > 0));
    if (!hasActiveTimers) {
      _countdownTickerTimer?.cancel();
      _countdownTickerTimer = null;
      return;
    }
    if (_countdownTickerTimer != null && _countdownTickerTimer!.isActive) return;

    _countdownTickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isAlive) {
        _countdownTickerTimer?.cancel();
        _countdownTickerTimer = null;
        return;
      }
      bool anyActive = false;
      bool stateChanged = false;

      final updatedDevices = state.map((dev) {
        bool devChanged = false;
        final updatedRelays = dev.relays.map((relay) {
          if (relay.timerActive && relay.timerRemaining > 0) {
            final nextRemaining = relay.timerRemaining - 1;
            devChanged = true;
            if (nextRemaining > 0) {
              anyActive = true;
              return relay.copyWith(timerRemaining: nextRemaining);
            } else {
              // Timer expired: relay reaches target state
              return relay.copyWith(
                timerActive: false,
                timerRemaining: 0,
                state: relay.timerTarget,
              );
            }
          }
          return relay;
        }).toList();

        if (devChanged) {
          stateChanged = true;
          return dev.copyWith(relays: updatedRelays);
        }
        return dev;
      }).toList();

      if (stateChanged) {
        state = updatedDevices;
      }

      if (!anyActive) {
        _countdownTickerTimer?.cancel();
        _countdownTickerTimer = null;
      }
    });
  }

  /// Master ON / OFF for all relays on a device
  Future<void> setAllRelays(String deviceId, String action) async {
    if (!_isAlive) return;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return;

    final dev = state[idx];
    if (dev.needsAuth) {
      _handleDeviceAuthError(dev.id, promptUser: true);
      return;
    }
    final oldRelays = List<RelayChannel>.from(dev.relays);
    final targetState = action == 'on';
    final rList = dev.relays.map((r) {
      if (targetState && !r.enabled) return r;
      final bool cancelTimer = r.timerActive && (targetState == r.timerTarget);
      return r.copyWith(
        state: targetState,
        timerActive: cancelTimer ? false : r.timerActive,
        timerRemaining: cancelTimer ? 0 : r.timerRemaining,
      );
    }).toList();
    final updated = dev.copyWith(relays: rList, isOnline: true);
    final newList = List<SmartDevice>.from(state);
    newList[idx] = updated;
    state = newList;
    _checkAndStartCountdownTicker();

    final ok = await _api.setAllRelays(
      dev.ip,
      action,
      password: dev.authPassword,
    );
    if (!_isAlive) return;
    if (ok) {
      _setDeviceOnlineState(deviceId, true);
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!_isAlive) return;
        final currentIdx = state.indexWhere((d) => d.id == deviceId);
        if (currentIdx >= 0) {
          _refreshDeviceStatus(state[currentIdx]);
        }
      });
    } else {
      final currentIdx = state.indexWhere((d) => d.id == deviceId);
      if (currentIdx >= 0) {
        final revList = List<SmartDevice>.from(state);
        revList[currentIdx] = state[currentIdx].copyWith(relays: oldRelays);
        state = revList;
      }
    }
  }

  /// Assign device to room
  Future<void> assignRoom(String deviceId, String roomName) async {
    if (!_isAlive) return;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return;

    final updated = state[idx].copyWith(room: roomName);
    final newList = List<SmartDevice>.from(state);
    newList[idx] = updated;
    state = newList;

    await _storage.saveDevices(newList);
  }

  /// Update custom device name (persists to both ESP32 flash and local phone storage)
  Future<bool> updateDeviceName(String deviceId, String newName) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;

    final dev = state[idx];
    final updated = dev.copyWith(name: newName);
    final newList = List<SmartDevice>.from(state);
    newList[idx] = updated;
    state = newList;

    await _storage.saveDevices(newList);
    return await _api.saveDeviceConfig(
      dev.ip,
      {'device_name': newName},
      password: dev.authPassword,
      username: dev.authUsername,
    );
  }

  /// Update stored login credentials for an existing controller and verify connectivity
  Future<bool> updateDeviceCredentials(
    String deviceId, {
    required String username,
    required String? password,
  }) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;

    final dev = state[idx];
    final cleanUser = username.trim().isEmpty ? 'admin' : username.trim();
    final cleanPass = (password == null || password.isEmpty) ? null : password;

    // Verify credentials against the controller before unlocking or persisting them
    final statusJson = await _api.fetchStatus(
      dev.ip,
      password: cleanPass,
      username: cleanUser,
      skipUnauthorizedCallback: true,
    );
    if (!_isAlive) return statusJson != null;

    final curIdx = state.indexWhere((d) => d.id == deviceId);
    if (curIdx < 0) return statusJson != null;
    final current = state[curIdx];

    if (statusJson != null) {
      ApiClient.registerDeviceUsername(current.ip, cleanUser);
      final isGuestUser = cleanUser.toLowerCase() != 'admin';
      final updated = current.copyWith(
        authUsername: cleanUser,
        authPassword: cleanPass,
        clearAuthPassword: cleanPass == null,
        authLocked: false,
        authRole: (statusJson['auth_role'] as String?) ??
            (isGuestUser ? 'guest' : current.authRole),
      );
      final newList = List<SmartDevice>.from(state);
      newList[curIdx] = updated;
      state = newList;
      _handleWsData(current.id, statusJson);
      final latestIdx = state.indexWhere((d) => d.id == deviceId);
      if (latestIdx >= 0) {
        await _storage.saveDevices(state);
        if (_isAlive && _foregroundSyncEnabled) {
          _replaceForegroundStream(state[latestIdx]);
        }
      }
      return true;
    }

    // Credentials rejected or unreachable: keep device locked without persisting bad password
    _handleDeviceAuthError(current.id, promptUser: false);
    return false;
  }

  /// Log out from a controller, clearing stored credentials and closing active sessions
  Future<void> logoutDevice(String deviceId) async {
    if (!_isAlive) return;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return;

    final dev = state[idx];
    _wsClients.remove(dev.id)?.dispose();

    ApiClient.unregisterDevice(dev.ip);
    await _storage.deleteDeviceCredentials(deviceId);
    if (!_isAlive) return;

    final curIdx = state.indexWhere((d) => d.id == deviceId);
    if (curIdx < 0) return;
    final current = state[curIdx];
    final updated = current.copyWith(
      authPassword: null,
      clearAuthPassword: true,
      authLocked: true,
      authRole: 'admin',
    );
    final newList = List<SmartDevice>.from(state);
    newList[curIdx] = updated;
    state = newList;
    await _storage.saveDevices(newList);
  }

  /// Refresh a specific device status & relays
  Future<void> refreshDevice(String deviceId) async {
    if (!_isAlive) return;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx >= 0) {
      await _refreshDeviceStatus(state[idx]);
    }
  }

  /// Reboot device
  Future<bool> rebootDevice(String deviceId) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    return await _api.reboot(dev.ip, password: dev.authPassword);
  }

  /// Fetch live hardware relay configuration directly from ESP32 flash
  Future<List<RelayChannel>?> fetchDeviceRelays(String deviceId) async {
    if (!_isAlive) return null;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return null;
    final dev = state[idx];

    final rawList = await _api.fetchRelays(dev.ip, password: dev.authPassword);
    if (rawList == null) return null;

    final List<RelayChannel> updatedRelays = [];
    for (int i = 0; i < rawList.length; i++) {
      updatedRelays.add(RelayChannel.fromJson(i, rawList[i]));
    }
    if (!_isAlive) return updatedRelays;

    final curIdx = state.indexWhere((d) => d.id == deviceId);
    if (curIdx < 0) return updatedRelays;

    // Merge into state
    final updatedDev = state[curIdx].copyWith(
      relays: updatedRelays,
      numRelays: updatedRelays.length,
      isOnline: true,
    );
    final newList = List<SmartDevice>.from(state);
    newList[curIdx] = updatedDev;
    state = newList;
    _storage.saveDevices(newList);

    return updatedRelays;
  }

  /// Fetch system configuration (LCD, Sensor calibration, MQTT, Buzzer) from ESP32
  Future<Map<String, dynamic>?> fetchDeviceConfig(String deviceId) async {
    if (!_isAlive) return null;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return null;
    final dev = state[idx];
    return await _api.fetchConfig(dev.ip, password: dev.authPassword);
  }

  /// Wi-Fi credentials are persisted by the selected controller. A successful
  /// write may make the current controller address unreachable while it joins
  /// the new network.
  Future<bool> saveDeviceWifi(
    String deviceId, {
    required String ssid,
    required String password,
  }) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    return _api.saveWifiConfig(
      dev.ip,
      ssid,
      password,
      authPassword: dev.authPassword,
    );
  }

  Future<bool> saveDeviceMqtt(
    String deviceId,
    Map<String, dynamic> config,
  ) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    return _api.saveMqttConfig(dev.ip, config, password: dev.authPassword);
  }

  /// Save per-relay hardware configuration
  Future<bool> saveRelayHardwareConfig(
    String deviceId,
    int relayIndex,
    Map<String, dynamic> config,
  ) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    final payload = Map<String, dynamic>.from(config);
    payload['id'] = relayIndex;
    final ok = await _api.saveRelayConfig(
      dev.ip,
      payload,
      password: dev.authPassword,
    );
    if (!_isAlive) return ok;
    if (ok) {
      await fetchDeviceRelays(deviceId);
      if (!_isAlive) return ok;
      final latestIdx = state.indexWhere((d) => d.id == deviceId);
      if (latestIdx >= 0) {
        await _refreshDeviceStatus(state[latestIdx]);
      }
    }
    return ok;
  }

  /// Fetch Alarms
  Future<List<ScheduledAlarm>> fetchDeviceAlarms(String deviceId) async {
    if (!_isAlive) return [];
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return [];
    final dev = state[idx];
    final raw = await _api.fetchAlarms(dev.ip, password: dev.authPassword);
    if (raw == null) return [];
    return raw.map((e) => ScheduledAlarm.fromJson(e)).toList();
  }

  /// Save Alarm
  Future<bool> saveDeviceAlarm(String deviceId, ScheduledAlarm alarm) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    return await _api.saveAlarm(
      dev.ip,
      alarm.toJson(),
      password: dev.authPassword,
    );
  }

  /// Toggle Alarm
  Future<bool> toggleDeviceAlarm(
    String deviceId,
    int alarmId,
    bool enabled,
  ) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    return await _api.setAlarmEnabled(
      dev.ip,
      alarmId,
      enabled,
      password: dev.authPassword,
    );
  }

  /// Delete Alarm
  Future<bool> deleteDeviceAlarm(String deviceId, int alarmId) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    return await _api.deleteAlarm(dev.ip, alarmId, password: dev.authPassword);
  }

  /// Control Buzzer
  Future<bool> controlBuzzer(
    String deviceId, {
    String? action,
    bool? enabled,
    int? volume,
  }) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    final payload = <String, dynamic>{};
    if (action != null) payload['action'] = action;
    if (enabled != null) payload['enabled'] = enabled;
    if (volume != null) payload['volume'] = volume;
    return await _api.controlBuzzer(
      dev.ip,
      payload,
      password: dev.authPassword,
    );
  }

  /// Calibrate Sensors
  Future<bool> calibrateSensors(
    String deviceId, {
    int? sensorIndex,
    double? tempOffset,
    double? humOffset,
    double? tempAlarm,
    int? mq2Threshold,
    bool? mq2Enabled,
    bool? calibrateMq2,
  }) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    final payload = <String, dynamic>{};
    if (sensorIndex != null) payload['sensor_index'] = sensorIndex;
    if (tempOffset != null) payload['temp_offset'] = tempOffset;
    if (humOffset != null) payload['hum_offset'] = humOffset;
    if (tempAlarm != null) payload['temp_alarm'] = tempAlarm;
    if (mq2Threshold != null) payload['mq2_threshold'] = mq2Threshold;
    if (mq2Enabled != null) payload['mq2_enabled'] = mq2Enabled;
    if (calibrateMq2 != null) payload['calibrate_mq2'] = calibrateMq2;
    return await _api.saveSensorCalibration(
      dev.ip,
      payload,
      password: dev.authPassword,
    );
  }

  /// Save LCD display settings
  Future<bool> saveLcdSettings(
    String deviceId, {
    bool? enabled,
    bool? backlight,
    int? rotation,
    int? brightness,
    String? displayMode,
    bool? autoDim,
    String? dimStart,
    String? dimEnd,
    int? dimBrightness,
  }) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    final payload = <String, dynamic>{};
    if (enabled != null) payload['enabled'] = enabled;
    if (backlight != null) payload['backlight'] = backlight;
    if (rotation != null) payload['rotation'] = rotation;
    if (brightness != null) payload['brightness'] = brightness;
    if (displayMode != null) payload['display_mode'] = displayMode;
    if (autoDim != null) payload['auto_dim'] = autoDim;
    if (dimStart != null) payload['dim_start'] = dimStart;
    if (dimEnd != null) payload['dim_end'] = dimEnd;
    if (dimBrightness != null) payload['dim_brightness'] = dimBrightness;
    return await _api.saveLcdConfig(
      dev.ip,
      payload,
      password: dev.authPassword,
    );
  }

  /// Fetch Logs
  Future<List<SystemLogEntry>> fetchDeviceLogs(String deviceId) async {
    if (!_isAlive) return [];
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return [];
    final dev = state[idx];
    final raw = await _api.fetchLogs(dev.ip, password: dev.authPassword);
    if (raw == null) return [];
    return raw.map((e) => SystemLogEntry.fromJson(e)).toList();
  }

  /// Clear Logs
  Future<bool> clearDeviceLogs(String deviceId) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    return await _api.clearLogs(dev.ip, password: dev.authPassword);
  }

  /// Fetch Diagnostics
  Future<DeviceDiagnostics?> fetchDeviceDiagnostics(String deviceId) async {
    if (!_isAlive) return null;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return null;
    final dev = state[idx];
    final raw = await _api.fetchDiagnostics(dev.ip, password: dev.authPassword);
    if (raw == null) return null;
    return DeviceDiagnostics.fromJson(raw);
  }

  /// Factory Reset
  Future<bool> factoryReset(String deviceId) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    return await _api.factoryReset(dev.ip, password: dev.authPassword);
  }

  /// Export Backup
  Future<String?> exportBackup(String deviceId) async {
    if (!_isAlive) return null;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return null;
    final dev = state[idx];
    return await _api.fetchBackup(
      dev.ip,
      password: dev.authPassword,
      username: dev.authUsername,
    );
  }

  /// Restore Backup
  Future<bool> restoreBackup(String deviceId, String backupJson) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    final ok = await _api.restoreConfig(
      dev.ip,
      backupJson,
      password: dev.authPassword,
      username: dev.authUsername,
    );
    if (!_isAlive) return ok;
    if (ok) {
      // Wait for the ESP32 1000ms deferred reboot + boot sequence, then re-sync
      Future.delayed(const Duration(milliseconds: 4500), () async {
        if (!_isAlive) return;
        await refreshDevice(deviceId);
        if (!_isAlive) return;
        await fetchDeviceRelays(deviceId);
      });
    }
    return ok;
  }

  /// Save core system & network configuration (e.g. ArduinoOTA, name, timezone)
  Future<bool> saveDeviceConfig(
    String deviceId,
    Map<String, dynamic> config,
  ) async {
    if (!_isAlive) return false;
    final idx = state.indexWhere((d) => d.id == deviceId);
    if (idx < 0) return false;
    final dev = state[idx];
    final ok = await _api.saveDeviceConfig(
      dev.ip,
      config,
      password: dev.authPassword,
      username: dev.authUsername,
    );
    if (!_isAlive) return ok;
    if (ok) {
      final curIdx = state.indexWhere((d) => d.id == deviceId);
      if (curIdx < 0) return ok;
      final current = state[curIdx];
      final newName = config['device_name']?.toString().trim();
      final newHost = config['hostname']?.toString().trim();
      final newUser = config['web_user']?.toString().trim();
      final newPass = config['web_pass']?.toString();

      final updated = current.copyWith(
        name: (newName != null && newName.isNotEmpty) ? newName : current.name,
        hostname: (newHost != null && newHost.isNotEmpty)
            ? newHost
            : current.hostname,
        authUsername: (newUser != null && newUser.isNotEmpty)
            ? newUser
            : current.authUsername,
        authPassword: (newPass != null && newPass.isNotEmpty)
            ? newPass
            : current.authPassword,
      );
      final list = List<SmartDevice>.from(state);
      list[curIdx] = updated;
      state = list;
      await _storage.saveDevices(list);
      if (!_isAlive) return ok;
      ApiClient.registerDeviceUsername(updated.ip, updated.authUsername);
      if (config.containsKey('web_user') || config.containsKey('web_pass')) {
        _replaceForegroundStream(updated);
      }
    }
    return ok;
  }

  /// Remove device
  Future<void> removeDevice(String deviceId) async {
    if (!_isAlive) return;
    final existingIdx = state.indexWhere((d) => d.id == deviceId);
    final removed = existingIdx >= 0 ? state[existingIdx] : null;

    _wsClients[deviceId]?.dispose();
    _wsClients.remove(deviceId);
    _activeAlertKeys.removeWhere((k) => k.startsWith('$deviceId:'));

    if (removed != null && removed.ip.isNotEmpty) {
      ApiClient.unregisterDevice(removed.ip);
    }
    await _storage.deleteDeviceCredentials(deviceId);
    if (!_isAlive) return;

    final newList = state.where((d) => d.id != deviceId).toList();
    state = newList;
    await _storage.saveDevices(newList);
  }

  /// Pre-register a device that was just provisioned in SoftAP mode so its room,
  /// custom name, and admin credentials are automatically linked when it joins LAN.
  Future<void> registerProvisionedDevice(SmartDevice provisioned) async {
    if (!_isAlive) return;
    final existingIdx = state.indexWhere(
      (d) =>
          (d.mac.isNotEmpty && d.mac == provisioned.mac) ||
          d.id == provisioned.id,
    );
    final newList = List<SmartDevice>.from(state);
    if (existingIdx >= 0) {
      newList[existingIdx] = newList[existingIdx].copyWith(
        name: provisioned.name,
        room: provisioned.room,
        authRequired: provisioned.authRequired,
        authLocked: false,
        authUsername: provisioned.authUsername ?? 'admin',
        authPassword: provisioned.authPassword,
      );
    } else {
      newList.add(provisioned.copyWith(isOnline: false));
    }
    state = newList;
    await _storage.saveDevices(newList);
  }

  /// Export the full Multi-Controller Hub configuration to a single JSON string.
  Future<String> exportHubBackupJson({bool includeCredentials = true}) async {
    if (!_isAlive) return '';
    return await _storage.exportHubBackupJson(
      state,
      includeCredentials: includeCredentials,
    );
  }

  /// Import and restore a Multi-Controller Hub configuration from JSON.
  Future<bool> importHubBackupJson(String rawJson) async {
    if (!_isAlive) return false;
    final restored = await _storage.importHubBackupJson(rawJson);
    if (!_isAlive || restored == null) return false;

    for (final client in _wsClients.values) {
      client.dispose();
    }
    _wsClients.clear();

    for (final dev in restored) {
      ApiClient.registerDeviceUsername(dev.ip, dev.authUsername);
    }
    state = restored;

    if (_foregroundSyncEnabled && restored.isNotEmpty) {
      await startForegroundSync();
    }
    return true;
  }
}
