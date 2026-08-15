import '../../core/money.dart';
import 'package:intl/intl.dart';

enum GoalType {
  targetByDate,
  monthlySavings,
  monthlySpending;

  static GoalType fromString(String s) => switch (s) {
    'target_by_date'    => GoalType.targetByDate,
    'monthly_savings'   => GoalType.monthlySavings,
    'monthly_spending'  => GoalType.monthlySpending,
    _                   => GoalType.targetByDate,
  };

  String get toDb => switch (this) {
    GoalType.targetByDate    => 'target_by_date',
    GoalType.monthlySavings  => 'monthly_savings',
    GoalType.monthlySpending => 'monthly_spending',
  };
}

class BudgetGoal {
  final String id;
  final String categoryId;
  final GoalType type;
  final double targetAmount;
  final DateTime? targetDate;
  final double? monthlyAmount;

  const BudgetGoal({
    required this.id,
    required this.categoryId,
    required this.type,
    required this.targetAmount,
    this.targetDate,
    this.monthlyAmount,
  });

  factory BudgetGoal.fromJson(Map<String, dynamic> j) => BudgetGoal(
    id:            j['id'] as String,
    categoryId:    j['category_id'] as String,
    type:          GoalType.fromString(j['goal_type'] as String),
    targetAmount:  (j['target_amount'] as num).toDouble(),
    targetDate:    j['target_date'] != null
        ? DateTime.parse(j['target_date'] as String)
        : null,
    monthlyAmount: j['monthly_amount'] != null
        ? (j['monthly_amount'] as num).toDouble()
        : null,
  );

  int monthsRemaining(DateTime currentMonth) {
    if (targetDate == null) return 0;
    return (targetDate!.year - currentMonth.year) * 12 +
        (targetDate!.month - currentMonth.month);
  }

  double monthlyNeeded(DateTime currentMonth, double savedSoFar) {
    if (type == GoalType.monthlySavings || type == GoalType.monthlySpending) {
      return monthlyAmount ?? targetAmount;
    }
    final remaining = targetAmount - savedSoFar;
    final months = monthsRemaining(currentMonth);
    if (months <= 0) return remaining.clamp(0, double.infinity);
    return remaining / months;
  }

  double progressPercent(double savedSoFar) =>
      (savedSoFar / targetAmount).clamp(0.0, 1.0);

  bool isOnTrack(DateTime currentMonth, double budgetedThisMonth, double savedSoFar) {
    final needed = monthlyNeeded(currentMonth, savedSoFar);
    return budgetedThisMonth >= needed;
  }

  String targetDateLabel() {
    if (targetDate == null) return '';
    return DateFormat('MMM yyyy').format(targetDate!);
  }
}

class BudgetEntry {
  final String categoryId;
  final String categoryName;
  final String groupId;
  final String groupName;
  final int groupSortOrder;
  final int categorySortOrder;
  final double budgeted;
  /// Money that left this category. Negative for spending. For a CC
  /// payment envelope this is payments sent to the card only — charges
  /// are in [reserved].
  final double activity;
  /// carriedIn + budgeted + reserved + activity.
  final double balance;
  final bool isCcPayment;
  final bool carryOverspend;
  /// Balance rolled in from previous months. Available is
  /// [carriedIn] + [budgeted] + [reserved] + [activity], so without this the
  /// displayed columns look like they do not add up.
  final double carriedIn;
  /// CC payment envelopes only: money set aside this month by charges on the
  /// linked card. Kept apart from [activity] because charges and payments move
  /// the envelope in opposite directions — lumping them together made a normal
  /// month (spent more than paid) show as a positive Activity, which reads as
  /// an inflow everywhere else in the budget.
  final double reserved;
  final BudgetGoal? goal;
  final int? iconCodePoint;
  /// Non-null for CC payment envelopes — the linked CC account ID.
  final String? ccAccountId;

  const BudgetEntry({
    required this.categoryId,
    required this.categoryName,
    required this.groupId,
    required this.groupName,
    required this.groupSortOrder,
    required this.categorySortOrder,
    required this.budgeted,
    required this.activity,
    required this.balance,
    required this.isCcPayment,
    required this.carryOverspend,
    this.carriedIn = 0,
    this.reserved  = 0,
    this.goal,
    this.iconCodePoint,
    this.ccAccountId,
  });

  double get spent => activity < 0 ? activity.abs() : 0;

  /// A CC payment envelope is filled by card charges rather than drained by
  /// them, so [spent] stays 0 and a consumption bar would read as an empty
  /// battery no matter how heavily the card is used.
  bool get showsBudgetProgress => !isCcPayment && budgeted > 0;
}

class BudgetGroupData {
  final String id;
  final String name;
  final int sortOrder;
  final List<BudgetEntry> entries;

  const BudgetGroupData({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.entries,
  });

  double get balance => entries.fold(0.0, (s, e) => s + e.balance);
  bool get hasOverspend => entries.any((e) => isNegativeMoney(e.balance));
}

class CategoryTransaction {
  final String id;
  final DateTime date;
  final String payee;
  final double amount;
  final String accountName;

  const CategoryTransaction({
    required this.id,
    required this.date,
    required this.payee,
    required this.amount,
    required this.accountName,
  });
}
