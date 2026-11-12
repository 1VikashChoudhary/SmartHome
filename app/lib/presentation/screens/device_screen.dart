import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import '../widgets/relay_tile.dart';
import '../widgets/telemetry_gauge.dart';
import '../widgets/device_tools_sheet.dart';
import '../widgets/relay_config_sheet.dart';
import '../widgets/controller_login_dialog.dart';
import 'automations_screen.dart';
import 'batch_ota_screen.dart';

class DeviceScreen extends ConsumerStatefulWidget {
  final String deviceId;

  const DeviceScreen({super.key, required this.deviceId});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceManagerProvider.notifier).fetchDeviceRelays(widget.deviceId);
      ref.read(deviceManagerProvider.notifier).fetchDeviceConfig(widget.deviceId);
    });
  }

  static const List<String> _commonRooms = [
    'Living Room',
    'Bedroom',
    'Kitchen',
    'Office',
    'Balcony',
    'Bathroom',
    'Hallway',
    'Garage',
  ];

  void _showRenameDialog(BuildContext context, SmartDevice device) {
    if (device.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Forbidden: Administrator privileges required to rename controller.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final controller = TextEditingController(text: device.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Rename Device', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Device Name',
            labelStyle: TextStyle(color: AppColors.textSecondary),
            hintText: 'e.g. Living Room Controller',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              if (newName.isNotEmpty) {
                final ok = await ref.read(deviceManagerProvider.notifier).updateDeviceName(device.id, newName);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Device renamed to "$newName"' : 'Failed to update device name on controller',
                    ),
                    backgroundColor: ok ? AppColors.success : AppColors.danger,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showRoomPicker(BuildContext context, SmartDevice device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).padding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assign Room',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _commonRooms.map((room) {
                final isSelected = device.room == room;
                return ChoiceChip(
                  label: Text(room),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(deviceManagerProvider.notifier).assignRoom(device.id, room);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Device assigned to $room'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showCredentialsDialog(BuildContext context, SmartDevice device) {
    ControllerLoginDialog.show(context, ref, device);
  }

  void _confirmReboot(BuildContext context, SmartDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Reboot Controller?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Are you sure you want to reboot ${device.name}? It will take ~5 seconds to reconnect.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(deviceManagerProvider.notifier).rebootDevice(device.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Reboot command dispatched to ${device.name}...'),
                  backgroundColor: AppColors.danger,
                ),
              );
            },
            child: const Text('Reboot', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final isDark = AppColors.isDark;
    final deviceIndex = devices.indexWhere((d) => d.id == widget.deviceId);

    if (deviceIndex < 0) {
      return Scaffold(
        appBar: AppBar(title: const Text('Device Not Found')),
        body: Center(
          child: Text('Device was removed or is not available.', style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    final device = devices[deviceIndex];
    final manager = ref.read(deviceManagerProvider.notifier);

    ref.listen<AuthPromptRequest?>(authPromptProvider, (prev, next) {
      if (next != null && next.deviceId == device.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ControllerLoginDialog.show(context, ref, device);
          }
        });
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              device.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            Row(
              children: [
                if (device.room.isNotEmpty) ...[
                  Flexible(
                    child: Text(
                      device.room,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent),
                    ),
                  ),
                  Text(' • ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
                Flexible(
                  child: Text(
                    device.ip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ),
                if (device.isGuest) ...[
                  Text(' • ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 0.8),
                    ),
                    child: const Text(
                      'Guest Tier',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.amber),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0x18FFFFFF) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: const Icon(Icons.handyman_outlined, size: 18),
            ),
            tooltip: 'Hardware Tools & Logs',
            onPressed: () => DeviceToolsSheet.show(context, device, manager),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0x18FFFFFF) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: const Icon(Icons.edit_outlined, size: 18),
            ),
            tooltip: 'Rename Device',
            onPressed: () => _showRenameDialog(context, device),
          ),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0x18FFFFFF) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: const Icon(Icons.refresh_rounded, size: 18),
            ),
            tooltip: 'Refresh Status',
            onPressed: () => manager.refreshDevice(device.id),
          ),
          PopupMenuButton<String>(
            color: isDark ? const Color(0xFF1A2337) : Colors.white,
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0x18FFFFFF) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
              ),
              child: const Icon(Icons.more_vert_rounded, size: 18),
            ),
            onSelected: (val) {
              if (val == 'tools') {
                DeviceToolsSheet.show(context, device, manager);
              } else if (val == 'auth') {
                _showCredentialsDialog(context, device);
              } else if (val == 'logout') {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text('Log Out Controller'),
                    content: Text(
                      'Are you sure you want to log out of ${device.name} (${device.ip})?\n\nStored credentials will be cleared and the controller will be locked so you can sign in with another account.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await manager.logoutDevice(device.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Logged out of ${device.name}.'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            _showCredentialsDialog(context, device);
                          }
                        },
                        child: const Text('Log Out', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
              } else if (val == 'room') {
                _showRoomPicker(context, device);
              } else if (val == 'reboot') {
                if (device.isGuest) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Forbidden: Administrator privileges required to reboot device.'),
                      backgroundColor: AppColors.warning,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                _confirmReboot(context, device);
              } else if (val == 'ota') {
                if (device.isGuest) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Forbidden: Administrator privileges required for OTA firmware update.'),
                      backgroundColor: AppColors.warning,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => BatchOtaScreen(preselectedDeviceId: device.id)),
                );
              } else if (val == 'delete') {
                manager.removeDevice(device.id);
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'tools', child: Text('Hardware Tools & Diagnostics')),
              const PopupMenuItem(value: 'auth', child: Text('Login Credentials')),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: AppColors.textSecondary),
                    SizedBox(width: 8),
                    Text('Log Out / Switch User'),
                  ],
                ),
              ),
              const PopupMenuItem(value: 'room', child: Text('Change Room')),
              const PopupMenuItem(value: 'reboot', child: Text('Reboot Controller')),
              const PopupMenuItem(value: 'ota', child: Text('Firmware Update (OTA)')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Remove Device', style: TextStyle(color: AppColors.danger)),
              ),
            ],
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => manager.refreshDevice(device.id),
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                if (device.needsAuth) ...[
                  InkWell(
                    onTap: () => ControllerLoginDialog.show(context, ref, device),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.warning, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_person_rounded, color: AppColors.warning, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'CONTROLLER LOCKED — LOGIN REQUIRED',
                                  style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  'Web Password Protection is enabled on ${device.ip}. Tap here to enter Username & Password.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.warning,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Unlock',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                // Hardware & Network Overview Card
                _buildHardwareOverviewCard(context, device, isDark),
                const SizedBox(height: 14),

                // Hardware Tools Command Strip
                _buildToolsHubCard(context, device, manager, isDark),
                const SizedBox(height: 14),

                // Gas Alarm Emergency Banner (if detected)
                if (device.telemetry.gasAlarm) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.danger, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'GAS / SMOKE WARNING',
                                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                'MQ-2 Reading: ${device.telemetry.gasRaw} ADC. Check room environment immediately!',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Live Environmental Telemetry Card (Equal symmetrical layout)
                _buildTelemetryCard(context, device, isDark),
                const SizedBox(height: 14),

                // Master Power Scene Buttons (Aurora Emerald & Nocturnal Violet)
                if (device.relays.any((r) => r.enabled)) ...[
                  _buildMasterPowerScenes(context, device, manager, isDark),
                  const SizedBox(height: 18),
                ],

                // Active Hardware Flash Configuration Card
                _buildHardwareConfigCard(context, device, manager, isDark),
                const SizedBox(height: 18),

                // Channels Grid (Responsive 2/3/4-col adaptive grid)
                _buildChannelsSection(context, device, manager, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHardwareOverviewCard(BuildContext context, SmartDevice device, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131927) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Status Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                decoration: BoxDecoration(
                  color: (device.isOnline ? AppColors.success : AppColors.danger).withValues(alpha: isDark ? 0.16 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (device.isOnline ? AppColors.success : AppColors.danger).withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6.5,
                      height: 6.5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: device.isOnline ? AppColors.success : AppColors.danger,
                        boxShadow: [
                          BoxShadow(
                            color: (device.isOnline ? AppColors.success : AppColors.danger).withValues(alpha: 0.6),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      device.isOnline ? 'ONLINE • REAL-TIME WEBSOCKET' : 'OFFLINE CONTROLLER',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: device.isOnline ? AppColors.success : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      'FW v${device.fwVersion}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 4 Partitioned Hardware Telemetry Items
          Row(
            children: [
              Expanded(
                child: _buildHardwareStatTile(
                  icon: Icons.wifi_rounded,
                  iconGradient: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                  value: '${device.signalPercent}%',
                  label: 'WIFI LINK',
                  sub: '${device.rssi} dBm',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHardwareStatTile(
                  icon: Icons.timer_rounded,
                  iconGradient: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
                  value: device.uptime.isNotEmpty ? device.uptime : '0m',
                  label: 'UPTIME',
                  sub: 'Continuous',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHardwareStatTile(
                  icon: Icons.memory_rounded,
                  iconGradient: const [Color(0xFF6366F1), Color(0xFF818CF8)],
                  value: '${device.freeHeap ~/ 1024} KB',
                  label: 'FREE HEAP',
                  sub: '${device.isEsp8266 ? "ESP8266" : "ESP32"} RAM',
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildHardwareStatTile(
                  icon: Icons.fingerprint_rounded,
                  iconGradient: const [Color(0xFF10B981), Color(0xFF059669)],
                  value: device.mac.isNotEmpty ? device.mac.substring(max(0, device.mac.length - 8)) : 'N/A',
                  label: 'MAC ID',
                  sub: 'Hardware ID',
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareStatTile({
    required IconData icon,
    required List<Color> iconGradient,
    required String value,
    required String label,
    required String sub,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF182033) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: iconGradient),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppColors.textMuted,
            ),
          ),
          Text(
            sub,
            style: TextStyle(
              fontSize: 8.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolsHubCard(BuildContext context, SmartDevice device, DeviceManager manager, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => DeviceToolsSheet.show(context, device, manager),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? const [Color(0xFF1E1B4B), Color(0xFF131927)]
                  : const [Color(0xFFEEF2FF), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: isDark ? 0.45 : 0.3),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.08),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.handyman_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hardware Tools & System Console',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Buzzer, I2C LCD, Sensor Calibration, Logs & System Diagnostics',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'LAUNCH',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppColors.primaryLight,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primaryLight),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryCard(BuildContext context, SmartDevice device, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131927) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Environmental Telemetry',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                icon: Icon(Icons.auto_mode_rounded, size: 15, color: AppColors.accent),
                label: Text(
                  'Automation Rules',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AutomationsScreen(preselectedDeviceId: device.id),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 3 Expanded Gauges (Equal Symmetrical Sizing - Zero Blank Gaps!)
          Builder(
            builder: (context) {
              final t = device.telemetry;
              final gasMax = t.gasMax > 0 ? t.gasMax : (device.isEsp8266 ? 1023 : 4095);
              return Row(
                children: [
                  Expanded(
                    child: TelemetryGauge(
                      label: 'Temperature',
                      value: !t.dhtEnabled
                          ? 'OFF'
                          : (t.dhtFault
                                ? 'ERR'
                                : (t.temperature > 0 ? t.temperature.toStringAsFixed(1) : '--')),
                      unit: (!t.dhtEnabled || t.dhtFault) ? '' : '°C',
                      percent: (!t.dhtEnabled || t.dhtFault)
                          ? 0.0
                          : ((t.temperature - 10) / 40).clamp(0.0, 1.0),
                      color: !t.dhtEnabled
                          ? AppColors.textMuted
                          : (t.dhtFault ? AppColors.danger : AppColors.tempAmber),
                      icon: Icons.thermostat_rounded,
                      statusBadge: !t.dhtEnabled
                          ? 'DISABLED'
                          : (t.dhtFault
                                ? 'FAULT'
                                : (t.temperature > 32 ? 'WARM' : 'COMFORT')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TelemetryGauge(
                      label: 'Humidity',
                      value: !t.dhtEnabled
                          ? 'OFF'
                          : (t.dhtFault
                                ? 'ERR'
                                : (t.humidity > 0 ? t.humidity.toStringAsFixed(0) : '--')),
                      unit: (!t.dhtEnabled || t.dhtFault) ? '' : '%',
                      percent: (!t.dhtEnabled || t.dhtFault)
                          ? 0.0
                          : (t.humidity / 100).clamp(0.0, 1.0),
                      color: !t.dhtEnabled
                          ? AppColors.textMuted
                          : (t.dhtFault ? AppColors.danger : AppColors.cyan),
                      icon: Icons.water_drop_rounded,
                      statusBadge: !t.dhtEnabled
                          ? 'DISABLED'
                          : (t.dhtFault
                                ? 'FAULT'
                                : (t.humidity > 70 ? 'HUMID' : 'OPTIMAL')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TelemetryGauge(
                      label: 'Air / Gas',
                      value: '${t.gasRaw}',
                      unit: 'ADC',
                      percent: (t.gasRaw / gasMax).clamp(0.0, 1.0),
                      color: t.gasAlarm
                          ? AppColors.danger
                          : (t.gasWarming ? AppColors.warning : AppColors.success),
                      icon: Icons.local_fire_department_rounded,
                      statusBadge: t.gasAlarm
                          ? 'ALARM'
                          : (t.gasWarming ? 'WARMING' : 'SAFE'),
                    ),
                  ),
                ],
              );
            },
          ),

          // Extended Telemetry (Multi-Instance Climate/Barometer/Light/Motion/Probe/MQ-2)
          Builder(
            builder: (context) {
              final t = device.telemetry;
              final gasMax = t.gasMax > 0 ? t.gasMax : (device.isEsp8266 ? 1023 : 4095);
              final extCards = <Widget>[
                if (t.pressureEnabled && t.pressure > 300)
                  TelemetryGauge(
                    label: 'Pressure',
                    value: t.pressure.toStringAsFixed(1),
                    unit: 'hPa',
                    percent: ((t.pressure - 950) / 100).clamp(0.0, 1.0),
                    color: AppColors.primary,
                    icon: Icons.compress_rounded,
                    statusBadge: 'BARO',
                  ),
                for (int i = 1; i < t.climates.length; i++) ...[
                  if (t.climates[i].enabled) ...[
                    TelemetryGauge(
                      label: '${t.climates[i].displayName} Temp',
                      value: t.climates[i].fault ? 'ERR' : t.climates[i].temperature.toStringAsFixed(1),
                      unit: t.climates[i].fault ? '' : '°C',
                      percent: t.climates[i].fault ? 0.0 : ((t.climates[i].temperature - 10) / 40).clamp(0.0, 1.0),
                      color: t.climates[i].fault ? AppColors.danger : AppColors.tempAmber,
                      icon: Icons.thermostat_rounded,
                      statusBadge: t.climates[i].fault ? 'FAULT' : '${t.climates[i].humidity.toStringAsFixed(0)}%',
                    ),
                    if (t.climates[i].barometer && t.climates[i].pressure > 300)
                      TelemetryGauge(
                        label: '${t.climates[i].displayName} Baro',
                        value: t.climates[i].pressure.toStringAsFixed(1),
                        unit: 'hPa',
                        percent: ((t.climates[i].pressure - 950) / 100).clamp(0.0, 1.0),
                        color: AppColors.primary,
                        icon: Icons.compress_rounded,
                        statusBadge: 'BARO',
                      ),
                  ],
                ],
                for (int i = 1; i < t.mq2s.length; i++)
                  if (t.mq2s[i].enabled)
                    TelemetryGauge(
                      label: t.mq2s[i].displayName,
                      value: '${t.mq2s[i].raw}',
                      unit: 'ADC',
                      percent: (t.mq2s[i].raw / gasMax).clamp(0.0, 1.0),
                      color: t.mq2s[i].alarm
                          ? AppColors.danger
                          : (t.mq2s[i].warming ? AppColors.warning : AppColors.success),
                      icon: Icons.local_fire_department_rounded,
                      statusBadge: t.mq2s[i].alarm
                          ? 'ALARM'
                          : (t.mq2s[i].warming ? 'WARMING' : 'SAFE'),
                    ),
                if (t.lights.isNotEmpty)
                  for (final l in t.lights.where((x) => x.enabled))
                    TelemetryGauge(
                      label: t.lights.length > 1 || l.label.isNotEmpty ? l.displayName : 'Ambient Light',
                      value: l.lux.toStringAsFixed(0),
                      unit: 'lx',
                      percent: (l.lux / 1000).clamp(0.0, 1.0),
                      color: AppColors.accent,
                      icon: Icons.light_mode_rounded,
                      statusBadge: l.lux > 200 ? 'BRIGHT' : 'DIM',
                    )
                else if (t.luxEnabled)
                  TelemetryGauge(
                    label: 'Ambient Light',
                    value: t.lux.toStringAsFixed(0),
                    unit: 'lx',
                    percent: (t.lux / 1000).clamp(0.0, 1.0),
                    color: AppColors.accent,
                    icon: Icons.light_mode_rounded,
                    statusBadge: t.lux > 200 ? 'BRIGHT' : 'DIM',
                  ),
                if (t.motions.isNotEmpty)
                  for (final m in t.motions.where((x) => x.enabled))
                    TelemetryGauge(
                      label: t.motions.length > 1 || m.label.isNotEmpty ? m.displayName : 'Motion PIR',
                      value: m.detected ? 'ACTIVE' : 'CLEAR',
                      unit: m.detected
                          ? ''
                          : (m.ageSeconds < 9999 ? '${m.ageSeconds}s' : 'IDLE'),
                      percent: m.detected ? 1.0 : 0.15,
                      color: m.detected ? AppColors.warning : AppColors.success,
                      icon: Icons.directions_run_rounded,
                      statusBadge: m.detected ? 'MOTION' : 'SECURE',
                    )
                else if (t.motionEnabled)
                  TelemetryGauge(
                    label: 'Motion PIR',
                    value: t.motionDetected ? 'ACTIVE' : 'CLEAR',
                    unit: t.motionDetected
                        ? ''
                        : (t.motionAgeSeconds < 9999
                            ? '${t.motionAgeSeconds}s'
                            : 'IDLE'),
                    percent: t.motionDetected ? 1.0 : 0.15,
                    color: t.motionDetected ? AppColors.warning : AppColors.success,
                    icon: Icons.directions_run_rounded,
                    statusBadge: t.motionDetected ? 'MOTION' : 'SECURE',
                  ),
                if (t.probes.isNotEmpty)
                  for (final p in t.probes.where((x) => x.enabled && (x.temperature > -55 || x.fault)))
                    TelemetryGauge(
                      label: t.probes.length > 1 || p.label.isNotEmpty ? p.displayName : 'Water Probe',
                      value: p.fault ? 'ERR' : p.temperature.toStringAsFixed(1),
                      unit: p.fault ? '' : '°C',
                      percent: p.fault ? 0.0 : ((p.temperature - 10) / 50).clamp(0.0, 1.0),
                      color: p.fault ? AppColors.danger : AppColors.cyan,
                      icon: Icons.water_rounded,
                      statusBadge: p.fault ? 'FAULT' : 'TEMP',
                    )
                else if (t.probeEnabled && (t.probeTemp > -55 || t.probeFault))
                  TelemetryGauge(
                    label: 'Water Probe',
                    value: t.probeFault ? 'ERR' : t.probeTemp.toStringAsFixed(1),
                    unit: t.probeFault ? '' : '°C',
                    percent: t.probeFault ? 0.0 : ((t.probeTemp - 10) / 50).clamp(0.0, 1.0),
                    color: t.probeFault ? AppColors.danger : AppColors.cyan,
                    icon: Icons.water_rounded,
                    statusBadge: t.probeFault ? 'FAULT' : 'TEMP',
                  ),
              ];
              if (extCards.isEmpty) return const SizedBox.shrink();

              final rows = <Widget>[];
              for (int i = 0; i < extCards.length; i += 2) {
                final chunk = extCards.sublist(i, (i + 2).clamp(0, extCards.length));
                rows.add(
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Expanded(child: chunk[0]),
                        if (chunk.length > 1) ...[
                          const SizedBox(width: 10),
                          Expanded(child: chunk[1]),
                        ],
                      ],
                    ),
                  ),
                );
              }
              return Column(children: rows);
            },
          ),
          ...() {
            final t = device.telemetry;
            final tanks = t.tanks.where((u) => u.enabled).toList();
            if (tanks.isNotEmpty) {
              return tanks.map((tank) {
                final title = (tanks.length == 1 && tank.label.isEmpty)
                    ? 'Overhead Water Tank'
                    : tank.displayName;
                return Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Icon(Icons.water_damage_rounded, size: 18, color: AppColors.cyan),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      title,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${tank.levelPct}% (${tank.distanceCm.toStringAsFixed(1)} cm)',
                              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.cyan),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (tank.levelPct / 100).clamp(0.0, 1.0),
                            minHeight: 10,
                            backgroundColor: isDark ? Colors.black26 : Colors.black12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              tank.levelPct < 20 ? AppColors.danger : (tank.levelPct > 80 ? AppColors.success : AppColors.cyan),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList();
            }
            if (!t.tankEnabled) return const <Widget>[];
            return [
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cyan.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.water_damage_rounded, size: 18, color: AppColors.cyan),
                            const SizedBox(width: 8),
                            Text('Overhead Water Tank', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
                          ],
                        ),
                        Text('${t.tankLevelPct}% (${t.distanceCm.toStringAsFixed(1)} cm)',
                             style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.cyan)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (t.tankLevelPct / 100).clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: isDark ? Colors.black26 : Colors.black12,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          t.tankLevelPct < 20 ? AppColors.danger : (t.tankLevelPct > 80 ? AppColors.success : AppColors.cyan),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ];
          }(),
        ],
      ),
    );
  }

  Widget _buildMasterPowerScenes(BuildContext context, SmartDevice device, DeviceManager manager, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildSceneButton(
            title: 'ALL ON',
            subtitle: 'Activate all channels',
            icon: Icons.bolt_rounded,
            gradient: isDark
                ? const [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF0D9488)]
                : const [Color(0xFF059669), Color(0xFF10B981)],
            glowColor: const Color(0xFF10B981).withValues(alpha: isDark ? 0.3 : 0.15),
            borderColor: const Color(0xFF34D399).withValues(alpha: isDark ? 0.45 : 0.3),
            onTap: () => manager.setAllRelays(device.id, 'on'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSceneButton(
            title: 'ALL OFF',
            subtitle: 'Shut off all channels',
            icon: Icons.nightlight_round,
            gradient: isDark
                ? const [Color(0xFF31104B), Color(0xFF4C1D95), Color(0xFF1E1B4B)]
                : const [Color(0xFF4338CA), Color(0xFF312E81)],
            glowColor: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.28 : 0.15),
            borderColor: const Color(0xFFA78BFA).withValues(alpha: 0.4),
            onTap: () => manager.setAllRelays(device.id, 'off'),
          ),
        ),
      ],
    );
  }

  Widget _buildSceneButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required Color glowColor,
    required Color borderColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: glowColor,
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _buildHardwareConfigCard(BuildContext context, SmartDevice device, DeviceManager manager, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131927) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.developer_board_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active Hardware Configuration',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            'Stored in Controller Flash (LittleFS)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.sync_rounded, color: AppColors.primary, size: 18),
                ),
                tooltip: 'Sync Hardware Config from Controller',
                onPressed: () async {
                  await manager.fetchDeviceRelays(device.id);
                  await manager.fetchDeviceConfig(device.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hardware configuration synced with ${device.name}!'),
                        backgroundColor: AppColors.success,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0), height: 1),
          const SizedBox(height: 12),

          // Channel Matrix
          if (device.relays.isEmpty)
            Text(
              device.numRelays == 0
                  ? 'Sensor Node active (0 relays configured).'
                  : 'Loading relay hardware configuration...',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
            )
          else
            ...device.relays.map((relay) {
            final polarityStr = relay.trigger == 1 ? 'Active HIGH (3.3V)' : 'Active LOW (0V)';
            final bootStr = relay.boot == 0
                ? 'Boot: Restore Last'
                : (relay.boot == 1 ? 'Boot: Always ON' : 'Boot: Always OFF');
            final hasAutoOff = relay.autoOff > 0;
            final hasAutoOn = relay.autoOn > 0;

            return InkWell(
              onTap: () => RelayConfigSheet.show(context, device, relay, manager),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF182033) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: relay.state ? AppColors.success.withValues(alpha: 0.2) : (isDark ? const Color(0xFF131927) : const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${relay.index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: relay.state ? AppColors.success : AppColors.textSecondary,
                          ),
                        ),
                      ),
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
                                  relay.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    color: relay.enabled ? AppColors.textPrimary : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              if (!relay.enabled) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
                                  ),
                                  child: const Text(
                                    'DISABLED',
                                    style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.danger),
                                  ),
                                ),
                              ],
                              if (relay.failsafe) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.shield_rounded, size: 10, color: AppColors.success),
                                      SizedBox(width: 3),
                                      Text(
                                        'FAILSAFE',
                                        style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: AppColors.success),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(
                                polarityStr,
                                style: TextStyle(fontSize: 11, color: AppColors.primaryLight, fontWeight: FontWeight.w600),
                              ),
                              Text('•', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                              Text(
                                bootStr,
                                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                              if (hasAutoOff) ...[
                                Text('•', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                Text('Auto-OFF: ${relay.autoOff}m', style: const TextStyle(fontSize: 11, color: AppColors.cyan, fontWeight: FontWeight.w600)),
                              ],
                              if (hasAutoOn) ...[
                                Text('•', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                Text('Auto-ON: ${relay.autoOn}m', style: const TextStyle(fontSize: 11, color: AppColors.cyan, fontWeight: FontWeight.w600)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131927) : Colors.white,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Icon(Icons.tune_rounded, size: 16, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildChannelsSection(BuildContext context, SmartDevice device, DeviceManager manager, bool isDark) {
    final enabledRelays = device.relays.where((r) => r.enabled).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Control Channels (${enabledRelays.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${enabledRelays.where((r) => r.state).length} Active Channels',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        device.relays.isEmpty
            ? (device.numRelays == 0
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF182033) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Center(
                        child: Text(
                          'Sensor Node active (0 relay channels configured).',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ),
                    )
                  : Text('Loading channels...', style: TextStyle(color: AppColors.textMuted, fontSize: 12)))
            : enabledRelays.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF182033) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Center(
                      child: Text(
                        'All relay channels are disabled in Hardware Profile.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ),
                  )
                : LayoutBuilder(
                builder: (context, constraints) {
                  int crossAxisCount = 2;
                  double childAspectRatio = 1.22;
                  if (constraints.maxWidth >= 950) {
                    crossAxisCount = 4;
                    childAspectRatio = 1.28;
                  } else if (constraints.maxWidth >= 600) {
                    crossAxisCount = 3;
                    childAspectRatio = 1.26;
                  }

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: childAspectRatio,
                    ),
                    itemCount: enabledRelays.length,
                    itemBuilder: (ctx, rIdx) {
                      final relay = enabledRelays[rIdx];
                      return RelayTile(
                        relay: relay,
                        deviceName: device.name,
                        onToggle: () => manager.toggleRelay(device.id, relay.id),
                        onStartTimer: (action, sec) async {
                          final ok = await manager.startTimer(device.id, relay.id, action, sec);
                          if (context.mounted) {
                            final min = (sec / 60).round();
                            final timeStr = min > 0 ? '$min min' : '$sec sec';
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Timer set: ${relay.name} will turn ${action.toUpperCase()} in $timeStr'
                                      : 'Failed to start timer for ${relay.name}',
                                ),
                                backgroundColor: ok ? AppColors.success : AppColors.danger,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        onCancelTimer: () async {
                          final ok = await manager.cancelTimer(device.id, relay.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Timer cancelled for ${relay.name}'
                                      : 'Failed to cancel timer for ${relay.name}',
                                ),
                                backgroundColor: ok ? AppColors.accent : AppColors.danger,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        onSettings: () => RelayConfigSheet.show(context, device, relay, manager),
                      );
                    },
                  );
                },
              ),
      ],
    );
  }

  int max(int a, int b) => a > b ? a : b;
}
