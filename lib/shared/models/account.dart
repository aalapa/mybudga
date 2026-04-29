import 'package:flutter/material.dart';

enum AccountType {
  checking,
  savings,
  creditCard,
  cash,
  investment,
  loan,
  asset;

  static AccountType fromString(String s) => switch (s) {
    'checking'    => AccountType.checking,
    'savings'     => AccountType.savings,
    'credit_card' => AccountType.creditCard,
    'cash'        => AccountType.cash,
    'investment'  => AccountType.investment,
    'loan'        => AccountType.loan,
    'asset'       => AccountType.asset,
    _             => AccountType.checking,
  };

  String get toDb => switch (this) {
    AccountType.creditCard => 'credit_card',
    _                      => name,
  };

  String get label => switch (this) {
    AccountType.checking   => 'Checking',
    AccountType.savings    => 'Savings',
    AccountType.creditCard => 'Credit Card',
    AccountType.cash       => 'Cash',
    AccountType.investment => 'Investment',
    AccountType.loan       => 'Loan',
    AccountType.asset      => 'Asset',
  };

  String get typeName => switch (this) {
    AccountType.checking   => 'Checking account',
    AccountType.savings    => 'Savings account',
    AccountType.creditCard => 'Credit card',
    AccountType.cash       => 'Cash',
    AccountType.investment => 'Investment account',
    AccountType.loan       => 'Loan',
    AccountType.asset      => 'Asset',
  };

  IconData get icon => switch (this) {
    AccountType.checking   => Icons.account_balance_outlined,
    AccountType.savings    => Icons.savings_outlined,
    AccountType.creditCard => Icons.credit_card_outlined,
    AccountType.cash       => Icons.payments_outlined,
    AccountType.investment => Icons.show_chart,
    AccountType.loan       => Icons.home_outlined,
    AccountType.asset      => Icons.diamond_outlined,
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
  );

  bool get isCreditCard => type == AccountType.creditCard;

  String get displayName {
    final n = nickname?.isNotEmpty == true ? nickname! : name;
    return lastFour != null ? '$n · $lastFour' : n;
  }

  Account copyWith({double? balance}) => Account(
    id: id, householdId: householdId, name: name, nickname: nickname,
    type: type, isTracking: isTracking, lastFour: lastFour,
    balance: balance ?? this.balance, isActive: isActive,
  );
}
