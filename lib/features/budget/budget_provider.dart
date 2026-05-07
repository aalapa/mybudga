import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase/supabase_provider.dart';
import '../../shared/models/budget_entry.dart';
import '../../shared/providers/categories_provider.dart';
import '../../shared/providers/household_provider.dart';

// ---------------------------------------------------------------------------
// Quick-budget enums (public so the UI can reference them)
// ---------------------------------------------------------------------------

enum QuickBudgetStrategy { currentMonth, lastMonth, averageSpending, coverSpending }
enum QuickBudgetScope    { thisMonth, next3, next6, next12 }

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class BudgetState {
  final DateTime month;
  final List<BudgetGroupData> groups;
  final double tbb;

  /// Inflows that flow into TBB: transactions with no category (positive amount).
  final double income;

  /// Total amount assigned to categories this month.
  final double totalBudgeted;

  const BudgetState({
    required this.month,
    required this.groups,
    required this.tbb,
    this.income       = 0,
    this.totalBudgeted = 0,
  });

  BudgetState copyWith({
    DateTime?           month,
    List<BudgetGroupData>? groups,
    double?             tbb,
    double?             income,
    double?             totalBudgeted,
  }) => BudgetState(
    month:         month         ?? this.month,
    groups:        groups        ?? this.groups,
    tbb:           tbb           ?? this.tbb,
    income:        income        ?? this.income,
    totalBudgeted: totalBudgeted ?? this.totalBudgeted,
  );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class BudgetNotifier extends AsyncNotifier<BudgetState> {
  DateTime _month = _firstOfMonth(DateTime.now());

  @override
  Future<BudgetState> build() async {
    final householdId = await ref.watch(householdIdProvider.future);
    final client      = ref.watch(supabaseProvider);

    // Realtime: re-fetch on any budget or transaction change
    for (final table in ['budget_months', 'transactions', 'category_goals', 'categories']) {
      final ch = client.channel('budget_${table}_$householdId')
        ..onPostgresChanges(
          event:  PostgresChangeEvent.all,
          schema: 'public',
          table:  table,
          filter: PostgresChangeFilter(
            type:   PostgresChangeFilterType.eq,
            column: 'household_id',
            value:  householdId,
          ),
          callback: (_) => ref.invalidateSelf(),
        )
        ..subscribe();
      ref.onDispose(() => client.removeChannel(ch));
    }

    return _load(client, householdId, _month);
  }

  // ---------------------------------------------------------------------------
  // Month navigation
  // ---------------------------------------------------------------------------

  Future<void> goToMonth(DateTime month) async {
    _month = _firstOfMonth(month);
    ref.invalidateSelf();
  }

  // ---------------------------------------------------------------------------
  // Set budgeted amount for a category
  // ---------------------------------------------------------------------------

  Future<void> setBudgeted(String categoryId, double amount) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);
    final monthStr    = _toMonthString(_month);

    await client.from('budget_months').upsert({
      'household_id': householdId,
      'category_id':  categoryId,
      'month':        monthStr,
      'budgeted':     amount,
    }, onConflict: 'household_id, category_id, month');

    ref.invalidateSelf();
  }

  // ---------------------------------------------------------------------------
  // Category CRUD
  // ---------------------------------------------------------------------------

  Future<String> addCategory({
    required String name,
    required String groupId,
    int? iconCodePoint,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    final res = await client.from('categories').insert({
      'household_id':       householdId,
      'category_group_id':  groupId,
      'name':               name,
      if (iconCodePoint != null) 'icon_codepoint': iconCodePoint,
    }).select('id').single();

    ref.invalidate(categoriesProvider);
    ref.invalidateSelf();
    return res['id'] as String;
  }

  Future<void> updateCategoryIcon(String categoryId, int? iconCodePoint) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('categories')
        .update({'icon_codepoint': iconCodePoint})
        .eq('id', categoryId);
    ref.invalidateSelf();
  }

  Future<void> applyQuickBudget({
    required QuickBudgetStrategy strategy,
    required QuickBudgetScope scope,
    required DateTime baseMonth,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    // ── How many months to fill ───────────────────────────────────────────
    final monthCount = switch (scope) {
      QuickBudgetScope.thisMonth => 1,
      QuickBudgetScope.next3     => 3,
      QuickBudgetScope.next6     => 6,
      QuickBudgetScope.next12    => 12,
    };

    final targetMonths = List.generate(monthCount, (i) {
      final m = DateTime(baseMonth.year, baseMonth.month + i);
      return '${m.year}-${m.month.toString().padLeft(2, '0')}-01';
    });

    // ── Amounts per category ──────────────────────────────────────────────
    final amounts = <String, double>{};

    switch (strategy) {
      case QuickBudgetStrategy.currentMonth:
        final curStr = '${baseMonth.year}-${baseMonth.month.toString().padLeft(2, '0')}-01';
        final rows   = await client
            .from('budget_months')
            .select('category_id, budgeted')
            .eq('household_id', householdId)
            .eq('month', curStr);
        for (final r in rows as List) {
          final b = (r['budgeted'] as num).toDouble();
          if (b > 0) amounts[r['category_id'] as String] = b;
        }

      case QuickBudgetStrategy.lastMonth:
        final prev    = DateTime(baseMonth.year, baseMonth.month - 1);
        final prevStr = '${prev.year}-${prev.month.toString().padLeft(2, '0')}-01';
        final rows    = await client
            .from('budget_months')
            .select('category_id, budgeted')
            .eq('household_id', householdId)
            .eq('month', prevStr);
        for (final r in rows as List) {
          final b = (r['budgeted'] as num).toDouble();
          if (b > 0) amounts[r['category_id'] as String] = b;
        }

      case QuickBudgetStrategy.averageSpending:
        // Actual spending over the 3 complete months before baseMonth
        final from    = DateTime(baseMonth.year, baseMonth.month - 3);
        final fromStr = '${from.year}-${from.month.toString().padLeft(2, '0')}-01';
        final toStr   = '${baseMonth.year}-${baseMonth.month.toString().padLeft(2, '0')}-01';
        final txRows  = await client
            .from('transactions')
            .select('category_id, amount')
            .eq('household_id', householdId)
            .gte('date', fromStr)
            .lt('date', toStr)
            .eq('status', 'confirmed')
            .isFilter('deleted_at', null)
            .not('category_id', 'is', null);
        final totals = <String, double>{};
        for (final r in txRows as List) {
          final a = (r['amount'] as num).toDouble();
          if (a < 0) {
            final id = r['category_id'] as String;
            totals[id] = (totals[id] ?? 0) + a.abs();
          }
        }
        for (final e in totals.entries) {
          amounts[e.key] = (e.value / 3).ceilToDouble();
        }

      case QuickBudgetStrategy.coverSpending:
        final entries = state.valueOrNull?.groups.expand((g) => g.entries) ?? [];
        for (final e in entries) {
          if (e.spent > 0) amounts[e.categoryId] = e.spent;
        }
    }

    if (amounts.isEmpty) return;

    // ── Upsert for each target month ──────────────────────────────────────
    for (final monthStr in targetMonths) {
      await client.from('budget_months').upsert(
        amounts.entries.map((e) => {
          'household_id': householdId,
          'category_id':  e.key,
          'month':        monthStr,
          'budgeted':     e.value,
        }).toList(),
        onConflict: 'household_id, category_id, month',
      );
    }

    ref.invalidateSelf();
  }

  Future<String> addGroup(String name) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    final maxOrder = (state.valueOrNull?.groups
            .map((g) => g.sortOrder)
            .fold(0, (a, b) => a > b ? a : b) ??
        0) + 10;

    final res = await client.from('category_groups').insert({
      'household_id': householdId,
      'name':         name,
      'sort_order':   maxOrder,
    }).select('id').single();

    ref.invalidate(categoriesProvider);
    ref.invalidateSelf();
    return res['id'] as String;
  }

  // ---------------------------------------------------------------------------
  // Group & category edit / delete
  // ---------------------------------------------------------------------------

  Future<void> renameGroup(String groupId, String newName) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('category_groups')
        .update({'name': newName.trim()})
        .eq('id', groupId);
    ref.invalidateSelf();
  }

  Future<void> deleteGroup(String groupId) async {
    final client = ref.read(supabaseProvider);
    await client.from('category_groups').update({
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', groupId);
    ref.invalidate(categoriesProvider);
    ref.invalidateSelf();
  }

  Future<void> renameCategory(String categoryId, String newName) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('categories')
        .update({'name': newName.trim()})
        .eq('id', categoryId);
    ref.invalidateSelf();
  }

  Future<void> deleteCategory(String categoryId) async {
    final client = ref.read(supabaseProvider);
    await client.from('categories').update({
      'deleted_at': DateTime.now().toIso8601String(),
    }).eq('id', categoryId);
    ref.invalidate(categoriesProvider);
    ref.invalidateSelf();
  }

  // ---------------------------------------------------------------------------
  // Goals
  // ---------------------------------------------------------------------------

  Future<void> saveGoal({
    required String categoryId,
    required GoalType type,
    required double targetAmount,
    DateTime? targetDate,
    double? monthlyAmount,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);

    await client.from('category_goals').upsert({
      'household_id':   householdId,
      'category_id':    categoryId,
      'goal_type':      type.toDb,
      'target_amount':  targetAmount,
      'target_date':    targetDate != null ? _toMonthString(targetDate) : null,
      'monthly_amount': monthlyAmount,
      'is_active':      true,
    }, onConflict: 'category_id');

    ref.invalidateSelf();
  }

  Future<void> deleteGoal(String categoryId) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('category_goals')
        .delete()
        .eq('category_id', categoryId);
    ref.invalidateSelf();
  }

  // ---------------------------------------------------------------------------
  // Reordering
  // ---------------------------------------------------------------------------

  /// Persists a new category order within a single group.
  /// [orderedIds] is the full list of category IDs in the desired order.
  Future<void> reorderCategoriesInGroup(
      String groupId, List<String> orderedIds) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);
    await Future.wait([
      for (int i = 0; i < orderedIds.length; i++)
        client
            .from('categories')
            .update({'sort_order': (i + 1) * 10})
            .eq('id', orderedIds[i])
            .eq('household_id', householdId),
    ]);
    ref.invalidateSelf();
  }

  /// Persists a new group order.
  /// [orderedGroups] is the full list in the desired order.
  Future<void> reorderGroups(List<BudgetGroupData> orderedGroups) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);
    await Future.wait([
      for (int i = 0; i < orderedGroups.length; i++)
        client
            .from('category_groups')
            .update({'sort_order': (i + 1) * 10})
            .eq('id', orderedGroups[i].id)
            .eq('household_id', householdId),
    ]);
    ref.invalidate(categoriesProvider);
    ref.invalidateSelf();
  }

  // ---------------------------------------------------------------------------
  // Update overspending behavior
  // ---------------------------------------------------------------------------

  Future<void> setCarryOverspend(String categoryId, bool carry) async {
    final client = ref.read(supabaseProvider);
    await client.from('categories').update({
      'overspending_behavior': carry ? 'carry_forward' : 'reduce_tbb',
    }).eq('id', categoryId);
    ref.invalidateSelf();
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  static Future<BudgetState> _load(
    SupabaseClient client,
    String householdId,
    DateTime month,
  ) async {
    final monthStr     = _toMonthString(month);
    final nextMonthStr = _toMonthString(DateTime(month.year, month.month + 1));

    // Parallel fetch
    final results = await Future.wait([
      // 1. category groups + categories
      client
          .from('category_groups')
          .select('id, name, sort_order, categories(id, name, sort_order, icon_codepoint, is_cc_payment, overspending_behavior, is_hidden)')
          .eq('household_id', householdId)
          .eq('is_hidden', false)
          .isFilter('deleted_at', null)
          .order('sort_order')
          .order('sort_order', referencedTable: 'categories'),

      // 2. budget_months for this month
      client
          .from('budget_months')
          .select('category_id, budgeted')
          .eq('household_id', householdId)
          .eq('month', monthStr),

      // 3. transaction activity per category
      client
          .from('transactions')
          .select('category_id, amount')
          .eq('household_id', householdId)
          .gte('date', monthStr)
          .lt('date', nextMonthStr)
          .eq('status', 'confirmed')
          .isFilter('deleted_at', null),

      // 4. category goals
      client
          .from('category_goals')
          .select()
          .eq('household_id', householdId)
          .eq('is_active', true),
    ]);

    // Build lookup maps
    final budgetMap = <String, double>{};
    for (final row in results[1] as List) {
      budgetMap[row['category_id'] as String] =
          (row['budgeted'] as num).toDouble();
    }

    final activityMap = <String, double>{};
    for (final tx in results[2] as List) {
      final catId = tx['category_id'] as String?;
      if (catId == null) continue;
      activityMap[catId] =
          (activityMap[catId] ?? 0.0) + (tx['amount'] as num).toDouble();
    }

    final goalMap = <String, BudgetGoal>{};
    for (final row in results[3] as List) {
      final g = BudgetGoal.fromJson(row as Map<String, dynamic>);
      goalMap[g.categoryId] = g;
    }

    // Build groups
    final groups = <BudgetGroupData>[];
    for (final gRaw in results[0] as List) {
      final gMap      = gRaw as Map<String, dynamic>;
      final groupId   = gMap['id'] as String;
      final groupName = gMap['name'] as String;
      final groupSort = gMap['sort_order'] as int;
      // Sort categories client-side — the nested .order() on a PostgREST
      // embedded relation is not reliably honoured by all client versions.
      final catsRaw = (gMap['categories'] as List? ?? [])
          .where((c) => (c as Map)['is_hidden'] != true)
          .toList()
          ..sort((a, b) {
            final ao = (a as Map)['sort_order'] as int? ?? 0;
            final bo = (b as Map)['sort_order'] as int? ?? 0;
            return ao.compareTo(bo);
          });

      final entries = catsRaw.map((cRaw) {
        final c          = cRaw as Map<String, dynamic>;
        final catId      = c['id'] as String;
        final budgeted   = budgetMap[catId] ?? 0.0;
        final activity   = activityMap[catId] ?? 0.0;
        final balance    = budgeted + activity;
        final carryOver  = (c['overspending_behavior'] as String?) == 'carry_forward';

        return BudgetEntry(
          categoryId:          catId,
          categoryName:        c['name'] as String,
          groupId:             groupId,
          groupName:           groupName,
          groupSortOrder:      groupSort,
          categorySortOrder:   c['sort_order'] as int,
          budgeted:            budgeted,
          activity:            activity,
          balance:             balance,
          isCcPayment:         c['is_cc_payment'] as bool? ?? false,
          carryOverspend:      carryOver,
          goal:                goalMap[catId],
          iconCodePoint:       c['icon_codepoint'] as int?,
        );
      }).toList();

      if (entries.isNotEmpty) {
        groups.add(BudgetGroupData(
          id:        groupId,
          name:      groupName,
          sortOrder: groupSort,
          entries:   entries,
        ));
      }
    }

    // Sort groups client-side for the same reason as categories above.
    groups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // ── Income: uncategorised positive transactions flow straight into TBB ──────
    // (results[2] is already the full confirmed-tx set for the month)
    double income = 0;
    for (final tx in results[2] as List) {
      final catId = tx['category_id'] as String?;
      final amt   = (tx['amount']      as num).toDouble();
      if (catId == null && amt > 0) income += amt;
    }

    // ── Total assigned this month (sum of all budgeted entries) ──────────────
    final totalBudgeted = groups.fold(0.0,
        (s, g) => s + g.entries.fold(0.0, (s2, e) => s2 + e.budgeted));

    // ── TBB from view ────────────────────────────────────────────────────────
    double tbb = 0;
    try {
      final tbbRes = await client
          .from('v_to_be_budgeted')
          .select('to_be_budgeted')
          .eq('household_id', householdId)
          .eq('month', monthStr)
          .maybeSingle();
      tbb = tbbRes != null
          ? (tbbRes['to_be_budgeted'] as num).toDouble()
          : 0.0;
    } catch (_) {}

    return BudgetState(
      month:         month,
      groups:        groups,
      tbb:           tbb,
      income:        income,
      totalBudgeted: totalBudgeted,
    );
  }

  // ignore: library_private_types_in_public_api
  static DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);

  static String _toMonthString(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-01';
}

final budgetProvider =
    AsyncNotifierProvider<BudgetNotifier, BudgetState>(BudgetNotifier.new);

/// User's layout preference: true = 3-column (when screen is wide enough).
final budgetThreeColPrefProvider = StateProvider<bool>((ref) => true);

/// Read-only snapshot for any month — used by the 3-column desktop view.
/// Does NOT subscribe to realtime; the main budgetProvider handles invalidation.
final budgetForMonthProvider = FutureProvider.autoDispose
    .family<BudgetState, DateTime>((ref, month) async {
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);
  // Invalidate whenever the main budget changes (category edits, transactions, etc.)
  ref.watch(budgetProvider);
  return BudgetNotifier._load(client, householdId, BudgetNotifier._firstOfMonth(month));
});

/// Fetches actual transactions for a single category + month.
/// Key: (categoryId, monthKey) where monthKey = "2026-05"
final categoryTransactionsProvider = FutureProvider.autoDispose
    .family<List<CategoryTransaction>, (String, String)>(
  (ref, args) async {
    final (categoryId, monthKey) = args;
    final householdId = await ref.watch(householdIdProvider.future);
    final client      = ref.watch(supabaseProvider);

    final parts = monthKey.split('-');
    final year  = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final lastDay = DateTime(year, month + 1, 0).day;
    final dateFrom = '$year-${month.toString().padLeft(2, '0')}-01';
    final dateTo   = '$year-${month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

    final res = await client
        .from('transactions')
        .select('id, date, amount, payees(name), accounts(name, nickname, last_four)')
        .eq('household_id', householdId)
        .eq('category_id', categoryId)
        .gte('date', dateFrom)
        .lte('date', dateTo)
        .isFilter('deleted_at', null)
        .order('date', ascending: false);

    return (res as List).map((r) {
      final payee   = r['payees']   as Map<String, dynamic>?;
      final acct    = r['accounts'] as Map<String, dynamic>?;
      final base    = acct?['nickname'] as String? ?? acct?['name'] as String? ?? '';
      final last4   = acct?['last_four'] as String?;
      return CategoryTransaction(
        id:          r['id'] as String,
        date:        DateTime.parse(r['date'] as String),
        payee:       payee?['name'] as String? ?? '',
        amount:      (r['amount'] as num).toDouble(),
        accountName: last4 != null ? '$base · $last4' : base,
      );
    }).toList();
  },
);
