import 'package:flutter/material.dart';
import '../../core/models/relay_channel.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import 'luxury_segmented_selector.dart';

class RelayConfigSheet extends StatefulWidget {
  final SmartDevice device;
  final RelayChannel relay;
  final DeviceManager manager;

  const RelayConfigSheet({
    super.key,
    required this.device,
    required this.relay,
    required this.manager,
  });

  static void show(BuildContext context, SmartDevice device, RelayChannel relay, DeviceManager manager) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RelayConfigSheet(
        device: device,
        relay: relay,
        manager: manager,
      ),
    );
  }

  @override
  State<RelayConfigSheet> createState() => _RelayConfigSheetState();
}

class _RelayConfigSheetState extends State<RelayConfigSheet> {
  late TextEditingController _nameController;
  late String _iconType;
  late int _triggerMode; // 0: Active LOW, 1: Active HIGH
  late int _bootState; // 0: Restore Last (BOOT_RESTORE_LAST), 1: Always ON (BOOT_ALWAYS_ON), 2: Always OFF (BOOT_ALWAYS_OFF)
  late int _autoOffMinutes;
  late int _autoOnMinutes;
  late bool _failsafe;
  bool _isSaving = false;
  bool _isLoading = false;
  bool _isSynced = false;

  static const List<Map<String, dynamic>> _applianceCategories = [
    {'id': 'light', 'label': 'Light', 'icon': Icons.lightbulb_outline},
    {'id': 'fan', 'label': 'Ceiling Fan', 'icon': Icons.wind_power_rounded},
    {'id': 'ac', 'label': 'Air Cond.', 'icon': Icons.ac_unit_rounded},
    {'id': 'geyser', 'label': 'Geyser', 'icon': Icons.hot_tub_rounded},
    {'id': 'tv', 'label': 'Television', 'icon': Icons.tv_rounded},
    {'id': 'socket', 'label': 'Socket', 'icon': Icons.electrical_services_rounded},
    {'id': 'pump', 'label': 'Water Pump', 'icon': Icons.water_drop_outlined},
    {'id': 'router', 'label': 'Router', 'icon': Icons.router_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.relay.name);
    _iconType = widget.relay.iconType.toLowerCase();
    _triggerMode = widget.relay.trigger;
    _bootState = widget.relay.boot;
    _autoOffMinutes = widget.relay.autoOff;
    _autoOnMinutes = widget.relay.autoOn;
    _failsafe = widget.relay.failsafe;

    // Immediately fetch fresh hardware config from physical ESP32
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchLiveConfig();
    });
  }

  Future<void> _fetchLiveConfig() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final relays = await widget.manager.fetchDeviceRelays(widget.device.id);
    if (!mounted) return;
    if (relays != null && widget.relay.index < relays.length) {
      final live = relays[widget.relay.index];
      setState(() {
        _nameController.text = live.name;
        _iconType = live.iconType.toLowerCase();
        _triggerMode = live.trigger;
        _bootState = live.boot;
        _autoOffMinutes = live.autoOff;
        _autoOnMinutes = live.autoOn;
        _failsafe = live.failsafe;
        _isLoading = false;
        _isSynced = true;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final ok = await widget.manager.saveRelayHardwareConfig(
      widget.device.id,
      widget.relay.index,
      {
        'name': _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : widget.relay.name,
        'icon': _iconType,
        'trigger': _triggerMode,
        'boot': _bootState,
        'autoOff': _autoOffMinutes,
        'autoOn': _autoOnMinutes,
        'failsafe': _failsafe,
      },
    );
    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Relay hardware config saved to controller flash!' : 'Failed to update relay config'),
          backgroundColor: ok ? AppColors.success : AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom +
        20;
    final isDark = AppColors.isDark;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: bottomPadding,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.settings_suggest_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Relay ${widget.relay.index + 1} Hardware Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        widget.device.name,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : Icon(
                          Icons.sync_rounded,
                          color: _isSynced ? AppColors.success : AppColors.primary,
                        ),
                  tooltip: 'Sync live from controller',
                  onPressed: _isLoading ? null : _fetchLiveConfig,
                ),
                IconButton(
                  icon: Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            if (_isLoading)
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Fetching active configuration from controller flash...',
                        style: TextStyle(fontSize: 12, color: AppColors.primaryLight, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )
            else if (_isSynced)
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Synced with live controller hardware flash memory',
                        style: TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),

            // Channel Label Input (Sleek filled card, zero harsh lines!)
            Text(
              'Channel Label',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder, width: 1),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.label_outline_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'e.g. Living Room Lamp',
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Appliance Category & Icon Picker
            Text(
              'Appliance Category & Icon',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _applianceCategories.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.15,
              ),
              itemBuilder: (context, idx) {
                final cat = _applianceCategories[idx];
                final id = cat['id'] as String;
                final label = cat['label'] as String;
                final icon = cat['icon'] as IconData;
                final isSelected = _iconType == id;
                return GestureDetector(
                  onTap: () => setState(() => _iconType = id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryGlow : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.cardBorder,
                        width: isSelected ? 1.6 : 1.0,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            color: isSelected ? AppColors.primary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),

            // Hardware Trigger Polarity (iOS-style segmented pill selector)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hardware Trigger Polarity',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary),
                ),
                Text(
                  _triggerMode == 0 ? 'Active LOW (Standard)' : 'Active HIGH',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Match the physical relay board logic (Active LOW is standard for optocouplers).',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            LuxurySegmentedSelector<int>(
              values: const [0, 1],
              labels: const {
                0: 'Active LOW ',
                1: 'Active HIGH ',
              },
              selectedValue: _triggerMode,
              onSelected: (val) => setState(() => _triggerMode = val),
            ),
            const SizedBox(height: 18),

            // Power-Outage Boot State (iOS-style segmented pill selector)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Power-Outage Boot State',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary),
                ),
                Text(
                  _bootState == 0 ? 'Restore Last State' : (_bootState == 1 ? 'Always ON' : 'Always OFF'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'State of this relay immediately after power loss recovery.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            LuxurySegmentedSelector<int>(
              values: const [0, 1, 2],
              labels: const {
                0: 'Restore Last',
                1: 'Always ON',
                2: 'Always OFF',
              },
              selectedValue: _bootState,
              onSelected: (val) => setState(() => _bootState = val),
            ),
            const SizedBox(height: 18),

            // Auto-Off & Auto-On Timers (Sleek filled dropdowns, zero harsh black lines!)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto-OFF Timer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      _buildLuxuryDropdown(
                        value: _autoOffMinutes,
                        onChanged: (v) => setState(() => _autoOffMinutes = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Auto-ON Timer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      _buildLuxuryDropdown(
                        value: _autoOnMinutes,
                        onChanged: (v) => setState(() => _autoOnMinutes = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Failsafe Mode Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder, width: 1),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _failsafe ? AppColors.successGlow : AppColors.cardBorder.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      color: _failsafe ? AppColors.success : AppColors.textMuted,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Failsafe Shutdown',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                        ),
                        Text(
                          'Auto-shutoff if sensors report fault or gas alarm triggers',
                          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _failsafe,
                    activeThumbColor: AppColors.success,
                    activeTrackColor: AppColors.success.withValues(alpha: 0.35),
                    inactiveThumbColor: isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                    inactiveTrackColor: AppColors.surfaceElevated,
                    onChanged: (v) => setState(() => _failsafe = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Save to Flash Button (Full-width luxury button, floating cleanly above system nav bar!)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: AppColors.primary.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.save_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Save to Hardware Flash',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: -0.2),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLuxuryDropdown({
    required int value,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surfaceElevated,
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary, size: 20),
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Disabled')),
            DropdownMenuItem(value: 5, child: Text('5 minutes')),
            DropdownMenuItem(value: 15, child: Text('15 minutes')),
            DropdownMenuItem(value: 30, child: Text('30 minutes')),
            DropdownMenuItem(value: 60, child: Text('1 hour')),
            DropdownMenuItem(value: 120, child: Text('2 hours')),
            DropdownMenuItem(value: 360, child: Text('6 hours')),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
