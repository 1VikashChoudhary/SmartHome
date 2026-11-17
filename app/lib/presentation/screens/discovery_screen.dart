import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/smart_device.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import '../../main.dart';
import '../widgets/glass_card.dart';
import '../widgets/controller_login_dialog.dart';
import '../widgets/wifi_provisioning_sheet.dart';
import 'device_screen.dart';

class DiscoveryScreen extends ConsumerStatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  ConsumerState<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends ConsumerState<DiscoveryScreen> {
  final _ipController = TextEditingController();
  final _userController = TextEditingController(text: 'admin');
  final _passController = TextEditingController();
  final ApiClient _api = ApiClient();
  bool _isManualAdding = false;
  SmartDevice? _detectedApDevice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkApModeConnection();
    });
  }

  Future<void> _checkApModeConnection() async {
    final ap = await _api.probeDiscovery('192.168.4.1');
    if (mounted) {
      setState(() => _detectedApDevice = ap);
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _userController.dispose();
    _passController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _openDevice(SmartDevice dev) async {
    if (dev.needsAuth) {
      final unlocked = await ControllerLoginDialog.show(context, ref, dev);
      if (!unlocked || !mounted) return;
    }
    ref.read(deviceManagerProvider.notifier).refreshDevice(dev.id);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceScreen(deviceId: dev.id),
      ),
    );
  }

  void _manualAdd() async {
    final rawInput = _ipController.text.trim();
    if (rawInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an IP address or hostname, or tap an online device above.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _isManualAdding = true);
    final ok = await ref.read(deviceManagerProvider.notifier).addDeviceByIp(
      rawInput,
      username: _userController.text.trim().isEmpty
          ? 'admin'
          : _userController.text.trim(),
      password: _passController.text.isNotEmpty ? _passController.text : null,
    );
    if (!mounted) return;
    setState(() => _isManualAdding = false);

    if (mounted) {
      if (ok) {
        _ipController.clear();
        _passController.clear();
        final promptReq = ref.read(authPromptProvider);
        if (promptReq != null) {
          ref.read(authPromptProvider.notifier).clear();
          final devices = ref.read(deviceManagerProvider);
          final idx = devices.indexWhere((d) => d.id == promptReq.deviceId);
          if (idx >= 0 && devices[idx].needsAuth) {
            final unlocked = await ControllerLoginDialog.show(
              context,
              ref,
              devices[idx],
            );
            if (!mounted) return;
            if (!unlocked) return;
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device added successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          ref.read(navigationIndexProvider.notifier).setIndex(0);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not connect to device at that IP or hostname'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _addDiscoveredDevice(SmartDevice dev) async {
    final added = await ref
        .read(deviceManagerProvider.notifier)
        .addDiscoveredDevice(dev);
    if (!mounted || added == null) return;

    final promptReq = ref.read(authPromptProvider);
    if (promptReq != null && promptReq.deviceId == added.id) {
      ref.read(authPromptProvider.notifier).clear();
    }

    if (added.needsAuth) {
      final unlocked = await ControllerLoginDialog.show(context, ref, added);
      if (!mounted || !unlocked) return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${added.name}" added to your controllers.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  Future<void> _triggerRadarScan(DeviceManager manager) async {
    final foundCount = await manager.scanForDevices();
    if (!mounted) return;
    final unaddedCount = ref.read(discoveredDevicesProvider).length;

    final String message;
    final Color bgColor;
    if (foundCount == 0) {
      message = 'Scan complete: no SmartHome controllers found on local network.';
      bgColor = AppColors.warning;
    } else if (unaddedCount > 0) {
      message =
          'Found $unaddedCount new controller${unaddedCount == 1 ? '' : 's'} — tap + Add below to include.';
      bgColor = AppColors.success;
    } else {
      message =
          'Scan complete: $foundCount added controller${foundCount == 1 ? '' : 's'} responded (no new unadded devices).';
      bgColor = AppColors.accent;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: bgColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final discoveredDevices = ref.watch(discoveredDevicesProvider);
    final manager = ref.read(deviceManagerProvider.notifier);
    final isScanning = ref.watch(isScanningProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add & Discover Devices'),
        actions: [
          IconButton(
            icon: isScanning
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.accent,
                    ),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Scan Now',
            onPressed: isScanning ? null : () => _triggerRadarScan(manager),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Zero-Touch AP Onboarding Wizard Banner
          GlassCard(
            borderColor: _detectedApDevice != null
                ? AppColors.success
                : AppColors.primary.withValues(alpha: 0.45),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _detectedApDevice != null
                            ? AppColors.success.withValues(alpha: 0.18)
                            : AppColors.primaryGlow,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _detectedApDevice != null
                              ? AppColors.success
                              : AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Icon(
                        Icons.wifi_tethering_rounded,
                        color: _detectedApDevice != null
                            ? AppColors.success
                            : AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Flexible(
                                child: Text(
                                  'Setup New Device (AP Mode)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_detectedApDevice != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(
                                      alpha: 0.16,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'AP DETECTED',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _detectedApDevice != null
                                ? 'Connected to ${_detectedApDevice!.hostname.toUpperCase()} (192.168.4.1). Tap below to configure Wi-Fi & room.'
                                : 'First boot or Wi-Fi reset? Connect phone to SmartHome-XXXX Wi-Fi and launch the wizard.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _detectedApDevice != null
                            ? AppColors.success
                            : AppColors.primary,
                      ),
                      foregroundColor: _detectedApDevice != null
                          ? AppColors.success
                          : AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.rocket_launch_outlined, size: 17),
                    label: Text(
                      _detectedApDevice != null
                          ? 'Provision ${_detectedApDevice!.hostname.toUpperCase()} Now'
                          : 'Launch Wi-Fi Onboarding Wizard',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () async {
                      await WifiProvisioningSheet.show(
                        context,
                        initialApDevice: _detectedApDevice,
                      );
                      if (mounted) _checkApModeConnection();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Radar Discovery Banner
          GlassCard(
            borderColor: isScanning ? AppColors.primary : AppColors.cardBorder,
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isScanning
                            ? AppColors.primary.withValues(alpha: 0.25)
                            : AppColors.surfaceElevated,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isScanning
                              ? AppColors.primary
                              : AppColors.cardBorder,
                        ),
                      ),
                      child: isScanning
                          ? Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.accent,
                              ),
                            )
                          : Icon(
                              Icons.radar,
                              color: AppColors.primary,
                              size: 26,
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
                                isScanning
                                    ? 'Scanning Network...'
                                    : 'On-Demand Radar',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isScanning
                                      ? AppColors.warning.withValues(alpha: 0.15)
                                      : AppColors.surfaceElevated,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isScanning ? 'SEARCHING' : 'IDLE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isScanning
                                        ? AppColors.warning
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isScanning
                                ? 'Probing local subnet & mDNS (_smarthome._tcp)...'
                                : 'Scanner is idle. Tap button below to scan.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isScanning
                          ? AppColors.surfaceElevated
                          : AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search, size: 18),
                    label: Text(
                      isScanning
                          ? 'Scanning Network (takes ~3s)...'
                          : 'Scan For New Device',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed:
                        isScanning ? null : () => _triggerRadarScan(manager),
                  ),
                ),
              ],
            ),
          ),
          if (discoveredDevices.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Discovered Devices (${discoveredDevices.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  'Tap + Add to include',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...discoveredDevices.map(
              (dev) => _buildDeviceTile(dev, isDiscoveredCandidate: true),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Added Devices',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              if (devices.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  icon: Icon(
                    Icons.dashboard_outlined,
                    size: 16,
                    color: AppColors.accent,
                  ),
                  label: Text(
                    'View on Dashboard',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () {
                    ref.read(navigationIndexProvider.notifier).setIndex(0);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (devices.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  discoveredDevices.isNotEmpty
                      ? 'No devices added yet. Tap + Add on a discovered device above or add manually.'
                      : 'No devices added yet. Scan above to discover ESP devices or add manually.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
            )
          else
            ...devices.map((dev) => _buildDeviceTile(dev)),

          const SizedBox(height: 24),
          Text(
            'Manual Add by IP / Hostname',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              children: [
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'IP Address or Hostname',
                    hintText: 'e.g. 192.168.1.105 or smarthome-3C4D.local',
                    prefixIcon: Icon(Icons.lan_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: 'Username (if Web Auth enabled)',
                    hintText: 'admin',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Device Password (if enabled)',
                    hintText: 'Optional',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isManualAdding ? null : _manualAdd,
                    child: _isManualAdding
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Connect to Device',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(
    SmartDevice dev, {
    bool isDiscoveredCandidate = false,
  }) {
    final bool isAuthWarn =
        isDiscoveredCandidate ? dev.authRequired : dev.needsAuth;
    final Color statusColor = isAuthWarn
        ? AppColors.warning
        : (isDiscoveredCandidate
              ? AppColors.accent
              : (dev.isOnline ? AppColors.success : AppColors.danger));
    final String statusLabel = isDiscoveredCandidate
        ? (dev.authRequired ? 'AUTH REQ' : 'FOUND')
        : (dev.needsAuth
              ? 'LOCKED'
              : (dev.isOnline ? 'ONLINE' : 'OFFLINE'));
    final VoidCallback onAction = isDiscoveredCandidate
        ? () => _addDiscoveredDevice(dev)
        : () => _openDevice(dev);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAction,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primary.withValues(alpha: 0.2),
          highlightColor: AppColors.primary.withValues(alpha: 0.1),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            borderColor: isAuthWarn
                ? AppColors.warning.withValues(alpha: 0.45)
                : (isDiscoveredCandidate
                      ? AppColors.accent.withValues(alpha: 0.35)
                      : (dev.isOnline
                            ? AppColors.success.withValues(alpha: 0.3)
                            : AppColors.cardBorder)),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(
                    isAuthWarn ? Icons.lock_person_rounded : Icons.memory,
                    color: isAuthWarn
                        ? AppColors.warning
                        : (isDiscoveredCandidate
                              ? AppColors.accent
                              : (dev.isOnline
                                    ? AppColors.success
                                    : AppColors.textMuted)),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              dev.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
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
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${dev.ip} (${dev.hostname}.local) • ${dev.numRelays} Ch',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        'MAC: ${dev.mac}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDiscoveredCandidate
                        ? AppColors.success
                        : (dev.needsAuth
                              ? AppColors.warning
                              : AppColors.primary),
                    foregroundColor:
                        (!isDiscoveredCandidate && dev.needsAuth)
                        ? Colors.black
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: onAction,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: isDiscoveredCandidate
                        ? const [
                            Icon(Icons.add_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 4),
                            Text(
                              'Add',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ]
                        : [
                            Text(
                              dev.needsAuth ? 'Unlock' : 'Open',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: dev.needsAuth
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              dev.needsAuth
                                  ? Icons.lock_open_rounded
                                  : Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: dev.needsAuth ? Colors.black : Colors.white,
                            ),
                          ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
