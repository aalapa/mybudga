enum ScheduledFrequency {
  once,
  weekly,
  biweekly,
  monthly,
  yearly;

  static ScheduledFrequency fromString(String s) => switch (s) {
    'once'     => ScheduledFrequency.once,
    'weekly'   => ScheduledFrequency.weekly,
    'biweekly' => ScheduledFrequency.biweekly,
    'monthly'  => ScheduledFrequency.monthly,
    'yearly'   => ScheduledFrequency.yearly,
    _          => ScheduledFrequency.monthly,
  };

  String get toDb => name;

  String get label => switch (this) {
    ScheduledFrequency.once     => 'Once',
    ScheduledFrequency.weekly   => 'Weekly',
    ScheduledFrequency.biweekly => 'Bi-weekly',
    ScheduledFrequency.monthly  => 'Monthly',
    ScheduledFrequency.yearly   => 'Yearly',
  };

  DateTime? advance(DateTime from) => switch (this) {
    ScheduledFrequency.once     => null,
    ScheduledFrequency.weekly   => from.add(const Duration(days: 7)),
    ScheduledFrequency.biweekly => from.add(const Duration(days: 14)),
    ScheduledFrequency.monthly  => DateTime(from.year, from.month + 1, from.day),
    ScheduledFrequency.yearly   => DateTime(from.year + 1, from.month, from.day),
  };
}

class ScheduledTransaction {
  final String id;
  final String householdId;
  final String accountId;
  final String accountName;
  final String? payeeId;
  final String? payeeName;
  final String? categoryId;
  final String? categoryName;
  final double amount;
  final String? memo;
  final ScheduledFrequency frequency;
  final DateTime nextDate;
  final DateTime? endDate;
  final bool autoApprove;
  final bool isActive;

  const ScheduledTransaction({
    required this.id,
    required this.householdId,
    required this.accountId,
    required this.accountName,
    this.payeeId,
    this.payeeName,
    this.categoryId,
    this.categoryName,
    required this.amount,
    this.memo,
    required this.frequency,
    required this.nextDate,
    this.endDate,
    required this.autoApprove,
    required this.isActive,
  });

  factory ScheduledTransaction.fromJson(Map<String, dynamic> j) {
    final acct  = j['accounts'] as Map<String, dynamic>? ?? {};
    final payee = j['payees']   as Map<String, dynamic>?;
    final cat   = j['categories'] as Map<String, dynamic>?;

    String accountName = acct['nickname'] as String? ??
        acct['name'] as String? ?? '';
    final lastFour = acct['last_four'] as String?;
    if (lastFour != null) accountName = '$accountName · $lastFour';

    return ScheduledTransaction(
      id:           j['id'] as String,
      householdId:  j['household_id'] as String,
      accountId:    j['account_id'] as String,
      accountName:  accountName,
      payeeId:      payee?['id'] as String?,
      payeeName:    payee?['name'] as String?,
      categoryId:   cat?['id'] as String?,
      categoryName: cat?['name'] as String?,
      amount:       (j['amount'] as num).toDouble(),
      memo:         j['memo'] as String?,
      frequency:    ScheduledFrequency.fromString(j['frequency'] as String),
      nextDate:     DateTime.parse(j['next_date'] as String),
      endDate:      j['end_date'] != null
          ? DateTime.parse(j['end_date'] as String)
          : null,
      autoApprove:  j['auto_approve'] as bool? ?? false,
      isActive:     j['is_active'] as bool? ?? true,
    );
  }

  bool get isIncome => amount > 0;

  /// All occurrences of this transaction within [today, cutoff] inclusive.
  List<DateTime> occurrencesUntil(DateTime today, DateTime cutoff) {
    final result = <DateTime>[];
    DateTime? current = nextDate;

    while (current != null && !current.isAfter(cutoff)) {
      if (!current.isBefore(today)) {
        if (endDate == null || !current.isAfter(endDate!)) {
          result.add(current);
        }
      }
      current = frequency.advance(current);
    }

    return result;
  }
}
