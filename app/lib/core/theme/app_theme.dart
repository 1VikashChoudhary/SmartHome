import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _prefKey = 'app_theme_mode_pref';

  @override
  ThemeMode build() {
    _loadPreference();
    return ThemeMode.dark; // Default to dark theme for SmartHome controller
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'light') {
        state = ThemeMode.light;
      } else if (saved == 'system') {
        state = ThemeMode.system;
      } else {
        state = ThemeMode.dark;
      }
    } catch (_) {}
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mode == ThemeMode.light) {
        await prefs.setString(_prefKey, 'light');
      } else if (mode == ThemeMode.dark) {
        await prefs.setString(_prefKey, 'dark');
      } else {
        await prefs.setString(_prefKey, 'system');
      }
    } catch (_) {}
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class AppTheme {
  // Static cached instances to prevent expensive GoogleFonts recalculation on every theme query
  static final ThemeData darkTheme = _buildDarkTheme();
  static final ThemeData lightTheme = _buildLightTheme();

  static ThemeData _buildDarkTheme() {
    GoogleFonts.config.allowRuntimeFetching = false;
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF090D16),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF6366F1),
        secondary: Color(0xFF818CF8),
        surface: Color(0xFF111726),
        error: Color(0xFFEF4444),
        onPrimary: Colors.white,
        onSurface: Color(0xFFF8FAFC),
      ),
      textTheme: baseTextTheme.copyWith(
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: const Color(0xFFF8FAFC),
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: const Color(0xFFF8FAFC),
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: const Color(0xFFF8FAFC),
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: const Color(0xFF94A3B8),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Color(0xFFF8FAFC)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xCC151C30),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0x1FFFFFFF), width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xEE111726),
        indicatorColor: const Color(0x336366F1),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: Color(0xFFA5B4FC), fontWeight: FontWeight.w600, fontSize: 12);
          }
          return const TextStyle(color: Color(0xFF64748B), fontSize: 12);
        }),
      ),
    );
  }

  static ThemeData _buildLightTheme() {
    GoogleFonts.config.allowRuntimeFetching = false;
    final baseTextTheme = GoogleFonts.plusJakartaSansTextTheme(
      ThemeData(brightness: Brightness.light).textTheme,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF4F46E5),
        secondary: Color(0xFF4338CA),
        surface: Color(0xFFFFFFFF),
        error: Color(0xFFEF4444),
        onPrimary: Colors.white,
        onSurface: Color(0xFF0F172A),
      ),
      textTheme: baseTextTheme.copyWith(
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: const Color(0xFF0F172A),
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: const Color(0xFF0F172A),
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: const Color(0xFF0F172A),
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: const Color(0xFF475569),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: Color(0xFF0F172A)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shadowColor: const Color(0x0C000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4F46E5),
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xF2FFFFFF),
        indicatorColor: const Color(0x204F46E5),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.w600, fontSize: 12);
          }
          return const TextStyle(color: Color(0xFF94A3B8), fontSize: 12);
        }),
      ),
    );
  }
}
