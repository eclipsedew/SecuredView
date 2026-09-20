import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Exact website CSS variables from securedviewvpn.vercel.app
  static const Color paper = Color(0xFFECEEF0);         // --paper
  static const Color paper2 = Color(0xFFE3E6E9);        // --paper-2
  static const Color surface = Color(0xFFFFFFFF);       // --surface
  static const Color ink = Color(0xFF0E1417);           // --ink
  static const Color ink2 = Color(0xFF4A555C);          // --ink-2
  static const Color muted = Color(0xFF7E8A91);         // --muted
  static const Color line = Color(0xFFD8DCDD);          // --line
  static const Color line2 = Color(0xFFC2C8CA);         // --line-2
  static const Color blue = Color(0xFF163F8F);          // --blue
  static const Color blueDeep = Color(0xFF0E2A63);      // --blue-deep
  static const Color blueWash = Color(0xFFE7ECF7);      // --blue-wash
  static const Color signal = Color(0xFF1C7A52);        // --signal (green)

  // Backward compat aliases
  static const Color bg = paper;
  static const Color bgCard = surface;
  static const Color bgElevated = Color(0xFFF6F7F9);
  static const Color card = surface;
  static const Color accent = blue;
  static const Color accentLight = Color(0xFF4A7BD4);
  static const Color accentDark = blueDeep;
  static const Color success = signal;
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);
  static const Color textHigh = ink;
  static const Color textMed = ink2;
  static const Color textLow = muted;
  static const Color textPrimary = ink;
  static const Color textSecondary = ink2;
  static const Color textMuted = muted;
  static const Color primary = blue;
  static const Color primaryLight = Color(0xFF4A7BD4);
  static const Color premium = Color(0xFFB45309);
  static const Color background = paper;
  static const Color border = line;
  static const Color divider = line;

  static ThemeData get dark => _build();
  static ThemeData get darkTheme => _build();

  static ThemeData _build() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: paper,
      textTheme: GoogleFonts.publicSansTextTheme(
        ThemeData(brightness: Brightness.light).textTheme,
      ),
      colorScheme: const ColorScheme.light(
        primary: blue,
        surface: surface,
        error: error,
        onPrimary: Colors.white,
        onSurface: ink,
      ),
      cardColor: surface,
      dividerColor: line,
      appBarTheme: AppBarTheme(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.archivo(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: ink2, size: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: blue.withValues(alpha: 0.08),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.publicSans(color: blue, fontSize: 11, fontWeight: FontWeight.w600);
          }
          return GoogleFonts.publicSans(color: muted, fontSize: 11, fontWeight: FontWeight.w500);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: blue, size: 22);
          }
          return const IconThemeData(color: muted, size: 22);
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          textStyle: GoogleFonts.archivo(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          side: const BorderSide(color: line2, width: 1.5),
          textStyle: GoogleFonts.archivo(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: blue,
          textStyle: GoogleFonts.publicSans(fontSize: 14),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return blue;
          return line;
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: GoogleFonts.publicSans(color: surface, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
        ),
      ),
    );
  }
}
