import 'package:flutter/material.dart';
import '../../core/models/relay_channel.dart';
import '../../core/theme/app_colors.dart';
import 'quick_timer_sheet.dart';

class RelayTile extends StatelessWidget {
  final RelayChannel relay;
  final String deviceName;
  final VoidCallback onToggle;
  final void Function(String action, int durationSeconds) onStartTimer;
  final VoidCallback onCancelTimer;
  final VoidCallback? onSettings;

  const RelayTile({
    super.key,
    required this.relay,
    required this.deviceName,
    required this.onToggle,
    required this.onStartTimer,
    required this.onCancelTimer,
    this.onSettings,
  });

  IconData _getIcon(String type) {
    switch (type.toLowerCase()) {
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
      case 'light':
      default:
        return Icons.lightbulb_outline;
    }
  }

  String _getCategoryLabel(String type) {
    switch (type.toLowerCase()) {
      case 'fan':
        return 'Ceiling Fan';
      case 'ac':
        return 'Air Conditioner';
      case 'geyser':
      case 'heater':
        return 'Water Heater';
      case 'tv':
        return 'Television';
      case 'socket':
      case 'plug':
        return 'Power Socket';
      case 'pump':
        return 'Water Pump';
      case 'router':
        return 'Wi-Fi / Router';
      case 'light':
      default:
        return 'Lighting';
    }
  }

  String _formatSeconds(int sec) {
    if (sec <= 0) return '0s';
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  void _showTileOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1.5)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
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
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: relay.state ? AppColors.successGlow : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_getIcon(relay.iconType), color: relay.state ? AppColors.success : AppColors.textSecondary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(relay.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary)),
                      Text(deviceName, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: AppColors.cardBorder, height: 1),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.timer_outlined, color: AppColors.accent),
              title: Text('Countdown Timer', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              subtitle: Text(
                relay.timerActive
                    ? 'Active: Auto ${relay.timerTarget ? "ON" : "OFF"} in ${_formatSeconds(relay.timerRemaining)}'
                    : 'Set automatic shut-off or turn-on timer',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              trailing: relay.timerActive
                  ? TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onCancelTimer();
                      },
                      child: const Text('Cancel Timer', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                    )
                  : const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                Navigator.pop(context);
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => QuickTimerSheet(
                    relayName: relay.name,
                    currentState: relay.state,
                    onStartTimer: onStartTimer,
                  ),
                );
              },
            ),
            if (onSettings != null)
              ListTile(
                leading: Icon(Icons.tune_rounded, color: AppColors.primary),
                title: Text('Hardware Configuration', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                subtitle: Text('Polarity, boot state, auto-off & failsafe shutdown', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.pop(context);
                  onSettings!();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOn = relay.state;
    final hasTimer = relay.timerActive && relay.timerRemaining > 0;
    final isDark = AppColors.isDark;

    return GestureDetector(
      onTap: onToggle,
      onLongPress: () => _showTileOptions(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: isOn
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF093125),
                          Color(0xFF0F1B27),
                        ]
                      : const [
                          Color(0xFFE8FBF2),
                          Color(0xFFF7FCF9),
                        ],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF141A29),
                          Color(0xFF101624),
                        ]
                      : const [
                          Colors.white,
                          Color(0xFFF8FAFC),
                        ],
                ),
          border: Border.all(
            color: isOn
                ? AppColors.success.withValues(alpha: isDark ? 0.7 : 0.5)
                : (isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0)),
            width: isOn ? 1.4 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isOn
                  ? AppColors.success.withValues(alpha: isDark ? 0.22 : 0.12)
                  : Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: isOn ? 18 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Row: Appliance Icon Squircle on Left, Sleek Switch on Right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isOn
                        ? AppColors.success.withValues(alpha: isDark ? 0.22 : 0.15)
                        : (isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOn
                          ? AppColors.success.withValues(alpha: 0.6)
                          : (isDark ? const Color(0x14FFFFFF) : const Color(0xFFE2E8F0)),
                      width: 1,
                    ),
                    boxShadow: isOn
                        ? [
                            BoxShadow(
                              color: AppColors.success.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    _getIcon(relay.iconType),
                    color: isOn ? AppColors.success : AppColors.textMuted,
                    size: 20,
                  ),
                ),
                // Compact Switch with custom track & thumb
                SizedBox(
                  height: 32,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch(
                      value: isOn,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.success,
                      inactiveThumbColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      inactiveTrackColor: isDark ? const Color(0xFF1E283E) : const Color(0xFFE2E8F0),
                      onChanged: (_) => onToggle(),
                    ),
                  ),
                ),
              ],
            ),

            // Middle: Name & Subtitle
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  relay.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_getCategoryLabel(relay.iconType)} • ${isOn ? "Active" : "Standby"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: isOn ? AppColors.success : AppColors.textMuted,
                  ),
                ),
              ],
            ),

            // Bottom Row: Status / Timer / Active Rule Pill on Left, Options Button on Right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Status / Countdown timer / Active automation rule
                Expanded(
                  child: hasTimer
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.warning.withValues(alpha: 0.4),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.alarm, size: 11, color: AppColors.warning),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  _formatSeconds(relay.timerRemaining),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : (relay.activeRule != null && relay.activeRule!.isNotEmpty)
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.45),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.auto_awesome_rounded, size: 11, color: AppColors.primaryLight),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      relay.activeRule!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: AppColors.primaryLight,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOn
                                ? AppColors.success.withValues(alpha: isDark ? 0.16 : 0.1)
                                : (isDark ? const Color(0xFF1A2234) : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isOn
                                  ? AppColors.success.withValues(alpha: 0.35)
                                  : Colors.transparent,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5.5,
                                height: 5.5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isOn ? AppColors.success : AppColors.textMuted,
                                  boxShadow: isOn
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
                              const SizedBox(width: 5),
                              Text(
                                isOn ? 'ACTIVE' : 'STANDBY',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: isOn ? AppColors.success : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),

                const SizedBox(width: 6),

                // Discrete More Options Button
                GestureDetector(
                  onTap: () => _showTileOptions(context),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1B2337) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.more_horiz_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
