import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/theme_provider.dart';
import '../../shared/models/transaction.dart';
import 'transactions_provider.dart';

// ---------------------------------------------------------------------------
// Pinned template model
// ---------------------------------------------------------------------------

class QuickTemplate {
  final String  id;
  final String  name;        // user-given label, e.g. "Monthly Rent"
  final String  payeeName;
  final double? amount;      // null = user enters amount at the time of use
  final String? categoryId;
  final String? categoryName;
  final int?    categoryIconCodePoint;
  final String? accountId;
  final bool    isIncome;

  const QuickTemplate({
    required this.id,
    required this.name,
    required this.payeeName,
    this.amount,
    this.categoryId,
    this.categoryName,
    this.categoryIconCodePoint,
    this.accountId,
    this.isIncome = false,
  });

  Map<String, dynamic> toJson() => {
    'id':                   id,
    'name':                 name,
    'payeeName':            payeeName,
    'amount':               amount,
    'categoryId':           categoryId,
    'categoryName':         categoryName,
    'categoryIconCodePoint':categoryIconCodePoint,
    'accountId':            accountId,
    'isIncome':             isIncome,
  };

  factory QuickTemplate.fromJson(Map<String, dynamic> json) => QuickTemplate(
    id:                   json['id']          as String,
    name:                 json['name']        as String,
    payeeName:            json['payeeName']   as String,
    amount:               (json['amount']     as num?)?.toDouble(),
    categoryId:           json['categoryId']  as String?,
    categoryName:         json['categoryName'] as String?,
    categoryIconCodePoint:json['categoryIconCodePoint'] as int?,
    accountId:            json['accountId']   as String?,
    isIncome:             json['isIncome']    as bool? ?? false,
  );

  QuickTemplate copyWith({String? name, double? amount}) => QuickTemplate(
    id:                    id,
    name:                  name ?? this.name,
    payeeName:             payeeName,
    amount:                amount ?? this.amount,
    categoryId:            categoryId,
    categoryName:          categoryName,
    categoryIconCodePoint: categoryIconCodePoint,
    accountId:             accountId,
    isIncome:              isIncome,
  );
}

// ---------------------------------------------------------------------------
// Notifier — CRUD persisted in SharedPreferences
// ---------------------------------------------------------------------------

class QuickTemplatesNotifier extends Notifier<List<QuickTemplate>> {
  static const _prefKey = 'quick_templates_v1';

  @override
  List<QuickTemplate> build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final raw   = prefs.getString(_prefKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => QuickTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(QuickTemplate template) async {
    final prefs   = ref.read(sharedPreferencesProvider);
    final updated = [...state, template];
    await prefs.setString(_prefKey, _encode(updated));
    state = updated;
  }

  Future<void> remove(String id) async {
    final prefs   = ref.read(sharedPreferencesProvider);
    final updated = state.where((t) => t.id != id).toList();
    await prefs.setString(_prefKey, _encode(updated));
    state = updated;
  }

  Future<void> reorder(int oldIdx, int newIdx) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final list  = [...state];
    final item  = list.removeAt(oldIdx);
    list.insert(newIdx > oldIdx ? newIdx - 1 : newIdx, item);
    await prefs.setString(_prefKey, _encode(list));
    state = list;
  }

  static String _encode(List<QuickTemplate> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}

final quickTemplatesProvider =
    NotifierProvider<QuickTemplatesNotifier, List<QuickTemplate>>(
        QuickTemplatesNotifier.new);

// ---------------------------------------------------------------------------
// Auto-suggestion — derived from recent transaction history, no DB call.
// Top 5 expense payees by frequency in the last 60 days.
// ---------------------------------------------------------------------------

class AutoSuggestion {
  final String  payeeName;
  final double  medianAmount;
  final String? categoryId;
  final String? categoryName;
  final int?    categoryIconCodePoint;
  final int     frequency; // occurrences in the last 60 days

  const AutoSuggestion({
    required this.payeeName,
    required this.medianAmount,
    this.categoryId,
    this.categoryName,
    this.categoryIconCodePoint,
    required this.frequency,
  });
}

final quickSuggestionsProvider = Provider<List<AutoSuggestion>>((ref) {
  final txList = ref.watch(transactionsProvider).valueOrNull ?? [];
  final cutoff = DateTime.now().subtract(const Duration(days: 60));

  // Only confirmed expenses (not transfers) within the window
  final recent = txList.where((t) =>
      !t.isPendingReview &&
      !t.isTransfer &&
      t.amount < 0 &&
      !t.date.isBefore(cutoff) &&
      t.displayPayee.isNotEmpty,
  ).toList();

  // Group by lower-cased payee name
  final byPayee = <String, List<Transaction>>{};
  for (final tx in recent) {
    (byPayee[tx.displayPayee.toLowerCase()] ??= []).add(tx);
  }

  final suggestions = byPayee.entries.map((e) {
    final txs     = e.value;
    final amounts = txs.map((t) => t.amount.abs()).toList()..sort();
    final median  = amounts[amounts.length ~/ 2];

    // Most-used category for this payee
    final catFreq = <String, int>{};
    for (final t in txs) {
      if (t.categoryId != null) {
        catFreq.update(t.categoryId!, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    String? topCatId, topCatName;
    int?    topIcon;
    if (catFreq.isNotEmpty) {
      topCatId = (catFreq.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .first.key;
      final catTx = txs.firstWhere(
        (t) => t.categoryId == topCatId,
        orElse: () => txs.first,
      );
      topCatName = catTx.categoryName;
      topIcon    = catTx.categoryIconCodePoint;
    }

    return AutoSuggestion(
      payeeName:            txs.first.displayPayee, // preserve original casing
      medianAmount:         median,
      categoryId:           topCatId,
      categoryName:         topCatName,
      categoryIconCodePoint: topIcon,
      frequency:            txs.length,
    );
  }).toList()
    ..sort((a, b) => b.frequency.compareTo(a.frequency));

  return suggestions.take(5).toList();
});

// ---------------------------------------------------------------------------
// Helper — build a fresh QuickTemplate from a suggestion (for pinning)
// ---------------------------------------------------------------------------

QuickTemplate templateFromSuggestion(AutoSuggestion s, {String? name}) {
  const uuid = Uuid();
  return QuickTemplate(
    id:                    uuid.v4(),
    name:                  name ?? s.payeeName,
    payeeName:             s.payeeName,
    amount:                s.medianAmount,
    categoryId:            s.categoryId,
    categoryName:          s.categoryName,
    categoryIconCodePoint: s.categoryIconCodePoint,
    isIncome:              false,
  );
}
