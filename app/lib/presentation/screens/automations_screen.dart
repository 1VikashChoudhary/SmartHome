import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/automation_rule.dart';
import '../../core/models/scheduled_alarm.dart';
import '../../core/models/smart_device.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../main.dart';
import '../../services/device_manager.dart';
import '../widgets/glass_card.dart';
import '../widgets/luxury_segmented_selector.dart';

class AutomationsScreen extends ConsumerStatefulWidget {
  final String? preselectedDeviceId;

  const AutomationsScreen({super.key, this.preselectedDeviceId});

  @override
  ConsumerState<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends ConsumerState<AutomationsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ApiClient _api = ApiClient();

  String? _selectedDeviceId;
  List<AutomationRule> _rules = [];
  List<ScheduledAlarm> _alarms = [];
  bool _loadingRules = false;
  bool _loadingAlarms = false;
  bool _initialLoadRequested = false;
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _selectedDeviceId = widget.preselectedDeviceId;
    _countdownTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _alarms.isNotEmpty) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  SmartDevice? _resolveDevice(List<SmartDevice> devices) {
    if (devices.isEmpty) return null;
    if (_selectedDeviceId != null) {
      try {
        return devices.firstWhere((d) => d.id == _selectedDeviceId);
      } catch (_) {}
    }
    return devices.first;
  }

  void _loadData() {
    final devices = ref.read(deviceManagerProvider);
    final dev = _resolveDevice(devices);
    if (dev != null) {
      _selectedDeviceId = dev.id;
      _loadRules(dev);
      _loadAlarms(dev);
    }
  }

  Future<void> _loadRules(SmartDevice dev) async {
    setState(() => _loadingRules = true);
    final rawRules = await _api.fetchRules(dev.ip, password: dev.authPassword);
    if (mounted) {
      setState(() {
        _rules = rawRules != null
            ? rawRules.map((m) => AutomationRule.fromJson(m)).toList()
            : [];
        _loadingRules = false;
      });
    }
  }

  Future<void> _loadAlarms(SmartDevice dev) async {
    setState(() => _loadingAlarms = true);
    final rawAlarms = await _api.fetchAlarms(
      dev.ip,
      password: dev.authPassword,
    );
    if (mounted) {
      setState(() {
        _alarms = rawAlarms != null
            ? rawAlarms.map((m) => ScheduledAlarm.fromJson(m)).toList()
            : [];
        _loadingAlarms = false;
      });
    }
  }

  // --- Rule Actions ---
  Future<void> _toggleRule(
    SmartDevice dev,
    AutomationRule rule,
    bool enabled,
  ) async {
    final idx = _rules.indexWhere((r) => r.id == rule.id);
    if (idx >= 0) {
      setState(() => _rules[idx] = _rules[idx].copyWith(enabled: enabled));
    }

    final ok = await _api.setRuleEnabled(
      dev.ip,
      rule.id,
      enabled,
      password: dev.authPassword,
    );
    if (!ok && mounted) {
      setState(() => _rules[idx] = _rules[idx].copyWith(enabled: !enabled));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to update rule state'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _deleteRule(SmartDevice dev, AutomationRule rule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete Rule?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Delete "${rule.name}" permanently from controller flash?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await _api.deleteRule(
        dev.ip,
        rule.id,
        password: dev.authPassword,
      );
      if (ok) {
        setState(() => _rules.removeWhere((r) => r.id == rule.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Rule deleted successfully'),
              backgroundColor: AppColors.accent,
            ),
          );
        }
      }
    }
  }

  // --- Alarm Actions ---
  Future<void> _toggleAlarm(
    SmartDevice dev,
    ScheduledAlarm alarm,
    bool enabled,
  ) async {
    final idx = _alarms.indexWhere((a) => a.id == alarm.id);
    if (idx >= 0) {
      setState(() => _alarms[idx] = _alarms[idx].copyWith(enabled: enabled));
    }

    final ok = await _api.setAlarmEnabled(
      dev.ip,
      alarm.id,
      enabled,
      password: dev.authPassword,
    );
    if (!ok && mounted) {
      setState(() => _alarms[idx] = _alarms[idx].copyWith(enabled: !enabled));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Failed to update schedule'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _deleteAlarm(SmartDevice dev, ScheduledAlarm alarm) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Delete Schedule?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text('Delete this timer schedule from controller memory?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final ok = await _api.deleteAlarm(
        dev.ip,
        alarm.id,
        password: dev.authPassword,
      );
      if (ok) {
        setState(() => _alarms.removeWhere((a) => a.id == alarm.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Schedule deleted'),
              backgroundColor: AppColors.accent,
            ),
          );
        }
      }
    }
  }

  // Kept temporarily for compatibility with older navigation state. New
  // entry points use _showRuleEditor, which exposes the complete ESP rule API.
  // ignore: unused_element
  void _showAddRuleSheet(BuildContext context, SmartDevice dev) {
    final nameController = TextEditingController(
      text: 'Auto Rule ${_rules.length + 1}',
    );
    int selectedSensor = 0; // 0: Temp, 1: Hum, 2: Gas
    int selectedCondition = 0; // 0: Above, 1: Below
    double thresholdValue = 30.0;
    double hystValue = 0.5;
    int selectedRelay = 0;
    int selectedAction = 0; // 0: ON, 1: OFF

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(
                top: BorderSide(color: AppColors.cardBorder, width: 1.5),
              ),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'New Hardware Sensor Rule',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Rule Name
                  TextField(
                    controller: nameController,
                    style: TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Rule Label',
                      hintText: 'e.g. Overheat Exhaust Fan',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Sensor Selector
                  Text(
                    'Sensor Trigger:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LuxurySegmentedSelector<int>(
                    values: const [0, 1, 2],
                    labels: const {
                      0: 'Temp (°C)',
                      1: 'Hum (%)',
                      2: 'Gas (ADC)',
                    },
                    icons: const {
                      0: Icons.thermostat,
                      1: Icons.water_drop,
                      2: Icons.warning,
                    },
                    selectedValue: selectedSensor,
                    onSelected: (val) {
                      setSheetState(() {
                        selectedSensor = val;
                        if (selectedSensor == 0) {
                          thresholdValue = 30.0;
                          hystValue = 0.5;
                        } else if (selectedSensor == 1) {
                          thresholdValue = 70.0;
                          hystValue = 2.0;
                        } else {
                          thresholdValue = 800.0;
                          hystValue = 30.0;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Condition
                  Text(
                    'Trigger Condition:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LuxurySegmentedSelector<int>(
                    values: const [0, 1],
                    labels: const {
                      0: 'Greater or Equal (≥)',
                      1: 'Less or Equal (≤)',
                    },
                    selectedValue: selectedCondition,
                    onSelected: (val) =>
                        setSheetState(() => selectedCondition = val),
                  ),
                  const SizedBox(height: 16),

                  // Threshold Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Threshold Value:',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGlow,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          '${thresholdValue.toStringAsFixed(selectedSensor == 2 ? 0 : 1)} ${selectedSensor == 0 ? "°C" : (selectedSensor == 1 ? "%" : "ADC")}',
                          style: TextStyle(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Builder(
                    builder: (context) {
                      final maxVal = selectedSensor == 0
                          ? 60.0
                          : (selectedSensor == 1
                              ? 100.0
                              : (dev.telemetry.gasMax > 0
                                  ? dev.telemetry.gasMax.toDouble()
                                  : (dev.isEsp8266 ? 1023.0 : 4095.0)));
                      return Slider(
                        value: thresholdValue.clamp(0.0, maxVal),
                        min: 0.0,
                        max: maxVal,
                        divisions: selectedSensor == 2 ? 80 : 60,
                        activeColor: AppColors.primary,
                        onChanged: (val) =>
                            setSheetState(() => thresholdValue = val),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Target Relay
                  Text(
                    'Target Relay Channel:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: selectedRelay,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      dev.relays.isNotEmpty ? dev.relays.length : 5,
                      (index) {
                        final r = index < dev.relays.length ? dev.relays[index] : null;
                        final rName = r != null
                            ? (r.name + (!r.enabled ? ' (Disabled)' : ''))
                            : 'Relay ${index + 1}';
                        return DropdownMenuItem(
                          value: index,
                          child: Text(rName),
                        );
                      },
                    ),
                    onChanged: (val) {
                      if (val != null) setSheetState(() => selectedRelay = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Action
                  Text(
                    'Relay Action:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LuxurySegmentedSelector<int>(
                    values: const [0, 1],
                    labels: const {0: 'Turn ON', 1: 'Turn OFF'},
                    icons: const {0: Icons.power, 1: Icons.power_off},
                    selectedValue: selectedAction,
                    onSelected: (val) =>
                        setSheetState(() => selectedAction = val),
                  ),
                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final newRule = AutomationRule(
                          id: 0,
                          enabled: true,
                          name: nameController.text.trim().isEmpty
                              ? 'Auto Rule'
                              : nameController.text.trim(),
                          sensor: selectedSensor,
                          condition: selectedCondition,
                          threshold: thresholdValue,
                          hysteresis: hystValue,
                          targetRelay: selectedRelay,
                          action: selectedAction,
                        );

                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(ctx);
                        final ok = await _api.saveRule(
                          dev.ip,
                          newRule.toJson(),
                          password: dev.authPassword,
                        );
                        if (ok) {
                          _loadRules(dev);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Rule saved to controller flash!',
                                ),
                                backgroundColor: AppColors.accent,
                              ),
                            );
                          }
                        } else if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text('Failed to save rule'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Save Rule to Controller Flash',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Kept temporarily for compatibility with older navigation state. New
  // entry points use _showTimerEditor, which exposes clock and delay timers.
  // ignore: unused_element
  void _showAddScheduleSheet(BuildContext context, SmartDevice dev) {
    TimeOfDay selectedTime = const TimeOfDay(hour: 7, minute: 0);
    int selectedType = 1; // 1: Daily
    int selectedRelay = 0;
    int selectedAction = 0; // 0: ON, 1: OFF, 2: Toggle

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(
                top: BorderSide(color: AppColors.cardBorder, width: 1.5),
              ),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  20,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'New Time Schedule / Alarm',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: AppColors.textSecondary),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Time Picker Button
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryGlow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.access_time, color: AppColors.accent),
                    ),
                    title: const Text(
                      'Scheduled Time of Day',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '${selectedTime.format(context)} (Controller RTC/NTP time)',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setSheetState(() => selectedTime = picked);
                        }
                      },
                      child: const Text('Change Time'),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Frequency / Type
                  Text(
                    'Schedule Frequency:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: selectedType,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 1,
                        child: Text('Every Day (Daily)'),
                      ),
                      DropdownMenuItem(
                        value: 3,
                        child: Text('Weekdays Only (Mon - Fri)'),
                      ),
                      DropdownMenuItem(
                        value: 4,
                        child: Text('Weekends Only (Sat - Sun)'),
                      ),
                      DropdownMenuItem(value: 0, child: Text('Run Once Only')),
                    ],
                    onChanged: (v) =>
                        setSheetState(() => selectedType = v ?? 1),
                  ),
                  const SizedBox(height: 16),

                  // Target Relay
                  Text(
                    'Target Relay Channel:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: selectedRelay,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      ...dev.relays.map((r) => DropdownMenuItem(
                        value: r.index,
                        child: Text(r.name + (!r.enabled ? ' (Disabled)' : '')),
                      )),
                      const DropdownMenuItem(
                        value: 255,
                        child: Text('ALL Relays (Master)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setSheetState(() => selectedRelay = val);
                    },
                  ),
                  const SizedBox(height: 16),

                  // Action
                  Text(
                    'Action to Perform:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LuxurySegmentedSelector<int>(
                    values: const [0, 1, 2],
                    labels: const {0: 'Turn ON', 1: 'Turn OFF', 2: 'Toggle'},
                    icons: const {
                      0: Icons.power,
                      1: Icons.power_off,
                      2: Icons.swap_horiz,
                    },
                    selectedValue: selectedAction,
                    onSelected: (val) =>
                        setSheetState(() => selectedAction = val),
                  ),
                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final newAlarm = ScheduledAlarm(
                          id: 0,
                          enabled: true,
                          mode: 0,
                          type: selectedType,
                          hour: selectedTime.hour,
                          minute: selectedTime.minute,
                          action: selectedAction,
                          targetRelay: selectedRelay,
                        );

                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(ctx);
                        final ok = await _api.saveAlarm(
                          dev.ip,
                          newAlarm.toJson(),
                          password: dev.authPassword,
                        );
                        if (ok) {
                          _loadAlarms(dev);
                          if (mounted) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: const Text(
                                  'Time schedule saved to controller!',
                                ),
                                backgroundColor: AppColors.accent,
                              ),
                            );
                          }
                        } else if (mounted) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: const Text('Failed to save schedule'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Save Schedule to Hardware',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _relayLabel(SmartDevice dev, int relay) {
    if (relay == 255) return 'All active relays';
    if (relay >= 0 && relay < dev.relays.length) {
      final r = dev.relays[relay];
      return r.name + (!r.enabled ? ' (Disabled)' : '');
    }
    return 'Relay ${relay + 1}';
  }

  String _delayLabel(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0 && minutes > 0) return '${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h';
    return '${minutes}m';
  }

  void _showRuleEditor(
    BuildContext context,
    SmartDevice dev, [
    AutomationRule? existing,
  ]) {
    final nameController = TextEditingController(
      text: existing?.name ?? 'Auto Rule ${_rules.length + 1}',
    );
    final hysteresisController = TextEditingController(
      text: (existing?.hysteresis ?? 0.5).toString(),
    );
    var sensor = existing?.sensor ?? 0;
    var condition = existing?.condition ?? 0;
    var threshold = existing?.threshold ?? 30.0;
    var relay = existing?.targetRelay ?? 0;
    var action = existing?.action ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null ? 'New Sensor Rule' : 'Edit Sensor Rule',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Saved and evaluated directly by this controller every second.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  maxLength: 23,
                  decoration: const InputDecoration(
                    labelText: 'Rule name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: sensor,
                  decoration: const InputDecoration(
                    labelText: 'Sensor',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Temperature (°C)')),
                    DropdownMenuItem(value: 1, child: Text('Humidity (%)')),
                    DropdownMenuItem(value: 2, child: Text('Gas / MQ-2 (ADC)')),
                    DropdownMenuItem(value: 3, child: Text('Ambient Light (Lux)')),
                    DropdownMenuItem(value: 4, child: Text('Water Temp Probe (°C)')),
                    DropdownMenuItem(value: 5, child: Text('Water Tank Level (%)')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setSheetState(() {
                      sensor = value;
                      switch (value) {
                        case 0:
                          threshold = 30.0;
                          hysteresisController.text = '0.5';
                          break;
                        case 1:
                          threshold = 70.0;
                          hysteresisController.text = '2.0';
                          break;
                        case 2:
                          threshold = 800.0;
                          hysteresisController.text = '30';
                          break;
                        case 3:
                          threshold = 200.0;
                          hysteresisController.text = '15';
                          break;
                        case 4:
                          threshold = 35.0;
                          hysteresisController.text = '0.5';
                          break;
                        case 5:
                          threshold = 20.0;
                          hysteresisController.text = '3';
                          break;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: condition,
                  decoration: const InputDecoration(
                    labelText: 'Trigger condition',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 0,
                      child: Text('Rises to / above threshold (≥)'),
                    ),
                    DropdownMenuItem(
                      value: 1,
                      child: Text('Falls to / below threshold (≤)'),
                    ),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => condition = value ?? condition),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    String unitStr = '°C';
                    double maxVal = 60.0;
                    int divisionsVal = 60;
                    int decimals = 1;

                    if (sensor == 0) {
                      unitStr = '°C';
                      maxVal = 60.0;
                      divisionsVal = 60;
                      decimals = 1;
                    } else if (sensor == 1) {
                      unitStr = '%';
                      maxVal = 100.0;
                      divisionsVal = 100;
                      decimals = 0;
                    } else if (sensor == 2) {
                      unitStr = 'ADC';
                      maxVal = dev.telemetry.gasMax > 0
                          ? dev.telemetry.gasMax.toDouble()
                          : (dev.isEsp8266 ? 1023.0 : 4095.0);
                      divisionsVal = dev.isEsp8266 ? 50 : 80;
                      decimals = 0;
                    } else if (sensor == 3) {
                      unitStr = 'lx';
                      maxVal = 2000.0;
                      divisionsVal = 100;
                      decimals = 0;
                    } else if (sensor == 4) {
                      unitStr = '°C';
                      maxVal = 100.0;
                      divisionsVal = 100;
                      decimals = 1;
                    } else if (sensor == 5) {
                      unitStr = '%';
                      maxVal = 100.0;
                      divisionsVal = 100;
                      decimals = 0;
                    }

                    final clampedTh = threshold.clamp(0.0, maxVal);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Threshold: ${clampedTh.toStringAsFixed(decimals)} $unitStr',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Slider(
                          value: clampedTh,
                          min: 0,
                          max: maxVal,
                          divisions: divisionsVal,
                          activeColor: AppColors.primary,
                          onChanged: (value) => setSheetState(() => threshold = value),
                        ),
                      ],
                    );
                  },
                ),
                TextField(
                  controller: hysteresisController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Hysteresis (anti-flapping)',
                    helperText:
                        'The reading must cross this reset margin before the rule can fire again.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: relay,
                  decoration: const InputDecoration(
                    labelText: 'Target',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    ...List.generate(
                      dev.relays.length,
                      (index) => DropdownMenuItem(
                        value: index,
                        child: Text(_relayLabel(dev, index)),
                      ),
                    ),
                    const DropdownMenuItem(
                      value: 255,
                      child: Text('All relays'),
                    ),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => relay = value ?? relay),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: action,
                  decoration: const InputDecoration(
                    labelText: 'Action',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Turn ON')),
                    DropdownMenuItem(value: 1, child: Text('Turn OFF')),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => action = value ?? action),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      final hysteresis = double.tryParse(
                        hysteresisController.text.trim(),
                      );
                      if (hysteresis == null || hysteresis < 0) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enter a valid non-negative hysteresis value.',
                            ),
                          ),
                        );
                        return;
                      }
                      final rule = AutomationRule(
                        id: existing?.id ?? 0,
                        enabled: existing?.enabled ?? true,
                        name: nameController.text.trim().isEmpty
                            ? 'Auto Rule'
                            : nameController.text.trim(),
                        sensor: sensor,
                        condition: condition,
                        threshold: threshold,
                        hysteresis: hysteresis,
                        targetRelay: relay,
                        action: action,
                      );
                      final ok = await _api.saveRule(
                        dev.ip,
                        rule.toJson(),
                        password: dev.authPassword,
                      );
                      if (!sheetContext.mounted) return;
                      if (ok) {
                        Navigator.pop(sheetContext);
                        await _loadRules(dev);
                      } else {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(
                            content: Text('Controller rejected the rule.'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    },
                    child: Text(
                      existing == null
                          ? 'Save rule to controller'
                          : 'Update rule on controller',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTimerEditor(
    BuildContext context,
    SmartDevice dev, {
    ScheduledAlarm? existing,
    int initialMode = 0,
  }) {
    var mode = existing?.mode ?? initialMode;
    var scheduleType = existing?.type ?? 1;
    var dayOfWeek = existing?.dayOfWeek ?? 1;
    var action = existing?.action ?? 0;
    var relay = existing?.targetRelay ?? 0;
    var time = TimeOfDay(
      hour: existing?.hour ?? 8,
      minute: existing?.minute ?? 0,
    );
    final hoursController = TextEditingController(
      text: '${(existing?.delayMinutes ?? 30) ~/ 60}',
    );
    final minutesController = TextEditingController(
      text: '${(existing?.delayMinutes ?? 30) % 60}',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final actionNeedsRelay = action <= 2;
          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null
                        ? 'New Hardware Timer'
                        : 'Edit Hardware Timer',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The ESP keeps this timer and runs it even when the app is closed.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  LuxurySegmentedSelector<int>(
                    values: const [0, 1],
                    labels: const {0: 'Fixed time', 1: 'Delay timer'},
                    icons: const {0: Icons.schedule, 1: Icons.timer_outlined},
                    selectedValue: mode,
                    onSelected: (value) => setSheetState(() => mode = value),
                  ),
                  const SizedBox(height: 16),
                  if (mode == 0) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Time: ${time.format(sheetContext)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Uses this ESP controller’s NTP/RTC time.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      trailing: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: sheetContext,
                            initialTime: time,
                          );
                          if (picked != null) {
                            setSheetState(() => time = picked);
                          }
                        },
                        child: const Text('Change'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: scheduleType,
                      decoration: const InputDecoration(
                        labelText: 'Repeat',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Once')),
                        DropdownMenuItem(value: 1, child: Text('Daily')),
                        DropdownMenuItem(value: 2, child: Text('Weekly')),
                        DropdownMenuItem(
                          value: 3,
                          child: Text('Weekdays (Mon–Fri)'),
                        ),
                        DropdownMenuItem(
                          value: 4,
                          child: Text('Weekends (Sat–Sun)'),
                        ),
                      ],
                      onChanged: (value) => setSheetState(
                        () => scheduleType = value ?? scheduleType,
                      ),
                    ),
                    if (scheduleType == 2) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: dayOfWeek,
                        decoration: const InputDecoration(
                          labelText: 'Day of week',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Sunday')),
                          DropdownMenuItem(value: 1, child: Text('Monday')),
                          DropdownMenuItem(value: 2, child: Text('Tuesday')),
                          DropdownMenuItem(value: 3, child: Text('Wednesday')),
                          DropdownMenuItem(value: 4, child: Text('Thursday')),
                          DropdownMenuItem(value: 5, child: Text('Friday')),
                          DropdownMenuItem(value: 6, child: Text('Saturday')),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => dayOfWeek = value ?? dayOfWeek),
                      ),
                    ],
                  ] else ...[
                    Text(
                      'Delay from now',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: hoursController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Hours',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: minutesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Minutes',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A delay timer runs once, then disables itself. Editing or enabling it re-arms it from now.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: action,
                    decoration: const InputDecoration(
                      labelText: 'Action',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Turn relay ON')),
                      DropdownMenuItem(value: 1, child: Text('Turn relay OFF')),
                      DropdownMenuItem(value: 2, child: Text('Toggle relay')),
                      DropdownMenuItem(value: 3, child: Text('Sound buzzer')),
                      DropdownMenuItem(
                        value: 4,
                        child: Text('Turn ALL relays ON'),
                      ),
                      DropdownMenuItem(
                        value: 5,
                        child: Text('Turn ALL relays OFF'),
                      ),
                    ],
                    onChanged: (value) => setSheetState(() {
                      action = value ?? action;
                      if (action > 2) {
                        relay = 255;
                      } else if (relay == 255) {
                        relay = 0;
                      }
                    }),
                  ),
                  if (actionNeedsRelay) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: relay,
                      decoration: const InputDecoration(
                        labelText: 'Target relay',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(
                        dev.relays.length,
                        (index) => DropdownMenuItem(
                          value: index,
                          child: Text(_relayLabel(dev, index)),
                        ),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => relay = value ?? relay),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final hours =
                            int.tryParse(hoursController.text.trim()) ?? -1;
                        final minutes =
                            int.tryParse(minutesController.text.trim()) ?? -1;
                        final delay = (hours * 60) + minutes;
                        if (mode == 1 &&
                            (hours < 0 ||
                                minutes < 0 ||
                                minutes > 59 ||
                                delay <= 0)) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Set a delay of at least one minute (minutes: 0–59).',
                              ),
                            ),
                          );
                          return;
                        }
                        final timer = ScheduledAlarm(
                          id: existing?.id ?? 0,
                          enabled: existing?.enabled ?? true,
                          mode: mode,
                          type: mode == 0 ? scheduleType : 0,
                          hour: time.hour,
                          minute: time.minute,
                          dayOfWeek: dayOfWeek,
                          delayMinutes: mode == 1 ? delay : 0,
                          action: action,
                          targetRelay: actionNeedsRelay ? relay : 255,
                          fired: false,
                        );
                        final ok = await _api.saveAlarm(
                          dev.ip,
                          timer.toJson(),
                          password: dev.authPassword,
                        );
                        if (!sheetContext.mounted) return;
                        if (ok) {
                          Navigator.pop(sheetContext);
                          await _loadAlarms(dev);
                        } else {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Controller rejected the timer.',
                              ),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      },
                      child: Text(
                        existing == null
                            ? 'Save timer to controller'
                            : 'Update timer on controller',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final dev = _resolveDevice(devices);
    final isVisible = ref.watch(navigationIndexProvider) == 2;
    final isDark = AppColors.isDark;

    // MainShell retains tabs in an IndexedStack. Do not load automation data
    // merely because this offstage widget was constructed at app startup.
    if (isVisible && !_initialLoadRequested && dev != null) {
      _initialLoadRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadData();
      });
    }

    // Check if the currently active tab has items to decide whether to show FAB
    final hasItemsInCurrentTab =
        (_tabController.index == 0 && _rules.isNotEmpty) ||
        (_tabController.index == 1 && _alarms.isNotEmpty);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Hardware Automations',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.textPrimary),
            tooltip: 'Reload Rules from Controller',
            onPressed: () {
              if (dev != null) {
                _loadRules(dev);
                _loadAlarms(dev);
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: isDark ? Colors.white : AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: isDark ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.sensors, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Sensor Rules',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.schedule, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Timers & Schedules',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // Only show Floating Action Button when there ARE active rules (NO MORE DUPLICATE BUTTONS IN EMPTY STATE!)
      floatingActionButton: (dev != null && hasItemsInCurrentTab)
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(_tabController.index == 0 ? 'New Rule' : 'New Timer'),
              onPressed: () {
                if (_tabController.index == 0) {
                  _showRuleEditor(context, dev);
                } else {
                  _showTimerEditor(context, dev);
                }
              },
            )
          : null,
      body: dev == null
          ? Center(
              child: Text(
                'No SmartHome controllers connected.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          : Column(
              children: [
                // Controller Selector Bar (Clean glass design)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder, width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGlow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.developer_board,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: dev.id,
                              dropdownColor: AppColors.surface,
                              items: devices.map((d) {
                                return DropdownMenuItem(
                                  value: d.id,
                                  child: Row(
                                    children: [
                                      Text(
                                        d.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppColors.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (d.room.isNotEmpty) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          '(${d.room})',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (id) {
                                if (id != null) {
                                  setState(() => _selectedDeviceId = id);
                                  _loadData();
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Tab Content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildRulesTab(dev), _buildAlarmsTab(dev)],
                  ),
                ),
              ],
            ),
    );
  }

  // --- Rules Tab View ---
  Widget _buildRulesTab(SmartDevice dev) {
    if (_loadingRules) return const Center(child: CircularProgressIndicator());
    if (_rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryGlow,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No Sensor Rules Configured',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Trigger relays automatically based on real-time DHT22 Temperature, Humidity, or MQ-2 Gas levels.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Create Sensor Rule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onPressed: () => _showRuleEditor(context, dev),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rules.length,
      itemBuilder: (ctx, idx) {
        final rule = _rules[idx];
        final rName = _relayLabel(dev, rule.targetRelay);

        Color sColor = AppColors.tempAmber;
        IconData sIcon = Icons.thermostat;
        String liveSensorValue =
            '${dev.telemetry.temperature.toStringAsFixed(1)} °C';
        if (rule.sensor == 1) {
          sColor = AppColors.humCyan;
          sIcon = Icons.water_drop;
          liveSensorValue = '${dev.telemetry.humidity.toStringAsFixed(1)} %';
        } else if (rule.sensor == 2) {
          sColor = AppColors.danger;
          sIcon = Icons.warning;
          liveSensorValue = '${dev.telemetry.gasRaw} ADC';
        } else if (rule.sensor == 3) {
          sColor = Colors.amber;
          sIcon = Icons.wb_sunny;
          liveSensorValue = '${dev.telemetry.lux.toStringAsFixed(1)} lx';
        } else if (rule.sensor == 4) {
          sColor = Colors.cyan;
          sIcon = Icons.device_thermostat;
          liveSensorValue = '${dev.telemetry.probeTemp.toStringAsFixed(1)} °C';
        } else if (rule.sensor == 5) {
          sColor = Colors.blue;
          sIcon = Icons.waves;
          liveSensorValue = '${dev.telemetry.tankLevelPct} %';
        }

        final isTriggered =
            rule.enabled &&
            (rule.triggered ||
                dev.relays.any((r) => r.activeRule == rule.name));

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: isTriggered
                ? AppColors.warning
                : (rule.enabled
                      ? AppColors.accent.withValues(alpha: 0.35)
                      : AppColors.cardBorder),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: sColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(sIcon, color: sColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  rule.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isTriggered
                                      ? AppColors.warning.withValues(
                                          alpha: 0.18,
                                        )
                                      : (rule.enabled
                                            ? AppColors.success.withValues(
                                                alpha: 0.14,
                                              )
                                            : AppColors.surfaceElevated),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isTriggered
                                        ? AppColors.warning.withValues(
                                            alpha: 0.5,
                                          )
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Text(
                                  isTriggered
                                      ? '⚡ TRIGGERED'
                                      : (rule.enabled ? 'ARMED' : 'PAUSED'),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: isTriggered
                                        ? AppColors.warning
                                        : (rule.enabled
                                              ? AppColors.success
                                              : AppColors.textMuted),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'IF ${rule.sensorLabel} ${rule.condition == 0 ? "≥" : "≤"} ${rule.threshold.toStringAsFixed(rule.sensor == 2 ? 0 : 1)}${rule.unit}  •  Live: $liveSensorValue',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: rule.enabled,
                      activeThumbColor: AppColors.success,
                      onChanged: (v) => _toggleRule(dev, rule, v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Divider(color: AppColors.cardBorder, height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          rule.action == 0 ? Icons.power : Icons.power_off,
                          size: 16,
                          color: rule.action == 0
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'THEN ${rule.actionLabel}: $rName',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit rule',
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _showRuleEditor(context, dev, rule),
                        ),
                        IconButton(
                          tooltip: 'Delete rule',
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: AppColors.danger,
                          ),
                          onPressed: () => _deleteRule(dev, rule),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- Alarms Tab View ---
  Widget _buildAlarmsTab(SmartDevice dev) {
    if (_loadingAlarms) return const Center(child: CircularProgressIndicator());
    if (_alarms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryGlow,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'No Hardware Timers Configured',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create fixed-time schedules or persistent one-shot delay timers. The ESP runs them without the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Add Hardware Timer',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onPressed: () => _showTimerEditor(context, dev),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _alarms.length,
      itemBuilder: (ctx, idx) {
        final a = _alarms[idx];
        final rName = _relayLabel(dev, a.targetRelay);
        final isDelay = a.mode == 1;
        final title = isDelay ? _delayLabel(a.delayMinutes) : a.timeString;
        final frequency = isDelay ? 'Delay timer (once)' : a.typeLabel;
        final actionText = a.action <= 2
            ? '${a.actionLabel} $rName'
            : a.actionLabel;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            borderColor: a.enabled
                ? AppColors.accent.withValues(alpha: 0.35)
                : AppColors.cardBorder,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.alarm, color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: a.enabled
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : AppColors.surfaceElevated,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: a.enabled
                                      ? AppColors.primary.withValues(alpha: 0.4)
                                      : AppColors.cardBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.timer_outlined,
                                    size: 11,
                                    color: a.enabled
                                        ? AppColors.primaryLight
                                        : AppColors.textMuted,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      a.nextRunBadge,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: a.enabled
                                            ? AppColors.primaryLight
                                            : AppColors.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$frequency • $actionText',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: a.enabled,
                  activeThumbColor: AppColors.success,
                  onChanged: (v) => _toggleAlarm(dev, a, v),
                ),
                IconButton(
                  tooltip: 'Edit timer',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _showTimerEditor(context, dev, existing: a),
                ),
                IconButton(
                  tooltip: 'Delete timer',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.danger,
                    size: 20,
                  ),
                  onPressed: () => _deleteAlarm(dev, a),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
