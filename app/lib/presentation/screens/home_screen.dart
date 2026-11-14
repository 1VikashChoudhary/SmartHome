import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../services/device_manager.dart';
import '../../main.dart';
import '../widgets/relay_tile.dart';
import '../widgets/relay_config_sheet.dart';
import '../widgets/app_settings_sheet.dart';
import '../widgets/controller_login_dialog.dart';
import 'device_screen.dart';
import 'discovery_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _selectedRoom = 'All';

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final manager = ref.read(deviceManagerProvider.notifier);
    final isScanning = ref.watch(isScanningProvider);
    final themeNotifier = ref.read(themeModeProvider.notifier);
    ref.watch(themeModeProvider);
    final isDark = AppColors.isDark;

    ref.listen<AuthPromptRequest?>(authPromptProvider, (prev, next) {
      if (next == null) return;
      final idx = devices.indexWhere((d) => d.id == next.deviceId);
      if (idx >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ControllerLoginDialog.show(context, ref, devices[idx]);
          }
        });
      }
    });

    // Collect all unique rooms
    final rooms = <String>{'All'};
    for (final dev in devices) {
      if (dev.room.isNotEmpty) rooms.add(dev.room);
    }

    // Filter devices based on room selection
    final filteredDevices = _selectedRoom == 'All'
        ? devices
        : devices.where((d) => d.room == _selectedRoom).toList();

    // Global Statistics
    final onlineDevices = devices.where((d) => d.isOnline).length;
    int totalActiveRelays = 0;
    int totalRelayChannels = 0;
    double tempSum = 0;
    int tempCount = 0;
    double humSum = 0;
    int humCount = 0;
    final gasAlarmDevices = <SmartDevice>[];

    for (final dev in devices) {
      final enabledRelays = dev.relays.where((r) => r.enabled).toList();
      totalRelayChannels += enabledRelays.length;
      for (final r in enabledRelays) {
        if (r.state) totalActiveRelays++;
      }
      if (dev.isOnline &&
          dev.telemetry.dhtEnabled &&
          !dev.telemetry.dhtError &&
          (dev.telemetry.temperature != 0 || dev.telemetry.humidity > 0)) {
        tempSum += dev.telemetry.temperature;
        tempCount++;
      }
      if (dev.isOnline &&
          dev.telemetry.dhtEnabled &&
          dev.telemetry.humidity > 0 &&
          !dev.telemetry.dhtError) {
        humSum += dev.telemetry.humidity;
        humCount++;
      }
      if (dev.isOnline && dev.telemetry.gasAlarm) {
        gasAlarmDevices.add(dev);
      }
    }

    final avgTemp = tempCount > 0 ? (tempSum / tempCount) : null;
    final avgHum = humCount > 0 ? (humSum / humCount) : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/icon.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.home_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SmartHome Pro',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.4,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: onlineDevices > 0 ? AppColors.success : AppColors.warning,
                          boxShadow: [
                            BoxShadow(
                              color: (onlineDevices > 0 ? AppColors.success : AppColors.warning).withValues(alpha: 0.6),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'LAN HUB',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Theme Quick-Toggle Button
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
              child: Icon(
                isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                color: isDark ? AppColors.tempAmber : AppColors.primary,
                size: 18,
              ),
            ),
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: () {
              themeNotifier.setTheme(isDark ? ThemeMode.light : ThemeMode.dark);
            },
          ),
          // Radar Discovery Button
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
              child: Stack(
                children: [
                  Icon(Icons.radar_outlined, color: AppColors.textPrimary, size: 18),
                  if (isScanning)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            tooltip: 'Discovery Radar',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
              );
            },
          ),
          // Settings Sheet Button
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
              child: Icon(Icons.settings_outlined, color: AppColors.textPrimary, size: 18),
            ),
            tooltip: 'App Settings',
            onPressed: () => AppSettingsSheet.show(context),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: devices.isEmpty
          ? _buildEmptyState(context, manager)
          : RefreshIndicator(
              onRefresh: () => manager.refreshAllDevices(),
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // Gas Emergency Banner (supports all simultaneous emergency devices)
                  for (final gasDevice in gasAlarmDevices) ...[
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                DeviceScreen(deviceId: gasDevice.id),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: AppColors.danger, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: AppColors.danger, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'GAS / SMOKE WARNING: ${gasDevice.name.toUpperCase()}',
                                    style: const TextStyle(
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13),
                                  ),
                                  Text(
                                    'MQ-2 Reading: ${gasDevice.telemetry.gasRaw} ADC. Tap to inspect controller.',
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: AppColors.danger),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Overview Summary Metric Cards (Bespoke Luxury UI)
                  Row(
                    children: [
                      // Controllers Metric
                      Expanded(
                        child: _buildMetricCard(
                          label: 'CONTROLLERS',
                          value: '$onlineDevices / ${devices.length}',
                          subText: onlineDevices == devices.length ? 'All Online' : '${devices.length - onlineDevices} Offline',
                          subColor: onlineDevices == devices.length ? AppColors.success : AppColors.warning,
                          icon: Icons.hub_rounded,
                          iconGradient: const [Color(0xFF6366F1), Color(0xFF818CF8)],
                          isDark: isDark,
                          onTap: () => ref.read(navigationIndexProvider.notifier).setIndex(1),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Active Loads Metric
                      Expanded(
                        child: _buildMetricCard(
                          label: 'ACTIVE LOADS',
                          value: '$totalActiveRelays ON',
                          subText: 'of $totalRelayChannels channels',
                          subColor: AppColors.cyan,
                          icon: Icons.bolt_rounded,
                          iconGradient: const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
                          isDark: isDark,
                          valueColor: AppColors.cyan,
                          onTap: () => ref.read(navigationIndexProvider.notifier).setIndex(3),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Climate Metric
                      Expanded(
                        child: _buildMetricCard(
                          label: 'CLIMATE',
                          value: avgTemp != null ? '${avgTemp.toStringAsFixed(1)}°' : '--',
                          subText: avgHum != null ? '${avgHum.toStringAsFixed(0)}% Hum' : 'Sensors idle',
                          subColor: AppColors.tempAmber,
                          icon: Icons.thermostat_rounded,
                          iconGradient: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
                          isDark: isDark,
                          valueColor: AppColors.tempAmber,
                          onTap: () => ref.read(navigationIndexProvider.notifier).setIndex(3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Quick Action Scenes (Master Commercial Controls)
                  Row(
                    children: [
                      // All ON Button
                      Expanded(
                        child: _buildSceneButton(
                          title: 'ALL ON',
                          subtitle: 'Turn on all loads',
                          icon: Icons.bolt_rounded,
                          gradient: isDark
                              ? const [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF0D9488)]
                              : const [Color(0xFF059669), Color(0xFF10B981)],
                          glowColor: const Color(0xFF10B981).withValues(alpha: isDark ? 0.3 : 0.15),
                          borderColor: const Color(0xFF34D399).withValues(alpha: isDark ? 0.45 : 0.3),
                          onTap: () async {
                            final targetDevices = filteredDevices
                                .where((d) =>
                                    d.isOnline &&
                                    !d.needsAuth &&
                                    d.numRelays > 0 &&
                                    (d.relays.isEmpty ||
                                        d.relays.any((r) => r.enabled)))
                                .toList();
                            if (targetDevices.isEmpty) return;
                            final roomLabel = _selectedRoom == 'All'
                                ? 'all controllers'
                                : '$_selectedRoom controllers';
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                title: const Text('Turn ALL ON?'),
                                content: Text(
                                  'Turn on all enabled relay loads across $roomLabel?',
                                  style: TextStyle(
                                      color: AppColors.textSecondary),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Turn ON'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              for (final d in targetDevices) {
                                manager.setAllRelays(d.id, 'on');
                              }
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Good Night (All OFF) Button
                      Expanded(
                        child: _buildSceneButton(
                          title: 'ALL OFF',
                          subtitle: 'Power down loads',
                          icon: Icons.nightlight_round,
                          gradient: isDark
                              ? const [Color(0xFF31104B), Color(0xFF4C1D95), Color(0xFF1E1B4B)]
                              : const [Color(0xFF4338CA), Color(0xFF312E81)],
                          glowColor: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.28 : 0.15),
                          borderColor: const Color(0xFFA78BFA).withValues(alpha: isDark ? 0.4 : 0.3),
                          onTap: () async {
                            final targetDevices = filteredDevices
                                .where((d) =>
                                    d.isOnline &&
                                    !d.needsAuth &&
                                    d.numRelays > 0 &&
                                    (d.relays.isEmpty ||
                                        d.relays.any((r) => r.enabled)))
                                .toList();
                            if (targetDevices.isEmpty) return;
                            final roomLabel = _selectedRoom == 'All'
                                ? 'all controllers'
                                : '$_selectedRoom controllers';
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: AppColors.surface,
                                title: const Text('Turn ALL OFF?'),
                                content: Text(
                                  'Power off all enabled relay loads across $roomLabel?',
                                  style: TextStyle(
                                      color: AppColors.textSecondary),
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
                                    child: const Text('Turn OFF'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              for (final d in targetDevices) {
                                manager.setAllRelays(d.id, 'off');
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Room Filter Segmented Tabs (Tactile pills with icons)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: rooms.map((room) {
                        final isSelected = _selectedRoom == room;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildRoomPill(room, isSelected, isDark),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Devices & Relays List
                  ...filteredDevices.map((dev) => _buildDeviceSection(context, dev, manager, isDark)),
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String subText,
    required Color subColor,
    required IconData icon,
    required List<Color> iconGradient,
    required bool isDark,
    Color? valueColor,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131927) : Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          // Row 1: Gradient Squircle on left, glowing status indicator dot on right
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: iconGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: iconGradient.first.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: subColor,
                  boxShadow: [
                    BoxShadow(
                      color: subColor.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Category Label (Full width, zero horizontal collision!)
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 3),

          // Row 3: Hero Value (Full width, bold, zero overflow!)
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18.5,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),

          // Row 4: Subtext
          Text(
            subText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: subColor,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: cardContent,
      );
    }
    return cardContent;
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  IconData _getRoomIcon(String room) {
    switch (room.toLowerCase()) {
      case 'all':
        return Icons.grid_view_rounded;
      case 'living room':
        return Icons.weekend_rounded;
      case 'bedroom':
      case 'bed room':
        return Icons.bed_rounded;
      case 'kitchen':
        return Icons.kitchen_rounded;
      case 'office':
      case 'study':
        return Icons.computer_rounded;
      case 'balcony':
      case 'patio':
        return Icons.balcony_rounded;
      default:
        return Icons.meeting_room_rounded;
    }
  }

  Widget _buildRoomPill(String room, bool isSelected, bool isDark) {
    return GestureDetector(
      onTap: () => setState(() => _selectedRoom = room),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : (isDark ? const Color(0xFF131927) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryLight.withValues(alpha: 0.4)
                : (isDark ? const Color(0x18FFFFFF) : const Color(0xFFE2E8F0)),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getRoomIcon(room),
              size: 15,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              room,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceSection(BuildContext context, SmartDevice dev, DeviceManager manager, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Header Tile (Luxury Card Styling)
          GestureDetector(
            onTap: () {
              if (dev.needsAuth) {
                ControllerLoginDialog.show(context, ref, dev);
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DeviceScreen(deviceId: dev.id)),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131927) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: dev.needsAuth
                      ? AppColors.warning.withValues(alpha: 0.6)
                      : (isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0)),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dev.needsAuth
                          ? AppColors.warning
                          : (dev.isOnline ? AppColors.success : AppColors.danger),
                      boxShadow: [
                        BoxShadow(
                          color: (dev.needsAuth
                                  ? AppColors.warning
                                  : (dev.isOnline ? AppColors.success : AppColors.danger))
                              .withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1.5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dev.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (dev.room.isNotEmpty) ...[
                          const SizedBox(height: 1),
                          Text(
                            dev.needsAuth
                                ? '${dev.room} • Locked (Login Required)'
                                : dev.room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: dev.needsAuth
                                  ? AppColors.warning
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (dev.needsAuth) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.45),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_person_rounded, size: 13, color: AppColors.warning),
                          SizedBox(width: 4),
                          Text(
                            'LOGIN',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.warning,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ] else if (dev.isOnline) ...() {
                    final activeClimates =
                        dev.telemetry.climates.where((c) => c.enabled).toList();
                    final primaryCliFault = activeClimates.isNotEmpty
                        ? activeClimates.first.fault
                        : dev.telemetry.dhtError;
                    final pTemp = activeClimates.isNotEmpty
                        ? activeClimates.first.temperature
                        : dev.telemetry.temperature;
                    final pHum = activeClimates.isNotEmpty
                        ? activeClimates.first.humidity
                        : dev.telemetry.humidity;
                    if (!dev.telemetry.hasActiveClimate ||
                        primaryCliFault ||
                        (pTemp == 0 && pHum <= 0)) {
                      return const <Widget>[];
                    }
                    return [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? const Color(0x18FFFFFF) : const Color(0xFFE2E8F0),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.thermostat, size: 12, color: AppColors.tempAmber),
                            const SizedBox(width: 2),
                            Text(
                              '${pTemp.toStringAsFixed(1)}°',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.tempAmber),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.water_drop, size: 12, color: AppColors.cyan),
                            const SizedBox(width: 2),
                            Text(
                              '${pHum.toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.cyan),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                    ];
                  }(),
                  Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (dev.needsAuth) ...[
            InkWell(
              onTap: () => ControllerLoginDialog.show(context, ref, dev),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_rounded, color: AppColors.warning, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Password Protection Enabled on Controller',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.warning,
                            ),
                          ),
                          Text(
                            'Tap here to enter Username & Password for ${dev.ip} to unlock control.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
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
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Responsive Relay Tiles Grid (2 cols on phone, 3 on tablet, 4 on desktop)
          () {
            final visibleRelays = dev.relays.where((r) => r.enabled).toList();
            if (dev.relays.isEmpty) {
              if (dev.numRelays == 0) {
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DeviceScreen(deviceId: dev.id)),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sensors_rounded, size: 18, color: AppColors.cyan),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Sensor Node active (0 relay channels configured). Tap to inspect telemetry & profile.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (dev.needsAuth) {
                return const SizedBox.shrink();
              }
              return Text('Loading channels...', style: TextStyle(color: AppColors.textMuted, fontSize: 12));
            }
            if (visibleRelays.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder, style: BorderStyle.solid),
                ),
                child: Center(
                  child: Text(
                    'All relay channels are currently disabled in Hardware Profile.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              );
            }

            return LayoutBuilder(
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
                  itemCount: visibleRelays.length,
                  itemBuilder: (ctx, rIdx) {
                    final relay = visibleRelays[rIdx];
                    return RelayTile(
                      relay: relay,
                      deviceName: dev.name,
                      onToggle: () => manager.toggleRelay(dev.id, relay.id),
                      onStartTimer: (action, sec) async {
                        final ok = await manager.startTimer(dev.id, relay.id, action, sec);
                        if (context.mounted) {
                          final min = (sec / 60).round();
                          final timeStr = min > 0 ? '$min min' : '$sec sec';
                          final desc = 'Timer set: ${relay.name} will turn ${action.toUpperCase()} in $timeStr';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok ? desc : 'Failed to start timer for ${relay.name}'),
                              backgroundColor: ok ? AppColors.success : AppColors.danger,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      onCancelTimer: () async {
                        final ok = await manager.cancelTimer(dev.id, relay.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok ? 'Timer cancelled for ${relay.name}' : 'Failed to cancel timer'),
                              backgroundColor: ok ? AppColors.warning : AppColors.danger,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      onSettings: () => RelayConfigSheet.show(context, dev, relay, manager),
                    );
                  },
                );
              },
            );
          }(),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, DeviceManager manager) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryGlow,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.wifi_find, size: 60, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'No SmartHome Controllers Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            Text(
              'Make sure your controller is powered and connected to the same Wi-Fi network. Tap below to run our dual-engine mDNS & subnet probe radar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.radar, color: Colors.white),
              label: const Text('Open Radar Scanner', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
