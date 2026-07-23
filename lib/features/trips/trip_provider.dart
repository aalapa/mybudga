import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_provider.dart';
import '../../shared/providers/household_provider.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class TripSettings {
  final bool      isActive;
  final String?   tripName;
  final String?   categoryId;
  final DateTime? startDate;
  final DateTime? endDate;
  final double?   budget;

  const TripSettings({
    this.isActive   = false,
    this.tripName,
    this.categoryId,
    this.startDate,
    this.endDate,
    this.budget,
  });

  bool get hasEnded =>
      endDate != null && endDate!.isBefore(DateTime.now());

  bool get effectivelyActive => isActive && !hasEnded;

  int? get daysLeft {
    if (endDate == null) return null;
    final d = endDate!.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  factory TripSettings.fromJson(Map<String, dynamic> j) => TripSettings(
    isActive:   (j['is_active']  as bool?) ?? false,
    tripName:   j['trip_name']   as String?,
    categoryId: j['category_id'] as String?,
    startDate:  j['start_date'] != null
        ? DateTime.parse(j['start_date'] as String)
        : null,
    endDate:    j['end_date'] != null
        ? DateTime.parse(j['end_date'] as String)
        : null,
    budget: j['budget'] != null
        ? (j['budget'] as num).toDouble()
        : null,
  );

  static const empty = TripSettings();
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class TripNotifier extends AsyncNotifier<TripSettings> {
  @override
  Future<TripSettings> build() async {
    final householdId = await ref.watch(householdIdProvider.future);
    final client      = ref.watch(supabaseProvider);

    // Realtime: invalidate when trip_settings row changes
    final channel = client.channel('trip_settings:$householdId')
      ..onPostgresChanges(
        event:  PostgresChangeEvent.all,
        schema: 'public',
        table:  'trip_settings',
        filter: PostgresChangeFilter(
          type:   PostgresChangeFilterType.eq,
          column: 'household_id',
          value:  householdId,
        ),
        callback: (_) => ref.invalidateSelf(),
      )
      ..subscribe();
    ref.onDispose(() => client.removeChannel(channel));

    final row = await client
        .from('trip_settings')
        .select()
        .eq('household_id', householdId)
        .maybeSingle();

    return row != null
        ? TripSettings.fromJson(row as Map<String, dynamic>)
        : TripSettings.empty;
  }

  Future<void> save({
    required bool      isActive,
    String?            tripName,
    String?            categoryId,
    DateTime?          startDate,
    DateTime?          endDate,
    double?            budget,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    await client.from('trip_settings').upsert({
      'household_id': householdId,
      'is_active':    isActive,
      'trip_name':    tripName?.trim().isEmpty == true ? null : tripName?.trim(),
      'category_id':  categoryId,
      'start_date':   startDate != null ? _ds(startDate) : null,
      'end_date':     endDate   != null ? _ds(endDate)   : null,
      'budget':       budget,
      'updated_at':   DateTime.now().toIso8601String(),
    }, onConflict: 'household_id');

    ref.invalidateSelf();
  }

  Future<void> deactivate() async {
    final current = state.valueOrNull;
    if (current == null) return;
    await save(
      isActive:   false,
      tripName:   current.tripName,
      categoryId: current.categoryId,
      startDate:  current.startDate,
      endDate:    current.endDate,
      budget:     current.budget,
    );
  }

  static String _ds(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
}

final tripProvider =
    AsyncNotifierProvider<TripNotifier, TripSettings>(TripNotifier.new);
