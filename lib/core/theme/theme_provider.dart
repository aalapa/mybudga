import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Pref keys ──────────────────────────────────────────────────────────────
const _kThemeMode    = 'pref_theme_mode';    // ThemeMode.index
const _kSeedColor    = 'pref_seed_color';    // ARGB int
const _kCardStyle    = 'pref_card_style';    // CardStyle.index
const _kCardRadius   = 'pref_card_radius';   // CardRadius.index
const _kSidebarColor = 'pref_sidebar_color'; // ARGB int, 0 = default
const _kTextScale    = 'pref_text_scale';    // double, 1.0 = default
const _kNewNav       = 'pref_new_nav';       // bool, opt-in bottom navigation

// ── Default seed ────────────────────────────────────────────────────────────
const _kDefaultSeedValue = 0xFF5C00F2; // Electric Indigo

// ── Card style & radius enums ───────────────────────────────────────────────

enum CardStyle { flat, outlined, elevated, tinted }

extension CardStyleExt on CardStyle {
  String get label => switch (this) {
    CardStyle.flat     => 'Flat',
    CardStyle.outlined => 'Outlined',
    CardStyle.elevated => 'Elevated',
    CardStyle.tinted   => 'Tinted',
  };
}

enum CardRadius { compact, standard, large }

extension CardRadiusExt on CardRadius {
  String get label => switch (this) {
    CardRadius.compact  => 'Compact',
    CardRadius.standard => 'Standard',
    CardRadius.large    => 'Rounded',
  };
  double get value => switch (this) {
    CardRadius.compact  => 8.0,
    CardRadius.standard => 16.0,
    CardRadius.large    => 24.0,
  };
}

// ── Sidebar colour options (shown in settings, adapt to theme mode) ──────────
/// Light options — use when theme is dark so sidebar stands out.
const sidebarColorsForDark = [
  (color: Color(0xFFF5F5F5), label: 'Snow'),
  (color: Color(0xFFF0EBE3), label: 'Cream'),
  (color: Color(0xFFE8EAF6), label: 'Lavender'),
  (color: Color(0xFFE3F2FD), label: 'Ice Blue'),
  (color: Color(0xFFE8F5E9), label: 'Mint'),
  (color: Color(0xFFFFF3E0), label: 'Peach'),
];

/// Dark options — use when theme is light so sidebar stands out.
const sidebarColorsForLight = [
  (color: Color(0xFF1A1A2E), label: 'Deep Navy'),
  (color: Color(0xFF263238), label: 'Slate'),
  (color: Color(0xFF1B5E20), label: 'Forest'),
  (color: Color(0xFF0D47A1), label: 'Royal'),
  (color: Color(0xFF4A148C), label: 'Plum'),
  (color: Color(0xFF37474F), label: 'Charcoal'),
];

// ── Preset colour palette (18 colours, two rows of 9) ───────────────────────
const appColorPalette = [
  (color: Color(0xFF5C00F2), label: 'Indigo'),
  (color: Color(0xFF1565C0), label: 'Blue'),
  (color: Color(0xFF01579B), label: 'Navy'),
  (color: Color(0xFF00695C), label: 'Teal'),
  (color: Color(0xFF00838F), label: 'Cyan'),
  (color: Color(0xFF2E7D32), label: 'Green'),
  (color: Color(0xFF558B2F), label: 'Forest'),
  (color: Color(0xFFF57F17), label: 'Amber'),
  (color: Color(0xFFE65100), label: 'Orange'),
  (color: Color(0xFFC62828), label: 'Red'),
  (color: Color(0xFFBF360C), label: 'Coral'),
  (color: Color(0xFFAD1457), label: 'Pink'),
  (color: Color(0xFF880E4F), label: 'Rose'),
  (color: Color(0xFF6A1B9A), label: 'Purple'),
  (color: Color(0xFF4A148C), label: 'Violet'),
  (color: Color(0xFF7B1FA2), label: 'Lavender'),
  (color: Color(0xFF37474F), label: 'Slate'),
  (color: Color(0xFF4E342E), label: 'Brown'),
];

// ── State model ─────────────────────────────────────────────────────────────

class ThemeSettings {
  final ThemeMode  mode;
  final Color      seedColor;
  final CardStyle  cardStyle;
  final CardRadius cardRadius;
  /// null = use default theme surface; non-null = custom sidebar background.
  final Color?     sidebarColor;

  /// Multiplier applied on top of the platform's own text scaling, so the
  /// app honours an OS accessibility setting and this preference together
  /// rather than overriding it.
  final double     textScale;

  /// Opt-in: Home · Budget · (+) · Cashflow · More. Off by default because it
  /// moves where four destinations live.
  final bool       useNewNav;

  const ThemeSettings({
    required this.mode,
    required this.seedColor,
    this.cardStyle   = CardStyle.flat,
    this.cardRadius  = CardRadius.standard,
    this.sidebarColor,
    this.textScale = 1.0,
    this.useNewNav = false,
  });

  ThemeSettings copyWith({
    ThemeMode?  mode,
    Color?      seedColor,
    CardStyle?  cardStyle,
    CardRadius? cardRadius,
    Color?      sidebarColor,
    bool        clearSidebarColor = false,
    double?     textScale,
    bool?       useNewNav,
  }) => ThemeSettings(
    mode:         mode       ?? this.mode,
    seedColor:    seedColor  ?? this.seedColor,
    cardStyle:    cardStyle  ?? this.cardStyle,
    cardRadius:   cardRadius ?? this.cardRadius,
    sidebarColor: clearSidebarColor ? null : (sidebarColor ?? this.sidebarColor),
    textScale:    textScale  ?? this.textScale,
    useNewNav:    useNewNav  ?? this.useNewNav,
  );
}

// ── SharedPreferences provider ───────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'sharedPreferencesProvider must be overridden in main.dart');
});

// ── Notifier ─────────────────────────────────────────────────────────────────

class ThemeNotifier extends StateNotifier<ThemeSettings> {
  final SharedPreferences _prefs;

  ThemeNotifier(this._prefs)
      : super(ThemeSettings(
          mode: ThemeMode.values[
              (_prefs.getInt(_kThemeMode) ?? ThemeMode.dark.index)
                  .clamp(0, ThemeMode.values.length - 1)],
          seedColor:  Color(_prefs.getInt(_kSeedColor)  ?? _kDefaultSeedValue),
          cardStyle:  CardStyle.values[
              (_prefs.getInt(_kCardStyle) ?? 0)
                  .clamp(0, CardStyle.values.length - 1)],
          cardRadius: CardRadius.values[
              (_prefs.getInt(_kCardRadius) ?? CardRadius.standard.index)
                  .clamp(0, CardRadius.values.length - 1)],
          sidebarColor: _prefs.getInt(_kSidebarColor) is int
              ? Color(_prefs.getInt(_kSidebarColor)!)
              : null,
          textScale: (_prefs.getDouble(_kTextScale) ?? 1.0).clamp(0.9, 1.2),
          useNewNav: _prefs.getBool(_kNewNav) ?? false,
        ));

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await _prefs.setInt(_kThemeMode, mode.index);
  }

  Future<void> setSeedColor(Color color) async {
    state = state.copyWith(seedColor: color);
    await _prefs.setInt(_kSeedColor, color.toARGB32());
  }

  Future<void> setCardStyle(CardStyle style) async {
    state = state.copyWith(cardStyle: style);
    await _prefs.setInt(_kCardStyle, style.index);
  }

  Future<void> setCardRadius(CardRadius radius) async {
    state = state.copyWith(cardRadius: radius);
    await _prefs.setInt(_kCardRadius, radius.index);
  }

  /// Steps rather than a free slider: fractional sizes read badly, and the
  /// budget's fixed-width numeric columns start clipping past ~1.2.
  static const textScaleSteps = <double>[0.9, 1.0, 1.1, 1.2];

  Future<void> setTextScale(double scale) async {
    state = state.copyWith(textScale: scale);
    await _prefs.setDouble(_kTextScale, scale);
  }

  Future<void> setUseNewNav(bool v) async {
    state = state.copyWith(useNewNav: v);
    await _prefs.setBool(_kNewNav, v);
  }

  Future<void> setSidebarColor(Color? color) async {
    if (color == null) {
      state = state.copyWith(clearSidebarColor: true);
      await _prefs.remove(_kSidebarColor);
    } else {
      state = state.copyWith(sidebarColor: color);
      await _prefs.setInt(_kSidebarColor, color.toARGB32());
    }
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeSettings>((ref) {
  return ThemeNotifier(ref.watch(sharedPreferencesProvider));
});
