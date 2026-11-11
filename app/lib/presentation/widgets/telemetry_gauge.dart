import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../../core/theme/app_colors.dart';

class TelemetryGauge extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final double percent; // 0.0 to 1.0
  final Color color;
  final IconData icon;
  final String? statusBadge;

  const TelemetryGauge({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.percent,
    required this.color,
    required this.icon,
    this.statusBadge,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131927) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0x1AFFFFFF) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row with Micro-Tracking
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Circular Arc Gauge with Dual Glow
          CircularPercentIndicator(
            radius: 40.0,
            lineWidth: 6.5,
            animation: true,
            animateFromLastPercent: true,
            percent: percent.clamp(0.0, 1.0),
            circularStrokeCap: CircularStrokeCap.round,
            progressColor: color,
            backgroundColor: isDark ? const Color(0xFF1E283E) : const Color(0xFFE2E8F0),
            center: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                if (unit.isNotEmpty)
                  Text(
                    unit,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Status Badge Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.16 : 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Text(
              statusBadge ?? (percent > 0.7 ? 'HIGH' : (percent > 0.3 ? 'OPTIMAL' : 'LOW')),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
