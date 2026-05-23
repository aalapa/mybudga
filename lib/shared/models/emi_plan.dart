/// A credit-card EMI plan: a large CC purchase split into [totalMonths]
/// equal monthly installments, each optionally carrying a [monthlyFee].
class EmiPlan {
  final String  id;
  final String  householdId;
  final String  description;   // user-facing name, e.g. "iPhone 16"
  final String  ccAccountId;   // credit card being paid down
  final String? fromAccountId; // checking/savings paying each installment
  final double  principal;     // total EMI amount (e.g. 1000)
  final double  monthlyAmount; // installment per month (e.g. 90)
  final double  monthlyFee;    // bank processing fee per month (e.g. 5)
  final int     totalMonths;
  final int     paidMonths;
  final DateTime startDate;
  final DateTime nextDate;
  final bool    isActive;
  final DateTime createdAt;

  const EmiPlan({
    required this.id,
    required this.householdId,
    required this.description,
    required this.ccAccountId,
    this.fromAccountId,
    required this.principal,
    required this.monthlyAmount,
    this.monthlyFee = 0,
    required this.totalMonths,
    required this.paidMonths,
    required this.startDate,
    required this.nextDate,
    required this.isActive,
    required this.createdAt,
  });

  // ── Computed ────────────────────────────────────────────────────────────────

  /// What leaves the bank account each month.
  double get monthlyOutflow => monthlyAmount + monthlyFee;

  int    get remainingMonths  => (totalMonths - paidMonths).clamp(0, totalMonths);
  double get remainingAmount  => remainingMonths * monthlyOutflow;
  double get totalInterest    => monthlyFee * totalMonths;
  bool   get isCompleted      => paidMonths >= totalMonths;
  double get progressFraction =>
      totalMonths > 0 ? (paidMonths / totalMonths).clamp(0.0, 1.0) : 0.0;

  // ── Serialisation ────────────────────────────────────────────────────────────

  factory EmiPlan.fromJson(Map<String, dynamic> j) => EmiPlan(
    id:            j['id']              as String,
    householdId:   j['household_id']    as String,
    description:   j['description']     as String,
    ccAccountId:   j['cc_account_id']   as String,
    fromAccountId: j['from_account_id'] as String?,
    principal:     (j['principal']      as num).toDouble(),
    monthlyAmount: (j['monthly_amount'] as num).toDouble(),
    monthlyFee:    (j['monthly_fee']    as num? ?? 0).toDouble(),
    totalMonths:   j['total_months']    as int,
    paidMonths:    j['paid_months']     as int,
    startDate:     DateTime.parse(j['start_date'] as String),
    nextDate:      DateTime.parse(j['next_date']  as String),
    isActive:      j['is_active']       as bool,
    createdAt:     DateTime.parse(j['created_at'] as String),
  );
}
