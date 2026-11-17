import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import '../../services/native_controls_service.dart';
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
  bool _sirenSilenced = false;
  Timer? _desktopSirenTimer;

  @override
  void initState() {
    super.initState();
    // Audible + Haptic emergency alert pattern on modal open
    _triggerAudibleAndHapticAlert();
  }

  @override
  void dispose() {
    _desktopSirenTimer?.cancel();
    _desktopSirenTimer = null;
    unawaited(NativeControlsService.instance.stopInAppSiren());
    super.dispose();
  }

  void _silencePhoneAlarm({bool markEpisode = true}) {
    _desktopSirenTimer?.cancel();
    _desktopSirenTimer = null;
    if (mounted) {
      setState(() => _sirenSilenced = true);
    }
    if (markEpisode) {
      unawaited(
        NativeControlsService.instance.silenceAlarmEpisode(
          widget.deviceId,
          widget.alarmType,
        ),
      );
    } else {
      unawaited(NativeControlsService.instance.stopInAppSiren());
    }
  }

  Future<void> _triggerAudibleAndHapticAlert() async {
    final sirenEnabled = await NativeControlsService.instance.isAlarmSirenEnabled();
    if (!mounted || _sirenSilenced) return;
    if (sirenEnabled) {
      await NativeControlsService.instance.startInAppSiren();
      final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
      if (!isAndroid) {
        // Repeat system alert chime on Windows/desktop while dialog stays open
        _desktopSirenTimer?.cancel();
        _desktopSirenTimer = Timer.periodic(
          const Duration(milliseconds: 1400),
          (_) {
            if (!mounted || _sirenSilenced) return;
            SystemSound.play(SystemSoundType.alert);
          },
        );
      }
    }
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
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
    final isFault = widget.alarmType == 'sensor_fault';

    final isVocGas =
        isGas && (dev?.telemetry.gasUnit.toUpperCase() == 'VOC');
    final title = isGas
        ? (isVocGas
              ? 'VOC AIR QUALITY HAZARD DETECTED'
              : 'GAS / SMOKE HAZARD DETECTED')
        : isFault
            ? 'SENSOR HARDWARE FAULT DETECTED'
            : 'HIGH TEMPERATURE ALARM';
    final devName = dev?.name ?? 'SmartHome Controller';
    final roomName = dev?.room ?? 'Local Room';
    final metricText = dev == null
        ? 'Emergency threshold exceeded on controller.'
        : isGas
            ? (isVocGas
                  ? 'SGP40 VOC Sensor: ${dev.telemetry.gasRaw} VOC (${dev.telemetry.gasPercent}% • Limit: ${dev.telemetry.gasThreshold} VOC)'
                  : '${dev.telemetry.gasTypeName} Gas Sensor: ${dev.telemetry.gasRaw} ADC (${dev.telemetry.gasPercent}% • Limit: ${dev.telemetry.gasThreshold} ADC)')
            : isFault
                ? 'Climate sensor failed to respond across consecutive reads. Failsafe relays have been activated.'
                : 'Temperature: ${dev.telemetry.temperature.toStringAsFixed(1)}°C (Safety Limit: ${dev.telemetry.tempThreshold.toStringAsFixed(1)}°C)';

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
                  : isFault
                      ? Icons.sensors_off_rounded
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
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      setState(() => _isMuting = true);
                      _silencePhoneAlarm();
                      final muted = await manager.controlBuzzer(
                        widget.deviceId,
                        action: 'mute',
                      );
                      if (!mounted) return;
                      navigator.pop();
                      if (!muted) {
                        messenger?.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not mute buzzer. Check connection or admin permissions.',
                            ),
                            backgroundColor: AppColors.warning,
                          ),
                        );
                      }
                      if (!DeviceScreen.isViewing(widget.deviceId)) {
                        navigator.push(
                          MaterialPageRoute(
                            builder: (_) =>
                                DeviceScreen(deviceId: widget.deviceId),
                          ),
                        );
                      }
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
                      _silencePhoneAlarm();
                      final muted = await manager.controlBuzzer(
                        widget.deviceId,
                        action: 'mute',
                      );
                      final shutoffOk = await manager.setAllRelays(
                        widget.deviceId,
                        'off',
                      );
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.maybeOf(context);
                      if (!shutoffOk) {
                        setState(() => _isShuttingOff = false);
                        messenger?.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Emergency shutoff failed! Check connection or admin permissions.',
                            ),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                        return;
                      }
                      Navigator.pop(context);
                      messenger?.showSnackBar(
                        SnackBar(
                          content: Text(
                            muted
                                ? 'Emergency All OFF executed and buzzer muted.'
                                : 'All relays turned OFF, but failed to mute buzzer.',
                          ),
                          backgroundColor:
                              muted ? AppColors.danger : AppColors.warning,
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
            if (!_sirenSilenced)
              TextButton.icon(
                onPressed: () => _silencePhoneAlarm(),
                icon: const Icon(Icons.notifications_off_outlined, size: 16),
                label: const Text(
                  'Silence Phone Siren',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            TextButton(
              onPressed: (_isMuting || _isShuttingOff)
                  ? null
                  : () {
                      _silencePhoneAlarm();
                      if (context.mounted) Navigator.pop(context);
                    },
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
