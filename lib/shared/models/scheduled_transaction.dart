import 'account.dart';

enum ScheduledFrequency {
  once,
  weekly,
  biweekly,
  bimonthly,
  monthly,
  quarterly,
  halfYearly,
  yearly;

  static ScheduledFrequency fromString(String s) => switch (s) {
    'once'       => ScheduledFrequency.once,
    'weekly'     => ScheduledFrequency.weekly,
    'biweekly'   => ScheduledFrequency.biweekly,
    'bimonthly'  => ScheduledFrequency.bimonthly,
    'monthly'    => ScheduledFrequency.monthly,
    'quarterly'  => ScheduledFrequency.quarterly,
    'halfYearly' => ScheduledFrequency.halfYearly,
    'yearly'     => ScheduledFrequency.yearly,
    _            => ScheduledFrequency.monthly,
  };

  String get toDb => name;

  String get label => switch (this) {
    ScheduledFrequency.once       => 'Once',
    ScheduledFrequency.weekly     => 'Weekly',
    ScheduledFrequency.biweekly   => 'Bi-weekly',
    ScheduledFrequency.bimonthly  => 'Bi-monthly (twice/month)',
    ScheduledFrequency.monthly    => 'Monthly',
    ScheduledFrequency.quarterly  => 'Quarterly',
    ScheduledFrequency.halfYearly => 'Half-yearly',
    ScheduledFrequency.yearly     => 'Yearly',
  };

  /// Next occurrence after [from].
  ///
  /// [anchorDay] is the day of the month the schedule was created on. Month
  /// arithmetic clamps to the end of a short month rather than overflowing —
  /// `DateTime(2026, 2, 31)` silently becomes 3 March, which skipped February
  /// outright and then left a rent bill permanently on the 3rd. Keeping the
  /// anchor separately means a 31st bill lands on 28 Feb and returns to the
  /// 31st in March, instead of sticking to whatever the short month forced.
  DateTime? advance(DateTime from, {int? anchorDay}) => switch (this) {
    ScheduledFrequency.once       => null,
    ScheduledFrequency.weekly     => from.add(const Duration(days: 7)),
    ScheduledFrequency.biweekly   => from.add(const Duration(days: 14)),
    ScheduledFrequency.bimonthly  => from.day < 15
        ? DateTime(from.year, from.month, 15)
        : DateTime(from.year, from.month + 1, 1),
    ScheduledFrequency.monthly    => addMonths(from, 1,  anchorDay),
    ScheduledFrequency.quarterly  => addMonths(from, 3,  anchorDay),
    ScheduledFrequency.halfYearly => addMonths(from, 6,  anchorDay),
    ScheduledFrequency.yearly     => addMonths(from, 12, anchorDay),
  };

  /// Adds [months] to [from], landing on [anchorDay] where the target month is
  /// long enough and its last day where it is not.
  static DateTime addMonths(DateTime from, int months, int? anchorDay) {
    final zero = from.month - 1 + months;
    final year  = from.year + (zero ~/ 12);
    final month = zero % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day; // day 0 = previous month's last
    final want = anchorDay ?? from.day;
    return DateTime(year, month, want < lastDay ? want : lastDay);
  }
}

class ScheduledTransaction {
  final String id;
  final String householdId;

  /// FROM account. Null = chosen at payment time.
  final String? accountId;
  final String? accountName;
  final AccountType? accountType;

  /// Transfer destination account (credit card, savings, etc.).
  final bool isTransfer;
  final String? transferToAccountId;
  final String? transferToAccountName;

  final String? payeeId;
  final String? payeeName;
  final String? categoryId;
  final String? categoryName;
  final double amount;
  final String? memo;
  final ScheduledFrequency frequency;
  final DateTime nextDate;
  final DateTime? endDate;

  /// Day of the month the schedule was anchored to, so a 31st bill returns to
  /// the 31st after a short month instead of sticking wherever it was clamped.
  /// Null on rows created before this existed; falls back to next_date's day.
  final int? anchorDay;
  final bool autoApprove;
  final bool isActive;

  const ScheduledTransaction({
    required this.id,
    required this.householdId,
    this.accountId,
    this.accountName,
    this.accountType,
    this.isTransfer = false,
    this.transferToAccountId,
    this.transferToAccountName,
    this.payeeId,
    this.payeeName,
    this.categoryId,
    this.categoryName,
    required this.amount,
    this.memo,
    required this.frequency,
    required this.nextDate,
    this.endDate,
    this.anchorDay,
    required this.autoApprove,
    required this.isActive,
  });

  static String? _buildAccountName(Map<String, dynamic>? acctJson) {
    if (acctJson == null) return null;
    var name = acctJson['nickname'] as String? ?? acctJson['name'] as String? ?? '';
    final lastFour = acctJson['last_four'] as String?;
    if (lastFour != null) name = '$name · $lastFour';
    return name.isEmpty ? null : name;
  }

  factory ScheduledTransaction.fromJson(Map<String, dynamic> j) {
    final fromAcct = j['from_account'] as Map<String, dynamic>?;
    // to_account join removed from query (two FKs to accounts table causes
    // PostgREST ambiguity). TO account name is resolved from accountsProvider in UI.
    final payee    = j['payees']       as Map<String, dynamic>?;
    final cat      = j['categories']   as Map<String, dynamic>?;

    return ScheduledTransaction(
      id:                    j['id']           as String,
      householdId:           j['household_id'] as String,
      accountId:             j['account_id']   as String?,
      accountName:           _buildAccountName(fromAcct),
      accountType:           fromAcct != null
          ? AccountType.fromString(
              fromAcct['account_type'] as String? ?? 'checking')
          : null,
      isTransfer:            j['is_transfer']             as bool? ?? false,
      transferToAccountId:   j['transfer_to_account_id'] as String?,
      transferToAccountName: null,
      payeeId:               payee?['id']   as String?,
      payeeName:             payee?['name'] as String?,
      categoryId:            cat?['id']     as String?,
      categoryName:          cat?['name']   as String?,
      amount:                (j['amount'] as num).toDouble(),
      memo:                  j['memo']        as String?,
      frequency:             ScheduledFrequency.fromString(j['frequency'] as String),
      nextDate:              DateTime.parse(j['next_date'] as String),
      endDate:               j['end_date'] != null
          ? DateTime.parse(j['end_date'] as String)
          : null,
      anchorDay:             j['anchor_day'] as int?,
      autoApprove:           j['auto_approve'] as bool? ?? false,
      isActive:              j['is_active']    as bool? ?? true,
    );
  }

  bool get isIncome => amount > 0;

  /// Always include transfers and unknown-account bills in cashflow forecasts.
  bool get isCashAccount =>
      isTransfer ||
      accountType == null ||
      accountType == AccountType.checking ||
      accountType == AccountType.savings ||
      accountType == AccountType.cash;

  /// Needs user confirmation to create the actual transaction(s).
  /// Transfers always need confirmation (two-leg creation).
  bool get needsAccount => accountId == null || isTransfer;

  List<DateTime> occurrencesUntil(DateTime today, DateTime cutoff) {
    final result = <DateTime>[];
    DateTime? current = nextDate;
    while (current != null && !current.isAfter(cutoff)) {
      if (!current.isBefore(today)) {
        if (endDate == null || !current.isAfter(endDate!)) {
          result.add(current);
        }
      }
      current = frequency.advance(current, anchorDay: anchorDay);
    }
    return result;
  }
}
