import 'semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_provider.dart' show CardStyle, CardRadius, CardRadiusExt;

const kDefaultSeedColor = Color(0xFF5C00F2); // Electric Indigo

class AppTheme {
  // Build the cardTheme from style + radius
  static CardThemeData _cardTheme(
    ColorScheme cs,
    CardStyle style,
    double radius,
  ) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: style == CardStyle.outlined
          ? BorderSide(color: cs.outline.withValues(alpha: 0.30), width: 1)
          : BorderSide.none,
    );
    return switch (style) {
      CardStyle.flat => CardThemeData(
          elevation: 0,
          color: cs.surfaceContainerHigh,
          shape: shape,
        ),
      CardStyle.outlined => CardThemeData(
          elevation: 0,
          color: Colors.transparent,
          shape: shape,
        ),
      CardStyle.elevated => CardThemeData(
          elevation: 1,
          shadowColor: cs.shadow.withValues(alpha: 0.35),
          color: cs.surfaceContainerHighest,
          shape: shape,
        ),
      CardStyle.tinted => CardThemeData(
          elevation: 0,
          color: Color.lerp(cs.surfaceContainerHigh, cs.primaryContainer, 0.30)!,
          shape: shape,
        ),
    };
  }

  static ThemeData dark({
    Color      seedColor  = kDefaultSeedColor,
    CardStyle  cardStyle  = CardStyle.flat,
    CardRadius cardRadius = CardRadius.standard,
  }) {
    final cs     = ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);
    final radius = cardRadius.value;
    return ThemeData(
      useMaterial3: true,
      colorScheme:  cs,
      // Fixed, not seed-derived: see MoneyColors.
      extensions:   const [MoneyColors.dark],
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor:  cs.primaryContainer,
        labelTextStyle:  WidgetStateProperty.all(
          GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: cs.surface,
        indicatorColor:  cs.primaryContainer,
        labelType:       NavigationRailLabelType.all,
      ),
      cardTheme: _cardTheme(cs, cardStyle, radius),
      inputDecorationTheme: InputDecorationTheme(
        filled:    true,
        fillColor: cs.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  static ThemeData light({
    Color      seedColor  = kDefaultSeedColor,
    CardStyle  cardStyle  = CardStyle.flat,
    CardRadius cardRadius = CardRadius.standard,
  }) {
    final cs     = ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light);
    final radius = cardRadius.value;
    return ThemeData(
      useMaterial3: true,
      colorScheme:  cs,
      extensions:   const [MoneyColors.light],
      textTheme: GoogleFonts.plusJakartaSansTextTheme(
        ThemeData(brightness: Brightness.light).textTheme,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cs.surface,
        indicatorColor:  cs.primaryContainer,
        labelTextStyle:  WidgetStateProperty.all(
          GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: _cardTheme(cs, cardStyle, radius),
      inputDecorationTheme: InputDecorationTheme(
        filled:    true,
        fillColor: cs.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 16, fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
