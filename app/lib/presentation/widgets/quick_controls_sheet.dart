import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/relay_channel.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import '../../services/native_controls_service.dart';
import 'glass_card.dart';

class QuickControlsSheet extends ConsumerStatefulWidget {
  final int? initialSlot;
  final String? prefillDeviceId;
  final int? prefillRelayId;

  const QuickControlsSheet({
    super.key,
    this.initialSlot,
    this.prefillDeviceId,
    this.prefillRelayId,
  });

  static void show(
    BuildContext context, {
    int? initialSlot,
    String? prefillDeviceId,
    int? prefillRelayId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => QuickControlsSheet(
        initialSlot: initialSlot,
        prefillDeviceId: prefillDeviceId,
        prefillRelayId: prefillRelayId,
      ),
    );
  }

  @override
  ConsumerState<QuickControlsSheet> createState() => _QuickControlsSheetState();
}

class _QuickControlsSheetState extends ConsumerState<QuickControlsSheet> {
  final NativeControlsService _native = NativeControlsService.instance;
  List<QuickTileSlotConfig> _slots = List.generate(
    12,
    (i) => QuickTileSlotConfig(slot: i + 1),
  );
  NativePlatformCapabilities _caps = const NativePlatformCapabilities();
  bool _loading = true;
  bool _handledInitialPrompt = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final devices = ref.read(deviceManagerProvider);
    await _native.syncDevices(devices, force: true);
    final results = await Future.wait([
      _native.getPlatformCapabilities(),
      _native.getTileSlots(),
    ]);
    if (!mounted) return;
    setState(() {
      _caps = results[0] as NativePlatformCapabilities;
      final fetched = results[1] as List<QuickTileSlotConfig>;
      if (fetched.isNotEmpty) _slots = fetched;
      _loading = false;
    });

    if (!_handledInitialPrompt && widget.initialSlot != null) {
      _handledInitialPrompt = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final slotNum = widget.initialSlot!.clamp(1, 12);
        final slotCfg = _slots.firstWhere(
          (s) => s.slot == slotNum,
          orElse: () => QuickTileSlotConfig(slot: slotNum),
        );
        _openSlotEditor(slotCfg);
      });
    }
  }

  IconData _relayIcon(String? iconType, int? relayId) {
    if (relayId == -1) return Icons.power_settings_new_rounded;
    switch (iconType?.toLowerCase()) {
      case 'fan':
        return Icons.wind_power_rounded;
      case 'ac':
        return Icons.ac_unit_rounded;
      case 'geyser':
      case 'heater':
        return Icons.hot_tub_rounded;
      case 'tv':
        return Icons.tv_rounded;
      case 'socket':
      case 'plug':
        return Icons.electrical_services_rounded;
      case 'pump':
        return Icons.water_drop_outlined;
      case 'router':
        return Icons.router_rounded;
      default:
        return Icons.lightbulb_outline;
    }
  }

  SmartDevice? _findDevice(List<SmartDevice> devices, String? deviceId) {
    if (deviceId == null) return null;
    for (final d in devices) {
      if (d.id == deviceId) return d;
    }
    return null;
  }

  RelayChannel? _findRelay(SmartDevice? dev, int? relayId) {
    if (dev == null || relayId == null || relayId < 0) return null;
    for (final r in dev.relays) {
      if (r.id == relayId) return r;
    }
    return null;
  }

  Future<void> _autoAssignAll() async {
    final devices = ref.read(deviceManagerProvider);
    await _native.syncDevices(devices, force: true);
    final count = await _native.autoAssignTileSlots();
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'Assigned $count Quick Settings tile(s). Drag them in your phone Quick Settings Edit drawer.'
              : 'No enabled relays found on paired controllers.',
        ),
        backgroundColor: count > 0 ? AppColors.success : AppColors.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clearSlot(int slot) async {
    await _native.clearTileSlot(slot);
    await _loadData();
  }

  Future<void> _assignQuickRelayToSlot(int slot) async {
    final devId = widget.prefillDeviceId;
    final relayId = widget.prefillRelayId;
    if (devId == null || relayId == null) return;
    final devices = ref.read(deviceManagerProvider);
    await _native.syncDevices(devices, force: true);
    final ok = await _native.setTileSlot(
      slot: slot,
      deviceId: devId,
      relayId: relayId,
    );
    await _loadData();
    if (!mounted) return;
    if (ok) {
      final dev = _findDevice(devices, devId);
      final relay = _findRelay(dev, relayId);
      final name = relay?.name ?? 'All Relays';
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pinned "$name" to Quick Settings Tile $slot.',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openSlotEditor(QuickTileSlotConfig current) async {
    final devices = ref.read(deviceManagerProvider);
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pair at least one controller first before assigning a tile.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    String selectedDevId =
        _findDevice(devices, current.deviceId)?.id ??
        _findDevice(devices, widget.prefillDeviceId)?.id ??
        devices.first.id;
    int selectedRelayId =
        current.relayId ?? widget.prefillRelayId ?? 0;

    final labelController = TextEditingController(
      text: current.customLabel ?? '',
    );

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final dev = _findDevice(devices, selectedDevId) ?? devices.first;
          final enabledRelays = dev.relays.where((r) => r.enabled).toList();
          final validRelayIds = <int>{
            ...enabledRelays.map((r) => r.id),
            if (enabledRelays.isNotEmpty) -1,
          };
          if (!validRelayIds.contains(selectedRelayId)) {
            selectedRelayId = enabledRelays.isNotEmpty ? enabledRelays.first.id : -1;
          }

          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.widgets_outlined, color: AppColors.primary),
                const SizedBox(width: 10),
                Text(
                  'Configure Tile ${current.slot}',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: dev.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Controller',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: devices
                        .map(
                          (d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(
                              '${d.name} (${d.room})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setDlgState(() {
                        selectedDevId = val;
                        final nextDev = _findDevice(devices, val);
                        final firstEnabled = nextDev?.relays
                            .where((r) => r.enabled)
                            .firstOrNull;
                        selectedRelayId = firstEnabled?.id ?? -1;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: selectedRelayId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Relay / Load',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      ...enabledRelays.map(
                        (r) => DropdownMenuItem<int>(
                          value: r.id,
                          child: Row(
                            children: [
                              Icon(
                                _relayIcon(r.iconType, r.id),
                                size: 18,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  r.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const DropdownMenuItem<int>(
                        value: -1,
                        child: Row(
                          children: [
                            Icon(
                              Icons.power_settings_new_rounded,
                              size: 18,
                              color: AppColors.warning,
                            ),
                            SizedBox(width: 8),
                            Text('All Relays (Master Toggle)'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDlgState(() => selectedRelayId = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelController,
                    maxLength: 24,
                    decoration: const InputDecoration(
                      labelText: 'Custom Tile Name (Optional)',
                      hintText: 'Leave blank to use Relay name',
                      border: OutlineInputBorder(),
                      isDense: true,
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (current.isAssigned)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx, false);
                    await _clearSlot(current.slot);
                  },
                  child: const Text(
                    'Clear',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  await _native.syncDevices(devices, force: true);
                  await _native.setTileSlot(
                    slot: current.slot,
                    deviceId: selectedDevId,
                    relayId: selectedRelayId,
                    customLabel: labelController.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text('Save Tile'),
              ),
            ],
          );
        },
      ),
    );
    labelController.dispose();

    if (saved == true && mounted) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final bool isPinMode =
        widget.prefillDeviceId != null && widget.prefillRelayId != null;
    final pinDev = _findDevice(devices, widget.prefillDeviceId);
    final pinRelay = _findRelay(pinDev, widget.prefillRelayId);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1.5)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).padding.bottom + 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.dashboard_customize_rounded,
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
                      isPinMode
                          ? 'Pin "${pinRelay?.name ?? 'All Relays'}" to Tile'
                          : 'Mobile Quick Controls',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      isPinMode
                          ? 'Tap any Quick Settings Tile slot below to assign it'
                          : 'Quick Settings Tiles & Android Device Controls',
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
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GlassCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _caps.supportsDeviceControls
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                      size: 16,
                      color: _caps.supportsDeviceControls
                          ? AppColors.success
                          : AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Android Device Controls (${_caps.supportsDeviceControls ? 'Active' : 'Android 11+'})',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'All enabled relays are automatically published to your phone\'s "Device controls" menu (Quick Settings -> Device controls -> Add controls -> SmartHome Pro).',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                if (!isPinMode) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primary),
                        foregroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: devices.isEmpty ? null : _autoAssignAll,
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 17),
                      label: const Text(
                        'Auto-Assign Enabled Relays to Tiles',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'QUICK SETTINGS TILES (1–12) • Drag in Phone Edit Drawer',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: _slots.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final cfg = _slots[idx];
                      final dev = _findDevice(devices, cfg.deviceId);
                      final relay = _findRelay(dev, cfg.relayId);
                      final bool assigned = cfg.isAssigned && dev != null;
                      final title = !assigned
                          ? 'Tile ${cfg.slot} (Unassigned)'
                          : (cfg.customLabel?.isNotEmpty == true
                                ? cfg.customLabel!
                                : (cfg.relayId == -1
                                      ? '${dev.name} • All Relays'
                                      : (relay?.name ??
                                            'Relay ${(cfg.relayId ?? 0) + 1}')));
                      final subtitle = !assigned
                          ? (isPinMode
                                ? 'Tap to pin "${pinRelay?.name ?? 'All Relays'}" here'
                                : 'Tap to choose relay')
                          : '${dev.name} (${dev.room}) • Tile ${cfg.slot}';

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => isPinMode
                            ? _assignQuickRelayToSlot(cfg.slot)
                            : _openSlotEditor(cfg),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: assigned
                                ? AppColors.primary.withValues(alpha: 0.08)
                                : AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: assigned
                                  ? AppColors.primary.withValues(alpha: 0.35)
                                  : AppColors.cardBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: assigned
                                      ? AppColors.primaryGlow
                                      : AppColors.card,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  assigned
                                      ? _relayIcon(relay?.iconType, cfg.relayId)
                                      : Icons.add_box_outlined,
                                  size: 19,
                                  color: assigned
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13.5,
                                        color: assigned
                                            ? AppColors.textPrimary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (assigned && !isPinMode)
                                IconButton(
                                  tooltip: 'Clear Tile ${cfg.slot}',
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: AppColors.textMuted,
                                  ),
                                  onPressed: () => _clearSlot(cfg.slot),
                                )
                              else
                                Icon(
                                  isPinMode
                                      ? Icons.push_pin_outlined
                                      : Icons.chevron_right_rounded,
                                  size: 20,
                                  color: AppColors.textMuted,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
