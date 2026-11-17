import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/smart_device.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import '../../services/discovery_service.dart';
import 'glass_card.dart';

class WifiProvisioningSheet extends ConsumerStatefulWidget {
  final SmartDevice? initialApDevice;

  const WifiProvisioningSheet({super.key, this.initialApDevice});

  static Future<bool?> show(
    BuildContext context, {
    SmartDevice? initialApDevice,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WifiProvisioningSheet(initialApDevice: initialApDevice),
    );
  }

  @override
  ConsumerState<WifiProvisioningSheet> createState() =>
      _WifiProvisioningSheetState();
}

class _WifiProvisioningSheetState extends ConsumerState<WifiProvisioningSheet> {
  static const String _apHost = '192.168.4.1';
  final ApiClient _api = ApiClient();

  final _ssidController = TextEditingController();
  final _wifiPassController = TextEditingController();
  final _deviceNameController = TextEditingController(text: 'SmartHome');
  final _adminUserController = TextEditingController(text: 'admin');
  final _adminPassController = TextEditingController();

  SmartDevice? _apDevice;
  List<Map<String, dynamic>> _networks = [];
  String _selectedRoom = 'Living Room';
  bool _enableWebAuth = false;
  bool _obscureWifiPass = true;
  bool _obscureAdminPass = true;
  bool _isProbingAp = false;
  bool _isScanningWifi = false;
  bool _isProvisioning = false;
  String? _statusStepText;
  String? _errorText;

  static const List<String> _rooms = [
    'Living Room',
    'Bedroom',
    'Kitchen',
    'Office',
    'Outdoor',
    'Balcony',
  ];

  @override
  void initState() {
    super.initState();
    _apDevice = widget.initialApDevice;
    if (_apDevice != null && _apDevice!.name.isNotEmpty) {
      _deviceNameController.text = _apDevice!.name;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probeAndScanAp(forceRefresh: false);
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _wifiPassController.dispose();
    _deviceNameController.dispose();
    _adminUserController.dispose();
    _adminPassController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _probeAndScanAp({bool forceRefresh = true}) async {
    if (!mounted || _isProbingAp || _isScanningWifi || _isProvisioning) return;
    setState(() {
      _isProbingAp = true;
      _errorText = null;
    });

    final probed = await _api.probeDiscovery(_apHost);
    if (!mounted) return;

    if (probed == null) {
      setState(() {
        _apDevice = null;
        _isProbingAp = false;
        _errorText =
            'Not connected to SmartHome AP (192.168.4.1). Connect your phone Wi-Fi to SmartHome-XXXX first, then tap Check Connection.';
      });
      return;
    }

    setState(() {
      _apDevice = probed;
      if (_deviceNameController.text.trim().isEmpty ||
          _deviceNameController.text == 'SmartHome') {
        _deviceNameController.text = probed.name;
      }
      _isProbingAp = false;
      _isScanningWifi = true;
    });

    final scanned = await _api.scanWifiNetworks(
      _apHost,
      forceRefresh: forceRefresh,
    );
    if (!mounted) return;

    setState(() {
      _isScanningWifi = false;
      if (scanned != null) {
        _networks = scanned;
        if (_ssidController.text.trim().isEmpty && _networks.isNotEmpty) {
          _ssidController.text = _networks.first['ssid']?.toString() ?? '';
        }
      }
    });
  }

  IconData _signalIcon(int signal) {
    if (signal >= 75) return Icons.network_wifi_rounded;
    if (signal >= 45) return Icons.network_wifi_3_bar_rounded;
    if (signal >= 20) return Icons.network_wifi_2_bar_rounded;
    return Icons.network_wifi_1_bar_rounded;
  }

  Color _signalColor(int signal) {
    if (signal >= 65) return AppColors.success;
    if (signal >= 35) return AppColors.warning;
    return AppColors.danger;
  }

  Future<void> _provisionDevice() async {
    if (_isProvisioning) return;
    final ssid = _ssidController.text.trim();
    final wifiPass = _wifiPassController.text;
    final devName = _deviceNameController.text.trim().isEmpty
        ? 'SmartHome'
        : _deviceNameController.text.trim();
    final adminUser = _adminUserController.text.trim().isEmpty
        ? 'admin'
        : _adminUserController.text.trim();
    final adminPass = _adminPassController.text;

    if (ssid.isEmpty) {
      setState(() => _errorText = 'Please select or enter a 2.4 GHz Wi-Fi SSID.');
      return;
    }
    if (_enableWebAuth && adminPass.isEmpty) {
      setState(
        () => _errorText =
            'Please enter an initial admin password or disable Web Password Protection.',
      );
      return;
    }

    setState(() {
      _isProvisioning = true;
      _errorText = null;
      _statusStepText = 'Sending Wi-Fi & security configuration to controller...';
    });

    final apDev = _apDevice ?? await _api.probeDiscovery(_apHost);
    if (!mounted) return;
    final sent = await _api.saveWifiConfig(
      _apHost,
      ssid,
      wifiPass,
      deviceName: devName,
      webAuth: _enableWebAuth,
      webUser: _enableWebAuth ? adminUser : null,
      webPass: _enableWebAuth ? adminPass : null,
    );

    if (!mounted) return;
    if (!sent) {
      setState(() {
        _isProvisioning = false;
        _statusStepText = null;
        _errorText =
            'Failed to send credentials to 192.168.4.1. Make sure your phone is still connected to SmartHome-XXXX Wi-Fi.';
      });
      return;
    }

    final manager = ref.read(deviceManagerProvider.notifier);

    // Pre-register the controller identity, room, and credentials so as soon as
    // the phone switches back to the home router, LAN radar links it seamlessly!
    if (apDev != null) {
      await manager.registerProvisionedDevice(
        apDev.copyWith(
          name: devName,
          room: _selectedRoom,
          authRequired: _enableWebAuth,
          authUsername: adminUser,
          authPassword: _enableWebAuth ? adminPass : null,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _statusStepText =
          'Controller is joining "$ssid"! Switching to LAN radar discovery...';
    });

    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    // Only scan LAN immediately if a non-SoftAP private subnet is reachable
    // (e.g., OS already switched back to router Wi-Fi or wired LAN is active).
    bool hasNonApLan = false;
    try {
      final rawIfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final targets = rawIfaces
          .map(
            (i) => (
              name: i.name,
              addresses: i.addresses.map((a) => a.address).toList(),
            ),
          )
          .toList();
      final resolved = DiscoveryService.resolveLanSubnets(interfaces: targets);
      hasNonApLan = resolved.subnets.any((s) => s != '192.168.4');
    } catch (_) {}

    if (hasNonApLan) {
      manager.scanForDevices();
    }

    if (!mounted) return;
    setState(() {
      _isProvisioning = false;
      _statusStepText = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          hasNonApLan
              ? '$devName configured for "$ssid" ($_selectedRoom)! Scanning LAN...'
              : '$devName configured for "$ssid" ($_selectedRoom)! Reconnect Wi-Fi to "$ssid" and tap Scan.',
        ),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset =
        MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom +
        20;
    final isDark = AppColors.isDark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
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
      padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.wifi_tethering_rounded,
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
                        'Zero-Touch Wi-Fi Onboarding',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Provision new ESP32 / ESP8266 controller via SoftAP (192.168.4.1)',
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
            const SizedBox(height: 16),

            // Step 1: AP Connection Status Card
            GlassCard(
              padding: const EdgeInsets.all(14),
              borderColor: _apDevice != null
                  ? AppColors.success.withValues(alpha: 0.5)
                  : AppColors.warning.withValues(alpha: 0.45),
              child: Row(
                children: [
                  Icon(
                    _apDevice != null
                        ? Icons.check_circle_rounded
                        : Icons.wifi_find_rounded,
                    color: _apDevice != null
                        ? AppColors.success
                        : AppColors.warning,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _apDevice != null
                              ? 'Connected to ${_apDevice!.hostname.toUpperCase()} (192.168.4.1)'
                              : 'Step 1: Connect Phone to SmartHome-XXXX AP',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _apDevice != null
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _apDevice != null
                              ? 'MAC: ${_apDevice!.mac} • FW v${_apDevice!.fwVersion}'
                              : 'Check the controller LCD for the SmartHome-XXXX Wi-Fi name and password.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                    ),
                    onPressed: _isProbingAp
                        ? null
                        : () => _probeAndScanAp(forceRefresh: true),
                    child: _isProbingAp
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Text(
                            _apDevice != null ? 'Rescan' : 'Check',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.danger,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorText!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Step 2: 2.4 GHz Network Scanner List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'NEARBY 2.4 GHz WI-FI NETWORKS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: AppColors.textMuted,
                  ),
                ),
                if (_isScanningWifi)
                  Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Scanning...',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => _probeAndScanAp(forceRefresh: true),
                    icon: Icon(Icons.refresh, size: 14, color: AppColors.primary),
                    label: Text(
                      'Rescan Networks',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            if (_networks.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 165),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _networks.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: AppColors.cardBorder),
                  itemBuilder: (context, idx) {
                    final net = _networks[idx];
                    final ssid = net['ssid']?.toString() ?? '';
                    final signal = (net['signal'] as num?)?.toInt() ?? 60;
                    final rssi = (net['rssi'] as num?)?.toInt() ?? -65;
                    final secure = net['secure'] == true;
                    final isSelected = _ssidController.text == ssid;

                    return InkWell(
                      onTap: () => setState(() => _ssidController.text = ssid),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.14)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            Icon(
                              _signalIcon(signal),
                              size: 18,
                              color: _signalColor(signal),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                ssid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  fontSize: 13.5,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (secure)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  Icons.lock_outline_rounded,
                                  size: 14,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            Text(
                              '$signal% ($rssi dBm)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Home Wi-Fi Credentials
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(
                labelText: 'Home Wi-Fi SSID (2.4 GHz)',
                hintText: 'Select above or type SSID',
                prefixIcon: Icon(Icons.wifi_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _wifiPassController,
              obscureText: _obscureWifiPass,
              decoration: InputDecoration(
                labelText: 'Home Wi-Fi Password',
                hintText: 'Enter router password',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureWifiPass
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscureWifiPass = !_obscureWifiPass),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Device Name & Room Assignment
            Text(
              'CONTROLLER IDENTITY & ROOM',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _deviceNameController,
                    decoration: const InputDecoration(
                      labelText: 'Controller Name',
                      hintText: 'e.g. Living Room Hub',
                      prefixIcon: Icon(Icons.developer_board_rounded),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedRoom,
                    dropdownColor: AppColors.surfaceElevated,
                    decoration: const InputDecoration(
                      labelText: 'Assign Room',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                    items: _rooms
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedRoom = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Optional Initial Admin Security
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: _enableWebAuth
                            ? AppColors.success
                            : AppColors.textMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enable Admin Password Protection',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Protect Web UI & REST/WebSocket control on LAN',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enableWebAuth,
                        activeThumbColor: AppColors.success,
                        onChanged: (v) => setState(() => _enableWebAuth = v),
                      ),
                    ],
                  ),
                  if (_enableWebAuth) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _adminUserController,
                            decoration: const InputDecoration(
                              labelText: 'Admin Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _adminPassController,
                            obscureText: _obscureAdminPass,
                            decoration: InputDecoration(
                              labelText: 'Admin Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureAdminPass
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                  size: 18,
                                ),
                                onPressed: () => setState(
                                  () => _obscureAdminPass = !_obscureAdminPass,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            if (_statusStepText != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusStepText!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _isProvisioning ? null : _provisionDevice,
                icon: _isProvisioning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.rocket_launch_rounded, size: 19),
                label: Text(
                  _isProvisioning
                      ? 'Provisioning Controller...'
                      : 'Configure & Connect to Home Wi-Fi',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
