import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../services/device_manager.dart';
import '../../services/native_controls_service.dart';
import 'glass_card.dart';
import 'quick_controls_sheet.dart';
import '../screens/discovery_screen.dart';
import '../screens/about_screen.dart';

class AppSettingsSheet extends ConsumerStatefulWidget {
  const AppSettingsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AppSettingsSheet(),
    );
  }

  @override
  ConsumerState<AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends ConsumerState<AppSettingsSheet>
    with WidgetsBindingObserver {
  bool _isExportingHub = false;
  bool _isImportingHub = false;
  bool _safetyMonitorEnabled = true;
  bool _alarmSirenEnabled = true;
  bool _notificationPermissionGranted = true;
  bool _ignoringBatteryOptimizations = true;
  bool _monitorChannelHidden = false;
  bool _testingSiren = false;
  Timer? _testSirenTimer;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSafetyState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _testSirenTimer?.cancel();
    if (_testingSiren) {
      NativeControlsService.instance.stopInAppSiren();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSafetyState();
    }
  }

  Future<void> _loadSafetyState() async {
    final st = await NativeControlsService.instance.getSafetyMonitorState();
    if (!mounted) return;
    setState(() {
      _safetyMonitorEnabled = st.monitorEnabled;
      _alarmSirenEnabled = st.sirenEnabled;
      _notificationPermissionGranted = st.notificationPermissionGranted;
      _ignoringBatteryOptimizations = st.ignoringBatteryOptimizations;
      _monitorChannelHidden = st.monitorChannelHidden;
    });
  }

  Future<void> _toggleSafetyMonitor(bool value) async {
    if (value && _isAndroid) {
      final granted = await NativeControlsService.instance
          .requestNotificationPermission();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notification permission is required for background emergency alarms.',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
        return;
      }
    }
    await NativeControlsService.instance.setSafetyMonitorEnabled(value);
    if (!mounted) return;
    setState(() {
      _safetyMonitorEnabled = value;
      if (value) _notificationPermissionGranted = true;
    });
  }

  Future<void> _toggleSirenTest() async {
    if (_testingSiren) {
      _testSirenTimer?.cancel();
      _testSirenTimer = null;
      if (mounted) setState(() => _testingSiren = false);
      unawaited(NativeControlsService.instance.stopInAppSiren());
      return;
    }
    setState(() => _testingSiren = true);
    _testSirenTimer?.cancel();
    _testSirenTimer = Timer(const Duration(seconds: 3), () {
      unawaited(NativeControlsService.instance.stopInAppSiren());
      if (mounted) setState(() => _testingSiren = false);
    });
    unawaited(NativeControlsService.instance.startInAppSiren(force: true));
    if (!_isAndroid) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _exportHubConfig() async {
    bool includeCredentials = false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Export Hub Backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Exports paired controllers, rooms, and layout preferences to a JSON file.',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeCredentials,
                title: const Text('Include controller passwords (plaintext)'),
                subtitle: const Text(
                  'Leave unchecked unless restoring directly to a trusted personal device.',
                ),
                onChanged: (v) =>
                    setDialogState(() => includeCredentials = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (proceed != true || !mounted) return;

    setState(() => _isExportingHub = true);
    try {
      final manager = ref.read(deviceManagerProvider.notifier);
      final jsonStr = await manager.exportHubBackupJson(
        includeCredentials: includeCredentials,
      );
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final timestamp = DateTime.now()
          .toIso8601String()
          .split('T')
          .first
          .replaceAll('-', '');

      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Export SmartHome Pro Hub Backup',
        fileName: 'smarthome_hub_backup_$timestamp.json',
        bytes: bytes,
      );

      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Multi-Controller Hub backup exported to .json file!',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Export cancelled. Nothing written to clipboard.'),
            backgroundColor: AppColors.textSecondary,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to export Hub backup.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingHub = false);
    }
  }

  Future<void> _importHubConfig() async {
    setState(() => _isImportingHub = true);
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: 'Select SmartHome Pro Hub Backup (.json)',
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );

      if (picked.isEmpty) {
        if (mounted) setState(() => _isImportingHub = false);
        return;
      }

      final fileBytes = await picked.first.readAsBytes();
      if (fileBytes.isEmpty) {
        if (mounted) {
          setState(() => _isImportingHub = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Selected backup file was empty.'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        return;
      }

      final rawJson = utf8.decode(fileBytes, allowMalformed: true);
      final manager = ref.read(deviceManagerProvider.notifier);
      final ok = await manager.importHubBackupJson(rawJson);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'SmartHome Hub restored! All controllers, rooms & icons loaded.'
                : 'Invalid Hub backup file format.',
          ),
          backgroundColor: ok ? AppColors.success : AppColors.danger,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not read Hub backup file.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImportingHub = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentTheme = ref.watch(themeModeProvider);
    final themeNotifier = ref.read(themeModeProvider.notifier);
    final devices = ref.watch(deviceManagerProvider);
    final isDark = AppColors.isDark;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom:
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            24,
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
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.3),
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
                  child: Icon(
                    Icons.tune_rounded,
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
                        'Application Settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Preferences, appearance & Multi-Controller Hub backup',
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
            const SizedBox(height: 24),

            // Appearance Section Header
            Row(
              children: [
                Icon(
                  Icons.palette_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'APPEARANCE & THEME',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Theme Options Row (3 Cards: Light, Dark, System)
            Row(
              children: [
                _buildThemeCard(
                  title: 'Light',
                  icon: Icons.light_mode_rounded,
                  mode: ThemeMode.light,
                  currentMode: currentTheme,
                  onSelect: () => themeNotifier.setTheme(ThemeMode.light),
                ),
                const SizedBox(width: 10),
                _buildThemeCard(
                  title: 'Dark',
                  icon: Icons.dark_mode_rounded,
                  mode: ThemeMode.dark,
                  currentMode: currentTheme,
                  onSelect: () => themeNotifier.setTheme(ThemeMode.dark),
                ),
                const SizedBox(width: 10),
                _buildThemeCard(
                  title: 'System',
                  icon: Icons.brightness_auto_rounded,
                  mode: ThemeMode.system,
                  currentMode: currentTheme,
                  onSelect: () => themeNotifier.setTheme(ThemeMode.system),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Controllers & Hardware Hub
            Row(
              children: [
                Icon(Icons.router_outlined, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  'HARDWARE & LOCAL CONTROLLERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.successGlow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.wifi_tethering,
                          color: AppColors.success,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${devices.length} Controller(s) Discovered',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${devices.where((d) => d.isOnline).length} currently active on local LAN',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          side: BorderSide(color: AppColors.primary),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DiscoveryScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Radar',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: AppColors.cardBorder, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 16,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '100% Local-First LAN: Zero cloud requirement, zero latency, maximum privacy.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Mobile Quick Settings & Android Device Controls
            GlassCard(
              onTap: () => QuickControlsSheet.show(context),
              borderColor: AppColors.primary.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGlow,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.dashboard_customize_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mobile Quick Settings & Device Controls',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pin relays to phone Quick Settings tiles (1–12) & Android Device Controls',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Safety Alerts & Background Alarm Monitor
            GlassCard(
              borderColor: AppColors.danger.withValues(alpha: 0.35),
              padding: const EdgeInsets.all(14),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: AppColors.danger,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Safety Alerts & Loud Alarm Siren',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Instant phone/desktop siren for Gas, Smoke & High Temp alarms',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isAndroid) ...[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Background Safety Monitor (Wi-Fi)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Monitors controllers when app is closed. Shows a quiet ongoing status indicator on Android.',
                          style: TextStyle(fontSize: 11),
                        ),
                        value: _safetyMonitorEnabled,
                        onChanged: _toggleSafetyMonitor,
                      ),
                      if (!_notificationPermissionGranted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: AppColors.warning,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              const Expanded(
                                child: Text(
                                  'Notification permission needed for background alarms.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final ok = await NativeControlsService.instance
                                      .requestNotificationPermission();
                                  if (!mounted) return;
                                  setState(() => _notificationPermissionGranted = ok);
                                  if (!ok) {
                                    await NativeControlsService.instance
                                        .openNotificationSettings();
                                  }
                                },
                                child: const Text('Allow'),
                              ),
                            ],
                          ),
                        ),
                      if (_safetyMonitorEnabled && _notificationPermissionGranted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                _monitorChannelHidden
                                    ? Icons.visibility_off_outlined
                                    : Icons.notifications_paused_outlined,
                                color: _monitorChannelHidden
                                    ? AppColors.accent
                                    : AppColors.textSecondary,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _monitorChannelHidden
                                      ? 'Status card hidden cleanly; 6s emergency alerts remain active.'
                                      : 'Turn off "Background Safety Monitor" channel to hide the permanent status card while keeping alarms.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _monitorChannelHidden
                                        ? AppColors.accent
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => NativeControlsService.instance
                                    .openMonitorChannelSettings(),
                                child: Text(
                                  _monitorChannelHidden ? 'Manage' : 'Hide Card',
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_safetyMonitorEnabled && !_ignoringBatteryOptimizations)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(
                                Icons.battery_saver_rounded,
                                color: AppColors.textSecondary,
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Set Battery -> Unrestricted & Autostart ON so Android does not kill alarms when closed.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => NativeControlsService.instance
                                    .openAppDetailsSettings(),
                                child: const Text('Fix'),
                              ),
                            ],
                          ),
                        ),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Loud alarm siren sound',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _isAndroid
                            ? 'Uses Android Alarm audio stream so alerts ring loudly even on silent/locked screens'
                            : 'Plays repeating emergency alert chimes while alarm modal is active',
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: _alarmSirenEnabled,
                      onChanged: (v) async {
                        await NativeControlsService.instance
                            .setAlarmSirenEnabled(v);
                        if (mounted) setState(() => _alarmSirenEnabled = v);
                      },
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _toggleSirenTest,
                            icon: Icon(
                              _testingSiren
                                  ? Icons.stop_rounded
                                  : Icons.volume_up_rounded,
                              size: 16,
                            ),
                            label: Text(
                              _testingSiren
                                  ? 'Stop Test Siren'
                                  : 'Test Siren (3s)',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tip: For 4G/5G alerts when away from home Wi-Fi, enable Optional Remote Push Alerts inside each controller’s Settings.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Multi-Controller Hub Backup & Restore Section
            Row(
              children: [
                Icon(
                  Icons.cloud_sync_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'MULTI-CONTROLLER HUB BACKUP & MIGRATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGlow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.save_alt_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Full App & Hub Configuration',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Export or restore all paired controllers, room assignments, custom icons & credentials in one .json file.',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isExportingHub ? null : _exportHubConfig,
                          icon: _isExportingHub
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.file_download_outlined,
                                  size: 18,
                                ),
                          label: const Text(
                            'Export Hub .JSON',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: AppColors.primary),
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isImportingHub ? null : _importHubConfig,
                          icon: _isImportingHub
                              ? SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                )
                              : const Icon(
                                  Icons.file_upload_outlined,
                                  size: 18,
                                ),
                          label: const Text(
                            'Restore Hub .JSON',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
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

            // About & Sponsorship Navigation Card
            GlassCard(
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                );
              },
              borderColor: AppColors.primary.withValues(alpha: 0.35),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/icon.png',
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.primary, AppColors.accent],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.home_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'About SmartHome Pro',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.favorite_rounded,
                                    size: 11,
                                    color: AppColors.danger,
                                  ),
                                  SizedBox(width: 3),
                                  Text(
                                    'Sponsor',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'v1.0.0 • By Vikash Choudhary',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textSecondary,
                    size: 22,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // App Information
            Center(
              child: Column(
                children: [
                  Text(
                    'SmartHome Pro v1.0.0',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Commercial Multi-Channel ESP32 & ESP8266 Controller Suite',
                    style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeCard({
    required String title,
    required IconData icon,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required VoidCallback onSelect,
  }) {
    final isSelected = currentMode == mode;

    return Expanded(
      child: GestureDetector(
        onTap: onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryGlow
                : AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.cardBorder,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                size: 24,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
