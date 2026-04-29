import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase/supabase_provider.dart';

/// The household_id for the currently signed-in user.
/// Throws if the user has no household (shouldn't happen after /setup).
final householdIdProvider = FutureProvider<String>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) throw Exception('Not authenticated');

  final client = ref.watch(supabaseProvider);
  final res = await client
      .from('household_members')
      .select('household_id')
      .eq('user_id', user.id)
      .limit(1)
      .single();

  return res['household_id'] as String;
});
