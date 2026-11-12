import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../main.dart';
import '../../services/device_manager.dart';
import '../../services/device_storage_service.dart';

/// A companion-only view of live controller data. It intentionally has no
/// fabricated history: every value is supplied by a selected ESP32 response.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  final DeviceStorageService _storage = DeviceStorageService();
  late final DeviceManager _manager;
  String? _selectedDeviceId; // null means the explicit All Devices view.
  bool _prefsLoaded = false;
  bool _initialRefreshStarted = false;
  bool _autoSelectedSingleDevice = false;
  Timer? _tickerTimer;

  @override
  void initState() {
    super.initState();
    _manager = ref.read(deviceManagerProvider.notifier);
    _loadPreferences();
    _tickerTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final selected = await _storage.loadMonitoringDeviceId();
    if (!mounted) return;
    setState(() {
      _selectedDeviceId = selected;
      _prefsLoaded = true;
    });
  }

  Future<void> _refreshScope() async {
    final selected = _selectedDeviceId;
    if (selected == null) {
      await _manager.refreshAllDevices();
    } else {
      await _manager.refreshDevice(selected);
    }
  }

  Future<void> _selectDevice(String? id) async {
    setState(() => _selectedDeviceId = id);
    await _storage.saveMonitoringDeviceId(id);
    await _refreshScope();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final currentIndex = ref.watch(navigationIndexProvider);

    // A stored device may have been removed. Fall back to the explicit All
    // Devices view instead of silently substituting unrelated hardware.
    if (_selectedDeviceId != null &&
        !devices.any((d) => d.id == _selectedDeviceId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _selectDevice(null);
        }
      });
    }

    // With a single controller, make the focused view convenient while still
    // preserving All Devices as the default for installations with many nodes.
    if (_prefsLoaded &&
        !_autoSelectedSingleDevice &&
        _selectedDeviceId == null &&
        devices.length == 1) {
      _autoSelectedSingleDevice = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedDeviceId == null) {
          _selectDevice(devices.first.id);
        }
      });
    }

    if (currentIndex == 3 &&
        _prefsLoaded &&
        !_initialRefreshStarted &&
        devices.isNotEmpty) {
      _initialRefreshStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshScope();
      });
    }

    final selected = _selectedDeviceId == null
        ? null
        : _findDevice(devices, _selectedDeviceId!);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monitoring',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'LIVE CONTROLLER STATUS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh current view',
            onPressed: _refreshScope,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshScope,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            _deviceSelector(devices),
            const SizedBox(height: 14),
            if (selected == null)
              _allDevices(devices)
            else
              _deviceDetails(selected),
          ],
        ),
      ),
    );
  }

  SmartDevice? _findDevice(List<SmartDevice> devices, String id) {
    for (final device in devices) {
      if (device.id == id) return device;
    }
    return null;
  }

  Widget _deviceSelector(List<SmartDevice> devices) {
    final validSelectedId = devices.any((d) => d.id == _selectedDeviceId)
        ? _selectedDeviceId
        : null;
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VIEW',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textMuted,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButton<String?>(
            value: validSelectedId,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All devices overview'),
              ),
              ...devices.map(
                (device) => DropdownMenuItem<String?>(
                  value: device.id,
                  child: Row(
                    children: [
                      _statusDot(device),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${device.name} · ${device.room}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            onChanged: (value) => _selectDevice(value),
          ),
        ],
      ),
    );
  }

  Widget _allDevices(List<SmartDevice> devices) {
    if (devices.isEmpty) {
      return _emptyState(
        icon: Icons.hub_outlined,
        title: 'No controllers added',
        message:
            'Add a SmartHome controller from the Controllers tab to monitor its live status.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONTROLLERS (${devices.length})',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...devices.map(
          (device) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _selectDevice(device.id),
              child: _surface(child: _deviceOverviewCard(device)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _deviceOverviewCard(SmartDevice device) {
    final telemetry = device.telemetry;
    final enabledRelays = device.relays.where((r) => r.enabled).toList();
    final chips = <Widget>[];
    if (device.isOnline) {
      if (!telemetry.dhtEnabled) {
        chips.add(
          _valueChip(
            Icons.thermostat_outlined,
            'Climate disabled',
            AppColors.textMuted,
          ),
        );
      } else if (telemetry.dhtFault) {
        chips.add(
          _valueChip(
            Icons.sensors_off_rounded,
            'DHT Fault',
            AppColors.danger,
          ),
        );
      } else {
        chips.add(
          _valueChip(
            Icons.thermostat_rounded,
            '${telemetry.temperature.toStringAsFixed(1)} °C',
            AppColors.tempAmber,
          ),
        );
        chips.add(
          _valueChip(
            Icons.water_drop_rounded,
            '${telemetry.humidity.toStringAsFixed(0)} %',
            AppColors.cyan,
          ),
        );
      }

      if (telemetry.gasWarming) {
        chips.add(
          _valueChip(
            Icons.hourglass_top_rounded,
            'MQ-2 warming',
            AppColors.warning,
          ),
        );
      } else {
        chips.add(
          _valueChip(
            Icons.local_fire_department_rounded,
            '${telemetry.gasRaw} ADC',
            telemetry.gasAlarm ? AppColors.danger : AppColors.success,
          ),
        );
      }

      if (telemetry.pressureEnabled && telemetry.pressure > 300) {
        chips.add(
          _valueChip(
            Icons.compress_rounded,
            '${telemetry.pressure.toStringAsFixed(1)} hPa',
            AppColors.primary,
          ),
        );
      }
      if (telemetry.luxEnabled) {
        chips.add(
          _valueChip(
            Icons.light_mode_rounded,
            '${telemetry.lux.toStringAsFixed(0)} lx',
            AppColors.accent,
          ),
        );
      }
      if (telemetry.motionEnabled) {
        chips.add(
          _valueChip(
            Icons.directions_run_rounded,
            telemetry.motionDetected ? 'Motion' : 'Clear',
            telemetry.motionDetected ? AppColors.warning : AppColors.textSecondary,
          ),
        );
      }
      if (telemetry.tankEnabled) {
        chips.add(
          _valueChip(
            Icons.water_damage_rounded,
            'Tank ${telemetry.tankLevelPct}%',
            AppColors.cyan,
          ),
        );
      }

      chips.add(
        _valueChip(
          enabledRelays.isEmpty ? Icons.sensors_rounded : Icons.power_rounded,
          enabledRelays.isEmpty
              ? 'Sensor Node'
              : '${enabledRelays.where((r) => r.state).length}/${enabledRelays.length} active',
          AppColors.primary,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _statusDot(device),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                device.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '${device.room} · ${_statusText(device)}',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (!device.isOnline)
          Text(
            'No current reading available',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
        if (device.isOnline && telemetry.gasAlarm) ...[
          const SizedBox(height: 8),
          Text(
            'Gas/smoke alert active',
            style: TextStyle(
              color: AppColors.danger,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }

  Widget _deviceDetails(SmartDevice device) {
    if (!device.isOnline) {
      return _emptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Controller offline',
        message:
            'No current data is available. Check power and Wi-Fi, then refresh.',
      );
    }
    final telemetry = device.telemetry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _statusDot(device),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      device.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const Icon(Icons.sync_rounded, color: AppColors.success),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${device.room} · ${_statusText(device)}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                'Live updates every 10 seconds while the app is open.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle(
          Icons.thermostat_rounded,
          'Environment',
          AppColors.tempAmber,
        ),
        const SizedBox(height: 8),
        if (!telemetry.dhtEnabled)
          _surface(
            child: _notice(
              Icons.thermostat_outlined,
              'Climate sensor disabled',
              'DHT temperature and humidity monitoring is disabled in Hardware Profile.',
              AppColors.textMuted,
            ),
          )
        else if (telemetry.dhtFault)
          _surface(
            child: _notice(
              Icons.sensors_off_rounded,
              'DHT22 sensor fault',
              'Temperature and humidity are unavailable until the sensor recovers.',
              AppColors.danger,
            ),
          )
        else
          _surface(
            child: Row(
              children: [
                Expanded(
                  child: _largeValue(
                    'Temperature',
                    '${telemetry.temperature.toStringAsFixed(1)} °C',
                    AppColors.tempAmber,
                  ),
                ),
                _divider(),
                Expanded(
                  child: _largeValue(
                    'Humidity',
                    '${telemetry.humidity.toStringAsFixed(0)} %',
                    AppColors.cyan,
                  ),
                ),
                _divider(),
                Expanded(
                  child: _largeValue(
                    'Alert threshold',
                    '${telemetry.tempThreshold.toStringAsFixed(1)} °C',
                    AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        _sectionTitle(
          Icons.local_fire_department_rounded,
          'Air Safety',
          telemetry.gasAlarm ? AppColors.danger : AppColors.success,
        ),
        const SizedBox(height: 8),
        _surface(
          child: telemetry.gasWarming
              ? _notice(
                  Icons.hourglass_top_rounded,
                  'MQ-2 warming up',
                  'Alarm decisions wait until the ESP sensor warm-up completes.',
                  AppColors.warning,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _largeValue(
                            'Current level',
                            '${telemetry.gasRaw} ADC',
                            telemetry.gasAlarm
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                        _divider(),
                        Expanded(
                          child: _largeValue(
                            'ESP threshold',
                            '${telemetry.gasThreshold} ADC',
                            AppColors.textPrimary,
                          ),
                        ),
                        _divider(),
                        Expanded(
                          child: _largeValue(
                            'Status',
                            telemetry.gasAlarm ? 'ALERT' : 'Normal',
                            telemetry.gasAlarm
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    if (telemetry.gasAlarm ||
                        (telemetry.dhtEnabled &&
                            !telemetry.dhtFault &&
                            telemetry.tempThreshold > 0 &&
                            telemetry.temperature >=
                                telemetry.tempThreshold)) ...[
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final ok = await _manager.controlBuzzer(
                            device.id,
                            action: 'mute',
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Controller buzzer muted for 5 minutes.'
                                    : 'Failed to mute buzzer.',
                              ),
                              backgroundColor: ok
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                          );
                        },
                        icon: const Icon(Icons.volume_off_rounded, size: 18),
                        label: const Text(
                          'Mute Alarm Buzzer (5 min)',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        if ((telemetry.pressureEnabled && telemetry.pressure > 300) ||
            telemetry.climates.length > 1 ||
            telemetry.mq2s.length > 1 ||
            telemetry.luxEnabled ||
            telemetry.motionEnabled ||
            telemetry.probeEnabled ||
            telemetry.tankEnabled ||
            telemetry.lights.isNotEmpty ||
            telemetry.motions.isNotEmpty ||
            telemetry.probes.isNotEmpty ||
            telemetry.tanks.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionTitle(
            Icons.sensors_rounded,
            'Extended Sensors',
            AppColors.cyan,
          ),
          const SizedBox(height: 8),
          _surface(
            child: Wrap(
              spacing: 22,
              runSpacing: 16,
              children: [
                if (telemetry.pressureEnabled && telemetry.pressure > 300)
                  _detail(
                    'Barometric Pressure',
                    '${telemetry.pressure.toStringAsFixed(1)} hPa',
                  ),
                for (int i = 1; i < telemetry.climates.length; i++)
                  if (telemetry.climates[i].enabled)
                    _detail(
                      telemetry.climates[i].displayName,
                      telemetry.climates[i].fault
                          ? 'Fault / Disconnected'
                          : '${telemetry.climates[i].temperature.toStringAsFixed(1)} °C • ${telemetry.climates[i].humidity.toStringAsFixed(0)} %'
                              '${telemetry.climates[i].barometer && telemetry.climates[i].pressure > 300 ? " • ${telemetry.climates[i].pressure.toStringAsFixed(1)} hPa" : ""}',
                    ),
                for (int i = 1; i < telemetry.mq2s.length; i++)
                  if (telemetry.mq2s[i].enabled)
                    _detail(
                      telemetry.mq2s[i].displayName,
                      '${telemetry.mq2s[i].raw} ADC (${telemetry.mq2s[i].alarm ? "ALERT" : "Normal"})',
                    ),
                if (telemetry.lights.isNotEmpty)
                  for (final l in telemetry.lights.where((x) => x.enabled))
                    _detail(
                      telemetry.lights.length > 1 || l.label.isNotEmpty
                          ? l.displayName
                          : 'Ambient Light',
                      '${l.lux.toStringAsFixed(0)} lx',
                    )
                else if (telemetry.luxEnabled)
                  _detail(
                    'Ambient Light',
                    '${telemetry.lux.toStringAsFixed(0)} lx',
                  ),
                if (telemetry.motions.isNotEmpty)
                  for (final m in telemetry.motions.where((x) => x.enabled))
                    _detail(
                      telemetry.motions.length > 1 || m.label.isNotEmpty
                          ? m.displayName
                          : 'Motion / PIR',
                      m.detected
                          ? 'MOTION DETECTED'
                          : 'Clear (${m.ageSeconds}s ago)',
                    )
                else if (telemetry.motionEnabled)
                  _detail(
                    'Motion / PIR',
                    telemetry.motionDetected
                        ? 'MOTION DETECTED'
                        : 'Clear (${telemetry.motionAgeSeconds}s ago)',
                  ),
                if (telemetry.probes.isNotEmpty)
                  for (final p in telemetry.probes.where((x) => x.enabled))
                    _detail(
                      telemetry.probes.length > 1 || p.label.isNotEmpty
                          ? p.displayName
                          : 'Water Probe',
                      p.fault || p.temperature <= -55
                          ? 'Fault / Disconnected'
                          : '${p.temperature.toStringAsFixed(1)} °C',
                    )
                else if (telemetry.probeEnabled)
                  _detail(
                    'Water Probe',
                    telemetry.probeFault || telemetry.probeTemp <= -55
                        ? 'Fault / Disconnected'
                        : '${telemetry.probeTemp.toStringAsFixed(1)} °C',
                  ),
                if (telemetry.tanks.isNotEmpty)
                  for (final u in telemetry.tanks.where((x) => x.enabled))
                    _detail(
                      telemetry.tanks.length > 1 || u.label.isNotEmpty
                          ? u.displayName
                          : 'Water Tank Level',
                      '${u.levelPct}% (${u.distanceCm.toStringAsFixed(1)} cm)',
                    )
                else if (telemetry.tankEnabled)
                  _detail(
                    'Water Tank Level',
                    '${telemetry.tankLevelPct}% (${telemetry.distanceCm.toStringAsFixed(1)} cm)',
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        _sectionTitle(
          Icons.memory_rounded,
          'Controller Status',
          AppColors.primary,
        ),
        const SizedBox(height: 8),
        _surface(
          child: Wrap(
            spacing: 22,
            runSpacing: 16,
            children: [
              _detail(
                'Wi-Fi signal',
                '${device.signalPercent}% (${device.rssi} dBm)',
              ),
              _detail('Address', device.ip.isEmpty ? 'Unavailable' : device.ip),
              _detail('Firmware', device.fwVersion),
              _detail(
                'Uptime',
                device.uptime.isEmpty ? 'Unavailable' : device.uptime,
              ),
              _detail(
                'Free heap',
                device.freeHeap > 0 ? '${device.freeHeap} B' : 'Unavailable',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle(Icons.power_rounded, 'Relay Status', AppColors.primary),
        const SizedBox(height: 8),
        _surface(
          child: device.relays.isEmpty
              ? Text(
                  device.numRelays == 0
                      ? 'Sensor Node active (0 relays configured).'
                      : 'Relay status has not been reported by this controller.',
                  style: TextStyle(color: AppColors.textMuted),
                )
              : Column(
                  children: device.relays
                      .map(
                        (relay) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(
                            children: [
                              Icon(
                                !relay.enabled
                                    ? Icons.block_rounded
                                    : (relay.state
                                          ? Icons.power_rounded
                                          : Icons.power_off_rounded),
                                color: !relay.enabled
                                    ? AppColors.textMuted
                                    : (relay.state
                                          ? AppColors.success
                                          : AppColors.textMuted),
                                size: 19,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  relay.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: relay.enabled
                                        ? AppColors.textPrimary
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ),
                              Text(
                                !relay.enabled
                                    ? 'DISABLED'
                                    : (relay.state ? 'ON' : 'OFF'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: !relay.enabled
                                      ? AppColors.textMuted
                                      : (relay.state
                                            ? AppColors.success
                                            : AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  Widget _surface({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.cardBorder),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: AppColors.isDark ? 0.20 : 0.035,
          ),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );

  Widget _sectionTitle(IconData icon, String label, Color color) => Row(
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
    ],
  );

  Widget _largeValue(String label, String value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          letterSpacing: 0.4,
          fontWeight: FontWeight.w800,
          color: AppColors.textMuted,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    ],
  );

  Widget _detail(String label, String value) => SizedBox(
    width: 132,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    ),
  );

  Widget _divider() => Container(
    width: 1,
    height: 44,
    color: AppColors.cardBorder,
    margin: const EdgeInsets.symmetric(horizontal: 10),
  );

  Widget _valueChip(IconData icon, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    ),
  );

  Widget _notice(IconData icon, String title, String message, Color color) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) => _surface(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Column(
        children: [
          Icon(icon, size: 38, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );

  Widget _statusDot(SmartDevice device) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      color: _statusColor(device),
      shape: BoxShape.circle,
    ),
  );

  Color _statusColor(SmartDevice device) {
    if (!device.isOnline) {
      return AppColors.textMuted;
    }
    if (DateTime.now().difference(device.lastSeen).inSeconds > 45) {
      return AppColors.warning;
    }
    return AppColors.success;
  }

  String _statusText(SmartDevice device) {
    if (!device.isOnline) {
      return 'Offline';
    }
    final elapsed = DateTime.now().difference(device.lastSeen);
    if (elapsed.inSeconds > 45) {
      return 'Stale · updated ${_elapsedText(elapsed)} ago';
    }
    return 'Updated ${_elapsedText(elapsed)} ago';
  }

  String _elapsedText(Duration elapsed) {
    if (elapsed.inSeconds < 5) return 'just now';
    if (elapsed.inMinutes < 1) return '${elapsed.inSeconds}s';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m';
    return '${elapsed.inHours}h';
  }
}
