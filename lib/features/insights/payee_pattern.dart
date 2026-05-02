// ---------------------------------------------------------------------------
// Payee pattern detection — pure Dart, no Flutter, no Riverpod
// ---------------------------------------------------------------------------

enum PatternConfidence {
  none,         // 0 visits — show nothing
  building,     // 1–2 visits — avg + budget remaining, no prediction yet
  tentative,    // 3–4 visits — early prediction with caveat
  established,  // 5+  visits — full confidence, drives notifications
}

enum FrequencyType { weekly, biweekly, monthly }

extension FrequencyLabel on FrequencyType {
  String get label {
    switch (this) {
      case FrequencyType.weekly:   return 'every week';
      case FrequencyType.biweekly: return 'every other week';
      case FrequencyType.monthly:  return 'once a month';
    }
  }

  String get shortLabel {
    switch (this) {
      case FrequencyType.weekly:   return 'weekly';
      case FrequencyType.biweekly: return 'bi-weekly';
      case FrequencyType.monthly:  return 'monthly';
    }
  }
}

const _kDayNames = [
  '', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

/// Immutable result of pattern analysis for a single payee.
class PayeePattern {
  final String payeeName;
  final int totalVisits;           // all-time visits in the query window
  final int visitsThisMonth;
  final double avgSpend;           // rolling avg of last 8 visits
  final double totalThisMonth;
  final PatternConfidence confidence;
  final FrequencyType? frequency;
  final int? typicalDayOfWeek;     // 1=Mon … 7=Sun; null = no clear day
  final int? projectedVisitsLeft;  // remaining expected visits this month

  const PayeePattern({
    required this.payeeName,
    required this.totalVisits,
    required this.visitsThisMonth,
    required this.avgSpend,
    required this.totalThisMonth,
    required this.confidence,
    this.frequency,
    this.typicalDayOfWeek,
    this.projectedVisitsLeft,
  });

  String? get typicalDayName =>
      typicalDayOfWeek != null ? _kDayNames[typicalDayOfWeek!] : null;

  /// How much budget to allocate per remaining visit.
  double? recommendedSpend(double budgetRemaining) {
    if (confidence.index < PatternConfidence.tentative.index) return null;
    if (projectedVisitsLeft == null || projectedVisitsLeft! <= 0) return null;
    return (budgetRemaining / projectedVisitsLeft!).clamp(0, double.infinity);
  }
}

// ---------------------------------------------------------------------------
// Detection
// ---------------------------------------------------------------------------

/// Pure function — call with expense amounts (positive) sorted or unsorted.
PayeePattern detectPayeePattern({
  required String payeeName,
  required List<({DateTime date, double amount})> transactions, // expenses, amount > 0
  required DateTime now,
}) {
  if (transactions.isEmpty) {
    return PayeePattern(
      payeeName: payeeName,
      totalVisits: 0,
      visitsThisMonth: 0,
      avgSpend: 0,
      totalThisMonth: 0,
      confidence: PatternConfidence.none,
    );
  }

  final sorted = [...transactions]..sort((a, b) => a.date.compareTo(b.date));

  // ── This month ─────────────────────────────────────────────────────────────
  final monthStart   = DateTime(now.year, now.month, 1);
  final thisMonthTxs = sorted.where((t) => !t.date.isBefore(monthStart)).toList();
  final totalThisMonth =
      thisMonthTxs.fold(0.0, (s, t) => s + t.amount);

  // ── Rolling average (last 8) ───────────────────────────────────────────────
  final recent = sorted.length > 8 ? sorted.sublist(sorted.length - 8) : sorted;
  final avgSpend = recent.fold(0.0, (s, t) => s + t.amount) / recent.length;

  // ── Confidence ────────────────────────────────────────────────────────────
  final confidence = sorted.length >= 5
      ? PatternConfidence.established
      : sorted.length >= 3
          ? PatternConfidence.tentative
          : PatternConfidence.building;

  // Not enough data for frequency/day detection
  if (confidence == PatternConfidence.building) {
    return PayeePattern(
      payeeName: payeeName,
      totalVisits: sorted.length,
      visitsThisMonth: thisMonthTxs.length,
      avgSpend: avgSpend,
      totalThisMonth: totalThisMonth,
      confidence: confidence,
    );
  }

  // ── Gap analysis → frequency ───────────────────────────────────────────────
  final gaps = <int>[];
  for (int i = 1; i < sorted.length; i++) {
    gaps.add(sorted[i].date.difference(sorted[i - 1].date).inDays);
  }
  final avgGap = gaps.fold(0, (s, g) => s + g) / gaps.length;

  final frequency = avgGap <= 9
      ? FrequencyType.weekly
      : avgGap <= 18
          ? FrequencyType.biweekly
          : avgGap <= 38
              ? FrequencyType.monthly
              : null;

  // ── Day-of-week mode ───────────────────────────────────────────────────────
  final dayCounts = <int, int>{};
  for (final t in sorted) {
    dayCounts[t.date.weekday] = (dayCounts[t.date.weekday] ?? 0) + 1;
  }
  final topEntry =
      dayCounts.entries.reduce((a, b) => a.value >= b.value ? a : b);
  // Require ≥50% of visits on the same day to call it "typical"
  final typicalDay =
      topEntry.value >= (sorted.length * 0.5).ceil() ? topEntry.key : null;

  // ── Project remaining visits this month ────────────────────────────────────
  int? projectedVisitsLeft;
  if (frequency != null) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final today       = now.day;

    switch (frequency) {
      case FrequencyType.weekly:
        if (typicalDay != null) {
          // Count how many Saturdays (etc.) are left after today
          var count = 0;
          for (var d = today + 1; d <= daysInMonth; d++) {
            if (DateTime(now.year, now.month, d).weekday == typicalDay) count++;
          }
          projectedVisitsLeft = count;
        } else {
          projectedVisitsLeft = ((daysInMonth - today) / 7).ceil();
        }
      case FrequencyType.biweekly:
        projectedVisitsLeft = ((daysInMonth - today) / 14).ceil().clamp(0, 2);
      case FrequencyType.monthly:
        projectedVisitsLeft = today <= (daysInMonth - 10) ? 1 : 0;
    }
  }

  return PayeePattern(
    payeeName: payeeName,
    totalVisits: sorted.length,
    visitsThisMonth: thisMonthTxs.length,
    avgSpend: avgSpend,
    totalThisMonth: totalThisMonth,
    confidence: confidence,
    frequency: frequency,
    typicalDayOfWeek: typicalDay,
    projectedVisitsLeft: projectedVisitsLeft,
  );
}
