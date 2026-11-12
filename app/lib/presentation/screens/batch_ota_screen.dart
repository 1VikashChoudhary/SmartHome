import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/network/api_client.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';
import '../widgets/glass_card.dart';

class BatchOtaScreen extends ConsumerStatefulWidget {
  final String? preselectedDeviceId;

  const BatchOtaScreen({super.key, this.preselectedDeviceId});

  @override
  ConsumerState<BatchOtaScreen> createState() => _BatchOtaScreenState();
}

class _OtaVerification {
  final bool controllerReturned;
  final bool buildChanged;
  final String message;

  const _OtaVerification._({
    required this.controllerReturned,
    required this.buildChanged,
    required this.message,
  });

  const _OtaVerification.cancelled()
    : this._(
        controllerReturned: false,
        buildChanged: false,
        message: 'Verification cancelled.',
      );

  const _OtaVerification.notReturned(String message)
    : this._(controllerReturned: false, buildChanged: false, message: message);

  _OtaVerification.returnedUnchanged(String message)
    : this._(controllerReturned: true, buildChanged: false, message: message);

  _OtaVerification.verified(String message)
    : this._(controllerReturned: true, buildChanged: true, message: message);
}

class _BatchOtaScreenState extends ConsumerState<BatchOtaScreen> {
  // `min_spiffs.csv` reserves a 0x1E0000-byte application OTA partition.
  // Checking this before upload avoids asking a controller to erase/write an
  // image that can never fit. The ESP32 Update library performs the final,
  // authoritative capacity check too.
  static const int _minimumFirmwareBytes = 10 * 1024;
  static const int _maximumFirmwareBytes = 0x1E0000;
  // ESP8266 4M1M / 4M2M OTA slot safely caps around ~1 MB (~1,044,464 bytes).
  static const int _maximumEsp8266FirmwareBytes = 1044464;
  static const Duration _rebootVerificationTimeout = Duration(seconds: 45);
  static const Duration _rebootPollInterval = Duration(seconds: 2);

  final ApiClient _api = ApiClient();

  String? _selectedDeviceId; // null means 'ALL Devices'
  String? _selectedFileName;
  int _selectedFileSize = 0;
  Uint8List? _firmwareBytes;

  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatusText = '';
  final Map<String, String> _deviceFlashStatus = {};

  @override
  void initState() {
    super.initState();
    _selectedDeviceId = widget.preselectedDeviceId;
  }

  Future<void> _pickFirmwareFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();
        final devices = ref.read(deviceManagerProvider);
        final validationError = _validateFirmwareFile(file.name, bytes, devices);
        if (validationError != null) {
          if (!mounted) return;
          setState(() {
            _firmwareBytes = null;
            _selectedFileName = null;
            _selectedFileSize = 0;
            _uploadStatusText = validationError;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(validationError),
              backgroundColor: AppColors.danger,
            ),
          );
          return;
        }

        if (!mounted) return;
        setState(() {
          _firmwareBytes = bytes;
          _selectedFileName = file.name;
          _selectedFileSize = bytes.length;
          _uploadStatusText =
              'Firmware image validated (${(_selectedFileSize / 1024).toStringAsFixed(1)} KB)';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking file: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  String? _validateFirmwareFile(String filename, Uint8List bytes, List<SmartDevice> devices) {
    final name = filename.toLowerCase();
    if (!name.endsWith('.bin')) {
      return 'Select a .bin application firmware image.';
    }
    if (bytes.length < _minimumFirmwareBytes) {
      return 'This file is too small to be SmartHome application firmware.';
    }
    if (bytes.length > _maximumFirmwareBytes) {
      return 'This image is larger than this controller’s OTA application partition.';
    }
    if (name.contains('8266') && bytes.length > _maximumEsp8266FirmwareBytes) {
      return 'This ESP8266 firmware image exceeds the 1 MB OTA flash slot.';
    }
    if (bytes.length < 2 ||
        bytes[0] != 0xE9 ||
        bytes[1] == 0 ||
        bytes[1] > 16) {
      return 'This is not a valid application firmware image.';
    }
    const unsupportedArtifacts = [
      'merged',
      'bootloader',
      'partition',
      'spiffs',
      'littlefs',
      'fs.bin',
    ];
    if (unsupportedArtifacts.any(name.contains)) {
      return 'Select the application file (for example SmartHome.ino.bin), not a merged, bootloader, partition, or filesystem image.';
    }
    if (_selectedDeviceId != null) {
      final targets = devices.where((d) => d.id == _selectedDeviceId).toList();
      if (targets.isNotEmpty) {
        final dev = targets.first;
        if (dev.isEsp8266 && bytes.length > _maximumEsp8266FirmwareBytes) {
          return 'This image exceeds ${dev.name}’s ESP8266 (~1 MB) OTA slot.';
        }
        if (dev.isEsp8266 && name.contains('esp32') && !name.contains('esp8266')) {
          return 'The selected binary appears to be for ESP32, but target is ${dev.name} (ESP8266).';
        }
        if (!dev.isEsp8266 && name.contains('8266')) {
          return 'The selected binary appears to be for ESP8266, but target is ${dev.name} (ESP32).';
        }
      }
    }
    return null;
  }

  Future<void> _startFlash() async {
    if (_firmwareBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a .bin firmware binary first'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final devices = ref.read(deviceManagerProvider);
    final filenameLower = (_selectedFileName ?? '').toLowerCase();
    final bool isEsp8266Binary = filenameLower.contains('8266');
    final bool isEsp32Binary = filenameLower.contains('esp32') && !isEsp8266Binary;

    final targetDevices = _selectedDeviceId == null
        ? devices.where((d) {
            if (!d.isOnline || d.isGuest || d.needsAuth) return false;
            // When flashing ALL controllers, smartly filter by architecture if binary name specifies it
            if (isEsp8266Binary && !d.isEsp8266) return false;
            if (isEsp32Binary && d.isEsp8266) return false;
            return true;
          }).toList()
        : devices
              .where((d) =>
                  d.id == _selectedDeviceId &&
                  d.isOnline &&
                  !d.isGuest &&
                  !d.needsAuth)
              .toList();

    if (targetDevices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No online, admin-unlocked target devices available to flash',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    for (final dev in targetDevices) {
      if (dev.isEsp8266 &&
          _firmwareBytes!.length > _maximumEsp8266FirmwareBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selected binary exceeds ${dev.name} (ESP8266) 1 MB OTA limit.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      if (dev.isEsp8266 && isEsp32Binary) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selected binary is for ESP32, but target is ${dev.name} (ESP8266).',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
      if (!dev.isEsp8266 && isEsp8266Binary) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selected binary is for ESP8266, but target is ${dev.name} (ESP32).',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'Confirm Firmware OTA',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Target: ${targetDevices.length == 1 ? targetDevices.first.name : "${targetDevices.length} Controllers"}\n'
          'Binary: $_selectedFileName (${(_selectedFileSize / 1024).toStringAsFixed(1)} KB)\n\n'
          'The controller(s) will reboot upon completion. Do not cut power during flashing.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Flash Now'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _deviceFlashStatus.clear();
      for (final d in targetDevices) {
        _deviceFlashStatus[d.id] = 'Waiting...';
      }
    });

    var verifiedCount = 0;
    var unchangedCount = 0;
    var failedCount = 0;

    for (int i = 0; i < targetDevices.length; i++) {
      final dev = targetDevices[i];
      setState(() {
        _uploadStatusText =
            'Checking ${dev.name} (${i + 1}/${targetDevices.length})...';
        _deviceFlashStatus[dev.id] = 'Reading current firmware...';
      });

      final before = await _api.fetchOtaStatus(
        dev.ip,
        password: dev.authPassword,
      );
      if (!mounted) return;

      setState(() {
        _uploadStatusText =
            'Flashing ${dev.name} (${i + 1}/${targetDevices.length})...';
        _deviceFlashStatus[dev.id] = 'Uploading and writing flash...';
      });

      final result = await _api.uploadFirmware(
        dev.ip,
        _firmwareBytes!,
        _selectedFileName ?? 'firmware.bin',
        password: dev.authPassword,
        onProgress: (sent, total) {
          if (total > 0 && mounted) {
            setState(() {
              final deviceRatio = sent / total;
              _uploadProgress =
                  (i + (deviceRatio * 0.85)) / targetDevices.length;
            });
          }
        },
      );

      if (!mounted) return;

      if (!result.accepted) {
        failedCount++;
        setState(() {
          _uploadProgress = (i + 1) / targetDevices.length;
          _deviceFlashStatus[dev.id] = 'Upload failed: ${result.message}';
        });
        continue;
      }

      setState(() {
        _deviceFlashStatus[dev.id] = 'Flash accepted; waiting for reboot...';
      });
      final verification = await _verifyReboot(
        dev,
        before,
        i,
        targetDevices.length,
      );
      if (!mounted) return;

      setState(() {
        _uploadProgress = (i + 1) / targetDevices.length;
        _deviceFlashStatus[dev.id] = verification.message;
      });
      if (!verification.controllerReturned) {
        failedCount++;
      } else if (verification.buildChanged) {
        verifiedCount++;
      } else {
        unchangedCount++;
      }
    }

    final summary = _completionSummary(
      verifiedCount,
      unchangedCount,
      failedCount,
    );
    setState(() {
      _isUploading = false;
      _uploadProgress = 1.0;
      _uploadStatusText = summary;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(summary),
          backgroundColor: failedCount == 0
              ? AppColors.success
              : AppColors.danger,
        ),
      );
    }
  }

  Future<_OtaVerification> _verifyReboot(
    SmartDevice device,
    OtaStatus? before,
    int deviceIndex,
    int deviceCount,
  ) async {
    // The controller schedules its restart one second after replying. Waiting
    // first prevents the old process being mistaken for the newly flashed one.
    await Future<void>.delayed(const Duration(seconds: 2));
    final deadline = DateTime.now().add(_rebootVerificationTimeout);
    var sawOffline = false;
    var attempts = 0;

    while (DateTime.now().isBefore(deadline)) {
      attempts++;
      if (!mounted) return const _OtaVerification.cancelled();

      final status = await _api.fetchOtaStatus(
        device.ip,
        password: device.authPassword,
      );
      if (!mounted) return const _OtaVerification.cancelled();
      if (status == null) {
        sawOffline = true;
        setState(() {
          _uploadStatusText = 'Waiting for ${device.name} to restart...';
          _uploadProgress = (deviceIndex + 0.92) / deviceCount;
          _deviceFlashStatus[device.id] = 'Controller is rebooting...';
        });
      } else if (sawOffline || attempts >= 4) {
        if (before != null && !status.differsFrom(before)) {
          return _OtaVerification.returnedUnchanged(
            'Controller returned, but reports the same version/build. Check that a newly compiled SmartHome.ino.bin was selected.',
          );
        }
        final identity = [
          status.firmwareVersion,
          status.firmwareBuild,
        ].where((value) => value.isNotEmpty).join(' • ');
        return _OtaVerification.verified(
          identity.isEmpty
              ? 'Verified: controller restarted after the firmware update.'
              : 'Verified: $identity',
        );
      }

      await Future<void>.delayed(_rebootPollInterval);
    }

    return const _OtaVerification.notReturned(
      'Flash was accepted, but the controller did not return within 45 seconds. Check power, Wi-Fi, and its IP address.',
    );
  }

  String _completionSummary(int verified, int unchanged, int failed) {
    final parts = <String>['$verified verified'];
    if (unchanged > 0) parts.add('$unchanged returned with unchanged build');
    if (failed > 0) parts.add('$failed need attention');
    return 'OTA finished: ${parts.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final devices = ref.watch(deviceManagerProvider);
    final validSelectedId = devices.any((d) => d.id == _selectedDeviceId)
        ? _selectedDeviceId
        : null;

    return Scaffold(
      appBar: AppBar(title: Text('Firmware OTA Manager')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Firmware Binary Selection Card
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_alt, color: AppColors.accent),
                    SizedBox(width: 8),
                    Text(
                      'Firmware Binary File',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        color: AppColors.textSecondary,
                        size: 28,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedFileName ?? 'No binary selected',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _selectedFileSize > 0
                                  ? '${(_selectedFileSize / 1024).toStringAsFixed(1)} KB (Ready)'
                                  : 'Select the SmartHome.ino.bin application image',
                              style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _isUploading ? null : _pickFirmwareFile,
                        child: Text(
                          'Browse',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),

          // Target Selection Card
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.devices, color: AppColors.primaryLight),
                    SizedBox(width: 8),
                    Text(
                      'Select Target Controller',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: validSelectedId,
                  isExpanded: true,
                  dropdownColor: AppColors.surfaceElevated,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        '⚡ Flash ALL Online Controllers',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...devices.map(
                      (d) => DropdownMenuItem<String?>(
                        value: d.id,
                        child: Text(
                          '${d.name} [${d.isEsp8266 ? "ESP8266" : "ESP32"}] (${d.room} • ${d.ip})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _isUploading
                      ? null
                      : (val) => setState(() => _selectedDeviceId = val),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),

          // Upload Progress Bar (if active)
          if (_isUploading || _uploadProgress > 0) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor: AppColors.accent.withValues(alpha: 0.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _uploadStatusText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: AppColors.surfaceElevated,
                    color: AppColors.accent,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  if (_deviceFlashStatus.isNotEmpty) ...[
                    SizedBox(height: 14),
                    Divider(color: AppColors.cardBorder),
                    ...devices
                        .where(
                          (d) => validSelectedId == null
                              ? true
                              : d.id == validSelectedId,
                        )
                        .map((d) {
                          final status = _deviceFlashStatus[d.id] ?? 'Waiting';
                          final isSuccess = status.startsWith('Verified:');
                          final isFailed =
                              status.contains('failed') ||
                              status.contains('did not return');
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    d.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    status,
                                    textAlign: TextAlign.end,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isSuccess
                                          ? AppColors.success
                                          : (isFailed
                                                ? AppColors.danger
                                                : AppColors.accent),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                  ],
                ],
              ),
            ),
            SizedBox(height: 16),
          ],

          // Flash Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                disabledBackgroundColor: AppColors.surfaceElevated,
                disabledForegroundColor: AppColors.textMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isUploading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Icon(
                      Icons.bolt,
                      color: _firmwareBytes != null
                          ? Colors.black
                          : AppColors.textMuted,
                      size: 22,
                    ),
              label: Text(
                _isUploading
                    ? 'Flashing in Progress...'
                    : 'Start Over-The-Air Upgrade',
                style: TextStyle(
                  color: _firmwareBytes != null
                      ? Colors.black
                      : AppColors.textMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: _isUploading || _firmwareBytes == null
                  ? null
                  : _startFlash,
            ),
          ),
          SizedBox(height: 20),

          // Information Note
          GlassCard(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.textMuted, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'OTA writes the inactive application partition. If upload or verification fails before completion, the current firmware remains selected. Keep power on until the controller returns; only use SmartHome.ino.bin, never the merged serial-flash file.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      height: 1.4,
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
}
