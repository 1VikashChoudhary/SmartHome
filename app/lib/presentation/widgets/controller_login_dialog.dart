import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/smart_device.dart';
import '../../core/theme/app_colors.dart';
import '../../services/device_manager.dart';

class ControllerLoginDialog extends ConsumerStatefulWidget {
  final SmartDevice device;

  const ControllerLoginDialog({super.key, required this.device});

  static bool _isShowing = false;

  static Future<bool> show(
    BuildContext context,
    WidgetRef ref,
    SmartDevice device,
  ) async {
    if (_isShowing || !context.mounted) return false;
    _isShowing = true;
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ControllerLoginDialog(device: device),
      );
      return result ?? false;
    } finally {
      _isShowing = false;
      if (context.mounted) {
        try {
          if (ref.read(authPromptProvider)?.deviceId == device.id) {
            ref.read(authPromptProvider.notifier).clear();
          }
        } catch (_) {}
      }
    }
  }

  @override
  ConsumerState<ControllerLoginDialog> createState() =>
      _ControllerLoginDialogState();
}

class _ControllerLoginDialogState extends ConsumerState<ControllerLoginDialog> {
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  bool _obscurePass = true;
  bool _isAuthenticating = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(
      text: (widget.device.authUsername?.trim().isNotEmpty ?? false)
          ? widget.device.authUsername!.trim()
          : 'admin',
    );
    _passCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty) {
      setState(() => _errorText = 'Please enter the controller username.');
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _errorText = null;
    });

    final ok = await ref
        .read(deviceManagerProvider.notifier)
        .updateDeviceCredentials(
          widget.device.id,
          username: user,
          password: pass,
        );

    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Authenticated with ${widget.device.name}!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } else {
      setState(() {
        _isAuthenticating = false;
        _errorText =
            'Login rejected by ${widget.device.ip}. Check username & password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF131A2B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.lock_person_rounded,
              color: AppColors.warning,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Authentication Required',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${widget.device.name} (${widget.device.ip})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
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
          Text(
            'Web Password Protection is active on this controller. Enter your username and password to unlock live telemetry and relay control:',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _userCtrl,
            enabled: !_isAuthenticating,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Username',
              hintText: 'admin',
              prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
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
            controller: _passCtrl,
            enabled: !_isAuthenticating,
            obscureText: _obscurePass,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Enter controller password',
              prefixIcon: const Icon(Icons.key_rounded, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePass
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
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
          if (_errorText != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.danger.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.danger,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorText!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isAuthenticating
              ? null
              : () => Navigator.pop(context, false),
          child: Text(
            'Later',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: _isAuthenticating ? null : _submit,
          icon: _isAuthenticating
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.login_rounded, size: 16),
          label: Text(
            _isAuthenticating ? 'Verifying...' : 'Unlock & Login',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
