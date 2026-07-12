import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DesignSystem {
  // Brand Colors
  static Color primary = const Color(0xFF56E472);
  static Color onPrimary = const Color(0xFF003911);
  static Color primaryContainer = const Color(0xFF34C759); // Core Accent
  
  static Color secondary = const Color(0xFF9FCAFF);
  static Color secondaryContainer = const Color(0xFF3A95E8); // Interactive Accent

  static Color error = const Color(0xFFFFB4AB);

  // Surfaces (Deep Dark)
  static Color background = const Color(0xFF000000); // Changed to pure black per specs
  static Color surface = const Color(0xFF000000); // Level 0
  static Color surfaceDim = const Color(0xFF0A0A0A); // Level 1 (Bubbles/Cards)
  static Color surfaceBright = const Color(0xFF111111); // Level 2 (User bubbles/dropdowns)
  
  static Color surfaceContainerLowest = const Color(0xFF000000);
  static Color surfaceContainerLow = const Color(0xFF0A0A0A);
  static Color surfaceContainer = const Color(0xFF111111);
  static Color surfaceContainerHigh = const Color(0xFF1C1C1C);
  static Color surfaceContainerHighest = const Color(0xFF262626);
  
  static Color onSurface = const Color(0xFFFFFFFF);
  static Color onSurfaceVariant = const Color(0xFFA0A0A0);

  // Borders
  static Color outline = const Color(0xFF1E1E1E); // Default
  static Color outlineVariant = const Color(0xFF2A2A2A); // Focus/Hover

  // Typography
  static final TextTheme textTheme = _buildTextTheme();

  static TextTheme _buildTextTheme() {
    return TextTheme(
      // Headlines (Hanken Grotesk)
      headlineLarge: GoogleFonts.hankenGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 32 / 24,
      ),
      headlineMedium: GoogleFonts.hankenGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 28 / 20,
      ),
      // Body (Inter)
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: const Color(0xFFDDE5D8),
        height: 24 / 16,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: const Color(0xFFDDE5D8),
        height: 20 / 14,
      ),
      // Metadata (JetBrains Mono)
      bodySmall: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF999999),
        height: 18 / 12,
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: const Color(0xFFBCCBB8),
        letterSpacing: 0.05,
        height: 14 / 11,
      ),
    );
  }

  // Theme parsing utilities
  static Color _fromHex(String hexString, {Color fallback = Colors.black}) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return fallback;
    }
  }

  static ThemeData buildDynamicTheme({
    required bool isDark,
    required String bgHex,
    required String fgHex,
    required String accentHex,
  }) {
    final bgColor = _fromHex(bgHex, fallback: background);
    final fgColor = _fromHex(fgHex, fallback: Colors.white);
    final accentColor = _fromHex(accentHex, fallback: primaryContainer);

    // Build surface container hierarchy from bg
    final hslBg = HSLColor.fromColor(bgColor);
    
    // For dark: surfaces get progressively lighter. For light: progressively darker.
    Color surfaceAt(double delta) {
      final l = isDark 
          ? (hslBg.lightness + delta).clamp(0.0, 1.0)
          : (hslBg.lightness - delta).clamp(0.0, 1.0);
      return hslBg.withLightness(l).toColor();
    }

    final surfContainerLowest = bgColor;
    final surfContainerLow = surfaceAt(0.02);
    final surfContainer = surfaceAt(0.04);
    final surfContainerHigh = surfaceAt(0.07);
    final surfContainerHighest = surfaceAt(0.10);
    final surfDim = surfaceAt(0.02);
    final surfBright = surfaceAt(0.04);

    // On-surface variant: muted foreground
    final hslFg = HSLColor.fromColor(fgColor);
    final onSurfVariant = hslFg.withLightness(
      isDark ? (hslFg.lightness * 0.6).clamp(0.3, 0.7) : (hslFg.lightness + 0.3).clamp(0.3, 0.7)
    ).toColor();

    // Outline colors
    final outlineColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFD0D0D0);
    final outlineVarColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFC0C0C0);

    // On-primary: contrasting text on accent
    final accentLum = accentColor.computeLuminance();
    final onPrimaryColor = accentLum > 0.5 ? Colors.black : Colors.white;

    // Error colors
    final errorColor = isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A);
    final onErrorColor = isDark ? const Color(0xFF690005) : Colors.white;

    // Secondary
    final secondaryColor = accentColor.withValues(alpha: 0.8);

    // Mutate legacy static colors so they automatically pick up the new theme
    background = bgColor;
    surface = bgColor;
    surfaceContainer = surfContainer;
    surfaceContainerHighest = surfContainerHighest;
    onSurface = fgColor;
    primary = accentColor;
    primaryContainer = accentColor;
    secondaryContainer = secondaryColor;
    DesignSystem.outline = outlineColor;
    DesignSystem.outlineVariant = outlineVarColor;
    DesignSystem.surfaceContainerLowest = surfContainerLowest;
    DesignSystem.surfaceContainerLow = surfContainerLow;
    DesignSystem.surfaceContainerHigh = surfContainerHigh;
    DesignSystem.surfaceDim = surfDim;
    DesignSystem.surfaceBright = surfBright;
    DesignSystem.onSurfaceVariant = onSurfVariant;
    DesignSystem.error = errorColor;
    DesignSystem.onPrimary = onPrimaryColor;

    // Build text theme with correct foreground color
    final dynamicTextTheme = TextTheme(
      headlineLarge: GoogleFonts.hankenGrotesk(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: fgColor,
        height: 32 / 24,
      ),
      headlineMedium: GoogleFonts.hankenGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: fgColor,
        height: 28 / 20,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: fgColor,
        height: 24 / 16,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: fgColor,
        height: 20 / 14,
      ),
      bodySmall: GoogleFonts.jetBrainsMono(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: onSurfVariant,
        height: 18 / 12,
      ),
      labelSmall: GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: onSurfVariant,
        letterSpacing: 0.05,
        height: 14 / 11,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: accentColor,
        onPrimary: onPrimaryColor,
        primaryContainer: accentColor,
        onPrimaryContainer: onPrimaryColor,
        secondary: secondaryColor,
        secondaryContainer: secondaryColor,
        surface: bgColor,
        surfaceDim: surfDim,
        surfaceBright: surfBright,
        surfaceContainerLowest: surfContainerLowest,
        surfaceContainerLow: surfContainerLow,
        surfaceContainer: surfContainer,
        surfaceContainerHigh: surfContainerHigh,
        surfaceContainerHighest: surfContainerHighest,
        error: errorColor,
        onError: onErrorColor,
        onSurface: fgColor,
        onSurfaceVariant: onSurfVariant,
        outline: outlineColor,
        outlineVariant: outlineVarColor,
      ),
      scaffoldBackgroundColor: bgColor,
      textTheme: dynamicTextTheme,
      
      // Inputs
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfBright,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: outlineColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: outlineColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: secondaryColor),
        ),
        hintStyle: dynamicTextTheme.bodyMedium?.copyWith(color: onSurfVariant.withValues(alpha: 0.5)),
      ),
      
      // Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: secondaryColor,
          foregroundColor: onPrimaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: dynamicTextTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
