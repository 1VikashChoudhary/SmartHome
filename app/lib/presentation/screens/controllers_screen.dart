import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/smart_device.dart';
import '../../core/models/relay_channel.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import '../widgets/device_tools_sheet.dart';
import '../widgets/controller_login_dialog.dart';
import 'device_screen.dart';
import 'batch_ota_screen.dart';
import 'discovery_screen.dart';

class ControllersScreen extends ConsumerStatefulWidget {
  const ControllersScreen({super.key});

  @override
  ConsumerState<ControllersScreen> createState() => _ControllersScreenState();
}

class _ControllersScreenState extends ConsumerState<ControllersScreen> {
  final _ipController = TextEditingController();
  final _userController = TextEditingController(text: 'admin');
  final _passController = TextEditingController();

  @override
  void dispose() {
    _ipController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  void _showAddModal(BuildContext context) {
    final isDark = AppColors.isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131A2B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? const Color(0x2AFFFFFF) : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.add_to_photos_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Controller',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Choose connection method to pair hardware',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Option 1: Discovery Radar
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A2338)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x20FFFFFF)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.cyan.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.radar_rounded,
                          color: AppColors.cyan,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Auto Discovery Radar',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Scan LAN via mDNS and SSDP for broadcasting ESP nodes',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Option 2: Direct IP
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _showDirectIpDialog(context);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1A2338)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x20FFFFFF)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.lan_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Direct IP / Static Host',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Connect directly using controller IP address or custom hostname',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDirectIpDialog(BuildContext context) {
    _ipController.clear();
    _userController.text = 'admin';
    _passController.clear();
    final isDark = AppColors.isDark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131A2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.lan_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Text(
              'Add by IP Address',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the local IP address assigned to the controller:',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ipController,
                decoration: InputDecoration(
                  hintText: 'e.g. 192.168.29.103',
                  prefixIcon: const Icon(Icons.network_ping, size: 20),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1A2338)
                      : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _userController,
                decoration: InputDecoration(
                  labelText: 'Device username',
                  hintText: 'admin',
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1A2338)
                      : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: InputDecoration(
                  hintText: 'API Password (if configured)',
                  prefixIcon: const Icon(Icons.lock_outline, size: 20),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1A2338)
                      : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final ip = _ipController.text.trim();
              if (ip.isEmpty) return;
              Navigator.pop(ctx);

              final success = await ref
                  .read(deviceManagerProvider.notifier)
                  .addDeviceByIp(
                    ip,
                    username: _userController.text.trim().isEmpty
                        ? 'admin'
                        : _userController.text.trim(),
                    password: _passController.text.trim().isEmpty
                        ? null
                        : _passController.text.trim(),
                  );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? 'Successfully paired controller!'
                          : 'Could not reach controller at $ip',
                    ),
                    backgroundColor: success
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Connect',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, SmartDevice dev) {
    if (dev.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Forbidden: Administrator privileges required to rename controller.',
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final textController = TextEditingController(text: dev.name);
    final isDark = AppColors.isDark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131A2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Rename Controller',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: TextField(
          controller: textController,
          decoration: InputDecoration(
            labelText: 'Controller Name',
            filled: true,
            fillColor: isDark
                ? const Color(0xFF1A2338)
                : const Color(0xFFF1F5F9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = textController.text.trim();
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              if (newName.isNotEmpty) {
                final ok = await ref
                    .read(deviceManagerProvider.notifier)
                    .updateDeviceName(dev.id, newName);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Controller renamed to "$newName"'
                          : 'Failed to save controller name to device flash',
                    ),
                    backgroundColor: ok ? AppColors.success : AppColors.danger,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text(
              'Save',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCredentialsDialog(BuildContext context, SmartDevice dev) {
    ControllerLoginDialog.show(context, ref, dev);
  }

  void _confirmReboot(BuildContext context, SmartDevice dev) {
    if (dev.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Forbidden: Administrator privileges required to reboot controller.',
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final isDark = AppColors.isDark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131A2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.restart_alt_rounded, color: AppColors.warning),
            const SizedBox(width: 8),
            const Text(
              'Reboot Controller?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to restart ${dev.name}? The controller will disconnect for about 4-6 seconds.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await ref
                  .read(deviceManagerProvider.notifier)
                  .rebootDevice(dev.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Reboot signal delivered to ${dev.name}'
                          : 'Failed to deliver reboot command',
                    ),
                    backgroundColor: ok ? AppColors.warning : AppColors.danger,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text(
              'Reboot',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmRemove(BuildContext context, SmartDevice dev) {
    final isDark = AppColors.isDark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131A2B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            const SizedBox(width: 8),
            const Text(
              'Remove Controller?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Remove "${dev.name}" from your SmartHome Hub? You can re-pair it anytime via LAN discovery.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(deviceManagerProvider.notifier).removeDevice(dev.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${dev.name} removed from hub'),
                  backgroundColor: AppColors.surfaceElevated,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text(
              'Remove',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final manager = ref.read(deviceManagerProvider.notifier);
    final isDark = AppColors.isDark;

    final onlineCount = devices.where((d) => d.isOnline).length;
    final totalChannels = devices.fold<int>(
      0,
      (acc, d) => acc + d.relays.where((r) => r.enabled).length,
    );
    final activeChannels = devices.fold<int>(
      0,
      (acc, d) => acc + d.relays.where((r) => r.enabled && r.state).length,
    );

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF090D16)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        titleSpacing: 16,
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF0D121F) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.hub_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Controllers Hub',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'MULTI-DEVICE HARDWARE CLUSTER',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Refresh All
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1B2337)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0x18FFFFFF)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Icon(
                Icons.refresh_rounded,
                color: AppColors.textPrimary,
                size: 18,
              ),
            ),
            tooltip: 'Refresh All Controllers',
            onPressed: () => manager.refreshAllDevices(),
          ),
          // Batch OTA Shortcut
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1B2337)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? const Color(0x18FFFFFF)
                      : const Color(0xFFE2E8F0),
                ),
              ),
              child: Icon(
                Icons.system_update_alt_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
            tooltip: 'Batch Firmware OTA',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BatchOtaScreen()),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: RefreshIndicator(
            onRefresh: () => manager.refreshAllDevices(),
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                // Cluster Summary Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF111726) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x1FFFFFFF)
                          : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.25 : 0.04,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Cluster Metrics 4-col
                      Row(
                        children: [
                          _buildSummaryItem(
                            label: 'CONTROLLERS',
                            value: '${devices.length}',
                            subtext: '$onlineCount Online',
                            subColor: onlineCount > 0
                                ? AppColors.success
                                : AppColors.danger,
                            icon: Icons.developer_board_rounded,
                            isDark: isDark,
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: isDark
                                ? const Color(0x1FFFFFFF)
                                : const Color(0xFFE2E8F0),
                          ),
                          _buildSummaryItem(
                            label: 'CHANNELS',
                            value: '$totalChannels',
                            subtext: '$activeChannels Active',
                            subColor: AppColors.cyan,
                            icon: Icons.power_rounded,
                            isDark: isDark,
                          ),
                          Container(
                            width: 1,
                            height: 40,
                            color: isDark
                                ? const Color(0x1FFFFFFF)
                                : const Color(0xFFE2E8F0),
                          ),
                          _buildSummaryItem(
                            label: 'NETWORK',
                            value: 'LAN',
                            subtext: 'WebSocket',
                            subColor: AppColors.primary,
                            icon: Icons.wifi_tethering_rounded,
                            isDark: isDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Cluster Actions Row
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showAddModal(context),
                              icon: const Icon(
                                Icons.add_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Add Controller',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const BatchOtaScreen(),
                                  ),
                                );
                              },
                              icon: Icon(
                                Icons.system_update_alt_rounded,
                                size: 18,
                                color: AppColors.textPrimary,
                              ),
                              label: Text(
                                'Batch Firmware',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: isDark
                                      ? const Color(0x28FFFFFF)
                                      : const Color(0xFFCBD5E1),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Section Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CONNECTED HARDWARE NODES (${devices.length})',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DiscoveryScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.radar_rounded,
                              size: 14,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Radar Scan',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Device Cards or Empty State
                if (devices.isEmpty)
                  _buildEmptyHub(context, isDark)
                else
                  ...devices.map(
                    (dev) =>
                        _buildControllerCard(context, dev, manager, isDark),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryItem({
    required String label,
    required String value,
    required String subtext,
    required Color subColor,
    required IconData icon,
    required bool isDark,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtext,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: subColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHub(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111726) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.memory_rounded,
              color: AppColors.primary,
              size: 48,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No Controllers Linked',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Link your local ESP32 or ESP8266 hardware units via LAN Discovery Radar or manual IP pairing.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: () => _showAddModal(context),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text(
              'Add Controller',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControllerCard(
    BuildContext context,
    SmartDevice dev,
    DeviceManager manager,
    bool isDark,
  ) {
    final enabledRelays = dev.relays.where((r) => r.enabled).toList();
    final activeRelays = enabledRelays.where((r) => r.state).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111726) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dev.isOnline
              ? (isDark ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0))
              : AppColors.danger.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Row
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Microchip Icon
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: dev.isOnline
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : AppColors.textMuted.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.memory_rounded,
                    color: dev.isOnline
                        ? AppColors.primary
                        : AppColors.textMuted,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Room
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              dev.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _showRenameDialog(context, dev),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF1B2338)
                                  : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              dev.room,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: dev.isEsp8266
                                  ? AppColors.tempAmber.withValues(alpha: 0.15)
                                  : AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              dev.platform,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: dev.isEsp8266
                                    ? AppColors.tempAmber
                                    : AppColors.primaryLight,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              dev.ip,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Online/Offline & FW Pill
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (dev.isOnline
                                    ? AppColors.success
                                    : AppColors.danger)
                                .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color:
                              (dev.isOnline
                                      ? AppColors.success
                                      : AppColors.danger)
                                  .withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dev.isOnline
                                  ? AppColors.success
                                  : AppColors.danger,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (dev.isOnline
                                              ? AppColors.success
                                              : AppColors.danger)
                                          .withValues(alpha: 0.6),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            dev.isOnline ? 'ONLINE' : 'OFFLINE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: dev.isOnline
                                  ? AppColors.success
                                  : AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'FW v${dev.fwVersion}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Hardware Specs Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0C101A) : const Color(0xFFF8FAFC),
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: isDark
                      ? const Color(0x15FFFFFF)
                      : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                _buildSpecCell(
                  label: 'WIFI',
                  value: '${dev.signalPercent}%',
                  sub: '${dev.rssi} dBm',
                  icon: Icons.wifi_rounded,
                  iconColor: AppColors.cyan,
                ),
                _buildSpecCell(
                  label: 'UPTIME',
                  value: dev.uptime.isNotEmpty ? dev.uptime : 'Active',
                  sub: '${dev.isEsp8266 ? "ESP8266" : "ESP32"} Timer',
                  icon: Icons.timer_outlined,
                  iconColor: AppColors.primary,
                ),
                _buildSpecCell(
                  label: 'FREE HEAP',
                  value: dev.freeHeap > 0
                      ? '${(dev.freeHeap / 1024).toStringAsFixed(0)} KB'
                      : '155 KB',
                  sub: 'Internal RAM',
                  icon: Icons.memory_rounded,
                  iconColor: AppColors.tempAmber,
                ),
                _buildSpecCell(
                  label: 'HARDWARE',
                  value: dev.mac.isNotEmpty
                      ? dev.mac.split(':').take(3).join(':')
                      : 'ESP32',
                  sub: 'MAC Base',
                  icon: Icons.fingerprint_rounded,
                  iconColor: AppColors.textSecondary,
                ),
              ],
            ),
          ),

          // Live Telemetry Mini Pills (if available)
          Builder(
            builder: (context) {
              final t = dev.telemetry;
              final pills = <Widget>[];
              final showDht = t.dhtEnabled && !t.dhtError && (t.temperature != 0 || t.humidity > 0);
              if (showDht) {
                pills.add(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.tempAmber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.tempAmber.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.thermostat_rounded,
                          size: 14,
                          color: AppColors.tempAmber,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${t.temperature.toStringAsFixed(1)} °C',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.tempAmber,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                pills.add(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.water_drop_rounded,
                          size: 14,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${t.humidity.toStringAsFixed(0)} %',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.cyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (t.gasRaw > 0 || t.gasAlarm) {
                pills.add(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (t.gasAlarm ? AppColors.danger : AppColors.success)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            (t.gasAlarm ? AppColors.danger : AppColors.success)
                                .withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_fire_department_rounded,
                          size: 14,
                          color:
                              t.gasAlarm ? AppColors.danger : AppColors.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${t.gasRaw} ADC',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: t.gasAlarm
                                ? AppColors.danger
                                : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (t.tankEnabled) {
                pills.add(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.cyan.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.water_damage_rounded,
                          size: 14,
                          color: AppColors.cyan,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Tank ${t.tankLevelPct}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.cyan,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (t.luxEnabled) {
                pills.add(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.wb_sunny_rounded,
                          size: 14,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${t.lux.toStringAsFixed(0)} lx',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (t.probeEnabled && !t.probeFault) {
                pills.add(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.device_thermostat_rounded,
                          size: 14,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Probe ${t.probeTemp.toStringAsFixed(1)} °C',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (t.motionEnabled) {
                final mColor = t.motionDetected
                    ? AppColors.danger
                    : AppColors.success;
                pills.add(
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: mColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: mColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sensors_rounded,
                          size: 14,
                          color: mColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          t.motionDetected ? 'Motion' : 'Clear',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: mColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (pills.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: pills,
                ),
              );
            },
          ),

          // Relay Channel Micro-Grid / Badges
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dev.relays.isEmpty && dev.numRelays == 0
                          ? 'SENSOR NODE MODE (0 RELAYS)'
                          : 'RELAY CHANNELS ($activeRelays of ${enabledRelays.length} ACTIVE)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    InkWell(
                      onTap: () => manager.fetchDeviceRelays(dev.id),
                      child: Text(
                        'Sync Flash',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (dev.relays.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: dev.relays
                        .map((r) => _buildChannelChip(dev, r, manager, isDark))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1321) : const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                // Open Control Panel or Unlock
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (dev.needsAuth) {
                        _showCredentialsDialog(context, dev);
                        return;
                      }
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DeviceScreen(deviceId: dev.id),
                        ),
                      );
                    },
                    icon: Icon(
                      dev.needsAuth
                          ? Icons.lock_open_rounded
                          : Icons.tune_rounded,
                      size: 16,
                      color: dev.needsAuth ? Colors.black : Colors.white,
                    ),
                    label: Text(
                      dev.needsAuth
                          ? 'Unlock Controller (Login)'
                          : 'Control Panel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: dev.needsAuth ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: dev.needsAuth
                          ? AppColors.warning
                          : AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Hardware Tools Sheet
                IconButton(
                  icon: const Icon(Icons.build_circle_outlined, size: 20),
                  tooltip: 'Hardware Diagnostics & Calibration',
                  color: AppColors.textPrimary,
                  onPressed: () {
                    if (dev.needsAuth) {
                      _showCredentialsDialog(context, dev);
                      return;
                    }
                    DeviceToolsSheet.show(context, dev, manager);
                  },
                ),

                // Credentials / Login Action
                IconButton(
                  icon: Icon(
                    dev.needsAuth
                        ? Icons.lock_person_rounded
                        : ((dev.authPassword?.isNotEmpty ?? false)
                              ? Icons.lock_rounded
                              : Icons.lock_open_rounded),
                    size: 19,
                  ),
                  tooltip: 'Controller Login Credentials',
                  color: dev.needsAuth
                      ? AppColors.warning
                      : ((dev.authPassword?.isNotEmpty ?? false)
                            ? AppColors.cyan
                            : AppColors.textSecondary),
                  onPressed: () => _showCredentialsDialog(context, dev),
                ),

                // Reboot Action
                IconButton(
                  icon: const Icon(Icons.restart_alt_rounded, size: 20),
                  tooltip: 'Reboot ${dev.isEsp8266 ? "ESP8266" : "ESP32"}',
                  color: AppColors.warning,
                  onPressed: () => _confirmReboot(context, dev),
                ),

                // Remove Action
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: 'Remove Node',
                  color: AppColors.danger,
                  onPressed: () => _confirmRemove(context, dev),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecCell({
    required String label,
    required String value,
    required String sub,
    required IconData icon,
    required Color iconColor,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelChip(
    SmartDevice dev,
    RelayChannel r,
    DeviceManager manager,
    bool isDark,
  ) {
    final active = r.enabled && r.state;
    final isEn = r.enabled;

    return InkWell(
      onTap: isEn ? () => manager.toggleRelay(dev.id, r.index) : null,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: !isEn
              ? (isDark ? const Color(0xFF131927) : const Color(0xFFF1F5F9))
              : active
                  ? (isDark ? const Color(0xFF0F3A2E) : const Color(0xFFD1FAE5))
                  : (isDark ? const Color(0xFF161F33) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: !isEn
                ? Colors.transparent
                : active
                    ? AppColors.success.withValues(alpha: 0.5)
                    : (isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Opacity(
          opacity: isEn ? 1.0 : 0.5,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !isEn
                      ? AppColors.danger.withValues(alpha: 0.6)
                      : active
                          ? AppColors.success
                          : AppColors.textMuted,
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.6),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                r.name + (!isEn ? ' (off)' : ''),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: !isEn
                      ? AppColors.textMuted
                      : active
                          ? (isDark
                                ? const Color(0xFF34D399)
                                : const Color(0xFF065F46))
                          : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
