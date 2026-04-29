import 'package:flutter/material.dart';

enum AccountType {
  checking,
  savings,
  creditCard,
  lineOfCredit,
  cash,
  investment,
  mortgage,
  loan,
  asset;

  static AccountType fromString(String s) => switch (s) {
    'checking'       => AccountType.checking,
    'savings'        => AccountType.savings,
    'credit_card'    => AccountType.creditCard,
    'line_of_credit' => AccountType.lineOfCredit,
    'cash'           => AccountType.cash,
    'investment'     => AccountType.investment,
    'mortgage'       => AccountType.mortgage,
    'loan'           => AccountType.loan,
    'asset'          => AccountType.asset,
    _                => AccountType.checking,
  };

  String get toDb => switch (this) {
    AccountType.creditCard    => 'credit_card',
    AccountType.lineOfCredit  => 'line_of_credit',
    _                         => name,
  };

  String get label => switch (this) {
    AccountType.checking     => 'Checking',
    AccountType.savings      => 'Savings',
    AccountType.creditCard   => 'Credit Card',
    AccountType.lineOfCredit => 'Line of Credit',
    AccountType.cash         => 'Cash',
    AccountType.investment   => 'Investment',
    AccountType.mortgage     => 'Mortgage',
    AccountType.loan         => 'Loan',
    AccountType.asset        => 'Asset',
  };

  String get typeName => switch (this) {
    AccountType.checking     => 'Checking account',
    AccountType.savings      => 'Savings account',
    AccountType.creditCard   => 'Credit card',
    AccountType.lineOfCredit => 'Line of credit',
    AccountType.cash         => 'Cash',
    AccountType.investment   => 'Investment account',
    AccountType.mortgage     => 'Mortgage',
    AccountType.loan         => 'Loan',
    AccountType.asset        => 'Asset',
  };

  IconData get icon => switch (this) {
    AccountType.checking     => Icons.account_balance_outlined,
    AccountType.savings      => Icons.savings_outlined,
    AccountType.creditCard   => Icons.credit_card_outlined,
    AccountType.lineOfCredit => Icons.credit_score_outlined,
    AccountType.cash         => Icons.payments_outlined,
    AccountType.investment   => Icons.show_chart,
    AccountType.mortgage     => Icons.home_outlined,
    AccountType.loan         => Icons.receipt_long_outlined,
    AccountType.asset        => Icons.diamond_outlined,
  };

  /// Whether this account type defaults to tracking (off-budget).
  bool get defaultTracking => switch (this) {
    AccountType.investment => true,
    AccountType.mortgage   => true,
    AccountType.loan       => true,
    AccountType.asset      => true,
    _                      => false,
  };
}

class Account {
  final String id;
  final String householdId;
  final String name;
  final String? nickname;
  final AccountType type;
  final bool isTracking;
  final String? lastFour;
  final double balance;
  final bool isActive;
  final DateTime? startDate;

  const Account({
    required this.id,
    required this.householdId,
    required this.name,
    this.nickname,
    required this.type,
    required this.isTracking,
    this.lastFour,
    required this.balance,
    this.isActive = true,
    this.startDate,
  });

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id:          json['id'] as String,
    householdId: json['household_id'] as String,
    name:        json['name'] as String,
    nickname:    json['nickname'] as String?,
    type:        AccountType.fromString(json['account_type'] as String),
    isTracking:  json['is_tracking'] as bool,
    lastFour:    json['last_four'] as String?,
    balance:     (json['current_balance'] as num).toDouble(),
    isActive:    json['is_active'] as bool,
    startDate:   json['start_date'] != null
                   ? DateTime.tryParse(json['start_date'] as String)
                   : null,
  );

  bool get isCreditCard => type == AccountType.creditCard;

  String get displayName {
    final n = nickname?.isNotEmpty == true ? nickname! : name;
    return lastFour != null ? '$n · $lastFour' : n;
  }

  Account copyWith({double? balance}) => Account(
    id: id, householdId: householdId, name: name, nickname: nickname,
    type: type, isTracking: isTracking, lastFour: lastFour,
    balance: balance ?? this.balance, isActive: isActive, startDate: startDate,
  );
}
