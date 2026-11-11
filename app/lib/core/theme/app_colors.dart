import 'package:flutter/material.dart';

class AppColors {
  /// Global theme flag: true for Dark mode, false for Light mode.
  /// Automatically updated by MaterialApp builder or theme provider.
  static bool isDark = true;

  // Backgrounds & Surfaces
  static Color get background => isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
  static Color get surface => isDark ? const Color(0xFF111726) : const Color(0xFFFFFFFF);
  static Color get surfaceElevated => isDark ? const Color(0xFF1A2238) : const Color(0xFFF1F5F9);
  static Color get card => isDark ? const Color(0xCC151C30) : const Color(0xFFFFFFFF);
  static Color get cardBorder => isDark ? const Color(0x1FFFFFFF) : const Color(0xFFE2E8F0);
  static Color get cardShadow => isDark ? Colors.transparent : const Color(0x0A000000);

  // Accent Colors
  static Color get primary => isDark ? const Color(0xFF6366F1) : const Color(0xFF4F46E5);
  static Color get primaryLight => isDark ? const Color(0xFFA5B4FC) : const Color(0xFF6366F1);
  static Color get primaryGlow => isDark ? const Color(0x4D6366F1) : const Color(0x204F46E5);
  static Color get accent => isDark ? const Color(0xFF818CF8) : const Color(0xFF4338CA);

  // Status & Telemetry
  static const Color success = Color(0xFF10B981); // Emerald Active Green
  static Color get successGlow => isDark ? const Color(0x3310B981) : const Color(0x2010B981);
  static const Color danger = Color(0xFFEF4444);  // Alarm / Danger Red
  static Color get dangerGlow => isDark ? const Color(0x33EF4444) : const Color(0x20EF4444);
  static const Color warning = Color(0xFFF59E0B); // Caution / Warming Amber
  static Color get warningGlow => isDark ? const Color(0x33F59E0B) : const Color(0x20F59E0B);
  static const Color info = Color(0xFF0EA5E9);    // Cyan / Sky
  static const Color cyan = Color(0xFF06B6D4);    // Electric Cyan
  static const Color purple = Color(0xFF8B5CF6);  // Electric Violet / Purple
  static const Color tempAmber = Color(0xFFF59E0B);
  static const Color humCyan = Color(0xFF06B6D4);
  static const Color gasNeonGreen = Color(0xFF10B981);

  // Luxury Gradients & Accents
  static List<Color> get cardGradient => isDark
      ? const [Color(0xFF161E30), Color(0xFF0F1524)]
      : const [Color(0xFFFFFFFF), Color(0xFFF8FAFC)];

  static List<Color> get activeRelayGradient => isDark
      ? const [Color(0xFF0A2E22), Color(0xFF0E1A27)]
      : const [Color(0xFFE8FBF1), Color(0xFFF6FCF8)];

  // Typography
  static Color get textPrimary => isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
  static Color get textSecondary => isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  static Color get textMuted => isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
}
