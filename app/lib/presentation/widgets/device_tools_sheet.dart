import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/device_diagnostics.dart';
import '../../core/models/hardware_profile.dart';
import '../../core/models/smart_device.dart';
import '../../core/models/system_log_entry.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import 'glass_card.dart';
import 'hardware_config_sheet.dart';

class DeviceToolsSheet extends StatefulWidget {
  final SmartDevice device;
  final DeviceManager manager;

  const DeviceToolsSheet({
    super.key,
    required this.device,
    required this.manager,
  });

  static void show(
    BuildContext context,
    SmartDevice device,
    DeviceManager manager,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DeviceToolsSheet(device: device, manager: manager),
    );
  }

  @override
  State<DeviceToolsSheet> createState() => _DeviceToolsSheetState();
}

class _DeviceToolsSheetState extends State<DeviceToolsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Diagnostics State
  DeviceDiagnostics? _diag;
  bool _loadingDiag = false;

  // Logs State
  List<SystemLogEntry> _logs = [];
  bool _loadingLogs = false;
  String _logFilter = 'ALL';

  // Calibration State
  double _tempOffset = 0.0;
  double _humOffset = 0.0;
  bool _selectedClimateHasHum = true;
  int _mq2Threshold = 400;
  int _gasMax = 4095;
  int _selectedMq2Type = 0;
  int _selectedClimateIdx = 0;
  int _selectedMq2Idx = 0;
  List<Map<String, dynamic>> _climateCals = [];
  List<Map<String, dynamic>> _mq2Cals = [];

  // Hardware profile permissions
  bool _lcdHwAllowed = true;
  bool _buzzerHwAllowed = true;
  bool _mq2HwAllowed = true;

  // Hardware Controls State
  bool _lcdBacklight = true;
  bool _lcdEnabled = true;
  bool _arduinoOta = false;

  // Full controller-settings state. These values are populated from the ESP
  // before editing; nothing here is an app-only setting.
  final _wifiSsid = TextEditingController();
  final _wifiPassword = TextEditingController();
  final _mqttBroker = TextEditingController();
  final _mqttPort = TextEditingController();
  final _mqttPrefix = TextEditingController();
  final _mqttClientId = TextEditingController();
  final _mqttUser = TextEditingController();
  final _mqttPassword = TextEditingController();
  final _deviceName = TextEditingController();
  final _hostname = TextEditingController();
  final _timezone = TextEditingController();
  final _webUser = TextEditingController();
  final _webPassword = TextEditingController();
  final _guestUser = TextEditingController();
  final _guestPassword = TextEditingController();
  final _apPassword = TextEditingController();
  final _alertWebhookUrl = TextEditingController();
  final _alertWebhookToken = TextEditingController();
  final _dimStart = TextEditingController();
  final _dimEnd = TextEditingController();
  bool _mqttEnabled = false;
  bool _webAuth = false;
  bool _webPasswordSet = false;
  bool _guestAuth = false;
  bool _guestPasswordSet = false;
  bool _guestPasswordClear = false;
  bool _apPasswordSet = false;
  bool _apPasswordClear = false;
  bool _alertWebhookEn = false;
  bool _alertWebhookTokenSet = false;
  bool _alertWebhookTokenClear = false;
  bool _alertHttpsSupported = true;
  bool _isTestingRemoteAlert = false;
  bool _use24h = false;
  bool _mq2Enabled = true;
  bool _autoDim = false;
  bool _buzzerEnabled = true;
  String _lcdDisplayMode = 'rotate';
  int _lcdCols = 16;
  int _lcdRows = 2;
  int _lcdRotation = 5;
  int _lcdBrightness = 100;
  int _lcdDimBrightness = 0;
  List<_LcdPageEntry> _lcdPages = _defaultLcdPages();
  List<String> _lcdLines = ['climate:0', 'relays', 'gas:0', 'ip'];
  List<_LcdWidgetOption> _lcdWidgetCatalog = _defaultLcdWidgets();

  static List<_LcdPageEntry> _defaultLcdPages() => [
        _LcdPageEntry(id: 'climate', label: 'Climate (Temp / Hum / Pressure)', available: true, enabled: true),
        _LcdPageEntry(id: 'gas', label: 'Air Quality / Gas', available: true, enabled: true),
        _LcdPageEntry(id: 'tank', label: 'Ultrasonic Tank Level', available: true, enabled: true),
        _LcdPageEntry(id: 'probe', label: 'Water Temp Probe', available: true, enabled: true),
        _LcdPageEntry(id: 'lux', label: 'Ambient Light (Lux)', available: true, enabled: true),
        _LcdPageEntry(id: 'motion', label: 'Motion / Presence', available: true, enabled: true),
        _LcdPageEntry(id: 'relays', label: 'Relays & Timers', available: true, enabled: true),
        _LcdPageEntry(id: 'network', label: 'Date, Time & IP', available: true, enabled: true),
        _LcdPageEntry(id: 'mqtt', label: 'MQTT & Uptime', available: true, enabled: true),
      ];

  static List<_LcdWidgetOption> _defaultLcdWidgets() => const [
        _LcdWidgetOption(id: 'climate:0', label: 'Climate #1 (Summary)'),
        _LcdWidgetOption(id: 'temp:0', label: 'Climate #1 - Temp'),
        _LcdWidgetOption(id: 'hum:0', label: 'Climate #1 - Humidity'),
        _LcdWidgetOption(id: 'gas:0', label: 'Gas / VOC #1'),
        _LcdWidgetOption(id: 'relays', label: 'Relay States'),
        _LcdWidgetOption(id: 'timer', label: 'Next Active Timer'),
        _LcdWidgetOption(id: 'time', label: 'Clock & Date'),
        _LcdWidgetOption(id: 'ip', label: 'IP Address'),
        _LcdWidgetOption(id: 'mqtt', label: 'MQTT & Uptime'),
        _LcdWidgetOption(id: 'none', label: '(Blank Row)'),
      ];
  int _buzzerVolume = 128;
  double _tempAlarm = 35;
  bool _isSavingWifi = false;
  bool _isSavingMqtt = false;
  bool _isSavingDevice = false;
  bool _isSavingLcd = false;
  bool _isSavingBuzzer = false;
  bool _isSavingCalibration = false;
  bool _isCalibratingCleanAir = false;
  bool _isExportingBackup = false;
  bool _backupIncludeSecrets = false;
  bool _isLoadingConfig = true;
  bool _configLoadFailed = false;

  @override
  void initState() {
    super.initState();
    final t = widget.device.telemetry;
    _selectedClimateHasHum = t.climates.isNotEmpty
        ? t.climates.first.humidityEnabled
        : t.humidityEnabled;
    _selectedMq2Type = t.mq2s.isNotEmpty
        ? t.mq2s.first.type
        : (t.gasUnit.toUpperCase() == 'VOC' ? 1 : 0);
    _gasMax = t.gasMax > 0
        ? t.gasMax
        : (_selectedMq2Type == 1
            ? 500
            : (widget.device.isEsp8266 ? 1023 : 4095));
    final initialThresh = t.gasThreshold > 0
        ? t.gasThreshold
        : (_selectedMq2Type == 1 ? 250 : (widget.device.isEsp8266 ? 100 : 400));
    _mq2Threshold = initialThresh.clamp(10, _gasMax);
    _tabController = TabController(length: 5, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in [
      _wifiSsid,
      _wifiPassword,
      _mqttBroker,
      _mqttPort,
      _mqttPrefix,
      _mqttClientId,
      _mqttUser,
      _mqttPassword,
      _deviceName,
      _hostname,
      _timezone,
      _webUser,
      _webPassword,
      _guestUser,
      _guestPassword,
      _apPassword,
      _alertWebhookUrl,
      _alertWebhookToken,
      _dimStart,
      _dimEnd,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _applyClimateCalIndex(int idx) {
    _selectedClimateIdx = idx;
    if (idx >= 0 && idx < _climateCals.length) {
      final c = _climateCals[idx];
      _tempOffset = ((c['temp_offset'] as num?)?.toDouble() ?? 0.0).clamp(-5.0, 5.0);
      _humOffset = ((c['hum_offset'] as num?)?.toDouble() ?? 0.0).clamp(-10.0, 10.0);
      _selectedClimateHasHum =
          c['humidity_enabled'] as bool? ?? ((c['type'] as num?)?.toInt() != 7);
    } else if (idx >= 0 && idx < widget.device.telemetry.climates.length) {
      final c = widget.device.telemetry.climates[idx];
      _tempOffset = c.tempOffset.clamp(-5.0, 5.0);
      _humOffset = c.humOffset.clamp(-10.0, 10.0);
      _selectedClimateHasHum = c.humidityEnabled;
    }
  }

  void _applyMq2CalIndex(int idx) {
    _selectedMq2Idx = idx;
    if (idx >= 0 && idx < _mq2Cals.length) {
      final m = _mq2Cals[idx];
      _selectedMq2Type = (m['type'] as num?)?.toInt() ?? 0;
      _gasMax = (m['gas_max'] as num?)?.toInt() ??
          (_selectedMq2Type == 1
              ? 500
              : (widget.device.isEsp8266 ? 1023 : 4095));
      _mq2Threshold = ((m['threshold'] as num?)?.toInt() ??
              (_selectedMq2Type == 1 ? 250 : 400))
          .clamp(10, _gasMax);
      _mq2Enabled = m['enabled'] as bool? ?? true;
      _mq2HwAllowed = m['hw_allowed'] as bool? ?? true;
    } else if (idx >= 0 && idx < widget.device.telemetry.mq2s.length) {
      final m = widget.device.telemetry.mq2s[idx];
      _selectedMq2Type = m.type;
      _gasMax = m.gasMax > 0
          ? m.gasMax
          : (_selectedMq2Type == 1
              ? 500
              : (widget.device.isEsp8266 ? 1023 : 4095));
      _mq2Threshold = m.threshold.clamp(10, _gasMax);
      _mq2Enabled = m.enabled;
      _mq2HwAllowed = m.hwAllowed;
    }
  }

  int get _climateSlotCount => math.max(
        _climateCals.length,
        widget.device.telemetry.climates.length,
      );

  int get _mq2SlotCount => math.max(
        _mq2Cals.length,
        widget.device.telemetry.mq2s.length,
      );

  String _climateSlotName(int idx) {
    final tList = widget.device.telemetry.climates;
    if (idx >= 0 && idx < tList.length) return tList[idx].displayName;
    return 'Climate #${idx + 1}';
  }

  String _mq2SlotName(int idx) {
    final tList = widget.device.telemetry.mq2s;
    if (idx >= 0 && idx < tList.length) {
      final tName = tList[idx].typeName.isNotEmpty
          ? tList[idx].typeName
          : GasSensorType.fromValue(tList[idx].type).shortName;
      return '${tList[idx].displayName} ($tName)';
    }
    if (idx >= 0 && idx < _mq2Cals.length) {
      final tVal = (_mq2Cals[idx]['type'] as num?)?.toInt() ?? 0;
      final tName = _mq2Cals[idx]['type_name']?.toString() ??
          GasSensorType.fromValue(tVal).shortName;
      return 'Gas #${idx + 1} ($tName)';
    }
    return 'Gas #${idx + 1}';
  }

  String get _selectedMq2ShortName =>
      GasSensorType.fromValue(_selectedMq2Type).shortName;

  Future<void> _loadInitialData() async {
    _loadDiagnostics();
    _loadLogs();
    _loadDeviceConfig();
  }

  Future<void> _loadDeviceConfig() async {
    if (mounted) {
      setState(() {
        _isLoadingConfig = true;
        _configLoadFailed = false;
      });
    }
    final cfg = await widget.manager.fetchDeviceConfig(widget.device.id);
    if (!mounted) return;
    if (cfg == null) {
      setState(() {
        _isLoadingConfig = false;
        _configLoadFailed = true;
      });
      return;
    }
    setState(() {
      _isLoadingConfig = false;
      _configLoadFailed = false;
      if (cfg['sensor'] is Map) {
        final s = cfg['sensor'] as Map;
        final cfgGasMax = (s['gas_max'] as num?)?.toInt();
        if (cfgGasMax != null && cfgGasMax >= 100) {
          _gasMax = cfgGasMax;
        }
        _tempAlarm =
            ((s['temp_alarm'] as num?)?.toDouble() ?? _tempAlarm).clamp(10.0, 60.0);

        if (s['climates'] is List) {
          _climateCals = (s['climates'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }
        if (s['mq2_sensors'] is List) {
          _mq2Cals = (s['mq2_sensors'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        }

        if (_climateCals.isNotEmpty) {
          _selectedClimateIdx = _selectedClimateIdx.clamp(0, _climateCals.length - 1);
          _applyClimateCalIndex(_selectedClimateIdx);
        } else {
          _tempOffset =
              ((s['temp_offset'] as num?)?.toDouble() ?? _tempOffset).clamp(-5.0, 5.0);
          _humOffset =
              ((s['hum_offset'] as num?)?.toDouble() ?? _humOffset).clamp(-10.0, 10.0);
          _selectedClimateHasHum =
              s['humidity_enabled'] as bool? ?? _selectedClimateHasHum;
        }

        if (_mq2Cals.isNotEmpty) {
          _selectedMq2Idx = _selectedMq2Idx.clamp(0, _mq2Cals.length - 1);
          _applyMq2CalIndex(_selectedMq2Idx);
        } else {
          if (cfgGasMax == 500) _selectedMq2Type = 1;
          _mq2Threshold =
              ((s['mq2_threshold'] as num?)?.toInt() ?? _mq2Threshold).clamp(10, _gasMax);
          _mq2Enabled = s['mq2_enabled'] as bool? ?? _mq2Enabled;
          _mq2HwAllowed = s['mq2_hw_allowed'] as bool? ?? true;
        }
      }
      if (cfg['lcd'] is Map) {
        final l = cfg['lcd'] as Map;
        _lcdEnabled = l['enabled'] as bool? ?? _lcdEnabled;
        _lcdHwAllowed = l['hw_allowed'] as bool? ?? true;
        _lcdCols = ((l['cols'] as num?)?.toInt() ?? _lcdCols).clamp(8, 20);
        _lcdRows = ((l['rows'] as num?)?.toInt() ?? _lcdRows).clamp(1, 4);
        _lcdBacklight = l['backlight'] as bool? ?? _lcdBacklight;
        final rawMode = l['display_mode'] as String?;
        if (rawMode == 'rotate' || rawMode == 'dht_relay' || rawMode == 'custom') {
          _lcdDisplayMode = rawMode!;
        }
        _lcdRotation =
            ((l['rotation'] as num?)?.toInt() ?? _lcdRotation).clamp(3, 30);
        _lcdBrightness =
            ((l['brightness'] as num?)?.toInt() ?? _lcdBrightness).clamp(0, 100);
        _autoDim = l['auto_dim'] as bool? ?? _autoDim;
        _dimStart.text = l['dim_start'] as String? ?? '22:00';
        _dimEnd.text = l['dim_end'] as String? ?? '06:00';
        _lcdDimBrightness =
            ((l['dim_brightness'] as num?)?.toInt() ?? _lcdDimBrightness).clamp(0, 100);

        final savedPages = l['pages'] is List
            ? (l['pages'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final cat = l['catalog'] is Map ? (l['catalog'] as Map) : null;
        final rawCatPages = cat?['pages'] is List ? (cat!['pages'] as List) : null;
        final basePages = rawCatPages != null
            ? rawCatPages
                .whereType<Map>()
                .map(
                  (p) => _LcdPageEntry(
                    id: p['id']?.toString() ?? '',
                    label: p['label']?.toString() ?? '',
                    available: p['available'] as bool? ?? true,
                    enabled: false,
                  ),
                )
                .where((p) => p.id.isNotEmpty)
                .toList()
            : _defaultLcdPages();
        final byId = <String, _LcdPageEntry>{
          for (final p in basePages) p.id: p,
        };
        final orderedPages = <_LcdPageEntry>[];
        for (final id in savedPages) {
          final entry = byId.remove(id);
          if (entry != null) {
            entry.enabled = true;
            orderedPages.add(entry);
          }
        }
        for (final rem in basePages) {
          if (byId.containsKey(rem.id)) {
            rem.enabled = savedPages.isEmpty;
            orderedPages.add(rem);
          }
        }
        if (orderedPages.isNotEmpty) {
          _lcdPages = orderedPages;
        }

        final rawWidgets = cat?['widgets'] is List ? (cat!['widgets'] as List) : null;
        if (rawWidgets != null && rawWidgets.isNotEmpty) {
          final parsed = rawWidgets
              .whereType<Map>()
              .map(
                (w) => _LcdWidgetOption(
                  id: w['id']?.toString() ?? '',
                  label: w['label']?.toString() ?? '',
                ),
              )
              .where((w) => w.id.isNotEmpty)
              .toList();
          if (parsed.isNotEmpty) {
            _lcdWidgetCatalog = parsed;
          }
        }

        if (l['lines'] is List) {
          final incoming = (l['lines'] as List).map((e) => e.toString()).toList();
          final nextLines = List<String>.filled(4, 'none');
          for (var i = 0; i < 4; i++) {
            nextLines[i] = i < incoming.length && incoming[i].isNotEmpty
                ? incoming[i]
                : (i < _lcdLines.length ? _lcdLines[i] : 'none');
          }
          _lcdLines = nextLines;
        }
      }
      if (cfg['buzzer'] is Map) {
        final b = cfg['buzzer'] as Map;
        _buzzerEnabled = b['enabled'] as bool? ?? _buzzerEnabled;
        _buzzerHwAllowed = b['hw_allowed'] as bool? ?? true;
        _buzzerVolume =
            ((b['volume'] as num?)?.toInt() ?? _buzzerVolume).clamp(0, 255);
      }
      if (cfg['mqtt'] is Map) {
        final m = cfg['mqtt'] as Map;
        _mqttEnabled = m['enabled'] as bool? ?? _mqttEnabled;
        _mqttBroker.text = m['broker']?.toString() ?? '';
        _mqttPort.text = m['port']?.toString() ?? '1883';
        _mqttPrefix.text = m['prefix']?.toString() ?? '';
        _mqttClientId.text = m['client_id']?.toString() ?? '';
        _mqttUser.text = m['user']?.toString() ?? '';
      }
      _deviceName.text = cfg['device_name']?.toString() ?? widget.device.name;
      _hostname.text = cfg['hostname']?.toString() ?? widget.device.hostname;
      _timezone.text = cfg['timezone']?.toString() ?? 'IST-5:30';
      _webAuth = cfg['web_auth'] as bool? ?? _webAuth;
      _webPasswordSet = cfg['web_pass_set'] as bool? ?? _webPasswordSet;
      _webUser.text = cfg['web_user']?.toString() ?? '';
      _guestAuth = cfg['guest_auth'] as bool? ?? _guestAuth;
      _guestPasswordSet = cfg['guest_pass_set'] as bool? ?? _guestPasswordSet;
      _guestUser.text = cfg['guest_user']?.toString() ?? '';
      _apPasswordSet = cfg['ap_pass_set'] as bool? ?? _apPasswordSet;
      _alertWebhookEn = cfg['alert_webhook_en'] as bool? ?? _alertWebhookEn;
      _alertWebhookUrl.text = cfg['alert_webhook_url']?.toString() ?? '';
      _alertWebhookTokenSet =
          cfg['alert_webhook_token_set'] as bool? ?? _alertWebhookTokenSet;
      _alertHttpsSupported =
          cfg['alert_https_supported'] as bool? ?? !widget.device.isEsp8266;
      _use24h = cfg['use_24h'] as bool? ?? _use24h;
      if (cfg['arduino_ota'] != null) {
        _arduinoOta = cfg['arduino_ota'] as bool? ?? false;
      }
    });
  }

  Future<void> _loadDiagnostics() async {
    setState(() => _loadingDiag = true);
    final diag = await widget.manager.fetchDeviceDiagnostics(widget.device.id);
    if (mounted) {
      setState(() {
        _diag = diag;
        _loadingDiag = false;
      });
    }
  }

  Future<void> _loadLogs() async {
    setState(() => _loadingLogs = true);
    final logs = await widget.manager.fetchDeviceLogs(widget.device.id);
    if (mounted) {
      setState(() {
        _logs = logs.reversed.toList();
        _loadingLogs = false;
      });
    }
  }

  Future<void> _clearLogs() async {
    final ok = await widget.manager.clearDeviceLogs(widget.device.id);
    if (!mounted) return;
    if (ok) {
      setState(() => _logs.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Hardware event logs cleared'),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to clear event logs from controller'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: AppColors.cardBorder, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGlow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.handyman_outlined,
                      color: AppColors.primaryLight,
                      size: 22,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hardware Tools & Control Hub',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                '${widget.device.name} (${widget.device.ip})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (widget.device.isGuest) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                ),
                                child: const Text(
                                  'Guest Tier',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.primaryLight,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(
                  icon: Icon(Icons.health_and_safety_outlined, size: 18),
                  text: 'Diagnostics',
                ),
                Tab(icon: Icon(Icons.tune, size: 18), text: 'Hardware Tuning'),
                Tab(
                  icon: Icon(Icons.settings_suggest_outlined, size: 18),
                  text: 'Controller Settings',
                ),
                Tab(
                  icon: Icon(Icons.view_list_outlined, size: 18),
                  text: 'Event Logs',
                ),
                Tab(
                  icon: Icon(Icons.phonelink_setup, size: 18),
                  text: 'Maintenance',
                ),
              ],
            ),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildDiagnosticsTab(),
                  _buildHardwareTuningTab(),
                  _buildControllerSettingsTab(),
                  _buildLogsTab(),
                  _buildMaintenanceTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 1. Diagnostics Tab ---
  Widget _buildDiagnosticsTab() {
    if (_loadingDiag) {
      return Center(child: CircularProgressIndicator());
    }
    final d = _diag;
    if (d == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Could not fetch diagnostics from controller',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 12),
            ElevatedButton(onPressed: _loadDiagnostics, child: Text('Retry')),
          ],
        ),
      );
    }

    final freeKb = d.freeHeap ~/ 1024;
    final totalKb = d.totalHeap ~/ 1024;
    final usedFsKb = d.fsUsed ~/ 1024;
    final totalFsKb = (d.fsTotal ~/ 1024).clamp(1, 1000000);
    final fsPercent = (usedFsKb / totalFsKb).clamp(0.0, 1.0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // System Health Row
        Row(
          children: [
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.memory,
                          size: 16,
                          color: AppColors.primaryLight,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'RAM Memory',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      '$freeKb KB Free',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Total $totalKb KB • Min ${d.minHeap ~/ 1024} KB',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: GlassCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.speed, size: 16, color: AppColors.accent),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'CPU Frequency',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      '${d.cpuFreq} MHz',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accent,
                      ),
                    ),
                    Text(
                      '${d.chipModel} rev${d.chipRev}',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),

        // LittleFS Flash Storage Card
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_special_outlined,
                          size: 16,
                          color: AppColors.humCyan,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'LittleFS Storage Flash',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$usedFsKb KB / $totalFsKb KB',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: fsPercent,
                  minHeight: 8,
                  backgroundColor: AppColors.surfaceElevated,
                  color: AppColors.humCyan,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12),

        // Detailed Hardware Specs
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _specRow('System Uptime', d.uptime, Icons.schedule),
              _specRow('Reset Reason', d.resetReason, Icons.restart_alt),
              _specRow(
                'Firmware Version',
                'v${d.fwVersion} (${d.fwBuild})',
                Icons.verified_outlined,
              ),
              _specRow(
                'Flash Chip Size',
                '${d.flashSize ~/ (1024 * 1024)} MB',
                Icons.storage,
              ),
              _specRow('SDK Version', d.sdkVersion, Icons.code),
              _specRow('OTA Status', d.otaStatus, Icons.system_update_alt),
              _specRow('OTA Partition', '${d.otaPartition} (${d.otaState})', Icons.layers_outlined),
            ],
          ),
        ),
      ],
    );
  }

  Widget _specRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 3,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestRestrictedBanner(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHwDisabledNotice(String message) {
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.developer_board_off, color: AppColors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.warning,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigErrorBanner() {
    if (!_configLoadFailed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppColors.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Could not load live settings from ${widget.device.name}. Showing cached/default values.',
              style: const TextStyle(color: AppColors.danger, fontSize: 11.5),
            ),
          ),
          TextButton(
            onPressed: _isLoadingConfig ? null : _loadDeviceConfig,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // --- 2. Hardware Tuning Tab ---
  Widget _buildHardwareTuningTab() {
    final isGuest = widget.device.isGuest;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildConfigErrorBanner(),
        if (isGuest)
          _buildGuestRestrictedBanner('Hardware Tuning & GPIO profile editing is restricted to Administrators. Guest accounts have read-only monitoring access (buzzer mute remains available).'),
        // Hardware & GPIO Template Engine Card
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.developer_board, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hardware Profile & GPIO Engine',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'Tasmota-style dynamic pin mapping, active relays (0-8) & switches',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('Configure Hardware & GPIOs'),
                  onPressed: isGuest
                      ? null
                      : () => HardwareConfigSheet.show(
                            context,
                            widget.device,
                            widget.manager,
                          ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Buzzer Controls
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.volume_up_outlined,
                    color: AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Active Hardware Buzzer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
              if (!_buzzerHwAllowed)
                _buildHwDisabledNotice(
                  'Alarm Buzzer is disabled or GPIO pin unassigned in Hardware Profile.',
                ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.music_note, size: 16),
                      label: const Text('Test Beep'),
                      onPressed: (isGuest || !_buzzerHwAllowed)
                          ? null
                          : () async {
                              final ok = await widget.manager.controlBuzzer(
                                widget.device.id,
                                action: 'test',
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Buzzer test beep triggered'
                                        : 'Failed to trigger buzzer test',
                                  ),
                                  backgroundColor: ok
                                      ? AppColors.success
                                      : AppColors.danger,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.volume_off, size: 16),
                      label: const Text('Mute 5 Min'),
                      onPressed: !_buzzerHwAllowed
                          ? null
                          : () async {
                              final ok = await widget.manager.controlBuzzer(
                                widget.device.id,
                                action: 'mute',
                              );
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Buzzer muted for 5 minutes'
                                        : 'Failed to mute buzzer',
                                  ),
                                  backgroundColor: ok
                                      ? AppColors.success
                                      : AppColors.danger,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 14),

        // LCD Display Controls
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tv_outlined, color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'LCD 20x4 / 16x2 Display',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
              if (!_lcdHwAllowed)
                _buildHwDisabledNotice(
                  'I2C LCD Display is disabled or pins unassigned in Hardware Profile.',
                ),
              SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'LCD Backlight',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                value: _lcdBacklight,
                activeThumbColor: AppColors.primary,
                onChanged: (isGuest || !_lcdHwAllowed)
                    ? null
                    : (v) async {
                        setState(() => _lcdBacklight = v);
                        final ok = await widget.manager.saveLcdSettings(
                          widget.device.id,
                          backlight: v,
                        );
                        if (!mounted) return;
                        if (!ok) {
                          setState(() => _lcdBacklight = !v);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? (v ? 'LCD Backlight enabled' : 'LCD Backlight turned off')
                                  : 'Failed to update LCD backlight',
                            ),
                            backgroundColor: ok ? AppColors.success : AppColors.danger,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Display Content Enabled',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                value: _lcdEnabled,
                activeThumbColor: AppColors.primary,
                onChanged: (isGuest || !_lcdHwAllowed)
                    ? null
                    : (v) async {
                        setState(() => _lcdEnabled = v);
                        final ok = await widget.manager.saveLcdSettings(widget.device.id, enabled: v);
                        if (!mounted) return;
                        if (!ok) {
                          setState(() => _lcdEnabled = !v);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? (v ? 'LCD display output enabled' : 'LCD display output turned off')
                                  : 'Failed to update LCD display status',
                            ),
                            backgroundColor: ok ? AppColors.success : AppColors.danger,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
              ),
            ],
          ),
        ),
        SizedBox(height: 14),

        // Sensor Calibration
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.tune, color: AppColors.tempAmber, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Sensor Calibration & Thresholds',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14),

              if (_climateSlotCount > 1) ...[
                DropdownButtonFormField<int>(
                  key: ValueKey('cal_climate_$_selectedClimateIdx'),
                  isExpanded: true,
                  initialValue: _selectedClimateIdx.clamp(0, _climateSlotCount - 1),
                  decoration: const InputDecoration(
                    labelText: 'Climate Sensor Instance',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: List.generate(
                    _climateSlotCount,
                    (i) => DropdownMenuItem(value: i, child: Text(_climateSlotName(i))),
                  ),
                  onChanged: isGuest
                      ? null
                      : (v) {
                          if (v != null) setState(() => _applyClimateCalIndex(v));
                        },
                ),
                const SizedBox(height: 12),
              ],

              // Temp Offset
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Temperature Offset',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${_tempOffset >= 0 ? "+" : ""}${_tempOffset.toStringAsFixed(1)} °C',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: _tempOffset.clamp(-5.0, 5.0),
                min: -5.0,
                max: 5.0,
                divisions: 20,
                activeColor: AppColors.tempAmber,
                onChanged: isGuest ? null : (v) => setState(() => _tempOffset = v),
              ),

              // Humidity Offset (only shown for climate sensors that report humidity)
              if (_selectedClimateHasHum) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Humidity Offset',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${_humOffset >= 0 ? "+" : ""}${_humOffset.toStringAsFixed(0)} %',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Slider(
                  value: _humOffset.clamp(-10.0, 10.0),
                  min: -10.0,
                  max: 10.0,
                  divisions: 20,
                  activeColor: AppColors.humCyan,
                  onChanged: isGuest ? null : (v) => setState(() => _humOffset = v),
                ),
              ],

              if (_mq2SlotCount > 1) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: ValueKey('cal_mq2_$_selectedMq2Idx'),
                  isExpanded: true,
                  initialValue: _selectedMq2Idx.clamp(0, _mq2SlotCount - 1),
                  decoration: const InputDecoration(
                    labelText: 'Gas / Air Quality Sensor Instance',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: List.generate(
                    _mq2SlotCount,
                    (i) => DropdownMenuItem(value: i, child: Text(_mq2SlotName(i))),
                  ),
                  onChanged: isGuest
                      ? null
                      : (v) {
                          if (v != null) setState(() => _applyMq2CalIndex(v));
                        },
                ),
                const SizedBox(height: 10),
              ],

              if (!_mq2HwAllowed)
                _buildHwDisabledNotice(
                  _selectedMq2Type == 1
                      ? 'SGP40 Air Quality Sensor is disabled or I2C pins unassigned in Hardware Profile.'
                      : '$_selectedMq2ShortName Gas Sensor is disabled or pins unassigned in Hardware Profile.',
                ),

              // Gas Threshold
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '${_selectedMq2Type == 1 ? "SGP40 VOC" : "$_selectedMq2ShortName Gas"} Alarm Threshold',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$_mq2Threshold ${_selectedMq2Type == 1 ? "VOC" : "ADC"}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _mq2Threshold.toDouble().clamp(10.0, _gasMax.toDouble()),
                min: 10.0,
                max: _gasMax.toDouble(),
                divisions: _selectedMq2Type == 1
                    ? 49
                    : (widget.device.isEsp8266 ? 50 : 80),
                activeColor: AppColors.danger,
                onChanged: (isGuest || !_mq2HwAllowed)
                    ? null
                    : (v) => setState(() => _mq2Threshold = v.toInt()),
              ),
              SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: _isCalibratingCleanAir
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.accent,
                              ),
                            )
                          : const Icon(Icons.air_rounded, size: 16),
                      label: Text(
                        _isCalibratingCleanAir
                            ? 'Calibrating...'
                            : 'Calibrate Clean Air',
                      ),
                      onPressed: (_isCalibratingCleanAir || isGuest || !_mq2HwAllowed)
                          ? null
                          : () async {
                              setState(() => _isCalibratingCleanAir = true);
                              final ok = await widget.manager.calibrateSensors(
                                widget.device.id,
                                sensorIndex: _selectedMq2Idx,
                                calibrateMq2: true,
                              );
                              if (mounted) {
                                setState(() => _isCalibratingCleanAir = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? (_selectedMq2Type == 1
                                                ? 'Clean air VOC 100 baseline calibrated successfully!'
                                                : '$_selectedMq2ShortName Clean Air baseline calibrated successfully!')
                                          : 'Failed to calibrate $_selectedMq2ShortName sensor baseline',
                                    ),
                                    backgroundColor: ok
                                        ? AppColors.success
                                        : AppColors.danger,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isSavingCalibration
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        _isSavingCalibration
                            ? 'Saving...'
                            : 'Save Calibration',
                      ),
                      onPressed: (_isSavingCalibration || isGuest)
                          ? null
                          : () async {
                              setState(() => _isSavingCalibration = true);
                              bool ok;
                              if (_selectedClimateIdx == _selectedMq2Idx || !_mq2HwAllowed) {
                                ok = await widget.manager.calibrateSensors(
                                  widget.device.id,
                                  sensorIndex: _selectedClimateIdx,
                                  tempOffset: _tempOffset,
                                  humOffset: _humOffset,
                                  mq2Threshold: _mq2HwAllowed ? _mq2Threshold : null,
                                );
                              } else {
                                final okCli = await widget.manager.calibrateSensors(
                                  widget.device.id,
                                  sensorIndex: _selectedClimateIdx,
                                  tempOffset: _tempOffset,
                                  humOffset: _humOffset,
                                );
                                final okMq = await widget.manager.calibrateSensors(
                                  widget.device.id,
                                  sensorIndex: _selectedMq2Idx,
                                  mq2Threshold: _mq2Threshold,
                                );
                                ok = okCli && okMq;
                              }
                              if (ok) {
                                if (_selectedClimateIdx < _climateCals.length) {
                                  _climateCals[_selectedClimateIdx]['temp_offset'] = _tempOffset;
                                  _climateCals[_selectedClimateIdx]['hum_offset'] = _humOffset;
                                }
                                if (_mq2HwAllowed && _selectedMq2Idx < _mq2Cals.length) {
                                  _mq2Cals[_selectedMq2Idx]['threshold'] = _mq2Threshold;
                                }
                              }
                              if (!mounted) return;
                              setState(() => _isSavingCalibration = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Sensor calibration saved to flash memory!'
                                        : 'Failed to save sensor calibration',
                                  ),
                                  backgroundColor: ok
                                      ? AppColors.success
                                      : AppColors.danger,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showSaveResult(bool ok, String success, String failure) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(ok ? success : failure)),
          ],
        ),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _settingsCard(String title, IconData icon, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primaryLight, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
        ),
      ),
    );
  }

  InputDecoration _field(String label, {String? helper, String? hint}) => InputDecoration(
    labelText: label,
    helperText: helper,
    hintText: hint,
    border: const OutlineInputBorder(),
  );

  Widget _buildControllerSettingsTab() {
    final isGuest = widget.device.isGuest;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildConfigErrorBanner(),
        if (isGuest)
          _buildGuestRestrictedBanner('Controller Settings (Wi-Fi, MQTT, Security) are restricted to Administrators. Guest accounts cannot modify network credentials.'),
        _settingsCard('Wi-Fi connection', Icons.wifi_outlined, [
          Text(
            'Credentials are stored on the ESP. Saving may disconnect this controller while it joins the new network.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wifiSsid,
            enabled: !isGuest,
            decoration: _field('Network name (SSID)'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _wifiPassword,
            enabled: !isGuest,
            obscureText: true,
            decoration: _field('Network password'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isSavingWifi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.wifi_protected_setup_rounded, size: 18),
              label: Text(_isSavingWifi ? 'Applying & Reconnecting...' : 'Save & Connect'),
              onPressed: (_isSavingWifi || isGuest)
                  ? null
                  : () async {
                      final ssid = _wifiSsid.text.trim();
                      if (ssid.isEmpty) {
                        _showSaveResult(false, '', 'Enter a Wi-Fi network name.');
                        return;
                      }
                      setState(() => _isSavingWifi = true);
                      final ok = await widget.manager.saveDeviceWifi(
                        widget.device.id,
                        ssid: ssid,
                        password: _wifiPassword.text,
                      );
                      if (mounted) {
                        setState(() => _isSavingWifi = false);
                        _showSaveResult(
                          ok,
                          'Wi-Fi saved. Controller is reconnecting.',
                          'Could not save Wi-Fi settings.',
                        );
                      }
                    },
            ),
          ),
        ]),
        _settingsCard('MQTT broker', Icons.hub_outlined, [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable MQTT'),
            value: _mqttEnabled,
            onChanged: isGuest ? null : (value) => setState(() => _mqttEnabled = value),
          ),
          TextField(
            controller: _mqttBroker,
            enabled: !isGuest,
            decoration: _field('Broker host or IP'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mqttPort,
                  enabled: !isGuest,
                  keyboardType: TextInputType.number,
                  decoration: _field('Port'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _mqttPrefix,
                  enabled: !isGuest,
                  decoration: _field('Topic prefix', hint: 'Auto: smarthome-XXXX'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _mqttClientId,
            enabled: !isGuest,
            decoration: _field('Client ID'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mqttUser,
                  enabled: !isGuest,
                  decoration: _field('Username'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _mqttPassword,
                  enabled: !isGuest,
                  obscureText: true,
                  decoration: _field('Password', helper: 'Enter to set/change'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isSavingMqtt
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_isSavingMqtt ? 'Saving to Controller...' : 'Save MQTT Settings'),
              onPressed: (_isSavingMqtt || isGuest)
                  ? null
                  : () async {
                      final port = int.tryParse(_mqttPort.text.trim());
                      if (_mqttEnabled &&
                          (_mqttBroker.text.trim().isEmpty ||
                              port == null ||
                              port < 1 ||
                              port > 65535)) {
                        _showSaveResult(
                          false,
                          '',
                          'Enter a broker host and valid port (1–65535).',
                        );
                        return;
                      }
                      setState(() => _isSavingMqtt = true);
                      final ok = await widget.manager.saveDeviceMqtt(widget.device.id, {
                        'enabled': _mqttEnabled,
                        'broker': _mqttBroker.text.trim(),
                        'port': port ?? 1883,
                        'prefix': _mqttPrefix.text.trim(),
                        'client_id': _mqttClientId.text.trim(),
                        'user': _mqttUser.text.trim(),
                        if (_mqttPassword.text.isNotEmpty) 'pass': _mqttPassword.text,
                      });
                      if (mounted) {
                        setState(() => _isSavingMqtt = false);
                        _showSaveResult(
                          ok,
                          'MQTT settings saved to controller.',
                          'Could not save MQTT settings.',
                        );
                      }
                    },
            ),
          ),
        ]),
        _settingsCard('Device, clock & access', Icons.devices_other_outlined, [
          Text(
            'MAC: ${widget.device.mac.isEmpty ? 'Unavailable' : widget.device.mac}',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _deviceName,
            enabled: !isGuest,
            maxLength: 20,
            decoration: _field('Device name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hostname,
            enabled: !isGuest,
            maxLength: 24,
            decoration: _field('mDNS hostname'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _timezone,
            enabled: !isGuest,
            decoration: _field('POSIX timezone', helper: 'Example: IST-5:30'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('24-hour time'),
            value: _use24h,
            onChanged: isGuest ? null : (value) => setState(() => _use24h = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Web password protection'),
            value: _webAuth,
            onChanged: isGuest ? null : (value) => setState(() => _webAuth = value),
          ),
          if (_webAuth) ...[
            TextField(
              controller: _webUser,
              enabled: !isGuest,
              maxLength: 20,
              decoration: _field('Web username'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _webPassword,
              enabled: !isGuest,
              obscureText: true,
              maxLength: 20,
              decoration: _field(
                'New web password',
                helper: 'Leave blank to keep the current password',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Guest read-only access'),
              subtitle: const Text(
                'Allow a restricted monitoring account',
                style: TextStyle(fontSize: 11.5),
              ),
              value: _guestAuth,
              onChanged: isGuest
                  ? null
                  : (value) => setState(() => _guestAuth = value),
            ),
            if (_guestAuth) ...[
              TextField(
                controller: _guestUser,
                enabled: !isGuest,
                maxLength: 20,
                decoration: _field('Guest username', helper: 'Default: guest'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _guestPassword,
                enabled: !isGuest && !_guestPasswordClear,
                obscureText: true,
                maxLength: 20,
                decoration: _field(
                  'New guest password',
                  helper: _guestPasswordSet
                      ? 'Leave blank to keep current password'
                      : 'Optional (blank = passwordless guest username)',
                ),
              ),
              if (_guestPasswordSet)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Clear stored guest password'),
                  value: _guestPasswordClear,
                  onChanged: isGuest
                      ? null
                      : (v) => setState(() {
                            _guestPasswordClear = v ?? false;
                            if (_guestPasswordClear) _guestPassword.clear();
                          }),
                ),
            ],
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _apPassword,
            enabled: !isGuest && !_apPasswordClear,
            obscureText: true,
            maxLength: 63,
            decoration: _field(
              'Custom SoftAP hotspot password',
              helper: _apPasswordSet
                  ? 'Custom AP password saved (8-63 chars; blank keeps current)'
                  : 'Optional (8-63 chars; blank = Open setup hotspot)',
            ),
          ),
          if (_apPasswordSet)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Clear custom SoftAP password (revert to default)'),
              value: _apPasswordClear,
              onChanged: isGuest
                  ? null
                  : (v) => setState(() {
                        _apPasswordClear = v ?? false;
                        if (_apPasswordClear) _apPassword.clear();
                      }),
            ),
          const SizedBox(height: 12),
          Divider(color: AppColors.cardBorder.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Optional Remote Push Alerts (4G/5G)',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Push emergency Gas/Temp/Fault alerts via Webhook or ntfy when away from home Wi-Fi',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
            value: _alertWebhookEn,
            onChanged: isGuest
                ? null
                : (v) => setState(() => _alertWebhookEn = v),
          ),
          if (_alertWebhookEn) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _alertWebhookUrl,
              enabled: !isGuest,
              keyboardType: TextInputType.url,
              maxLength: 192,
              decoration: _field(
                'Webhook / ntfy URL',
                helper: _alertHttpsSupported
                    ? 'Supports https:// (e.g. ntfy.sh) or http:// webhook URLs'
                    : 'ESP8266 supports http:// local/relay webhooks only (HTTPS requires ESP32)',
              ).copyWith(hintText: 'https://ntfy.sh/my-smarthome-alarm'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _alertWebhookToken,
              enabled: !isGuest && !_alertWebhookTokenClear,
              obscureText: true,
              maxLength: 96,
              decoration: _field(
                'Bearer token (optional)',
                helper: _alertWebhookTokenSet
                    ? 'Token saved (leave blank to keep current)'
                    : 'Optional authorization token for ntfy/webhook',
              ),
            ),
            if (_alertWebhookTokenSet)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Clear saved Bearer token'),
                value: _alertWebhookTokenClear,
                onChanged: isGuest
                    ? null
                    : (v) => setState(() {
                          _alertWebhookTokenClear = v ?? false;
                          if (_alertWebhookTokenClear) {
                            _alertWebhookToken.clear();
                          }
                        }),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                icon: _isTestingRemoteAlert
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined, size: 16),
                label: Text(
                  _isTestingRemoteAlert
                      ? 'Sending Test Push...'
                      : 'Test Remote Alert',
                ),
                onPressed: (_isTestingRemoteAlert || isGuest)
                    ? null
                    : () async {
                        setState(() => _isTestingRemoteAlert = true);
                        final err = await widget.manager.testRemoteAlert(
                          widget.device.id,
                        );
                        if (!mounted) return;
                        setState(() => _isTestingRemoteAlert = false);
                        _showSaveResult(
                          err == null,
                          'Test remote push alert dispatched.',
                          err ?? 'Remote test alert failed.',
                        );
                      },
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isSavingDevice
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded, size: 18),
              label: Text(_isSavingDevice ? 'Saving Settings...' : 'Save Device Settings'),
              onPressed: (_isSavingDevice || isGuest)
                  ? null
                  : () async {
                      if (_webAuth && _webUser.text.trim().isEmpty) {
                        _showSaveResult(
                          false,
                          '',
                          'Enter a web username before enabling password protection.',
                        );
                        return;
                      }
                      if (_webAuth && !_webPasswordSet && _webPassword.text.isEmpty) {
                        _showSaveResult(
                          false,
                          '',
                          'Set a web password before enabling password protection.',
                        );
                        return;
                      }
                      if (_webAuth &&
                          _guestAuth &&
                          _guestUser.text.trim().isEmpty) {
                        _showSaveResult(
                          false,
                          '',
                          'Enter a guest username before enabling guest access.',
                        );
                        return;
                      }
                      if (_webAuth &&
                          _guestAuth &&
                          _guestUser.text.trim() ==
                              (_webUser.text.trim().isEmpty
                                  ? 'admin'
                                  : _webUser.text.trim())) {
                        _showSaveResult(
                          false,
                          '',
                          'Admin and Guest usernames must be different.',
                        );
                        return;
                      }
                      if (!_apPasswordClear &&
                          _apPassword.text.isNotEmpty &&
                          (_apPassword.text.length < 8 ||
                              _apPassword.text.length > 63)) {
                        _showSaveResult(
                          false,
                          '',
                          'SoftAP password must be 8-63 characters.',
                        );
                        return;
                      }
                      final whUrl = _alertWebhookUrl.text.trim();
                      if (whUrl.isNotEmpty &&
                          !whUrl.startsWith('http://') &&
                          !whUrl.startsWith('https://')) {
                        _showSaveResult(
                          false,
                          '',
                          'Webhook URL must start with http:// or https://.',
                        );
                        return;
                      }
                      if (!_alertHttpsSupported && whUrl.startsWith('https://')) {
                        _showSaveResult(
                          false,
                          '',
                          'ESP8266 only supports http:// webhooks (HTTPS requires ESP32).',
                        );
                        return;
                      }
                      if (_alertWebhookEn && whUrl.isEmpty) {
                        _showSaveResult(
                          false,
                          '',
                          'Enter a Webhook / ntfy URL before enabling remote alerts.',
                        );
                        return;
                      }
                      setState(() => _isSavingDevice = true);
                      final ok = await widget.manager
                          .saveDeviceConfig(widget.device.id, {
                            'device_name': _deviceName.text.trim(),
                            'hostname': _hostname.text.trim(),
                            'timezone': _timezone.text.trim(),
                            'use_24h': _use24h,
                            'web_auth': _webAuth,
                            if (_webAuth) 'web_user': _webUser.text.trim(),
                            if (_webPassword.text.isNotEmpty)
                              'web_pass': _webPassword.text,
                            if (_webAuth) 'guest_auth': _guestAuth,
                            if (_webAuth && _guestAuth)
                              'guest_user': _guestUser.text.trim(),
                            if (_webAuth &&
                                _guestAuth &&
                                _guestPassword.text.isNotEmpty)
                              'guest_pass': _guestPassword.text,
                            if (_webAuth && _guestPasswordClear)
                              'guest_pass_clear': true,
                            if (!_apPasswordClear &&
                                _apPassword.text.isNotEmpty)
                              'ap_pass': _apPassword.text,
                            if (_apPasswordClear) 'ap_pass_clear': true,
                            'alert_webhook_en': _alertWebhookEn,
                            'alert_webhook_url': whUrl,
                            if (!_alertWebhookTokenClear &&
                                _alertWebhookToken.text.isNotEmpty)
                              'alert_webhook_token': _alertWebhookToken.text,
                            if (_alertWebhookTokenClear)
                              'alert_webhook_token_clear': true,
                          });
                      if (mounted) {
                        setState(() {
                          _isSavingDevice = false;
                          if (ok && _webPassword.text.isNotEmpty) {
                            _webPasswordSet = true;
                            _webPassword.clear();
                          }
                          if (ok && _guestPassword.text.isNotEmpty) {
                            _guestPasswordSet = true;
                            _guestPassword.clear();
                          }
                          if (ok && _guestPasswordClear) {
                            _guestPasswordSet = false;
                            _guestPasswordClear = false;
                          }
                          if (ok &&
                              !_apPasswordClear &&
                              _apPassword.text.isNotEmpty) {
                            _apPasswordSet = true;
                            _apPassword.clear();
                          }
                          if (ok && _apPasswordClear) {
                            _apPasswordSet = false;
                            _apPasswordClear = false;
                          }
                          if (ok &&
                              !_alertWebhookTokenClear &&
                              _alertWebhookToken.text.isNotEmpty) {
                            _alertWebhookTokenSet = true;
                            _alertWebhookToken.clear();
                          }
                          if (ok && _alertWebhookTokenClear) {
                            _alertWebhookTokenSet = false;
                            _alertWebhookTokenClear = false;
                          }
                        });
                        _showSaveResult(
                          ok,
                          'Device settings saved to controller.',
                          'Could not save device settings.',
                        );
                      }
                    },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded, size: 18, color: AppColors.danger),
              label: const Text('Log Out / Switch Account', style: TextStyle(color: AppColors.danger)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text('Log Out Controller'),
                    content: Text(
                      'Log out of ${widget.device.name} (${widget.device.ip})?\n\nStored credentials will be cleared and the controller will be locked so you can sign in with another account.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Log Out', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  Navigator.pop(context);
                  await widget.manager.logoutDevice(widget.device.id);
                }
              },
            ),
          ),
        ]),
        _settingsCard('LCD display', Icons.tv_outlined, [
          if (!_lcdHwAllowed)
            _buildHwDisabledNotice(
              'I2C LCD Display is disabled or pins unassigned in Hardware Profile.',
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('LCD enabled'),
            value: _lcdEnabled,
            onChanged: (isGuest || !_lcdHwAllowed)
                ? null
                : (value) => setState(() => _lcdEnabled = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Backlight enabled'),
            value: _lcdBacklight,
            onChanged: (isGuest || !_lcdHwAllowed)
                ? null
                : (value) => setState(() => _lcdBacklight = value),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('lcd_mode_${_lcdDisplayMode}_${isGuest}_$_lcdHwAllowed'),
            initialValue:
                (_lcdDisplayMode == 'dht_relay' ||
                        _lcdDisplayMode == 'rotate' ||
                        _lcdDisplayMode == 'custom')
                    ? _lcdDisplayMode
                    : 'rotate',
            isExpanded: true,
            decoration: _field('Display mode'),
            items: const [
              DropdownMenuItem(
                value: 'rotate',
                child: Text('Auto rotate (custom pages)', overflow: TextOverflow.ellipsis),
              ),
              DropdownMenuItem(
                value: 'custom',
                child: Text('Custom per-row layout', overflow: TextOverflow.ellipsis),
              ),
              DropdownMenuItem(
                value: 'dht_relay',
                child: Text('DHT + relays (classic)', overflow: TextOverflow.ellipsis),
              ),
            ],
            onChanged: (isGuest || !_lcdHwAllowed)
                ? null
                : (value) =>
                    setState(() => _lcdDisplayMode = value ?? _lcdDisplayMode),
          ),
          if (_lcdDisplayMode == 'rotate') ...[
            const SizedBox(height: 12),
            const Text(
              'Active Pages & Display Order (Top Shows First)',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < _lcdPages.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _lcdPages[i].enabled,
                      onChanged: (isGuest || !_lcdHwAllowed)
                          ? null
                          : (val) => setState(
                                () => _lcdPages[i].enabled = val ?? false,
                              ),
                    ),
                    Expanded(
                      child: Text(
                        _lcdPages[i].available
                            ? '${i + 1}. ${_lcdPages[i].label}'
                            : '${i + 1}. ${_lcdPages[i].label} (Off in HW)',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _lcdPages[i].available
                              ? null
                              : Colors.white54,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                      tooltip: 'Move up',
                      onPressed: (isGuest || !_lcdHwAllowed || i == 0)
                          ? null
                          : () => setState(() {
                                final item = _lcdPages.removeAt(i);
                                _lcdPages.insert(i - 1, item);
                              }),
                    ),
                    IconButton(
                      icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                      tooltip: 'Move down',
                      onPressed: (isGuest ||
                              !_lcdHwAllowed ||
                              i == _lcdPages.length - 1)
                          ? null
                          : () => setState(() {
                                final item = _lcdPages.removeAt(i);
                                _lcdPages.insert(i + 1, item);
                              }),
                    ),
                  ],
                ),
              ),
          ],
          if (_lcdDisplayMode == 'custom') ...[
            const SizedBox(height: 12),
            Text(
              'Pinned Row Layout (${_lcdCols}x$_lcdRows — Line 1 Shows First)',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (var r = 0; r < _lcdRows; r++) ...[
              Builder(
                builder: (context) {
                  final cur = r < _lcdLines.length ? _lcdLines[r] : 'none';
                  final items = <DropdownMenuItem<String>>[
                    for (final w in _lcdWidgetCatalog)
                      DropdownMenuItem(value: w.id, child: Text(w.label)),
                  ];
                  if (!items.any((it) => it.value == cur)) {
                    items.add(
                      DropdownMenuItem(value: cur, child: Text('$cur (Saved)')),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('lcd_line_${r}_${cur}_${isGuest}_$_lcdHwAllowed'),
                            initialValue: cur,
                            isExpanded: true,
                            decoration: _field('Line ${r + 1}'),
                            items: items,
                            onChanged: (isGuest || !_lcdHwAllowed)
                                ? null
                                : (val) {
                                    if (val == null) return;
                                    setState(() => _lcdLines[r] = val);
                                  },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                          tooltip: 'Move line up',
                          onPressed: (isGuest || !_lcdHwAllowed || r == 0)
                              ? null
                              : () => setState(() {
                                    final tmp = _lcdLines[r];
                                    _lcdLines[r] = _lcdLines[r - 1];
                                    _lcdLines[r - 1] = tmp;
                                  }),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                          tooltip: 'Move line down',
                          onPressed: (isGuest || !_lcdHwAllowed || r == _lcdRows - 1)
                              ? null
                              : () => setState(() {
                                    final tmp = _lcdLines[r];
                                    _lcdLines[r] = _lcdLines[r + 1];
                                    _lcdLines[r + 1] = tmp;
                                  }),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
          const SizedBox(height: 10),
          Text('Page rotation: $_lcdRotation seconds'),
          Slider(
            value: _lcdRotation.toDouble().clamp(3.0, 30.0),
            min: 3,
            max: 30,
            divisions: 27,
            onChanged: (isGuest || !_lcdHwAllowed)
                ? null
                : (value) => setState(() => _lcdRotation = value.round()),
          ),
          Text('Backlight brightness: $_lcdBrightness%'),
          Slider(
            value: _lcdBrightness.toDouble().clamp(0.0, 100.0),
            min: 0,
            max: 100,
            divisions: 20,
            onChanged: (isGuest || !_lcdHwAllowed)
                ? null
                : (value) => setState(() => _lcdBrightness = value.round()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-dim schedule'),
            value: _autoDim,
            onChanged: (isGuest || !_lcdHwAllowed)
                ? null
                : (value) => setState(() => _autoDim = value),
          ),
          if (_autoDim) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dimStart,
                    enabled: !isGuest && _lcdHwAllowed,
                    decoration: _field('Dim start', helper: 'HH:MM'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _dimEnd,
                    enabled: !isGuest && _lcdHwAllowed,
                    decoration: _field('Dim end', helper: 'HH:MM'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Dimmed brightness: $_lcdDimBrightness%'),
            Slider(
              value: _lcdDimBrightness.toDouble().clamp(0.0, 100.0),
              min: 0,
              max: 100,
              divisions: 20,
              onChanged: (isGuest || !_lcdHwAllowed)
                  ? null
                  : (value) => setState(() => _lcdDimBrightness = value.round()),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isSavingLcd
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.tv_rounded, size: 18),
              label: Text(_isSavingLcd ? 'Saving LCD...' : 'Save LCD Settings'),
              onPressed: (_isSavingLcd || isGuest || !_lcdHwAllowed)
                  ? null
                  : () async {
                      final selectedPages = _lcdPages
                          .where((p) => p.enabled)
                          .map((p) => p.id)
                          .toList();
                      if (_lcdDisplayMode == 'rotate' && selectedPages.isEmpty) {
                        _showSaveResult(
                          false,
                          '',
                          'Select at least one page for Auto Rotate.',
                        );
                        return;
                      }
                      setState(() => _isSavingLcd = true);
                      final ok = await widget.manager.saveLcdSettings(
                        widget.device.id,
                        enabled: _lcdEnabled,
                        backlight: _lcdBacklight,
                        displayMode: _lcdDisplayMode,
                        rotation: _lcdRotation,
                        brightness: _lcdBrightness,
                        autoDim: _autoDim,
                        dimStart: _dimStart.text.trim(),
                        dimEnd: _dimEnd.text.trim(),
                        dimBrightness: _lcdDimBrightness,
                        pages: selectedPages.isNotEmpty ? selectedPages : null,
                        lines: _lcdLines.take(_lcdRows).toList(),
                      );
                      if (mounted) {
                        setState(() => _isSavingLcd = false);
                        _showSaveResult(
                          ok,
                          'LCD settings saved to controller.',
                          'Could not save LCD settings.',
                        );
                      }
                    },
            ),
          ),
        ]),
        _settingsCard('Buzzer & sensor safety', Icons.sensors_outlined, [
          if (!_buzzerHwAllowed)
            _buildHwDisabledNotice(
              'Alarm Buzzer is disabled or GPIO pin unassigned in Hardware Profile.',
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Buzzer enabled'),
            value: _buzzerEnabled,
            onChanged: (isGuest || !_buzzerHwAllowed)
                ? null
                : (value) => setState(() => _buzzerEnabled = value),
          ),
          Text('Buzzer volume: $_buzzerVolume'),
          Slider(
            value: _buzzerVolume.toDouble().clamp(0.0, 255.0),
            min: 0,
            max: 255,
            divisions: 51,
            onChanged: (isGuest || !_buzzerHwAllowed)
                ? null
                : (value) => setState(() => _buzzerVolume = value.round()),
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (isGuest || !_buzzerHwAllowed)
                      ? null
                      : () async {
                          final ok = await widget.manager.controlBuzzer(
                            widget.device.id,
                            action: 'test',
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Buzzer test beep triggered'
                                    : 'Failed to trigger buzzer test',
                              ),
                              backgroundColor: ok
                                  ? AppColors.success
                                  : AppColors.danger,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  child: const Text('Test buzzer'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: !_buzzerHwAllowed
                      ? null
                      : () async {
                          final ok = await widget.manager.controlBuzzer(
                            widget.device.id,
                            action: 'mute',
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Buzzer muted for 5 minutes'
                                    : 'Failed to mute buzzer',
                              ),
                              backgroundColor: ok
                                  ? AppColors.success
                                  : AppColors.danger,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                  child: const Text('Mute 5 min'),
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          if (_mq2SlotCount > 1) ...[
            DropdownButtonFormField<int>(
              key: ValueKey('settings_mq2_$_selectedMq2Idx'),
              isExpanded: true,
              initialValue: _selectedMq2Idx.clamp(0, _mq2SlotCount - 1),
              decoration: const InputDecoration(
                labelText: 'Gas / Air Quality Sensor Instance',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: List.generate(
                _mq2SlotCount,
                (i) => DropdownMenuItem(value: i, child: Text(_mq2SlotName(i))),
              ),
              onChanged: isGuest
                  ? null
                  : (v) {
                      if (v != null) setState(() => _applyMq2CalIndex(v));
                    },
            ),
            const SizedBox(height: 10),
          ],
          if (!_mq2HwAllowed)
            _buildHwDisabledNotice(
              _selectedMq2Type == 1
                  ? 'SGP40 Air Quality Sensor is disabled or I2C pins unassigned in Hardware Profile.'
                  : '$_selectedMq2ShortName Gas Sensor is disabled or pins unassigned in Hardware Profile.',
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _mq2SlotCount > 1
                  ? '${_selectedMq2Type == 1 ? "SGP40 air quality" : "$_selectedMq2ShortName gas"} sensor enabled (${_mq2SlotName(_selectedMq2Idx)})'
                  : '${_selectedMq2Type == 1 ? "SGP40 air quality" : "$_selectedMq2ShortName gas"} sensor enabled',
            ),
            value: _mq2Enabled,
            onChanged: (isGuest || !_mq2HwAllowed)
                ? null
                : (value) => setState(() => _mq2Enabled = value),
          ),
          Text(
            'Temperature alarm threshold: ${_tempAlarm.toStringAsFixed(1)}°C',
          ),
          Slider(
            value: _tempAlarm.clamp(10.0, 60.0),
            min: 10,
            max: 60,
            divisions: 100,
            onChanged: isGuest ? null : (value) => setState(() => _tempAlarm = value),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _isSavingBuzzer
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.security_rounded, size: 18),
              label: Text(_isSavingBuzzer ? 'Saving Safety...' : 'Save buzzer & sensor settings'),
              onPressed: (_isSavingBuzzer || isGuest)
                  ? null
                  : () async {
                      setState(() => _isSavingBuzzer = true);
                      final buzzerOk = !_buzzerHwAllowed
                          ? true
                          : await widget.manager.controlBuzzer(
                              widget.device.id,
                              enabled: _buzzerEnabled,
                              volume: _buzzerVolume,
                            );
                      final sensorOk = await widget.manager.calibrateSensors(
                        widget.device.id,
                        sensorIndex: _selectedMq2Idx,
                        tempAlarm: _tempAlarm,
                        mq2Enabled: _mq2HwAllowed ? _mq2Enabled : null,
                      );
                      if (sensorOk && _mq2HwAllowed && _selectedMq2Idx < _mq2Cals.length) {
                        _mq2Cals[_selectedMq2Idx]['enabled'] = _mq2Enabled;
                      }
                      if (mounted) {
                        setState(() => _isSavingBuzzer = false);
                        _showSaveResult(
                          buzzerOk && sensorOk,
                          'Buzzer and safety settings saved.',
                          'Could not save all buzzer/sensor settings.',
                        );
                      }
                    },
            ),
          ),
        ]),
      ],
    );
  }

  // --- 3. Event Logs Tab ---
  Widget _buildLogsTab() {
    final filtered = _logFilter == 'ALL'
        ? _logs
        : _logs.where((l) => l.levelLabel == _logFilter).toList();

    return Column(
      children: [
        // Controls Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: ['ALL', 'INFO', 'WARN', 'ERROR'].map((lvl) {
                    final isSel = _logFilter == lvl;
                    return ChoiceChip(
                      label: Text(
                        lvl,
                        style: TextStyle(
                          fontSize: 11,
                          color: isSel ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                      selected: isSel,
                      selectedColor: AppColors.primary,
                      onSelected: (_) => setState(() => _logFilter = lvl),
                    );
                  }).toList(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Refresh Logs',
                onPressed: _loadLogs,
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: widget.device.isGuest
                      ? AppColors.textMuted
                      : AppColors.danger,
                ),
                tooltip: widget.device.isGuest
                    ? 'Clear Logs (Admin only)'
                    : 'Clear Logs',
                onPressed: widget.device.isGuest ? null : _clearLogs,
              ),
            ],
          ),
        ),

        // Logs List
        Expanded(
          child: _loadingLogs
              ? Center(child: CircularProgressIndicator())
              : filtered.isEmpty
              ? Center(
                  child: Text(
                    'No log entries found on controller flash ring buffer.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final l = filtered[i];
                    Color badgeColor = AppColors.accent;
                    if (l.level == 1) badgeColor = AppColors.warning;
                    if (l.level == 2) badgeColor = AppColors.danger;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.cardBorder.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l.levelLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: badgeColor,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        l.source,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      l.formattedTime,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 2),
                                Text(
                                  l.message,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- 4. Maintenance Tab ---
  Widget _buildMaintenanceTab() {
    final isGuest = widget.device.isGuest;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isGuest)
          _buildGuestRestrictedBanner('System Maintenance (Backup, Restore, Reboot, Factory Reset, and OTA updates) is restricted to Administrators.'),
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Backup & Diagnostics Export',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text(
                'Export full LittleFS system configuration (relays, rules, schedules, calibration) in standard JSON format.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Include Wi-Fi, MQTT & Webhook passwords (plaintext)',
                  style: TextStyle(fontSize: 12),
                ),
                value: _backupIncludeSecrets,
                onChanged: isGuest
                    ? null
                    : (v) => setState(() => _backupIncludeSecrets = v ?? false),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isExportingBackup
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.download_rounded),
                  label: Text(_isExportingBackup ? 'Exporting Backup...' : 'Export Config JSON Backup'),
                  onPressed: (isGuest || _isExportingBackup)
                      ? null
                      : () async {
                          setState(() => _isExportingBackup = true);
                          final jsonStr = await widget.manager.exportBackup(
                            widget.device.id,
                            sanitize: !_backupIncludeSecrets,
                          );
                          if (!mounted) return;
                          setState(() => _isExportingBackup = false);
                          if (jsonStr == null || jsonStr.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to download backup from controller. Check connection.'),
                                backgroundColor: AppColors.danger,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }
                          showDialog(
                            context: context,
                            builder: (ctx) => _ExportConfigDialog(
                              device: widget.device,
                              jsonStr: jsonStr,
                            ),
                          );
                        },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.6),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: const Text('Restore Config Backup'),
                  onPressed: isGuest
                      ? null
                      : () {
                          showDialog(
                            context: context,
                            builder: (ctx) => _RestoreConfigDialog(
                              device: widget.device,
                              manager: widget.manager,
                            ),
                          );
                        },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Network Services & Port Exposure',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Control network flashing ports. Keep ArduinoOTA disabled unless flashing via Arduino IDE.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'ArduinoOTA (Port 3232)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  _arduinoOta
                      ? 'Port 3232 is OPEN for network flashing.'
                      : 'Port 3232 is CLOSED (Recommended). Web/App HTTP OTA active.',
                  style: TextStyle(
                    fontSize: 12,
                    color: _arduinoOta
                        ? AppColors.warning
                        : AppColors.textMuted,
                  ),
                ),
                value: _arduinoOta,
                activeThumbColor: AppColors.primary,
                onChanged: isGuest
                    ? null
                    : (val) async {
                        setState(() => _arduinoOta = val);
                        final ok = await widget.manager.saveDeviceConfig(
                          widget.device.id,
                          {'arduino_ota': val},
                        );
                        if (!mounted) return;
                        if (!ok) {
                          setState(() => _arduinoOta = !val);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? (val
                                        ? 'ArduinoOTA (port 3232) enabled'
                                        : 'ArduinoOTA (port 3232) disabled')
                                  : 'Failed to update OTA settings',
                            ),
                            backgroundColor: ok
                                ? AppColors.success
                                : AppColors.danger,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        GlassCard(
          padding: const EdgeInsets.all(16),
          borderColor: AppColors.danger.withValues(alpha: 0.4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Danger Zone',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Actions that reboot or completely wipe the controller hardware configuration.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: BorderSide(
                          color: isGuest
                              ? AppColors.cardBorder
                              : AppColors.warning,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.restart_alt),
                      label: Text('Reboot ${widget.device.isEsp8266 ? "ESP8266" : "ESP32"}'),
                      onPressed: isGuest
                          ? null
                          : () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppColors.surface,
                                  title: Row(
                                    children: [
                                      const Icon(Icons.restart_alt, color: AppColors.warning),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Reboot Controller?',
                                        style: TextStyle(color: AppColors.textPrimary),
                                      ),
                                    ],
                                  ),
                                  content: Text(
                                    'Are you sure you want to reboot ${widget.device.name}? It will take ~5-10 seconds to reconnect.',
                                    style: TextStyle(color: AppColors.textSecondary),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.warning,
                                        foregroundColor: Colors.black,
                                      ),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Reboot Now', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                final messenger = ScaffoldMessenger.of(context);
                                final ok = await widget.manager.rebootDevice(widget.device.id);
                                if (!mounted) return;
                                Navigator.pop(context);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Reboot signal delivered to ${widget.device.name}!'
                                          : 'Failed to deliver reboot command',
                                    ),
                                    backgroundColor: ok ? AppColors.success : AppColors.danger,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.warning_amber),
                      label: const Text('Factory Reset'),
                      onPressed: isGuest
                          ? null
                          : () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: AppColors.surface,
                                  title: Text(
                                    'Confirm Factory Reset',
                                    style: TextStyle(color: AppColors.danger),
                                  ),
                                  content: Text(
                                    'This will wipe all LittleFS configs, Wi-Fi credentials, and automations. The controller will reboot into AP setup mode.',
                                    style: TextStyle(color: AppColors.textSecondary),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                                    ),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.danger,
                                        foregroundColor: Colors.white,
                                      ),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Wipe & Reset'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true && mounted) {
                                final messenger = ScaffoldMessenger.of(context);
                                final ok = await widget.manager.factoryReset(widget.device.id);
                                if (!mounted) return;
                                Navigator.pop(context);
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ok
                                          ? 'Factory reset initiated. Device wiping and rebooting...'
                                          : 'Failed to send factory reset command',
                                    ),
                                    backgroundColor: ok ? AppColors.warning : AppColors.danger,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Backup Export Dialog with Formatted View & One-Tap Copy
// -----------------------------------------------------------------------------
class _ExportConfigDialog extends StatelessWidget {
  final SmartDevice device;
  final String jsonStr;

  const _ExportConfigDialog({
    required this.device,
    required this.jsonStr,
  });

  @override
  Widget build(BuildContext context) {
    final sizeKb = (utf8.encode(jsonStr).length / 1024).toStringAsFixed(1);
    int keyCount = 0;
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) keyCount = decoded.length;
    } catch (_) {}

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.download_rounded, color: AppColors.primaryLight, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuration Backup',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${device.name} • $sizeKb KB ($keyCount modules)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ready to copy or save. Restoring will apply these settings to any compatible controller.',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  jsonStr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: TextStyle(color: AppColors.textSecondary)),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryLight,
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy JSON'),
          onPressed: () {
            final messenger = ScaffoldMessenger.of(context);
            Clipboard.setData(ClipboardData(text: jsonStr));
            Navigator.pop(context);
            messenger.showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Configuration JSON copied to clipboard!'),
                  ],
                ),
                backgroundColor: AppColors.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            );
          },
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.save_alt_rounded, size: 16),
          label: const Text('Save File (.json)'),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              final safeName = device.name
                  .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
                  .toLowerCase();
              final bytes = Uint8List.fromList(utf8.encode(jsonStr));
              final savedPath = await FilePicker.saveFile(
                dialogTitle: 'Save SmartHome Backup JSON',
                fileName: '${safeName}_backup.json',
                bytes: bytes,
              );
              if (!context.mounted) return;
              if (savedPath != null) {
                Navigator.pop(context);
                messenger.showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Backup file saved: $savedPath')),
                      ],
                    ),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              }
            } catch (e) {
              if (!context.mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Could not save file: $e'),
                  backgroundColor: AppColors.danger,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Upgraded Restore Config Dialog with File Picker, Real-time JSON Inspection,
// Component Badges, and One-Tap Restore & Reboot Confirmation
// -----------------------------------------------------------------------------
class _RestoreConfigDialog extends StatefulWidget {
  final SmartDevice device;
  final DeviceManager manager;

  const _RestoreConfigDialog({
    required this.device,
    required this.manager,
  });

  @override
  State<_RestoreConfigDialog> createState() => _RestoreConfigDialogState();
}

class _RestoreConfigDialogState extends State<_RestoreConfigDialog> {
  String? _selectedFileName;
  int _selectedFileSize = 0;
  String? _selectedFileContent;
  String _jsonText = '';
  Map<String, dynamic>? _parsedData;
  String? _validationError;
  bool _isManualPaste = false;
  bool _isRestoring = false;
  final _pasteController = TextEditingController();

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result.isNotEmpty) {
        final file = result.first;
        final bytes = await file.readAsBytes();
        final content = utf8.decode(bytes);
        if (!mounted) return;
        setState(() {
          _selectedFileName = file.name;
          _selectedFileSize = bytes.length;
          _selectedFileContent = content;
          _isManualPaste = false;
        });
        _validateJson(content);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validationError = 'Failed to read file: $e';
        _parsedData = null;
      });
    }
  }

  void _validateJson(String content) {
    _jsonText = content.trim();
    if (_jsonText.isEmpty) {
      setState(() {
        _validationError = 'Please select a file or paste configuration JSON.';
        _parsedData = null;
      });
      return;
    }
    try {
      final decoded = jsonDecode(_jsonText);
      if (decoded is! Map<String, dynamic>) {
        setState(() {
          _validationError = 'Invalid format: Root must be a JSON object {...}';
          _parsedData = null;
        });
        return;
      }
      if (decoded['type'] == 'smarthome_pro_hub_backup') {
        setState(() {
          _validationError =
              'This is an App Hub backup. Import it via App Settings -> Hub Backup & Restore.';
          _parsedData = null;
        });
        return;
      }
      if (_detectComponents(decoded).isEmpty) {
        setState(() {
          _validationError =
              'No recognized controller configuration sections found in JSON.';
          _parsedData = null;
        });
        return;
      }
      setState(() {
        _validationError = null;
        _parsedData = decoded;
      });
    } catch (e) {
      setState(() {
        _validationError = 'Invalid JSON syntax: $e';
        _parsedData = null;
      });
    }
  }

  List<String> _detectComponents(Map<String, dynamic> data) {
    final components = <String>[];
    if (data.containsKey('config.json') || data.containsKey('config')) {
      final cfg = data['config.json'] ?? data['config'];
      if (cfg is Map && cfg['device_name'] != null) {
        components.add('System (${cfg['device_name']})');
      } else {
        components.add('System Core Config');
      }
    }
    if (data.containsKey('hardware.json') || data.containsKey('hardware')) {
      final hw = data['hardware.json'] ?? data['hardware'];
      if (hw is Map && hw['board_name'] != null) {
        components.add('Hardware (${hw['board_name']})');
      } else {
        components.add('Hardware Profile');
      }
    }
    if (data.containsKey('wifi.json') || data.containsKey('wifi') || data.containsKey('network')) {
      components.add('Wi-Fi Credentials');
    }
    if (data.containsKey('relays.json') || data.containsKey('relays')) {
      final r = data['relays.json'] ?? data['relays'];
      if (r is Map && r['relays'] is List) {
        components.add('${(r['relays'] as List).length} Relay Channels');
      } else if (r is List) {
        components.add('${r.length} Relay Channels');
      } else {
        components.add('Relay Hardware');
      }
    }
    if (data.containsKey('relay_states.json') || data.containsKey('relay_states')) {
      components.add('Relay Power States');
    }
    if (data.containsKey('alarms.json') || data.containsKey('alarms') || data.containsKey('schedules')) {
      components.add('Timers & Schedules');
    }
    if (data.containsKey('rules.json') || data.containsKey('rules')) {
      components.add('Automation Rules');
    }
    if (data.containsKey('sensors.json') || data.containsKey('sensor') || data.containsKey('sensors')) {
      components.add('Sensor Calibration');
    }
    if (data.containsKey('lcd.json') || data.containsKey('lcd')) {
      components.add('LCD Display');
    }
    if (data.containsKey('buzzer.json') || data.containsKey('buzzer')) {
      components.add('Buzzer Alerts');
    }
    if (data.containsKey('mqtt.json') || data.containsKey('mqtt')) {
      components.add('MQTT Broker');
    }
    return components;
  }

  Future<void> _confirmAndRestore() async {
    if (_parsedData == null || _jsonText.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Confirm Restore',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Restoring this backup will overwrite existing settings on ${widget.device.name} and immediately reboot the controller.\n\nAre you sure you want to proceed?',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply & Reboot', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isRestoring = true);
    final ok = await widget.manager.restoreBackup(widget.device.id, _jsonText);

    if (!mounted) return;
    setState(() => _isRestoring = false);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context); // close restore dialog

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                ok
                    ? 'Backup successfully restored! ${widget.device.name} is rebooting...'
                    : 'Failed to restore backup: controller rejected payload.',
              ),
            ),
          ],
        ),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final components = _parsedData != null ? _detectComponents(_parsedData!) : <String>[];

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGlow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.settings_backup_restore_rounded,
                      color: AppColors.primaryLight,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Restore Configuration',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          'Target: ${widget.device.name} (${widget.device.ip})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: _isRestoring ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mode Selector (File vs Paste)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: !_isManualPaste ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                                side: BorderSide(
                                  color: !_isManualPaste ? AppColors.primary : AppColors.cardBorder,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.upload_file_rounded, size: 18),
                              label: const Text('Choose File'),
                              onPressed: () {
                                if (_isManualPaste) {
                                  setState(() => _isManualPaste = false);
                                  if (_selectedFileName == null ||
                                      _selectedFileContent == null) {
                                    _pickFile();
                                  } else {
                                    _validateJson(_selectedFileContent!);
                                  }
                                } else {
                                  _pickFile();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _isManualPaste ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                                side: BorderSide(
                                  color: _isManualPaste ? AppColors.primary : AppColors.cardBorder,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.code_rounded, size: 18),
                              label: const Text('Paste JSON'),
                              onPressed: () {
                                setState(() => _isManualPaste = true);
                                if (_pasteController.text.trim().isNotEmpty) {
                                  _validateJson(_pasteController.text);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // File Drop / Selection Card
                      if (!_isManualPaste) ...[
                        if (_selectedFileName == null)
                          InkWell(
                            onTap: _pickFile,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.4),
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 44,
                                    color: AppColors.primaryLight,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Select Backup JSON File',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Tap to browse device downloads or local storage',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.cardBorder),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGlow,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.description_rounded,
                                    color: AppColors.primaryLight,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedFileName!,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppColors.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${(_selectedFileSize / 1024).toStringAsFixed(1)} KB • JSON Document',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.file_upload_outlined, size: 20),
                                  tooltip: 'Choose different file',
                                  onPressed: _pickFile,
                                ),
                              ],
                            ),
                          ),
                      ],

                      // Paste Area
                      if (_isManualPaste) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Paste JSON Configuration:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.content_paste_rounded, size: 14),
                              label: const Text('Paste Clipboard', style: TextStyle(fontSize: 12)),
                              onPressed: () async {
                                final data = await Clipboard.getData(Clipboard.kTextPlain);
                                if (!mounted) return;
                                if (data?.text != null) {
                                  _pasteController.text = data!.text!;
                                  _validateJson(data.text!);
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _pasteController,
                          maxLines: 7,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            hintText: '{\n  "wifi": { ... },\n  "relays": [ ... ]\n}',
                            hintStyle: const TextStyle(color: Colors.white54),
                            fillColor: const Color(0xFF111827),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppColors.cardBorder),
                            ),
                          ),
                          onChanged: (val) {
                            _validateJson(val);
                          },
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Validation Results & Summary
                      if (_validationError != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _validationError!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (_parsedData != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.success.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.verified_rounded, color: AppColors.success, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Valid Configuration File',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ],
                              ),
                              if (components.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Detected modules ready to restore:',
                                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: components
                                      .map(
                                        (c) => Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: AppColors.surface,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: AppColors.success.withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Text(
                                            c,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Safety Note
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'The controller will write settings to flash and restart immediately upon completion.',
                                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Bottom Actions
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _isRestoring ? null : () => Navigator.pop(context),
                      child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      icon: _isRestoring
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.settings_backup_restore_rounded, size: 18),
                      label: Text(
                        _isRestoring ? 'Restoring to controller...' : 'Restore & Reboot',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: (_parsedData == null || _isRestoring)
                          ? null
                          : _confirmAndRestore,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LcdPageEntry {
  final String id;
  final String label;
  final bool available;
  bool enabled;

  _LcdPageEntry({
    required this.id,
    required this.label,
    required this.available,
    required this.enabled,
  });
}

class _LcdWidgetOption {
  final String id;
  final String label;

  const _LcdWidgetOption({required this.id, required this.label});
}
