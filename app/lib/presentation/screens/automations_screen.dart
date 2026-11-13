import 'dart:async';
import 'dart:math' as math;
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
    _countdownTicker = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted) return;
      setState(() {});
      // Silently refresh alarm fired status from device if connected
      final devices = ref.read(deviceManagerProvider);
      final dev = _resolveDevice(devices);
      if (dev != null && dev.isOnline && _alarms.isNotEmpty) {
        final rawAlarms = await _api.fetchAlarms(
          dev.ip,
          password: dev.authPassword,
        );
        if (mounted && rawAlarms != null && _selectedDeviceId == dev.id) {
          setState(() {
            _alarms = rawAlarms.map((m) => ScheduledAlarm.fromJson(m)).toList();
          });
        }
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

  int _loadGeneration = 0;

  void _loadData() {
    final devices = ref.read(deviceManagerProvider);
    final dev = _resolveDevice(devices);
    if (dev != null) {
      _selectedDeviceId = dev.id;
      final gen = ++_loadGeneration;
      _loadRules(dev, generation: gen);
      _loadAlarms(dev, generation: gen);
    }
  }

  Future<void> _loadRules(SmartDevice dev, {int? generation}) async {
    final gen = generation ?? _loadGeneration;
    setState(() => _loadingRules = true);
    final rawRules = await _api.fetchRules(dev.ip, password: dev.authPassword);
    if (!mounted || gen != _loadGeneration || _selectedDeviceId != dev.id) {
      return;
    }
    setState(() {
      _rules = rawRules != null
          ? rawRules.map((m) => AutomationRule.fromJson(m)).toList()
          : [];
      _loadingRules = false;
    });
  }

  Future<void> _loadAlarms(SmartDevice dev, {int? generation}) async {
    final gen = generation ?? _loadGeneration;
    setState(() => _loadingAlarms = true);
    final rawAlarms = await _api.fetchAlarms(
      dev.ip,
      password: dev.authPassword,
    );
    if (!mounted || gen != _loadGeneration || _selectedDeviceId != dev.id) {
      return;
    }
    setState(() {
      _alarms = rawAlarms != null
          ? rawAlarms.map((m) => ScheduledAlarm.fromJson(m)).toList()
          : [];
      _loadingAlarms = false;
    });
  }

  // --- Rule Actions ---
  Future<void> _toggleRule(
    SmartDevice dev,
    AutomationRule rule,
    bool enabled,
  ) async {
    final idx = _rules.indexWhere((r) => r.id == rule.id);
    final previousTriggered = rule.triggered;
    if (idx >= 0) {
      setState(
        () => _rules[idx] = _rules[idx].copyWith(
          enabled: enabled,
          // When re-enabling a rule, reset triggered flag immediately in UI
          triggered: enabled ? false : rule.triggered,
        ),
      );
    }

    final ok = await _api.setRuleEnabled(
      dev.ip,
      rule.id,
      enabled,
      password: dev.authPassword,
    );
    if (!mounted) return;
    if (ok) {
      // Silently sync latest rule state from controller without full-page spinner
      final rawRules = await _api.fetchRules(dev.ip, password: dev.authPassword);
      if (mounted && rawRules != null && _selectedDeviceId == dev.id) {
        setState(() {
          _rules = rawRules.map((m) => AutomationRule.fromJson(m)).toList();
        });
      }
    } else {
      final revertIdx = _rules.indexWhere((r) => r.id == rule.id);
      if (revertIdx >= 0) {
        setState(
          () => _rules[revertIdx] = _rules[revertIdx].copyWith(
            enabled: !enabled,
            triggered: previousTriggered,
          ),
        );
      }
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
      if (!mounted) return;
      if (ok) {
        setState(() => _rules.removeWhere((r) => r.id == rule.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Rule deleted successfully'),
            backgroundColor: AppColors.accent,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete rule'),
            backgroundColor: AppColors.danger,
          ),
        );
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
    final previousFired = alarm.fired;
    if (idx >= 0) {
      setState(
        () => _alarms[idx] = _alarms[idx].copyWith(
          enabled: enabled,
          // When re-enabling an alarm, reset fired flag immediately so UI reflects ARMED
          fired: enabled ? false : alarm.fired,
        ),
      );
    }

    final ok = await _api.setAlarmEnabled(
      dev.ip,
      alarm.id,
      enabled,
      password: dev.authPassword,
    );
    if (!mounted) return;
    if (ok) {
      // Silently sync latest alarm state from controller without full-page spinner
      final rawAlarms = await _api.fetchAlarms(
        dev.ip,
        password: dev.authPassword,
      );
      if (mounted && rawAlarms != null && _selectedDeviceId == dev.id) {
        setState(() {
          _alarms = rawAlarms.map((m) => ScheduledAlarm.fromJson(m)).toList();
        });
      }
    } else {
      final revertIdx = _alarms.indexWhere((a) => a.id == alarm.id);
      if (revertIdx >= 0) {
        setState(
          () => _alarms[revertIdx] = _alarms[revertIdx].copyWith(
            enabled: !enabled,
            fired: previousFired,
          ),
        );
      }
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
      if (!mounted) return;
      if (ok) {
        setState(() => _alarms.removeWhere((a) => a.id == alarm.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Schedule deleted'),
            backgroundColor: AppColors.accent,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete schedule'),
            backgroundColor: AppColors.danger,
          ),
        );
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

  String _formatAlarmTime(int hour, int minute) {
    final h12 = (hour % 12 == 0) ? 12 : (hour % 12);
    final mStr = minute.toString().padLeft(2, '0');
    final amPm = hour < 12 ? 'AM' : 'PM';
    return '${h12.toString().padLeft(2, '0')}:$mStr $amPm';
  }

  static Widget _buildScheduleChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.18)
              : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.cardBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildDayCircle(
    String letter,
    String title,
    int dow,
    int currentDow,
    ValueChanged<int> onSelect,
  ) {
    final isSelected = dow == currentDow;
    return Tooltip(
      message: title,
      child: InkWell(
        onTap: () => onSelect(dow),
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.cardBorder,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              letter,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildPresetChip(
    int minutes,
    String label,
    int currentTotal,
    ValueChanged<int> onSelect,
  ) {
    final isSelected = minutes == currentTotal;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => onSelect(minutes),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.22)
                : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.cardBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildStepperBox({
    required String label,
    required TextEditingController controller,
    required int value,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.remove_circle_outline_rounded,
                  size: 22,
                  color: value > 0 ? AppColors.textPrimary : AppColors.textMuted,
                ),
                onPressed: value > 0 ? onMinus : null,
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: onChanged,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.add_circle_outline_rounded,
                  size: 22,
                  color: AppColors.primary,
                ),
                onPressed: onPlus,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showRuleEditor(
    BuildContext context,
    SmartDevice dev, [
    AutomationRule? existing,
  ]) async {
    if (dev.isGuest) return;
    final nameController = TextEditingController(
      text: existing?.name ?? 'Auto Rule ${_rules.length + 1}',
    );
    final hysteresisController = TextEditingController(
      text: (existing?.hysteresis ?? 0.5).toString(),
    );
    var sensor = (existing?.sensor ?? 0).clamp(0, 6);
    var sensorIndex = existing?.sensorIndex ?? 0;
    var condition = (existing?.condition ?? 0).clamp(0, 1);
    var threshold = existing?.threshold ?? 30.0;
    final rawRelay = existing?.targetRelay ?? (dev.relays.isEmpty ? 255 : 0);
    var relay = dev.relays.isEmpty
        ? 255
        : (rawRelay == 255 || (rawRelay >= 0 && rawRelay < dev.relays.length)
              ? rawRelay
              : 0);
    var action = (existing?.action ?? 0).clamp(0, 1);

    List<String> slotLabelsFor(int sensorType) {
      final t = dev.telemetry;
      switch (sensorType) {
        case 0:
        case 1:
          return t.climates.map((c) => c.displayName).toList();
        case 2:
          return t.mq2s.map((g) => g.displayName).toList();
        case 3:
          return t.lights.map((l) => l.displayName).toList();
        case 4:
          return t.probes.map((p) => p.displayName).toList();
        case 5:
          return t.tanks.map((u) => u.displayName).toList();
        case 6:
          return t.motions.map((m) => m.displayName).toList();
        default:
          return const [];
      }
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final slotLabels = slotLabelsFor(sensor);
          final slotCount = math.max(slotLabels.length, sensorIndex + 1);
          final clampedSensorIdx = sensorIndex.clamp(0, slotCount - 1);
          final viewInsets = MediaQuery.of(sheetContext).viewInsets.bottom;
          final safeBottom = math.max(
            MediaQuery.of(sheetContext).padding.bottom,
            MediaQuery.of(sheetContext).viewPadding.bottom,
          );
          final bottomPadding =
              viewInsets > 0 ? (viewInsets + 16) : (safeBottom + 20);

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              bottomPadding,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(
                top: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGlow,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(
                          existing == null ? Icons.add_moderator_rounded : Icons.edit_note_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              existing == null ? 'New Sensor Rule' : 'Edit Sensor Rule',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Evaluated directly by controller every second',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                        ),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Rule Name Field
                  Text(
                    'RULE LABEL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    maxLength: 23,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.card,
                      hintText: 'e.g. Overheat Fan Trigger',
                      counterStyle: TextStyle(fontSize: 10, color: AppColors.textMuted),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Sensor Dropdown
                  Text(
                    'SENSOR TRIGGER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: sensor,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.card,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Row(
                          children: [
                            Icon(Icons.thermostat_rounded, color: AppColors.tempAmber, size: 20),
                            SizedBox(width: 10),
                            Text('Temperature (°C)', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Row(
                          children: [
                            Icon(Icons.water_drop_rounded, color: AppColors.humCyan, size: 20),
                            SizedBox(width: 10),
                            Text('Humidity (%)', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
                            SizedBox(width: 10),
                            Text('Gas / MQ-2 (ADC)', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 3,
                        child: Row(
                          children: [
                            Icon(Icons.wb_sunny_rounded, color: Colors.amber, size: 20),
                            SizedBox(width: 10),
                            Text('Ambient Light (Lux)', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 4,
                        child: Row(
                          children: [
                            Icon(Icons.device_thermostat_rounded, color: Colors.cyan, size: 20),
                            SizedBox(width: 10),
                            Text('Water Temp Probe (°C)', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 5,
                        child: Row(
                          children: [
                            Icon(Icons.waves_rounded, color: Colors.blue, size: 20),
                            SizedBox(width: 10),
                            Text('Water Tank Level (%)', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 6,
                        child: Row(
                          children: [
                            Icon(Icons.directions_run_rounded, color: AppColors.warning, size: 20),
                            SizedBox(width: 10),
                            Text('Motion / Occupancy (1=Motion, 0=Clear)', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() {
                        sensor = value;
                        sensorIndex = 0;
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
                          case 6:
                            threshold = condition == 1 ? 0.0 : 1.0;
                            hysteresisController.text = '0';
                            break;
                        }
                      });
                    },
                  ),
                  if (slotCount > 1) ...[
                    const SizedBox(height: 14),
                    Text(
                      'SENSOR INSTANCE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      key: ValueKey('rule_sidx_${sensor}_$clampedSensorIdx'),
                      initialValue: clampedSensorIdx,
                      dropdownColor: AppColors.surfaceElevated,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.card,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.cardBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.cardBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                      items: List.generate(
                        slotCount,
                        (idx) => DropdownMenuItem(
                          value: idx,
                          child: Text(
                            idx < slotLabels.length ? slotLabels[idx] : 'Sensor #${idx + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => sensorIndex = value ?? sensorIndex),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // Trigger Condition Segmented Control
                  Text(
                    'TRIGGER CONDITION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LuxurySegmentedSelector<int>(
                    values: const [0, 1],
                    labels: const {
                      0: 'Rises to / above (≥)',
                      1: 'Falls to / below (≤)',
                    },
                    icons: const {
                      0: Icons.arrow_upward_rounded,
                      1: Icons.arrow_downward_rounded,
                    },
                    selectedValue: condition,
                    onSelected: (value) => setSheetState(() {
                      condition = value;
                      if (sensor == 6) {
                        threshold = condition == 1 ? 0.0 : 1.0;
                      }
                    }),
                  ),
                  const SizedBox(height: 16),

                  // Threshold Hero Card
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
                      } else if (sensor == 6) {
                        unitStr = '';
                        maxVal = 1.0;
                        divisionsVal = 1;
                        decimals = 0;
                      }

                      final clampedTh = threshold.clamp(0.0, maxVal);
                      final thDisplay = sensor == 6
                          ? (clampedTh >= 0.5 ? 'Motion Detected (1)' : 'Clear (0)')
                          : '${clampedTh.toStringAsFixed(decimals)} $unitStr';

                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'ACTIVATION THRESHOLD',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.7,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Text(
                                    thDisplay,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SliderTheme(
                              data: SliderTheme.of(sheetContext).copyWith(
                                activeTrackColor: AppColors.primary,
                                thumbColor: AppColors.primary,
                                overlayColor: AppColors.primary.withValues(alpha: 0.2),
                              ),
                              child: Slider(
                                value: clampedTh,
                                min: 0,
                                max: maxVal,
                                divisions: divisionsVal,
                                onChanged: (value) =>
                                    setSheetState(() => threshold = value),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),

                  // Hysteresis Card
                  Text(
                    'ANTI-FLAPPING HYSTERESIS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: hysteresisController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.card,
                      helperText:
                          'Sensor reading must cross this reset margin before retriggering.',
                      helperMaxLines: 2,
                      helperStyle: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Target Relay
                  Text(
                    'TARGET RELAY CHANNEL',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: relay,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.card,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                    items: [
                      ...List.generate(
                        dev.relays.length,
                        (index) => DropdownMenuItem(
                          value: index,
                          child: Row(
                            children: [
                              Icon(Icons.toggle_on_rounded, color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(_relayLabel(dev, index), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 255,
                        child: Row(
                          children: [
                            Icon(Icons.flash_on_rounded, color: AppColors.accent, size: 18),
                            const SizedBox(width: 8),
                            const Text('All relays (Master)', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => relay = value ?? relay),
                  ),
                  const SizedBox(height: 14),

                  // Action Dropdown
                  Text(
                    'TRIGGER ACTION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: action,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.card,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 0,
                        child: Row(
                          children: [
                            Icon(Icons.power_rounded, color: AppColors.success, size: 20),
                            SizedBox(width: 10),
                            Text('Turn ON', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Row(
                          children: [
                            Icon(Icons.power_off_rounded, color: AppColors.danger, size: 20),
                            SizedBox(width: 10),
                            Text('Turn OFF', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setSheetState(() => action = value ?? action),
                  ),
                  const SizedBox(height: 22),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: AppColors.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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
                        final maxThreshold = sensor == 0
                            ? 60.0
                            : (sensor == 1 || sensor == 5
                                  ? 100.0
                                  : (sensor == 2
                                        ? (dev.telemetry.gasMax > 0
                                              ? dev.telemetry.gasMax.toDouble()
                                              : (dev.isEsp8266 ? 1023.0 : 4095.0))
                                        : (sensor == 3
                                              ? 2000.0
                                              : (sensor == 6 ? 1.0 : 100.0))));
                        final rule = AutomationRule(
                          id: existing?.id ?? 0,
                          enabled: existing?.enabled ?? true,
                          name: nameController.text.trim().isEmpty
                              ? 'Auto Rule'
                              : nameController.text.trim(),
                          sensor: sensor,
                          sensorIndex: clampedSensorIdx,
                          condition: condition,
                          threshold: threshold.clamp(0.0, maxThreshold),
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
                            const SnackBar(
                              content: Text('Controller rejected the rule.'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            existing == null ? Icons.check_circle_outline_rounded : Icons.sync_rounded,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            existing == null
                                ? 'Save Rule to Controller'
                                : 'Update Rule on Controller',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
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
    nameController.dispose();
    hysteresisController.dispose();
  }

  Future<void> _showTimerEditor(
    BuildContext context,
    SmartDevice dev, {
    ScheduledAlarm? existing,
    int initialMode = 0,
  }) async {
    if (dev.isGuest) return;
    var mode = (existing?.mode ?? initialMode).clamp(0, 1);
    var scheduleType = (existing?.type ?? 1).clamp(0, 4);
    var dayOfWeek = (existing?.dayOfWeek ?? 1).clamp(0, 6);
    var action = (dev.relays.isEmpty && existing == null)
        ? 3
        : (existing?.action ?? 0).clamp(0, 5);
    final rawRelay = existing?.targetRelay ?? (dev.relays.isEmpty ? 255 : 0);
    var relay = dev.relays.isEmpty
        ? 255
        : ((rawRelay >= 0 && rawRelay < dev.relays.length) ? rawRelay : 0);
    var time = TimeOfDay(
      hour: existing?.hour ?? 8,
      minute: existing?.minute ?? 0,
    );
    int delayHours = (existing?.delayMinutes ?? 30) ~/ 60;
    int delayMinutes = (existing?.delayMinutes ?? 30) % 60;
    final hoursController = TextEditingController(text: '$delayHours');
    final minutesController = TextEditingController(text: '$delayMinutes');

    void syncControllers() {
      hoursController.text = '$delayHours';
      minutesController.text = '$delayMinutes';
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final actionNeedsRelay = action <= 2;
          final totalDelayMinutes = (delayHours * 60) + delayMinutes;

          // Format TimeOfDay for hero clock display
          final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
          final minuteStr = time.minute.toString().padLeft(2, '0');
          final amPm = time.period == DayPeriod.am ? 'AM' : 'PM';
          final formattedClockTime = '${hour12.toString().padLeft(2, '0')}:$minuteStr';

          // Estimated fire time for delay timer
          final estFireDate = DateTime.now().add(Duration(minutes: totalDelayMinutes));
          final estHour = estFireDate.hour == 0 ? 12 : (estFireDate.hour > 12 ? estFireDate.hour - 12 : estFireDate.hour);
          final estMin = estFireDate.minute.toString().padLeft(2, '0');
          final estAmPm = estFireDate.hour >= 12 ? 'PM' : 'AM';
          final estFireString = '$estHour:$estMin $estAmPm';

          // Formatted duration string
          String formattedDuration;
          if (totalDelayMinutes <= 0) {
            formattedDuration = '0m';
          } else if (delayHours > 0 && delayMinutes > 0) {
            formattedDuration = '${delayHours}h ${delayMinutes}m';
          } else if (delayHours > 0) {
            formattedDuration = '${delayHours}h';
          } else {
            formattedDuration = '${delayMinutes}m';
          }

          final viewInsets = MediaQuery.of(sheetContext).viewInsets.bottom;
          final safeBottom = math.max(
            MediaQuery.of(sheetContext).padding.bottom,
            MediaQuery.of(sheetContext).viewPadding.bottom,
          );
          final bottomPadding =
              viewInsets > 0 ? (viewInsets + 16) : (safeBottom + 20);

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.9,
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              bottomPadding,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(
                top: BorderSide(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header with Icon, Title, and Close Button
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGlow,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Icon(
                          existing == null
                              ? Icons.alarm_add_rounded
                              : Icons.edit_calendar_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              existing == null
                                  ? 'New Hardware Timer'
                                  : 'Edit Hardware Timer',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Runs directly on ESP controller flash',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Mode Selector: Fixed Time vs Delay Timer
                  LuxurySegmentedSelector<int>(
                    values: const [0, 1],
                    labels: const {0: 'Fixed Clock Time', 1: 'Delay Countdown'},
                    icons: const {0: Icons.schedule_rounded, 1: Icons.hourglass_top_rounded},
                    selectedValue: mode,
                    onSelected: (value) => setSheetState(() => mode = value),
                  ),
                  const SizedBox(height: 18),

                  // Mode 0: Fixed Time UI
                  if (mode == 0) ...[
                    // Hero Digital Clock Card (Tap to pick time)
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: sheetContext,
                          initialTime: time,
                        );
                        if (picked != null) {
                          setSheetState(() => time = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.35),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryGlow,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.access_time_filled_rounded,
                                color: AppColors.primary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'TRIGGER TIME',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        formattedClockTime,
                                        style: TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.textPrimary,
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        amPm,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: const BoxDecoration(
                                          color: AppColors.success,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'ESP NTP / RTC Clock',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.edit_rounded,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Change',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
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

                    // Repeat Schedule Title & Chips
                    Text(
                      'REPEAT SCHEDULE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildScheduleChip(
                          label: 'Daily',
                          icon: Icons.repeat_rounded,
                          isSelected: scheduleType == 1,
                          onTap: () => setSheetState(() => scheduleType = 1),
                        ),
                        _buildScheduleChip(
                          label: 'Weekdays',
                          icon: Icons.work_outline_rounded,
                          isSelected: scheduleType == 3,
                          onTap: () => setSheetState(() => scheduleType = 3),
                        ),
                        _buildScheduleChip(
                          label: 'Weekends',
                          icon: Icons.weekend_outlined,
                          isSelected: scheduleType == 4,
                          onTap: () => setSheetState(() => scheduleType = 4),
                        ),
                        _buildScheduleChip(
                          label: 'Once Only',
                          icon: Icons.looks_one_outlined,
                          isSelected: scheduleType == 0,
                          onTap: () => setSheetState(() => scheduleType = 0),
                        ),
                        _buildScheduleChip(
                          label: 'Weekly Day',
                          icon: Icons.calendar_today_rounded,
                          isSelected: scheduleType == 2,
                          onTap: () => setSheetState(() => scheduleType = 2),
                        ),
                      ],
                    ),

                    // When "Weekly Day" (scheduleType == 2) is chosen: 7 Days selector
                    if (scheduleType == 2) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SELECT DAY OF WEEK',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildDayCircle('S', 'Sun', 0, dayOfWeek, (d) => setSheetState(() => dayOfWeek = d)),
                                _buildDayCircle('M', 'Mon', 1, dayOfWeek, (d) => setSheetState(() => dayOfWeek = d)),
                                _buildDayCircle('T', 'Tue', 2, dayOfWeek, (d) => setSheetState(() => dayOfWeek = d)),
                                _buildDayCircle('W', 'Wed', 3, dayOfWeek, (d) => setSheetState(() => dayOfWeek = d)),
                                _buildDayCircle('T', 'Thu', 4, dayOfWeek, (d) => setSheetState(() => dayOfWeek = d)),
                                _buildDayCircle('F', 'Fri', 5, dayOfWeek, (d) => setSheetState(() => dayOfWeek = d)),
                                _buildDayCircle('S', 'Sat', 6, dayOfWeek, (d) => setSheetState(() => dayOfWeek = d)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ] else ...[
                    // Mode 1: Delay Timer UI
                    // Hero Duration Display Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: totalDelayMinutes > 0
                              ? AppColors.primary.withValues(alpha: 0.35)
                              : AppColors.cardBorder,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGlow,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.hourglass_top_rounded,
                              color: AppColors.primary,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'COUNTDOWN DURATION',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  formattedDuration,
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textPrimary,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                if (totalDelayMinutes > 0) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.bolt_rounded,
                                        size: 14,
                                        color: AppColors.warning,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Will execute at ~$estFireString',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Quick Presets Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'QUICK PRESETS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.7,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          'Tap to select',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildPresetChip(5, '5m', totalDelayMinutes, (m) {
                            setSheetState(() {
                              delayHours = m ~/ 60;
                              delayMinutes = m % 60;
                              syncControllers();
                            });
                          }),
                          _buildPresetChip(10, '10m', totalDelayMinutes, (m) {
                            setSheetState(() {
                              delayHours = m ~/ 60;
                              delayMinutes = m % 60;
                              syncControllers();
                            });
                          }),
                          _buildPresetChip(15, '15m', totalDelayMinutes, (m) {
                            setSheetState(() {
                              delayHours = m ~/ 60;
                              delayMinutes = m % 60;
                              syncControllers();
                            });
                          }),
                          _buildPresetChip(30, '30m', totalDelayMinutes, (m) {
                            setSheetState(() {
                              delayHours = m ~/ 60;
                              delayMinutes = m % 60;
                              syncControllers();
                            });
                          }),
                          _buildPresetChip(45, '45m', totalDelayMinutes, (m) {
                            setSheetState(() {
                              delayHours = m ~/ 60;
                              delayMinutes = m % 60;
                              syncControllers();
                            });
                          }),
                          _buildPresetChip(60, '1h', totalDelayMinutes, (m) {
                            setSheetState(() {
                              delayHours = m ~/ 60;
                              delayMinutes = m % 60;
                              syncControllers();
                            });
                          }),
                          _buildPresetChip(120, '2h', totalDelayMinutes, (m) {
                            setSheetState(() {
                              delayHours = m ~/ 60;
                              delayMinutes = m % 60;
                              syncControllers();
                            });
                          }),
                          _buildPresetChip(240, '4h', totalDelayMinutes, (m) {
                            setSheetState(() {
                              delayHours = m ~/ 60;
                              delayMinutes = m % 60;
                              syncControllers();
                            });
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Dual Stepper Cards: Hours & Minutes
                    Row(
                      children: [
                        Expanded(
                          child: _buildStepperBox(
                            label: 'HOURS',
                            controller: hoursController,
                            value: delayHours,
                            onMinus: () {
                              if (delayHours > 0) {
                                setSheetState(() {
                                  delayHours--;
                                  hoursController.text = '$delayHours';
                                });
                              }
                            },
                            onPlus: () {
                              if (delayHours < 72) {
                                setSheetState(() {
                                  delayHours++;
                                  hoursController.text = '$delayHours';
                                });
                              }
                            },
                            onChanged: (val) {
                              setSheetState(() {
                                delayHours = int.tryParse(val.trim()) ?? delayHours;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStepperBox(
                            label: 'MINUTES',
                            controller: minutesController,
                            value: delayMinutes,
                            onMinus: () {
                              if (delayMinutes > 0) {
                                setSheetState(() {
                                  delayMinutes--;
                                  minutesController.text = '$delayMinutes';
                                });
                              }
                            },
                            onPlus: () {
                              if (delayMinutes < 59) {
                                setSheetState(() {
                                  delayMinutes++;
                                  minutesController.text = '$delayMinutes';
                                });
                              }
                            },
                            onChanged: (val) {
                              setSheetState(() {
                                delayMinutes = int.tryParse(val.trim()) ?? delayMinutes;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Explanation Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cardBorder, width: 0.8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: AppColors.primaryLight,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'A delay timer runs once from activation and auto-disarms upon completion.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Action Dropdown
                  Text(
                    'TRIGGER ACTION',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: action,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.card,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: AppColors.cardBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Row(
                          children: [
                            Icon(Icons.power_rounded, color: AppColors.success, size: 20),
                            SizedBox(width: 10),
                            Text('Turn relay ON', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Row(
                          children: [
                            Icon(Icons.power_off_rounded, color: AppColors.danger, size: 20),
                            SizedBox(width: 10),
                            Text('Turn relay OFF', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz_rounded, color: AppColors.primaryLight, size: 20),
                            SizedBox(width: 10),
                            Text('Toggle relay', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 3,
                        child: Row(
                          children: [
                            Icon(Icons.notifications_active_rounded, color: AppColors.warning, size: 20),
                            SizedBox(width: 10),
                            Text('Sound buzzer', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 4,
                        child: Row(
                          children: [
                            Icon(Icons.flash_on_rounded, color: AppColors.success, size: 20),
                            SizedBox(width: 10),
                            Text('Turn ALL relays ON', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 5,
                        child: Row(
                          children: [
                            Icon(Icons.flash_off_rounded, color: AppColors.danger, size: 20),
                            SizedBox(width: 10),
                            Text('Turn ALL relays OFF', style: TextStyle(fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) => setSheetState(() {
                      action = value ?? action;
                      if (action > 2) {
                        relay = 255;
                      } else if (relay == 255 && dev.relays.isNotEmpty) {
                        relay = 0;
                      }
                    }),
                  ),

                  // Target Relay Channel
                  if (actionNeedsRelay) ...[
                    const SizedBox(height: 14),
                    Text(
                      'TARGET RELAY CHANNEL',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (dev.relays.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.45),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'No relay channels on this Sensor Node. Choose "Sound buzzer" or "Turn ALL relays ON/OFF".',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<int>(
                        initialValue: (relay >= 0 && relay < dev.relays.length)
                            ? relay
                            : 0,
                        dropdownColor: AppColors.surfaceElevated,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.card,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.cardBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.cardBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        items: List.generate(
                          dev.relays.length,
                          (index) {
                            final r = dev.relays[index];
                            return DropdownMenuItem(
                              value: index,
                              child: Row(
                                children: [
                                  Icon(
                                    r.state ? Icons.bolt_rounded : Icons.power_outlined,
                                    color: r.state ? AppColors.accent : AppColors.textMuted,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _relayLabel(dev, index),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        onChanged: (value) =>
                            setSheetState(() => relay = value ?? relay),
                      ),
                  ],
                  const SizedBox(height: 22),

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: AppColors.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () async {
                        if (actionNeedsRelay && dev.relays.isEmpty) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Sensor Node has no relays. Select "Sound buzzer" or "Turn ALL relays ON/OFF".',
                              ),
                              backgroundColor: AppColors.warning,
                            ),
                          );
                          return;
                        }
                        final hoursText = hoursController.text.trim();
                        final minutesText = minutesController.text.trim();
                        final hours = hoursText.isEmpty ? 0 : (int.tryParse(hoursText) ?? -1);
                        final minutes = minutesText.isEmpty ? 0 : (int.tryParse(minutesText) ?? -1);
                        final delay = (hours * 60) + minutes;
                        if (mode == 1 &&
                            (hours < 0 ||
                                minutes < 0 ||
                                delay <= 0)) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Set a delay of at least one minute.',
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
                            const SnackBar(
                              content: Text(
                                'Controller rejected the timer.',
                              ),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            existing == null
                                ? Icons.check_circle_outline_rounded
                                : Icons.sync_rounded,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            existing == null
                                ? 'Save Timer to Controller'
                                : 'Update Timer on Controller',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
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
    hoursController.dispose();
    minutesController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final dev = _resolveDevice(devices);
    final isVisible =
        widget.preselectedDeviceId != null ||
        ref.watch(navigationIndexProvider) == 2;
    final isDark = AppColors.isDark;

    // MainShell retains tabs in an IndexedStack. Trigger initial load when
    // tab 2 is visible or when AutomationsScreen was pushed for a specific controller.
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
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sensors_rounded, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Sensor Rules',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (_rules.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.18)
                                : AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_rules.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Timers & Schedules',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_alarms.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.18)
                                : AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_alarms.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // Only show Floating Action Button when there ARE active rules and Admin access
      floatingActionButton: (dev != null && !dev.isGuest && hasItemsInCurrentTab)
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
                                      Flexible(
                                        child: Text(
                                          d.name,
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: AppColors.textPrimary,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (d.room.trim().isNotEmpty &&
                                          d.room.trim().toLowerCase() !=
                                              d.name.trim().toLowerCase()) ...[
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

                if (dev.isGuest)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 16,
                            color: AppColors.warning,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'View only: Administrator credentials required to create, toggle, or delete rules & timers.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
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
                onPressed: dev.isGuest
                    ? null
                    : () => _showRuleEditor(context, dev),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _rules.length,
      itemBuilder: (ctx, idx) {
        final rule = _rules[idx];
        final rName = _relayLabel(dev, rule.targetRelay);

        Color sColor = AppColors.tempAmber;
        IconData sIcon = Icons.thermostat;
        final sIdx = rule.sensorIndex;
        final tel = dev.telemetry;
        final tempVal = (sIdx >= 0 && sIdx < tel.climates.length)
            ? tel.climates[sIdx].temperature
            : (sIdx == 0 ? tel.temperature : null);
        String liveSensorValue = tempVal != null
            ? '${tempVal.toStringAsFixed(1)} °C'
            : 'N/A';
        if (rule.sensor == 1) {
          sColor = AppColors.humCyan;
          sIcon = Icons.water_drop;
          final humVal = (sIdx >= 0 && sIdx < tel.climates.length)
              ? tel.climates[sIdx].humidity
              : (sIdx == 0 ? tel.humidity : null);
          liveSensorValue = humVal != null
              ? '${humVal.toStringAsFixed(1)} %'
              : 'N/A';
        } else if (rule.sensor == 2) {
          sColor = AppColors.danger;
          sIcon = Icons.warning;
          final gasVal = (sIdx >= 0 && sIdx < tel.mq2s.length)
              ? tel.mq2s[sIdx].raw
              : (sIdx == 0 ? tel.gasRaw : null);
          liveSensorValue = gasVal != null ? '$gasVal ADC' : 'N/A';
        } else if (rule.sensor == 3) {
          sColor = Colors.amber;
          sIcon = Icons.wb_sunny;
          final luxVal = (sIdx >= 0 && sIdx < tel.lights.length)
              ? tel.lights[sIdx].lux
              : (sIdx == 0 ? tel.lux : null);
          liveSensorValue = luxVal != null
              ? '${luxVal.toStringAsFixed(1)} lx'
              : 'N/A';
        } else if (rule.sensor == 4) {
          sColor = Colors.cyan;
          sIcon = Icons.device_thermostat;
          final probeVal = (sIdx >= 0 && sIdx < tel.probes.length)
              ? tel.probes[sIdx].temperature
              : (sIdx == 0 ? tel.probeTemp : null);
          liveSensorValue = probeVal != null
              ? '${probeVal.toStringAsFixed(1)} °C'
              : 'N/A';
        } else if (rule.sensor == 5) {
          sColor = Colors.blue;
          sIcon = Icons.waves;
          final tankVal = (sIdx >= 0 && sIdx < tel.tanks.length)
              ? tel.tanks[sIdx].levelPct
              : (sIdx == 0 ? tel.tankLevelPct : null);
          liveSensorValue = tankVal != null ? '$tankVal %' : 'N/A';
        } else if (rule.sensor == 6) {
          sColor = AppColors.warning;
          sIcon = Icons.directions_run;
          final motionDet = (sIdx >= 0 && sIdx < tel.motions.length)
              ? tel.motions[sIdx].detected
              : (sIdx == 0 ? tel.motionDetected : null);
          liveSensorValue = motionDet == null
              ? 'N/A'
              : (motionDet ? 'MOTION' : 'CLEAR');
        }

        final isTriggered =
            rule.enabled &&
            (rule.triggered ||
                dev.relays.any((r) => r.activeRule == rule.name));

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            padding: EdgeInsets.zero,
            borderColor: isTriggered
                ? AppColors.warning
                : (rule.enabled
                      ? AppColors.accent.withValues(alpha: 0.35)
                      : AppColors.cardBorder),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ═══ Top Section ═══
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: rule.enabled
                              ? sColor.withValues(alpha: 0.15)
                              : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: rule.enabled
                                ? sColor.withValues(alpha: 0.3)
                                : AppColors.cardBorder,
                          ),
                        ),
                        child: Icon(sIcon, color: rule.enabled ? sColor : AppColors.textMuted, size: 20),
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
                                      color: rule.enabled
                                          ? AppColors.textPrimary
                                          : AppColors.textMuted,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isTriggered
                                        ? AppColors.warning.withValues(alpha: 0.18)
                                        : (rule.enabled
                                              ? AppColors.success.withValues(alpha: 0.14)
                                              : AppColors.surfaceElevated),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isTriggered
                                          ? AppColors.warning.withValues(alpha: 0.5)
                                          : (rule.enabled
                                                ? AppColors.success.withValues(alpha: 0.4)
                                                : AppColors.cardBorder),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: isTriggered
                                              ? AppColors.warning
                                              : (rule.enabled
                                                    ? AppColors.success
                                                    : AppColors.textMuted),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        isTriggered
                                            ? 'TRIGGERED'
                                            : (rule.enabled ? 'ARMED' : 'PAUSED'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                          color: isTriggered
                                              ? AppColors.warning
                                              : (rule.enabled
                                                    ? AppColors.success
                                                    : AppColors.textMuted),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.tune_rounded,
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'IF ${rule.sensorLabel} ${rule.condition == 0 ? "≥" : "≤"} ${rule.threshold.toStringAsFixed((rule.sensor == 2 || rule.sensor == 6) ? 0 : 1)}${rule.unit}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '  •  ',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  'Live: $liveSensorValue',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isTriggered
                                        ? AppColors.warning
                                        : sColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: rule.enabled,
                        activeThumbColor: AppColors.success,
                        onChanged: dev.isGuest
                            ? null
                            : (v) => _toggleRule(dev, rule, v),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(
                    color: AppColors.cardBorder.withValues(alpha: 0.5),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 10),

                // ═══ Bottom Section: Action chip + Edit/Delete ═══
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: (rule.action == 0
                                      ? AppColors.success
                                      : AppColors.danger)
                                  .withValues(alpha: rule.enabled ? 0.1 : 0.06),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: (rule.action == 0
                                        ? AppColors.success
                                        : AppColors.danger)
                                    .withValues(alpha: rule.enabled ? 0.3 : 0.15),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  rule.action == 0
                                      ? Icons.power_rounded
                                      : Icons.power_off_rounded,
                                  size: 14,
                                  color: (rule.action == 0
                                          ? AppColors.success
                                          : AppColors.danger)
                                      .withValues(alpha: rule.enabled ? 1.0 : 0.5),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'THEN ${rule.actionLabel}: $rName',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: (rule.action == 0
                                              ? AppColors.success
                                              : AppColors.danger)
                                          .withValues(alpha: rule.enabled ? 1.0 : 0.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Edit rule',
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: dev.isGuest
                            ? null
                            : () => _showRuleEditor(context, dev, rule),
                      ),
                      IconButton(
                        tooltip: 'Delete rule',
                        icon: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: dev.isGuest
                              ? AppColors.textMuted
                              : AppColors.danger,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: dev.isGuest
                            ? null
                            : () => _deleteRule(dev, rule),
                      ),
                    ],
                  ),
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
                onPressed: dev.isGuest
                    ? null
                    : () => _showTimerEditor(context, dev),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: _alarms.length,
      itemBuilder: (ctx, idx) {
        final a = _alarms[idx];
        final rName = _relayLabel(dev, a.targetRelay);
        final isDelay = a.mode == 1;
        final title = isDelay
            ? _delayLabel(a.delayMinutes)
            : _formatAlarmTime(a.hour, a.minute);
        final actionText = a.action <= 2
            ? '${a.actionLabel} $rName'
            : a.actionLabel;

        // Status state
        final bool isFired = isDelay && a.fired;
        final bool isCompleted = !isDelay && a.type == 0 && a.fired;
        final String statusText = !a.enabled
            ? 'PAUSED'
            : (isFired || isCompleted)
                ? 'COMPLETED'
                : 'ARMED';
        final Color statusColor = !a.enabled
            ? AppColors.textMuted
            : (isFired || isCompleted)
                ? AppColors.warning
                : AppColors.success;

        // Action colors
        Color actionColor;
        IconData actionIcon;
        switch (a.action) {
          case 0:
          case 4:
            actionColor = AppColors.success;
            actionIcon = Icons.power_rounded;
            break;
          case 1:
          case 5:
            actionColor = AppColors.danger;
            actionIcon = Icons.power_off_rounded;
            break;
          case 2:
            actionColor = AppColors.primaryLight;
            actionIcon = Icons.swap_horiz_rounded;
            break;
          case 3:
          default:
            actionColor = AppColors.warning;
            actionIcon = Icons.notifications_active_rounded;
            break;
        }

        // When paused, mute action colors
        final effectiveActionColor = a.enabled
            ? actionColor
            : actionColor.withValues(alpha: 0.45);

        // Subtitle pieces
        final String typeLabel = isDelay
            ? 'One-shot countdown'
            : a.typeLabel;

        // Only show next run badge for fixed-time armed timers
        final bool showNextRun = a.enabled &&
            !isDelay &&
            !isCompleted &&
            a.nextRunBadge.isNotEmpty &&
            !a.nextRunBadge.toLowerCase().contains('paused');

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            padding: EdgeInsets.zero,
            borderColor: a.enabled
                ? (isFired || isCompleted)
                    ? AppColors.warning.withValues(alpha: 0.4)
                    : AppColors.primary.withValues(alpha: 0.35)
                : AppColors.cardBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ═══ Top Section: Title + Status + Switch ═══
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                  child: Row(
                    children: [
                      // Icon bubble
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: a.enabled
                              ? (isFired || isCompleted)
                                  ? AppColors.warning.withValues(alpha: 0.12)
                                  : AppColors.primaryGlow
                              : AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: a.enabled
                                ? (isFired || isCompleted)
                                    ? AppColors.warning.withValues(alpha: 0.3)
                                    : AppColors.primary.withValues(alpha: 0.3)
                                : AppColors.cardBorder,
                          ),
                        ),
                        child: Icon(
                          isDelay
                              ? Icons.hourglass_top_rounded
                              : Icons.alarm_rounded,
                          color: a.enabled
                              ? (isFired || isCompleted)
                                  ? AppColors.warning
                                  : AppColors.primary
                              : AppColors.textMuted,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Title + subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: isDelay ? 24 : 22,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: isDelay ? -0.5 : -0.3,
                                      color: a.enabled
                                          ? AppColors.textPrimary
                                          : AppColors.textMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // Status badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: statusColor.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: statusColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        statusText,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.4,
                                          color: statusColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Subtitle row: type + optional next run
                            Row(
                              children: [
                                Icon(
                                  isDelay
                                      ? Icons.timer_outlined
                                      : Icons.repeat_rounded,
                                  size: 12,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  typeLabel,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (showNextRun) ...[
                                  Text(
                                    '  •  ',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Flexible(
                                    child: Text(
                                      a.nextRunBadge,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primaryLight,
                                      ),
                                    ),
                                  ),
                                ],
                                if (isDelay && a.enabled && !isFired) ...[
                                  Text(
                                    '  •  ',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    'Counting down',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primaryLight,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Switch
                      Switch(
                        value: a.enabled,
                        activeThumbColor: AppColors.success,
                        onChanged: dev.isGuest
                            ? null
                            : (v) => _toggleAlarm(dev, a, v),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(
                    color: AppColors.cardBorder.withValues(alpha: 0.5),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 10),

                // ═══ Bottom Section: Action chip + Edit/Delete ═══
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 12),
                  child: Row(
                    children: [
                      // Action chip (content-hugging, not stretched)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: effectiveActionColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: effectiveActionColor.withValues(
                                  alpha: a.enabled ? 0.3 : 0.15,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  actionIcon,
                                  size: 14,
                                  color: effectiveActionColor,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    actionText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: effectiveActionColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Edit & Delete buttons
                      IconButton(
                        tooltip: 'Edit timer',
                        icon: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: dev.isGuest
                            ? null
                            : () => _showTimerEditor(
                                context,
                                dev,
                                existing: a,
                              ),
                      ),
                      IconButton(
                        tooltip: 'Delete timer',
                        icon: Icon(
                          Icons.delete_outline,
                          color: dev.isGuest
                              ? AppColors.textMuted
                              : AppColors.danger,
                          size: 18,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: dev.isGuest
                            ? null
                            : () => _deleteAlarm(dev, a),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
