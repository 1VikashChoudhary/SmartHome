import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../widgets/glass_card.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  static const String upiId = '1vikash@ybl';
  static const String paypalUrl = 'https://paypal.me/1vikash';
  static const String githubUrl = 'https://github.com/1VikashChoudhary/SmartHome';
  static const String developerName = 'Vikash Choudhary';

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _copiedUpi = false;
  bool _copiedPaypal = false;
  Timer? _resetCopyTimer;

  @override
  void dispose() {
    _resetCopyTimer?.cancel();
    super.dispose();
  }

  Future<void> _copyToClipboard(String text, String label, {bool isUpi = false}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;

    _resetCopyTimer?.cancel();
    setState(() {
      if (isUpi) {
        _copiedUpi = true;
      } else {
        _copiedPaypal = true;
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text('$label copied to clipboard!')),
          ],
        ),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );

    _resetCopyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (isUpi) {
            _copiedUpi = false;
          } else {
            _copiedPaypal = false;
          }
        });
      }
    });
  }

  Future<void> _launchExternalUrl(String urlString, {String? fallbackCopy}) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && fallbackCopy != null && mounted) {
        await _copyToClipboard(fallbackCopy, 'Payment details');
      }
    } catch (_) {
      if (fallbackCopy != null && mounted) {
        await _copyToClipboard(fallbackCopy, 'Payment details');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $urlString'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _launchUpiIntent() async {
    final uri = Uri.parse(
      'upi://pay?pa=${AboutScreen.upiId}&pn=Vikash%20Choudhary&cu=INR&tn=SmartHome%20Project%20Sponsorship',
    );
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        await _copyToClipboard(
          AboutScreen.upiId,
          'UPI ID (${AboutScreen.upiId})',
          isUpi: true,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('UPI app not found. UPI ID copied! Open GPay, PhonePe, or Paytm to pay.'),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) {
        await _copyToClipboard(
          AboutScreen.upiId,
          'UPI ID (${AboutScreen.upiId})',
          isUpi: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About & Sponsorship'),
        actions: [
          IconButton(
            tooltip: 'GitHub Repository',
            icon: const Icon(Icons.code_rounded),
            onPressed: () => _launchExternalUrl(AboutScreen.githubUrl),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ═══ App Hero Card ═══
          GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              children: [
                // App Brand Icon
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      'assets/icon.png',
                      width: 82,
                      height: 82,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.home_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'SmartHome Pro',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Multi-Channel Controller Suite',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildPill(
                      label: 'v1.0.0 Stable',
                      icon: Icons.verified_rounded,
                      color: AppColors.primary,
                    ),
                    _buildPill(
                      label: '100% Local-First',
                      icon: Icons.lock_outline_rounded,
                      color: AppColors.success,
                    ),
                    _buildPill(
                      label: 'Zero Cloud Required',
                      icon: Icons.cloud_off_rounded,
                      color: AppColors.info,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ═══ Section Header: Sponsorship & Support ═══
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: AppColors.danger,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'SPONSOR & SUPPORT PROJECT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'SmartHome is an independent Smart Home & Environmental Monitoring System . If it brings value to your home or maker setups, consider sponsoring to fuel ongoing firmware development, hardware lab testing, and new features!',
            style: TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 14),

          // ═══ Sponsorship Card 1: India (UPI) ═══
          GlassCard(
            borderColor: AppColors.success.withValues(alpha: 0.35),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.qr_code_2_rounded,
                            color: AppColors.success,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'India • UPI Payment',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Zero transaction fee • Instant',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        'BHIM / UPI',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // UPI ID Display Box
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'UPI VPA ID',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 1),
                            const SelectableText(
                              AboutScreen.upiId,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy UPI ID',
                        icon: Icon(
                          _copiedUpi
                              ? Icons.check_circle_rounded
                              : Icons.copy_rounded,
                          color: _copiedUpi
                              ? AppColors.success
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                        onPressed: () => _copyToClipboard(
                          AboutScreen.upiId,
                          'UPI ID (${AboutScreen.upiId})',
                          isUpi: true,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Pay via UPI Action Button
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.flash_on_rounded, size: 18),
                        label: const Text(
                          'Pay via Any UPI App',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _launchUpiIntent,
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(color: AppColors.cardBorder),
                      ),
                      icon: Icon(
                        _copiedUpi ? Icons.check : Icons.copy,
                        size: 16,
                        color: _copiedUpi ? AppColors.success : null,
                      ),
                      label: Text(_copiedUpi ? 'Copied' : 'Copy ID'),
                      onPressed: () => _copyToClipboard(
                        AboutScreen.upiId,
                        'UPI ID (${AboutScreen.upiId})',
                        isUpi: true,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Supported UPI Apps Badges
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _buildSubtleBadge('Google Pay'),
                    _buildSubtleBadge('PhonePe'),
                    _buildSubtleBadge('Paytm'),
                    _buildSubtleBadge('BHIM'),
                    _buildSubtleBadge('Cred'),
                    _buildSubtleBadge('Amazon Pay'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ═══ Sponsorship Card 2: International (PayPal) ═══
          GlassCard(
            borderColor: const Color(0xFF0070BA).withValues(alpha: 0.4),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0070BA).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.public_rounded,
                            color: Color(0xFF38BDF8),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'International • PayPal',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Global donations • Cards & PayPal balance',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0070BA).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF0070BA).withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        'Worldwide',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF38BDF8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // PayPal Link Display
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.link_rounded,
                        size: 18,
                        color: Color(0xFF38BDF8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PAYPAL ME LINK',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMuted,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 1),
                            const SelectableText(
                              AboutScreen.paypalUrl,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy PayPal link',
                        icon: Icon(
                          _copiedPaypal
                              ? Icons.check_circle_rounded
                              : Icons.copy_rounded,
                          color: _copiedPaypal
                              ? AppColors.success
                              : AppColors.textSecondary,
                          size: 20,
                        ),
                        onPressed: () => _copyToClipboard(
                          AboutScreen.paypalUrl,
                          'PayPal link',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Donate via PayPal Button
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0070BA),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text(
                          'Donate via PayPal.Me',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () => _launchExternalUrl(
                          AboutScreen.paypalUrl,
                          fallbackCopy: AboutScreen.paypalUrl,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(color: AppColors.cardBorder),
                      ),
                      icon: Icon(
                        _copiedPaypal ? Icons.check : Icons.copy,
                        size: 16,
                        color: _copiedPaypal ? AppColors.success : null,
                      ),
                      label: Text(_copiedPaypal ? 'Copied' : 'Copy Link'),
                      onPressed: () => _copyToClipboard(
                        AboutScreen.paypalUrl,
                        'PayPal link',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ═══ Section Header: Architecture & Features ═══
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.layers_outlined,
                  color: AppColors.primaryLight,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'ARCHITECTURE & KEY CAPABILITIES',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildFeatureRow(
                  icon: Icons.shield_outlined,
                  title: '100% Local & Private',
                  subtitle:
                      'Complete operational independence with zero cloud subscriptions, zero third-party telemetry, and zero mandatory external connections.',
                  accentColor: AppColors.success,
                ),
                const Divider(height: 20),
                _buildFeatureRow(
                  icon: Icons.memory_rounded,
                  title: 'Flash-Persistent Automations',
                  subtitle:
                      'Timers and conditional sensor rules execute deterministically on-chip in hardware and persist across reboots via LittleFS / Flash.',
                  accentColor: AppColors.primaryLight,
                ),
                const Divider(height: 20),
                _buildFeatureRow(
                  icon: Icons.alt_route_rounded,
                  title: 'Custom DIY Pin Matrix',
                  subtitle:
                      'Dynamic pin mapping with boot-glitch prevention, active HIGH/LOW logic polarity, and real-time pin conflict detection.',
                  accentColor: AppColors.purple,
                ),
                const Divider(height: 20),
                _buildFeatureRow(
                  icon: Icons.sensors_rounded,
                  title: 'Multi-Sensor Engine',
                  subtitle:
                      'Real-time metrics for DHT11/DHT22 climate, BME280 barometric pressure, MQ-2 gas/smoke hazards, and ultrasonic tank monitoring.',
                  accentColor: AppColors.cyan,
                ),
                const Divider(height: 20),
                _buildFeatureRow(
                  icon: Icons.system_security_update_rounded,
                  title: 'Safe Over-the-Air (OTA) Updates',
                  subtitle:
                      'Rollback-protected dual partition updates on ESP32 and MD5 verified flash streaming for ESP8266.',
                  accentColor: AppColors.warning,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ═══ Section Header: Developer & Repository ═══
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  color: AppColors.accent,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'DEVELOPER & REPOSITORY',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.primaryGlow,
                      child: Text(
                        'VC',
                        style: TextStyle(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AboutScreen.developerName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Project Creator & Embedded Systems Engineer',
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
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceElevated,
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: AppColors.cardBorder),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.code_rounded, size: 18),
                  label: const Text(
                    'View Project on GitHub',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  onPressed: () => _launchExternalUrl(AboutScreen.githubUrl),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Footer
          Center(
            child: Column(
              children: [
                Text(
                  'SmartHome Pro ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  ' Smart Home & Environmental Monitoring System ',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtleBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: accentColor, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
