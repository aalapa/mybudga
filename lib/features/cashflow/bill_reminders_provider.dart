import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/theme_provider.dart';

const _kKey = 'bill_reminders_v1';

class BillRemindersNotifier extends StateNotifier<Set<String>> {
  BillRemindersNotifier(super.initial);

  void Function(Set<String>)? _onChanged;

  bool isEnabled(String id) => state.contains(id);

  Future<void> setEnabled(String id, {required bool enabled}) async {
    state = enabled
        ? {...state, id}
        : state.where((s) => s != id).toSet();
    _onChanged?.call(state);
  }
}

final billRemindersProvider =
    StateNotifierProvider<BillRemindersNotifier, Set<String>>((ref) {
  final prefs  = ref.watch(sharedPreferencesProvider);
  final initial = (prefs.getStringList(_kKey) ?? []).toSet();
  final notifier = BillRemindersNotifier(initial);
  notifier._onChanged = (s) => prefs.setStringList(_kKey, s.toList());
  return notifier;
});
