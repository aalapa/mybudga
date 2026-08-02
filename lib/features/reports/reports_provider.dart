import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase/supabase_provider.dart';
import '../../shared/models/account.dart';
import '../../shared/providers/household_provider.dart';
import '../accounts/accounts_provider.dart';

// ---------------------------------------------------------------------------
// Public data models
// ---------------------------------------------------------------------------

class ReportsState {
  final double totalIncome;
  final double totalExpenses;
  final List<CategorySpend> byCategory;
  final List<MonthData> byMonth;
  final List<PayeeSpend> topPayees;
  final List<BudgetVsActualEntry> budgetVsActual;

  /// categoryId → list of monthly spending amounts, same order as [byMonth].
  final Map<String, List<double>> categoryMonthlySpend;

  /// categoryId → date string ('yyyy-MM-dd') → spending amount.
  /// Used for the inline weekly / daily drill-down chart.
  final Map<String, Map<String, double>> categoryDailySpend;

  /// Outflow split by how much choice you have over it, one entry per month.
  final List<TierMonth> byTierMonth;

  /// Every group with its classification, for the inline editor.
  final List<GroupTier> groupTiers;

  /// Per-category budget accuracy, overspend recurrence and predictability.
  final List<CategoryHealth> categoryHealth;

  /// Net worth per month, oldest first. Empty for a single-month window,
  /// where there is no trend to draw.
  final List<NetWorthPoint> netWorthByMonth;

  // Net-worth snapshot (from accounts — not period-scoped)
  final double totalAssets;
  final double totalLiabilities;

  const ReportsState({
    required this.totalIncome,
    required this.totalExpenses,
    required this.byCategory,
    required this.byMonth,
    required this.topPayees,
    required this.budgetVsActual,
    required this.categoryMonthlySpend,
    required this.categoryDailySpend,
    this.byTierMonth    = const [],
    this.groupTiers     = const [],
    this.categoryHealth  = const [],
    this.netWorthByMonth = const [],
    required this.totalAssets,
    required this.totalLiabilities,
  });

  double get netSavings  => totalIncome - totalExpenses;
  double get savingsRate => totalIncome > 0
      ? (netSavings / totalIncome).clamp(-1.0, 1.0)
      : 0;
  double get netWorth    => totalAssets - totalLiabilities;

  double tierTotal(SpendingTier t) =>
      byTierMonth.fold(0.0, (sum, m) => sum + m.amountOf(t));

  double get classifiedOutflow =>
      byTierMonth.fold(0.0, (sum, m) => sum + m.total);

  /// Share across the whole period, 0–1.
  double tierShare(SpendingTier t) =>
      classifiedOutflow > 0 ? tierTotal(t) / classifiedOutflow : 0;
}

/// How much choice you have over a group's spending.
///
/// Classified per group rather than inferred, because recurrence does not
/// imply obligation — groceries recur weekly and the amount is entirely
/// yours, rent recurs and it is not.
enum SpendingTier {
  fixed,
  essential,
  discretionary;

  static SpendingTier fromDb(String? s) => switch (s) {
        'fixed'         => SpendingTier.fixed,
        'discretionary' => SpendingTier.discretionary,
        _               => SpendingTier.essential,
      };

  String get toDb => name;

  String get label => switch (this) {
        SpendingTier.fixed         => 'Fixed',
        SpendingTier.essential     => 'Essential',
        SpendingTier.discretionary => 'Discretionary',
      };

  String get blurb => switch (this) {
        SpendingTier.fixed => 'Same amount, same time — owed before you decide anything',
        SpendingTier.essential => 'You have to spend it; how much flexes',
        SpendingTier.discretionary => 'Genuinely yours to choose',
      };
}

/// One month's outflow split by tier. Amounts are positive.
class TierMonth {
  final DateTime month;
  final double fixed;
  final double essential;
  final double discretionary;

  const TierMonth({
    required this.month,
    required this.fixed,
    required this.essential,
    required this.discretionary,
  });

  double get total => fixed + essential + discretionary;

  double amountOf(SpendingTier t) => switch (t) {
        SpendingTier.fixed         => fixed,
        SpendingTier.essential     => essential,
        SpendingTier.discretionary => discretionary,
      };

  /// Share of the month's classified outflow, 0–1.
  double shareOf(SpendingTier t) => total > 0 ? amountOf(t) / total : 0;
}

/// Net worth at the end of one month, reconstructed rather than recorded.
class NetWorthPoint {
  final DateTime month;
  final double assets;
  final double liabilities; // positive

  const NetWorthPoint({
    required this.month,
    required this.assets,
    required this.liabilities,
  });

  double get netWorth => assets - liabilities;
}

/// How predictable a category's monthly spend is.
enum Predictability {
  steady,
  variable,
  erratic;

  /// From the coefficient of variation of monthly spend.
  static Predictability fromCv(double cv) => cv < 0.25
      ? Predictability.steady
      : cv < 0.60
          ? Predictability.variable
          : Predictability.erratic;

  String get label => switch (this) {
        Predictability.steady   => 'steady',
        Predictability.variable => 'variable',
        Predictability.erratic  => 'erratic',
      };

  String get advice => switch (this) {
        Predictability.steady   => 'safe to budget to the dollar',
        Predictability.variable => 'leave a little room',
        Predictability.erratic  => 'budget a buffer, not a target',
      };
}

/// Whether a category's budget is actually working: how far off it usually
/// lands, which way, how often it goes red, and how predictable it is.
class CategoryHealth {
  final String categoryId;
  final String name;

  /// Months in the period where something was budgeted — the only months a
  /// bias can be measured from.
  final int monthsBudgeted;
  final int overspendMonths;
  final double avgOverspend;

  /// Median of (spent - budgeted) / budgeted. Positive means you budget low.
  /// Median rather than mean so one unusual month cannot set the verdict.
  final double medianBias;

  /// Coefficient of variation of monthly spend across the whole period.
  final double volatility;

  /// Median monthly spend, as a starting point for a better number.
  final double suggestedBudget;

  const CategoryHealth({
    required this.categoryId,
    required this.name,
    required this.monthsBudgeted,
    required this.overspendMonths,
    required this.avgOverspend,
    required this.medianBias,
    required this.volatility,
    required this.suggestedBudget,
  });

  /// Three months is the fewest that can distinguish a pattern from noise.
  bool get hasSignal => monthsBudgeted >= 3;

  Predictability get predictability => Predictability.fromCv(volatility);

  /// Within 10% either way is close enough to call on target.
  bool get isOnTarget => medianBias.abs() < 0.10;

  bool get budgetsLow => medianBias >= 0.10;

  /// Ranks how much attention it wants: chronic overspending first, then how
  /// far the budget is off.
  double get severity =>
      (monthsBudgeted == 0 ? 0 : overspendMonths / monthsBudgeted) * 2 +
      medianBias.abs();
}

/// A group and how it is classified, for the inline editor.
class GroupTier {
  final String id;
  final String name;
  final SpendingTier tier;
  /// True when nobody has classified it and the default is a guess.
  final bool isDefault;
  const GroupTier({
    required this.id,
    required this.name,
    required this.tier,
    required this.isDefault,
  });
}

class CategorySpend {
  final String? categoryId;
  final String  name;
  final double  amount; // positive = spending

  const CategorySpend({this.categoryId, required this.name, required this.amount});
}

class MonthData {
  final DateTime month;
  final double   income;
  final double   expenses; // positive

  const MonthData({required this.month, required this.income, required this.expenses});

  double get savings     => income - expenses;
  double get savingsRate => income > 0 ? savings / income : 0;
}

class PayeeSpend {
  final String name;
  final double amount; // positive

  const PayeeSpend({required this.name, required this.amount});
}

class BudgetVsActualEntry {
  final String? categoryId;
  final String  name;
  final double  budgeted;
  final double  spent;

  const BudgetVsActualEntry({
    this.categoryId,
    required this.name,
    required this.budgeted,
    required this.spent,
  });

  double get variance     => budgeted - spent;
  bool   get isOverBudget => spent > budgeted && budgeted > 0;
  double get progress     => budgeted > 0 ? (spent / budgeted).clamp(0.0, 1.5) : 0;
}

// ---------------------------------------------------------------------------
// Chart palette — used by screen too
// ---------------------------------------------------------------------------

const chartPalette = <Color>[
  Color(0xFF6C63FF), // violet
  Color(0xFF00BFA5), // teal
  Color(0xFFFF6B6B), // coral
  Color(0xFFFFCA28), // amber
  Color(0xFF42A5F5), // sky blue
  Color(0xFFEC407A), // pink
  Color(0xFF66BB6A), // green
  Color(0xFFFF7043), // deep orange
  Color(0xFF26C6DA), // cyan
  Color(0xFFAB47BC), // purple
];

// ---------------------------------------------------------------------------
// Provider — keyed by number of months
// ---------------------------------------------------------------------------

final reportsProvider = FutureProvider.autoDispose
    .family<ReportsState, int>((ref, months) async {
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);
  final accounts    = ref.watch(accountsProvider).valueOrNull ?? [];

  // ── Date range ──────────────────────────────────────────────────────────
  final now       = DateTime.now();
  final startDate = DateTime(now.year, now.month - months + 1, 1);
  final startStr  = '${startDate.year}-'
      '${startDate.month.toString().padLeft(2, '0')}-01';
  final endStr    = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';

  // ── Fetch transactions + budget months in parallel ───────────────────────
  final results = await Future.wait([
    client
        .from('transactions')
        .select('date, amount, account_id, payees(name), '
            'categories(id, name, linked_account_id, '
            'category_groups(id, name, spending_tier))')
        .eq('household_id', householdId)
        .gte('date', startStr)
        .isFilter('deleted_at', null)
        .order('date', ascending: true),
    client
        .from('budget_months')
        .select('category_id, budgeted, month, '
            'categories(name, linked_account_id)')
        .eq('household_id', householdId)
        .gte('month', startStr)
        .lte('month', endStr),
  ]);

  final res       = results[0] as List;
  final budgetRes = results[1] as List;

  // ── Aggregate transactions ────────────────────────────────────────────────
  double totalIncome   = 0;
  double totalExpenses = 0;
  final Map<String, _CatAgg>             catMap      = {};
  final Map<String, double>              payeeMap    = {};
  final Map<String, _MonthAgg>           monthMap    = {};
  final Map<String, Map<String, double>> catMonthAgg = {}; // catId → monthKey → amt
  final Map<String, Map<String, double>> catDayAgg   = {}; // catId → 'yyyy-MM-dd' → amt

  // monthKey → tier → amount, plus every group seen and how it is classified.
  final Map<String, Map<SpendingTier, double>> tierAgg = {};
  final Map<String, GroupTier> groupTierMap = {};

  // accountId → monthKey → net movement, for reconstructing past balances.
  final Map<String, Map<String, double>> acctMonthDelta = {};

  for (final r in res) {
    final amount = (r['amount'] as num).toDouble();
    final date   = DateTime.parse(r['date'] as String);
    final cat    = r['categories'] as Map<String, dynamic>?;
    final payee  = r['payees']     as Map<String, dynamic>?;

    final acctId = r['account_id'] as String?;
    if (acctId != null) {
      final mk = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      (acctMonthDelta[acctId] ??= {})
          .update(mk, (v) => v + amount, ifAbsent: () => amount);
    }

    // Outflow by tier. Card payment envelopes are skipped: their charges are
    // already counted against the categories they were booked to, so including
    // both would double every card purchase.
    if (amount < 0 && cat != null && cat['linked_account_id'] == null) {
      final grp = cat['category_groups'] as Map<String, dynamic>?;
      if (grp != null) {
        final raw  = grp['spending_tier'] as String?;
        final gid  = grp['id']   as String;
        final gnm  = grp['name'] as String;
        final tier = raw != null
            ? SpendingTier.fromDb(raw)
            : _defaultTierFor(gnm);
        groupTierMap[gid] = GroupTier(
            id: gid, name: gnm, tier: tier, isDefault: raw == null);
        final mk = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        (tierAgg[mk] ??= {})
            .update(tier, (v) => v + amount.abs(), ifAbsent: () => amount.abs());
      }
    }

    if (amount > 0) {
      totalIncome += amount;
    } else {
      totalExpenses += amount.abs();
    }

    // By category (expenses only)
    if (amount < 0 && cat != null) {
      final id   = cat['id']   as String;
      final name = cat['name'] as String;
      catMap.update(
        id,
        (v) => v..amount += amount.abs(),
        ifAbsent: () => _CatAgg(id: id, name: name, amount: amount.abs()),
      );

      // Per-category per-month breakdown for deep-dive
      final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      catMonthAgg.putIfAbsent(id, () => {});
      catMonthAgg[id]!.update(monthKey, (v) => v + amount.abs(),
          ifAbsent: () => amount.abs());

      // Per-category daily breakdown for inline weekly/daily chart
      final dayKey = '${date.year}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      catDayAgg.putIfAbsent(id, () => {});
      catDayAgg[id]!.update(dayKey, (v) => v + amount.abs(),
          ifAbsent: () => amount.abs());
    }

    // By payee (expenses only)
    if (amount < 0) {
      final name = payee?['name'] as String? ?? 'Unknown';
      payeeMap.update(name, (v) => v + amount.abs(),
          ifAbsent: () => amount.abs());
    }

    // By month
    final monthKey  = '${date.year}-${date.month.toString().padLeft(2, '0')}';
    final monthDate = DateTime(date.year, date.month, 1);
    monthMap.update(
      monthKey,
      (v) {
        if (amount > 0) {
          v.income += amount;
        } else {
          v.expenses += amount.abs();
        }
        return v;
      },
      ifAbsent: () => _MonthAgg(month: monthDate)
        ..income   = amount > 0 ? amount : 0
        ..expenses = amount < 0 ? amount.abs() : 0,
    );
  }

  // Fill in months with no transactions so charts always have all bars
  for (var i = 0; i < months; i++) {
    final m   = DateTime(now.year, now.month - months + 1 + i);
    final key = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    monthMap.putIfAbsent(key, () => _MonthAgg(month: DateTime(m.year, m.month, 1)));
  }

  // ── Build sorted output lists ─────────────────────────────────────────────
  final byCategory = catMap.values
      .map((a) => CategorySpend(categoryId: a.id, name: a.name, amount: a.amount))
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  final topPayees = (payeeMap.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(8)
      .map((e) => PayeeSpend(name: e.key, amount: e.value))
      .toList();

  final sortedMonthKeys = (monthMap.keys.toList()..sort());
  final byMonth = sortedMonthKeys
      .map((k) => monthMap[k]!)
      .map((m) => MonthData(month: m.month, income: m.income, expenses: m.expenses))
      .toList();

  // ── Outflow by tier, aligned to the same month axis as byMonth ───────────
  final byTierMonth = sortedMonthKeys.map((k) {
    final t = tierAgg[k] ?? const {};
    return TierMonth(
      month:         monthMap[k]!.month,
      fixed:         t[SpendingTier.fixed]         ?? 0,
      essential:     t[SpendingTier.essential]     ?? 0,
      discretionary: t[SpendingTier.discretionary] ?? 0,
    );
  }).toList();

  final groupTiers = groupTierMap.values.toList()
    ..sort((a, b) {
      final c = a.tier.index.compareTo(b.tier.index);
      return c != 0 ? c : a.name.compareTo(b.name);
    });

  // ── Per-category monthly spend (for deep-dive chart) ─────────────────────
  final categoryMonthlySpend = <String, List<double>>{
    for (final catId in catMonthAgg.keys)
      catId: sortedMonthKeys
          .map((k) => catMonthAgg[catId]?[k] ?? 0.0)
          .toList(),
  };

  // ── Budget vs actual ──────────────────────────────────────────────────────
  final Map<String, _BudgetAgg> budgetMap = {};
  for (final r in budgetRes) {
    final catId = r['category_id'] as String;
    final amt   = (r['budgeted']   as num).toDouble();
    final cat   = r['categories']  as Map<String, dynamic>?;
    final name  = cat?['name']     as String? ?? 'Unknown';
    budgetMap.update(catId, (v) => v..amount += amt,
        ifAbsent: () => _BudgetAgg(id: catId, name: name, amount: amt));
  }

  // ── Budget health: accuracy, overspend recurrence, predictability ────────
  // Needs budget per category *per month*; the aggregate above cannot show a
  // pattern, only a period total.
  final budgetByCatMonth = <String, Map<String, double>>{};
  final healthNames      = <String, String>{};
  for (final r in budgetRes) {
    final catId = r['category_id'] as String?;
    final cat   = r['categories'] as Map<String, dynamic>?;
    if (catId == null || cat == null) continue;
    // Card envelopes have no assignable budget, so a bias against one is
    // meaningless — it would read as permanently 100% underbudgeted.
    if (cat['linked_account_id'] != null) continue;
    final amt = (r['budgeted'] as num).toDouble();
    if (amt <= 0) continue;
    final mk = _monthKeyOfDate(r['month'] as String);
    (budgetByCatMonth[catId] ??= {})[mk] = amt;
    healthNames[catId] = cat['name'] as String? ?? '';
  }

  final categoryHealth = <CategoryHealth>[];
  for (final catId in budgetByCatMonth.keys) {
    final months  = budgetByCatMonth[catId]!;
    final errors  = <double>[];
    final actuals = <double>[];
    var overspendMonths = 0;
    var overspendTotal  = 0.0;

    for (final entry in months.entries) {
      final budgeted = entry.value;
      final spent    = catMonthAgg[catId]?[entry.key] ?? 0.0;
      errors.add((spent - budgeted) / budgeted);
      actuals.add(spent);
      // 1% tolerance: landing a dollar or two over is rounding, not a
      // pattern, and counting it would rank a category that is essentially on
      // target alongside one that is genuinely running hot every month.
      if (spent > budgeted * 1.01) {
        overspendMonths++;
        overspendTotal += spent - budgeted;
      }
    }

    // Predictability is measured over every month in the period, not just the
    // budgeted ones: a category that is zero some months genuinely is erratic.
    final allSpend =
        sortedMonthKeys.map((k) => catMonthAgg[catId]?[k] ?? 0.0).toList();
    final mean = allSpend.isEmpty
        ? 0.0
        : allSpend.reduce((a, b) => a + b) / allSpend.length;
    var variance = 0.0;
    for (final v in allSpend) {
      variance += (v - mean) * (v - mean);
    }
    variance = allSpend.isEmpty ? 0 : variance / allSpend.length;
    final cv = mean > 0 ? math.sqrt(variance) / mean : 0.0;

    categoryHealth.add(CategoryHealth(
      categoryId:      catId,
      name:            healthNames[catId] ?? '',
      monthsBudgeted:  months.length,
      overspendMonths: overspendMonths,
      avgOverspend:    overspendMonths == 0 ? 0 : overspendTotal / overspendMonths,
      medianBias:      _median(errors),
      volatility:      cv,
      suggestedBudget: _median(actuals),
    ));
  }
  categoryHealth.sort((a, b) => b.severity.compareTo(a.severity));

  final budgetVsActual = budgetMap.keys
      .where((id) => budgetMap[id]!.amount > 0)
      .map((id) {
        final b     = budgetMap[id]!;
        final spent = catMap[id]?.amount ?? 0.0;
        return BudgetVsActualEntry(
          categoryId: id,
          name:       b.name,
          budgeted:   b.amount,
          spent:      spent,
        );
      })
      .toList()
    ..sort((a, b) {
      if (a.isOverBudget && !b.isOverBudget) return -1;
      if (!a.isOverBudget && b.isOverBudget) return 1;
      return b.spent.compareTo(a.spent);
    });

  // ── Net worth from live account balances ──────────────────────────────────
  double totalAssets      = 0;
  double totalLiabilities = 0;
  for (final a in accounts.where((a) => a.isActive)) {
    switch (a.type) {
      case AccountType.checking:
      case AccountType.savings:
      case AccountType.cash:
      case AccountType.investment:
      case AccountType.asset:
        totalAssets += a.balance.clamp(0, double.infinity);
      case AccountType.creditCard:
      case AccountType.lineOfCredit:
      case AccountType.loan:
      case AccountType.mortgage:
        if (a.balance < 0) totalLiabilities += a.balance.abs();
    }
  }

  // ── Net worth per month, unwound backwards from today's balances ─────────
  // Balances are only stored as they stand now, so history is reconstructed:
  // the balance at the end of a month is today's balance minus everything
  // that has moved since. Built backwards for that reason — forwards from
  // transactions alone would miss every opening balance that was set on the
  // account rather than recorded as a transaction, which for a house, a 401k
  // or a mortgage is nearly the whole figure.
  final netWorthByMonth = <NetWorthPoint>[];
  if (sortedMonthKeys.length > 1) {
    final active = accounts.where((a) => a.isActive).toList();
    for (var i = 0; i < sortedMonthKeys.length; i++) {
      double assets = 0, liabilities = 0;
      for (final a in active) {
        // Everything that moved after this month, so it can be taken back off.
        var movedSince = 0.0;
        for (var j = i + 1; j < sortedMonthKeys.length; j++) {
          movedSince += acctMonthDelta[a.id]?[sortedMonthKeys[j]] ?? 0.0;
        }
        final bal = a.balance - movedSince;
        // Sign, not account type: a card in credit is an asset that month,
        // and the live snapshot above reads it the same way.
        if (bal >= 0) {
          assets += bal;
        } else {
          liabilities += bal.abs();
        }
      }
      netWorthByMonth.add(NetWorthPoint(
        month:       monthMap[sortedMonthKeys[i]]!.month,
        assets:      assets,
        liabilities: liabilities,
      ));
    }
  }

  return ReportsState(
    totalIncome:          totalIncome,
    totalExpenses:        totalExpenses,
    byCategory:           byCategory,
    byMonth:              byMonth,
    topPayees:            topPayees,
    budgetVsActual:       budgetVsActual,
    categoryMonthlySpend: categoryMonthlySpend,
    categoryDailySpend:   catDayAgg,
    byTierMonth:          byTierMonth,
    groupTiers:           groupTiers,
    categoryHealth:       categoryHealth,
    netWorthByMonth:      netWorthByMonth,
    totalAssets:          totalAssets,
    totalLiabilities:     totalLiabilities,
  );
});

// ---------------------------------------------------------------------------
// Internal aggregation helpers (private)
// ---------------------------------------------------------------------------

class _CatAgg {
  final String id;
  final String name;
  double amount;
  _CatAgg({required this.id, required this.name, required this.amount});
}

class _MonthAgg {
  final DateTime month;
  double income   = 0;
  double expenses = 0;
  _MonthAgg({required this.month});
}

class _BudgetAgg {
  final String id;
  final String name;
  double amount;
  _BudgetAgg({required this.id, required this.name, required this.amount});
}

// ---------------------------------------------------------------------------
// Lifetime savings rate — all-time income vs expenses, excluding transfers
// and tracking accounts. Returns a value in [-1, 1].
// ---------------------------------------------------------------------------

final lifetimeSavingsRateProvider =
    FutureProvider.autoDispose<double>((ref) async {
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);

  final res = await client
      .from('transactions')
      .select('amount, transfer_id, accounts(is_tracking)')
      .eq('household_id', householdId)
      .eq('status', 'confirmed')
      .isFilter('deleted_at', null);

  double income   = 0;
  double expenses = 0;

  for (final r in res as List) {
    final transferId = r['transfer_id'] as String?;
    final isTracking = (r['accounts'] as Map?)?['is_tracking'] as bool? ?? false;
    if (transferId != null || isTracking) continue;
    final amount = (r['amount'] as num).toDouble();
    if (amount > 0) {
      income += amount;
    } else {
      expenses += amount.abs();
    }
  }

  return income > 0
      ? ((income - expenses) / income).clamp(-1.0, 1.0)
      : 0.0;
});


// ---------------------------------------------------------------------------
// Spending tier
// ---------------------------------------------------------------------------

/// Best guess for a group nobody has classified yet, from the seeded taxonomy
/// (Immediate Obligations, True Expenses, Debt Payments, Quality of Life
/// Goals, Just for Fun) which is already ordered by how much choice you have.
/// Only ever a starting point — the report marks these as unconfirmed.
SpendingTier _defaultTierFor(String groupName) {
  final n = groupName.toLowerCase();
  const fixed = [
    'obligation', 'debt', 'loan', 'credit card', 'mortgage', 'rent',
    'housing', 'insurance', 'subscription', 'emi', 'bill', 'premium',
    'tuition', 'childcare',
  ];
  const discretionary = [
    'fun', 'quality of life', 'discretion', 'want', 'entertainment',
    'dining', 'restaurant', 'shopping', 'leisure', 'hobby', 'hobbies',
    'travel', 'vacation', 'holiday', 'gift', 'lifestyle', 'luxur',
  ];
  if (fixed.any(n.contains))         return SpendingTier.fixed;
  if (discretionary.any(n.contains)) return SpendingTier.discretionary;
  return SpendingTier.essential;
}

/// Persists a group's classification. Kept as a function rather than a
/// notifier because reportsProvider is a plain family provider.
Future<void> setGroupSpendingTier(
  WidgetRef ref,
  String groupId,
  SpendingTier tier,
) async {
  final client = ref.read(supabaseProvider);
  await client
      .from('category_groups')
      .update({'spending_tier': tier.toDb})
      .eq('id', groupId);
  ref.invalidate(reportsProvider);
}

/// 'yyyy-MM-dd' → 'yyyy-MM'.
String _monthKeyOfDate(String date) => date.substring(0, 7);

double _median(List<double> xs) {
  if (xs.isEmpty) return 0;
  final s = [...xs]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}
