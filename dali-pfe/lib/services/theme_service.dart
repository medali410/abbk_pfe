import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  bool _isDarkMode = true;
  static const String _themeKey = 'app_theme_mode';

  bool get isDarkMode => _isDarkMode;

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool(_themeKey) ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, _isDarkMode);
    notifyListeners();
  }

  Future<void> setTheme(bool isDark) async {
    _isDarkMode = isDark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, _isDarkMode);
    notifyListeners();
  }

  ThemeData getTheme() {
    final textTheme = GoogleFonts.interTextTheme();

    if (_isDarkMode) {
      const primaryColor = Color(0xFFFF6E00);
      const scaffoldBackgroundColor = Color(0xFF0F0F1E);
      const surfaceContainer = Color(0xFF1E1E2E);
      const onSurfaceColor = Color(0xFFE2E8F0);
      const mutedColor = Color(0xFF6B869A);

      return ThemeData(
        brightness: Brightness.dark,
        primaryColor: primaryColor,
        scaffoldBackgroundColor: scaffoldBackgroundColor,
        colorScheme: const ColorScheme.dark(
          primary: primaryColor,
          surface: scaffoldBackgroundColor,
          onSurface: onSurfaceColor,
          surfaceContainerHighest: surfaceContainer,
        ),
        textTheme: textTheme.apply(bodyColor: onSurfaceColor, displayColor: onSurfaceColor),
        appBarTheme: const AppBarTheme(
          backgroundColor: scaffoldBackgroundColor,
          elevation: 0,
          iconTheme: IconThemeData(color: onSurfaceColor),
        ),
        cardTheme: CardThemeData(
          color: surfaceContainer,
          elevation: 2,
          shadowColor: Colors.black45,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF161625),
          labelStyle: const TextStyle(color: mutedColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: mutedColor.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: mutedColor.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
        ),
      );
    } else {
      const primaryColor = Color(0xFFCD7F32);
      const scaffoldBackgroundColor = Color(0xFFF9FAFB);
      const surfaceContainer = Color(0xFFFFFFFF);
      const onSurfaceColor = Color(0xFF1F2937);
      const mutedColor = Color(0xFF8B5E3C);

      return ThemeData(
        brightness: Brightness.light,
        primaryColor: primaryColor,
        scaffoldBackgroundColor: scaffoldBackgroundColor,
        colorScheme: const ColorScheme.light(
          primary: primaryColor,
          surface: scaffoldBackgroundColor,
          onSurface: onSurfaceColor,
          surfaceContainerHighest: Color(0xFFF1F5F9),
        ),
        textTheme: textTheme.apply(bodyColor: onSurfaceColor, displayColor: onSurfaceColor),
        appBarTheme: const AppBarTheme(
          backgroundColor: scaffoldBackgroundColor,
          elevation: 0,
          iconTheme: IconThemeData(color: onSurfaceColor),
        ),
        cardTheme: CardThemeData(
          color: surfaceContainer,
          elevation: 2,
          shadowColor: Colors.black12,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(color: mutedColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: mintedColorWithOpacityValue(mutedColor, 0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: mintedColorWithOpacityValue(mutedColor, 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryColor, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: primaryColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 10,
        ),
      );
    }
  }

  // Helper
  Color mintedColorWithOpacityValue(Color color, double opacity) => color.withOpacity(opacity);
}
