import 'package:flutter/material.dart';

/// Money semantics, kept deliberately apart from the brand palette.
///
/// `ColorScheme.fromSeed` derives `tertiary` at hue+60, which for the default
/// seed lands on pink — near-identical to `error`. The app had been using
/// `cs.tertiary` to mean "positive money", so positive and negative read the
/// same, and separate widgets had hard-coded their own greens and ambers on top
/// of that. Three colour languages in one row.
///
/// These values are fixed on purpose. They must never derive from `seedColor`:
/// re-theming the app is a brand choice, and it must not be able to turn
/// "you still have money" pink.
@immutable
class MoneyColors extends ThemeExtension<MoneyColors> {
  /// Money you still have.
  final Color positive;

  /// Fills and tracks behind [positive].
  final Color positiveMuted;

  /// Approaching a limit, or a tight day.
  final Color warning;

  /// Overspent, overdrawn. Matches `cs.error` in both brightnesses.
  final Color negative;

  const MoneyColors({
    required this.positive,
    required this.positiveMuted,
    required this.warning,
    required this.negative,
  });

  static const dark = MoneyColors(
    positive:      Color(0xFF86D9A6),
    positiveMuted: Color(0x2986D9A6),
    warning:       Color(0xFFFFC46B),
    negative:      Color(0xFFFFB4AB),
  );

  static const light = MoneyColors(
    positive:      Color(0xFF1E7A4B),
    positiveMuted: Color(0x1F1E7A4B),
    warning:       Color(0xFFA66A00),
    negative:      Color(0xFFBA1A1A),
  );

  @override
  MoneyColors copyWith({
    Color? positive,
    Color? positiveMuted,
    Color? warning,
    Color? negative,
  }) =>
      MoneyColors(
        positive:      positive      ?? this.positive,
        positiveMuted: positiveMuted ?? this.positiveMuted,
        warning:       warning       ?? this.warning,
        negative:      negative      ?? this.negative,
      );

  @override
  MoneyColors lerp(ThemeExtension<MoneyColors>? other, double t) {
    if (other is! MoneyColors) return this;
    return MoneyColors(
      positive:      Color.lerp(positive,      other.positive,      t)!,
      positiveMuted: Color.lerp(positiveMuted, other.positiveMuted, t)!,
      warning:       Color.lerp(warning,       other.warning,       t)!,
      negative:      Color.lerp(negative,      other.negative,      t)!,
    );
  }
}

extension MoneyColorsX on BuildContext {
  /// Money semantics for the current theme.
  MoneyColors get money => Theme.of(this).extension<MoneyColors>()!;
}
