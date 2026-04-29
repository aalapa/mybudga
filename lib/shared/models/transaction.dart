import 'account.dart';

enum TransactionStatus {
  pendingReview,
  confirmed;

  static TransactionStatus fromString(String s) =>
      s == 'pending_review' ? TransactionStatus.pendingReview : TransactionStatus.confirmed;

  String get toDb => switch (this) {
    TransactionStatus.pendingReview => 'pending_review',
    TransactionStatus.confirmed     => 'confirmed',
  };
}

class Transaction {
  final String id;
  final String householdId;
  final String accountId;
  final Account? account;
  final String? payeeId;
  final String? payeeName;
  final String? categoryId;
  final String? categoryName;
  final double amount;
  final DateTime date;
  final String? memo;
  final bool cleared;
  final TransactionStatus status;
  final String? transferId;

  const Transaction({
    required this.id,
    required this.householdId,
    required this.accountId,
    this.account,
    this.payeeId,
    this.payeeName,
    this.categoryId,
    this.categoryName,
    required this.amount,
    required this.date,
    this.memo,
    this.cleared = false,
    this.status = TransactionStatus.confirmed,
    this.transferId,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final accountJson = json['accounts'] as Map<String, dynamic>?;
    final payeeJson   = json['payees']   as Map<String, dynamic>?;
    final catJson     = json['categories'] as Map<String, dynamic>?;

    return Transaction(
      id:           json['id'] as String,
      householdId:  json['household_id'] as String,
      accountId:    json['account_id'] as String,
      account:      accountJson != null ? Account.fromJson(accountJson) : null,
      payeeId:      json['payee_id'] as String?,
      payeeName:    payeeJson?['name'] as String?,
      categoryId:   json['category_id'] as String?,
      categoryName: catJson?['name'] as String?,
      amount:       (json['amount'] as num).toDouble(),
      date:         DateTime.parse(json['date'] as String),
      memo:         json['memo'] as String?,
      cleared:      json['cleared'] as bool? ?? false,
      status:       TransactionStatus.fromString(json['status'] as String? ?? 'confirmed'),
      transferId:   json['transfer_id'] as String?,
    );
  }

  bool get isPendingReview => status == TransactionStatus.pendingReview;
  bool get isIncome => amount > 0;
  bool get isTransfer => transferId != null;

  String get displayPayee => payeeName ?? '';
}
