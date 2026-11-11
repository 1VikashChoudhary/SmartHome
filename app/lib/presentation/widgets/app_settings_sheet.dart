import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../services/device_manager.dart';
import 'glass_card.dart';
import '../screens/discovery_screen.dart';

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

class _AppSettingsSheetState extends ConsumerState<AppSettingsSheet> {
  bool _isExportingHub = false;
  bool _isImportingHub = false;

  Future<void> _exportHubConfig() async {
    setState(() => _isExportingHub = true);
    try {
      final manager = ref.read(deviceManagerProvider.notifier);
      final jsonStr = await manager.exportHubBackupJson(
        includeCredentials: true,
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
        await Clipboard.setData(ClipboardData(text: jsonStr));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Hub backup JSON copied to clipboard!'),
            backgroundColor: AppColors.accent,
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
            const SizedBox(height: 24),

            // App Information
            Center(
              child: Column(
                children: [
                  Text(
                    'SmartHome Pro v1.0.0',
                    style: TextStyle(
                      fontSize: 12,
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
