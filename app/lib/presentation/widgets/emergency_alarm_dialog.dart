import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import '../screens/device_screen.dart';

class EmergencyAlarmDialog extends ConsumerStatefulWidget {
  final String deviceId;
  final String alarmType; // 'gas' or 'temperature'

  const EmergencyAlarmDialog({
    super.key,
    required this.deviceId,
    required this.alarmType,
  });

  static bool _isShowing = false;

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required String deviceId,
    required String alarmType,
  }) async {
    if (_isShowing || !context.mounted) return;
    _isShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            EmergencyAlarmDialog(deviceId: deviceId, alarmType: alarmType),
      );
    } finally {
      _isShowing = false;
      if (context.mounted) {
        try {
          ref.read(emergencyAlarmProvider.notifier).clear();
        } catch (_) {}
      }
    }
  }

  @override
  ConsumerState<EmergencyAlarmDialog> createState() =>
      _EmergencyAlarmDialogState();
}

class _EmergencyAlarmDialogState extends ConsumerState<EmergencyAlarmDialog> {
  bool _isMuting = false;
  bool _isShuttingOff = false;

  @override
  void initState() {
    super.initState();
    // Audible + Haptic emergency alert pattern on modal open
    _triggerAudibleAndHapticAlert();
  }

  Future<void> _triggerAudibleAndHapticAlert() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 220));
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 220));
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  SmartDevice? _findDevice(List<SmartDevice> devices) {
    for (final d in devices) {
      if (d.id == widget.deviceId) return d;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final manager = ref.read(deviceManagerProvider.notifier);
    final dev = _findDevice(devices);
    final isGas = widget.alarmType == 'gas';

    final title = isGas
        ? 'GAS / SMOKE HAZARD DETECTED'
        : 'HIGH TEMPERATURE ALARM';
    final devName = dev?.name ?? 'SmartHome Controller';
    final roomName = dev?.room ?? 'Local Room';
    final metricText = dev == null
        ? 'Emergency threshold exceeded on controller.'
        : (isGas
              ? 'MQ-2 Gas Sensor: ${dev.telemetry.gasRaw} ADC (${dev.telemetry.gasPercent}% • Limit: ${dev.telemetry.gasThreshold} ADC)'
              : 'Temperature: ${dev.telemetry.temperature.toStringAsFixed(1)}°C (Safety Limit: ${dev.telemetry.tempThreshold.toStringAsFixed(1)}°C)');

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.danger, width: 2),
      ),
      titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(
              isGas
                  ? Icons.local_fire_department_rounded
                  : Icons.thermostat_rounded,
              color: AppColors.danger,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.danger,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$devName • $roomName',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              metricText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'The hardware buzzer is sounding on the controller. You can mute the buzzer for 5 minutes and inspect the telemetry, or cut power to all relay loads immediately.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (_isMuting || _isShuttingOff)
                  ? null
                  : () async {
                      final navigator =
                          Navigator.of(context, rootNavigator: true);
                      setState(() => _isMuting = true);
                      await manager.controlBuzzer(
                        widget.deviceId,
                        action: 'mute',
                      );
                      if (!mounted) return;
                      navigator.pop();
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DeviceScreen(deviceId: widget.deviceId),
                        ),
                      );
                    },
              icon: _isMuting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.volume_off_rounded, size: 18),
              label: const Text(
                'Mute Buzzer & Inspect Controller',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (_isMuting || _isShuttingOff)
                  ? null
                  : () async {
                      setState(() => _isShuttingOff = true);
                      await manager.controlBuzzer(
                        widget.deviceId,
                        action: 'mute',
                      );
                      await manager.setAllRelays(widget.deviceId, 'off');
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      Navigator.pop(context);
                      messenger?.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Emergency All OFF executed and buzzer muted.',
                          ),
                          backgroundColor: AppColors.danger,
                        ),
                      );
                    },
              icon: _isShuttingOff
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.power_settings_new_rounded, size: 18),
              label: const Text(
                'Emergency Shutoff All Relays + Mute',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: (_isMuting || _isShuttingOff)
                  ? null
                  : () => Navigator.pop(context),
              child: Text(
                'Dismiss Alert',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
