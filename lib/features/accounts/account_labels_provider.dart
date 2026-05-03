import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/theme_provider.dart';
import '../../shared/models/account.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

enum LabelMatchType { contains, startsWith }

class AccountLabel {
  final String id;
  final String name;
  final LabelMatchType matchType;
  final String keyword;

  const AccountLabel({
    required this.id,
    required this.name,
    required this.matchType,
    required this.keyword,
  });

  bool matches(Account a) {
    final haystack = a.displayName.toLowerCase();
    final needle   = keyword.toLowerCase().trim();
    if (needle.isEmpty) return false;
    return matchType == LabelMatchType.startsWith
        ? haystack.startsWith(needle)
        : haystack.contains(needle);
  }

  AccountLabel copyWith({String? name, LabelMatchType? matchType, String? keyword}) =>
      AccountLabel(
        id:        id,
        name:      name        ?? this.name,
        matchType: matchType   ?? this.matchType,
        keyword:   keyword     ?? this.keyword,
      );

  Map<String, dynamic> toJson() => {
    'id':        id,
    'name':      name,
    'matchType': matchType.index,
    'keyword':   keyword,
  };

  factory AccountLabel.fromJson(Map<String, dynamic> j) => AccountLabel(
    id:        j['id']        as String,
    name:      j['name']      as String,
    matchType: LabelMatchType.values[(j['matchType'] as int).clamp(0, 1)],
    keyword:   j['keyword']   as String,
  );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

const _kLabelsKey = 'account_labels_v1';
const _uuid = Uuid();

class AccountLabelsNotifier extends StateNotifier<List<AccountLabel>> {
  AccountLabelsNotifier(super.initial);

  // Provider ref is injected so we can persist after mutations.
  late final _persist = state; // placeholder — overwritten in factory

  // Called by the provider factory with the SharedPreferences save callback.
  void Function(List<AccountLabel>)? _onChanged;

  void _save() => _onChanged?.call(state);

  Future<void> addLabel({
    required String name,
    required LabelMatchType matchType,
    required String keyword,
  }) async {
    state = [
      ...state,
      AccountLabel(
        id:        _uuid.v4(),
        name:      name,
        matchType: matchType,
        keyword:   keyword,
      ),
    ];
    _save();
  }

  Future<void> updateLabel(AccountLabel updated) async {
    state = state.map((l) => l.id == updated.id ? updated : l).toList();
    _save();
  }

  Future<void> deleteLabel(String id) async {
    state = state.where((l) => l.id != id).toList();
    _save();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final list = List.of(state);
    if (newIndex > oldIndex) newIndex -= 1;
    list.insert(newIndex, list.removeAt(oldIndex));
    state = list;
    _save();
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final accountLabelsProvider =
    StateNotifierProvider<AccountLabelsNotifier, List<AccountLabel>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);

  List<AccountLabel> initial = [];
  final raw = prefs.getString(_kLabelsKey);
  if (raw != null) {
    try {
      initial = (jsonDecode(raw) as List)
          .map((e) => AccountLabel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  final notifier = AccountLabelsNotifier(initial);
  notifier._onChanged = (labels) {
    prefs.setString(_kLabelsKey, jsonEncode(labels.map((l) => l.toJson()).toList()));
  };
  return notifier;
});
