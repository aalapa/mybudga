import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Pref keys ──────────────────────────────────────────────────────────────
const _kThemeMode = 'pref_theme_mode'; // ThemeMode.index (0=system,1=light,2=dark)
const _kSeedColor = 'pref_seed_color'; // ARGB int

// ── Default seed ────────────────────────────────────────────────────────────
const _kDefaultSeedValue = 0xFF5C00F2; // Electric Indigo

// ── Preset colour palette ───────────────────────────────────────────────────
/// Ordered list of (color, label) records shown in the colour picker.
const appColorPalette = [
  (color: Color(0xFF5C00F2), label: 'Indigo'),
  (color: Color(0xFF1565C0), label: 'Blue'),
  (color: Color(0xFF00695C), label: 'Teal'),
  (color: Color(0xFF2E7D32), label: 'Green'),
  (color: Color(0xFF6A1B9A), label: 'Purple'),
  (color: Color(0xFFC62828), label: 'Red'),
  (color: Color(0xFFE65100), label: 'Orange'),
  (color: Color(0xFFAD1457), label: 'Pink'),
  (color: Color(0xFF00838F), label: 'Cyan'),
  (color: Color(0xFF37474F), label: 'Slate'),
];

// ── State model ─────────────────────────────────────────────────────────────

class ThemeSettings {
  final ThemeMode mode;
  final Color seedColor;

  const ThemeSettings({required this.mode, required this.seedColor});

  ThemeSettings copyWith({ThemeMode? mode, Color? seedColor}) => ThemeSettings(
        mode:      mode      ?? this.mode,
        seedColor: seedColor ?? this.seedColor,
      );
}

// ── SharedPreferences provider (override with real instance in main.dart) ───

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
          seedColor: Color(
              _prefs.getInt(_kSeedColor) ?? _kDefaultSeedValue),
        ));

  Future<void> setMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await _prefs.setInt(_kThemeMode, mode.index);
  }

  Future<void> setSeedColor(Color color) async {
    state = state.copyWith(seedColor: color);
    await _prefs.setInt(_kSeedColor, color.toARGB32());
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeSettings>((ref) {
  return ThemeNotifier(ref.watch(sharedPreferencesProvider));
});
