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

/// A single income transaction surfaced in the budget header.
class IncomeTxn {
  final double  amount;
  final String? payeeName;
  final DateTime date;
  const IncomeTxn({required this.amount, this.payeeName, required this.date});
}

class BudgetState {
  final DateTime month;
  final List<BudgetGroupData> groups;
  final double tbb;

  /// Inflows that flow into TBB: transactions with no category (positive amount).
  final double income;

  /// Individual income transactions for the expanded view.
  final List<IncomeTxn> incomeTxns;

  /// Total amount assigned to categories this month.
  final double totalBudgeted;

  /// Actual spending this month: sum of negative non-transfer budget-account txns.
  final double totalSpent;

  /// TBB carried forward from the previous month (may be negative).
  final double carryForward;

  const BudgetState({
    required this.month,
    required this.groups,
    required this.tbb,
    this.income        = 0,
    this.incomeTxns    = const [],
    this.totalBudgeted = 0,
    this.totalSpent    = 0,
    this.carryForward  = 0,
  });

  BudgetState copyWith({
    DateTime?           month,
    List<BudgetGroupData>? groups,
    double?             tbb,
    double?             income,
    List<IncomeTxn>?    incomeTxns,
    double?             totalBudgeted,
    double?             totalSpent,
    double?             carryForward,
  }) => BudgetState(
    month:         month         ?? this.month,
    groups:        groups        ?? this.groups,
    tbb:           tbb           ?? this.tbb,
    income:        income        ?? this.income,
    incomeTxns:    incomeTxns    ?? this.incomeTxns,
    totalBudgeted: totalBudgeted ?? this.totalBudgeted,
    totalSpent:    totalSpent    ?? this.totalSpent,
    carryForward:  carryForward  ?? this.carryForward,
  );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class BudgetNotifier extends AsyncNotifier<BudgetState> {
  DateTime _month = _firstOfMonth(DateTime.now());

  /// Upper bound on history rows pulled for carry-forward. PostgREST applies
  /// its own `max-rows` cap when one is configured, and a truncated history
  /// yields silently wrong balances — so we request an explicit cap and treat
  /// hitting it as an error rather than trusting a short result.
  static const _kHistoryRowCap = 100000;

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

  /// Assigns [amount] to [categoryId]. Defaults to the month currently being
  /// viewed; the 3-column view passes its own panel's month explicitly so an
  /// edit in the previous/next panel lands where the user is looking.
  Future<void> setBudgeted(
    String categoryId,
    double amount, {
    DateTime? month,
  }) async {
    final householdId = await ref.read(householdIdProvider.future);
    final client      = ref.read(supabaseProvider);
    final monthStr    = _toMonthString(month ?? _month);

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

    // A card-linked envelope funds itself from that card's charges, so
    // assigning to it here would fund it a second time — the user ends up with
    // twice the charge available and TBB short by the difference. Excluded
    // from every strategy, not just one: currentMonth and lastMonth copy
    // budgeted amounts forward, so a single stray value propagates onward, and
    // coverSpending reads `spent`, which for these envelopes is the payment.
    final autoFunded = <String>{
      for (final e in (state.valueOrNull?.groups ?? const <BudgetGroupData>[])
          .expand((g) => g.entries))
        if (e.ccAccountId != null) e.categoryId,
    };
    amounts.removeWhere((catId, _) => autoFunded.contains(catId));

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

  /// Retires a category from [from] onward, or reactivates it when [from] is
  /// null. Months before [from] are untouched — the category keeps appearing
  /// there with its history, which is the point of dating this rather than
  /// using a flag.
  ///
  /// Whatever balance it was holding returns to TBB in the retiring month.
  Future<void> setCategoryInactiveFrom(String categoryId, DateTime? from) async {
    final client = ref.read(supabaseProvider);
    await client.from('categories').update({
      'inactive_from': from == null ? null : _toMonthString(_firstOfMonth(from)),
      // Clear the old boolean too: it hides a category from every month, so
      // leaving it set would defeat the dated behaviour on reactivation.
      'is_hidden': false,
    }).eq('id', categoryId);
    ref.invalidate(categoriesProvider);
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
          .select('id, name, sort_order, categories(id, name, sort_order, icon_codepoint, is_cc_payment, overspending_behavior, rollover_behavior, is_hidden, inactive_from, deleted_at, linked_account_id)')
          .eq('household_id', householdId)
          .eq('is_hidden', false)
          .isFilter('deleted_at', null)
          // deleted_at above applies to the group; the embedded categories
          // need their own filter or soft-deleted ones keep rendering (and
          // keep counting against TBB).
          .isFilter('categories.deleted_at', null)
          .order('sort_order')
          .order('sort_order', referencedTable: 'categories'),

      // 2. budget_months for this month
      client
          .from('budget_months')
          .select('category_id, budgeted')
          .eq('household_id', householdId)
          .eq('month', monthStr),

      // 3. transaction activity per category (includes date + payee for income drill-down)
      client
          .from('transactions')
          .select('category_id, amount, date, transfer_id, payees(name), accounts(is_tracking)')
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

      // 5. all budget_months BEFORE this month (for carry-forward, bucketed by month)
      client
          .from('budget_months')
          .select('category_id, budgeted, month')
          .eq('household_id', householdId)
          .lt('month', monthStr)
          .limit(_kHistoryRowCap),

      // 6. all confirmed budget-account transactions BEFORE this month
      client
          .from('transactions')
          .select('category_id, amount, transfer_id, date, accounts(is_tracking)')
          .eq('household_id', householdId)
          .lt('date', monthStr)
          .eq('status', 'confirmed')
          .isFilter('deleted_at', null)
          .limit(_kHistoryRowCap),

      // 7. Every transfer leg keyed by id, with its account's tracking flag.
      // A row's own embedded accounts(is_tracking) describes its own side; to
      // decide whether a transfer leaves the budget we need the *counterpart*,
      // and transfer_id points at it. Fetched for all dates rather than the
      // current window because the two legs can be dated into different months.
      client
          .from('transactions')
          .select('id, accounts(is_tracking)')
          .eq('household_id', householdId)
          .not('transfer_id', 'is', null)
          .isFilter('deleted_at', null)
          .limit(_kHistoryRowCap),
    ]);

    // Carry-forward and TBB are both running totals over *all* history, so a
    // truncated result set would produce silently wrong balances. Fail loudly
    // instead — the cap is far above any realistic personal-budget history.
    if ((results[4] as List).length >= _kHistoryRowCap ||
        (results[5] as List).length >= _kHistoryRowCap) {
      throw StateError(
        'Budget history exceeded $_kHistoryRowCap rows; carry-forward would be '
        'incomplete. Aggregate older months before loading the budget.',
      );
    }

    // ── Per-category settings (drive how balances roll between months) ────────
    // Built first because the visible-category set gates every budgeted sum
    // below: money assigned to a hidden or deleted category must not be
    // subtracted from TBB, or it disappears from the books entirely.
    final visibleCatIds = <String>{};
    final rolloverMap   = <String, String>{}; // catId → rollover_behavior
    final overspendMap  = <String, String>{}; // catId → overspending_behavior
    final ccLinkMap     = <String, String>{}; // catId → linked_account_id
    final ccCandidates  = <({String catId, String accId, bool flagged})>[];
    final inactiveFromMap = <String, String>{}; // catId → 'YYYY-MM' it retires
    final loadedKey = _monthKeyOf(monthStr);
    for (final gRaw in results[0] as List) {
      for (final cRaw in ((gRaw as Map)['categories'] as List? ?? [])) {
        final c = cRaw as Map<String, dynamic>;
        if (c['is_hidden'] == true) continue;
        final catId = c['id'] as String;
        // Retired categories stay visible in the months they were live, so a
        // trip that ran in July still appears in July after being retired in
        // August. Only months from inactive_from onward drop it.
        final inactiveFrom = c['inactive_from'] as String?;
        if (inactiveFrom != null) {
          final endKey = _monthKeyOf(inactiveFrom);
          inactiveFromMap[catId] = endKey;
          if (loadedKey.compareTo(endKey) >= 0) continue;
        }
        visibleCatIds.add(catId);
        rolloverMap[catId]  =
            (c['rollover_behavior'] as String?) ?? 'rollover';
        overspendMap[catId] =
            (c['overspending_behavior'] as String?) ?? 'reduce_tbb';
        final ccAccId = c['linked_account_id'] as String?;
        if (ccAccId != null) {
          ccCandidates.add((
            catId:   catId,
            accId:   ccAccId,
            flagged: c['is_cc_payment'] == true,
          ));
        }
      }
    }

    // One card funds exactly one envelope. Nothing in the schema stops two
    // categories pointing at the same account, and the link tile lets it be
    // done by hand — but each would then reserve the full charge, so a $145
    // purchase shows up as $290. Resolve to a single winner per account:
    // prefer the category actually flagged as the CC payment envelope, then
    // lowest id so the choice is stable across loads.
    ccCandidates.sort((a, b) {
      if (a.flagged != b.flagged) return a.flagged ? -1 : 1;
      return a.catId.compareTo(b.catId);
    });
    final claimedAccounts = <String>{};
    for (final c in ccCandidates) {
      if (!claimedAccounts.add(c.accId)) continue; // already funded
      ccLinkMap[c.catId] = c.accId;
    }

    // ── Does a transfer leg belong to the budget? ────────────────────────────
    // Checking -> Savings never leaves the budget, so charging a category would
    // double-count it. Checking -> Mortgage (or a brokerage) does leave, and
    // that outgoing leg is exactly what its category records. The test is
    // therefore about the counterpart, not about being a transfer.
    final legIsTracking = <String, bool>{}; // transaction id -> on a tracking account
    for (final r in results[6] as List) {
      legIsTracking[r['id'] as String] =
          (r['accounts'] as Map?)?['is_tracking'] as bool? ?? false;
    }

    bool touchesBudget(String? transferId, bool isTracking) {
      if (isTracking)         return false; // this leg is itself off-budget
      if (transferId == null) return true;  // ordinary spending or income
      // Counterpart unknown (leg deleted, or not yet synced): treat it as an
      // in-budget transfer, the conservative reading — it leaves the category
      // untouched rather than inventing activity.
      return legIsTracking[transferId] ?? false;
    }

    // Build lookup maps
    final budgetMap = <String, double>{};
    for (final row in results[1] as List) {
      final catId = row['category_id'] as String;
      if (!visibleCatIds.contains(catId)) continue;
      // A card-linked envelope is funded solely by that card's charges, so an
      // assigned amount is never part of it. Dropping it here rather than just
      // from the balance also keeps it out of totalBudgeted, so anything
      // previously assigned flows back to TBB instead of being stranded in an
      // envelope that no longer counts it. Debt predating the budget is
      // handled by its own pre-budget debt category, not by assigning here.
      if (ccLinkMap.containsKey(catId)) continue;
      budgetMap[catId] = (row['budgeted'] as num).toDouble();
    }

    final activityMap = <String, double>{};
    // Non-zero only for CC payment envelopes: money set aside this month by
    // charges on the linked card.
    final reservedMap = <String, double>{};
    for (final tx in results[2] as List) {
      final catId      = tx['category_id'] as String?;
      final transferId = tx['transfer_id'] as String?;
      final isTracking = (tx['accounts']   as Map?)?['is_tracking'] as bool? ?? false;
      // Must match the past-month filter below, or an amount counts this month
      // and then vanishes when the month rolls over.
      if (catId == null || !touchesBudget(transferId, isTracking)) continue;
      activityMap[catId] =
          (activityMap[catId] ?? 0.0) + (tx['amount'] as num).toDouble();
    }

    final goalMap = <String, BudgetGoal>{};
    for (final row in results[3] as List) {
      final g = BudgetGoal.fromJson(row as Map<String, dynamic>);
      goalMap[g.categoryId] = g;
    }

    // ── Past budgeted + activity, bucketed by category and month ─────────────
    // Both are needed per-month (not as a flat sum) so the running balance can
    // be clamped at each month boundary — see the walk below.
    final pastBudget   = <String, Map<String, double>>{}; // catId → 'YYYY-MM' → budgeted
    final pastActivity = <String, Map<String, double>>{}; // catId → 'YYYY-MM' → activity
    // Uncategorised inflows per past month — the other half of the TBB total.
    final pastInflowByMonth = <String, double>{};

    for (final row in results[4] as List) {
      final catId = row['category_id'] as String?;
      if (catId == null || !visibleCatIds.contains(catId)) continue;
      if (ccLinkMap.containsKey(catId)) continue; // see budgetMap above
      final mKey = _monthKeyOf(row['month'] as String);
      (pastBudget[catId] ??= {})[mKey] =
          ((pastBudget[catId]![mKey]) ?? 0.0) + (row['budgeted'] as num).toDouble();
    }
    for (final tx in results[5] as List) {
      final catId      = tx['category_id'] as String?;
      final transferId = tx['transfer_id'] as String?;
      final isTracking = (tx['accounts']   as Map?)?['is_tracking'] as bool? ?? false;
      final amt        = (tx['amount']     as num).toDouble();
      final mKey       = _monthKeyOf(tx['date'] as String);

      // Uncategorised inflow → straight to TBB, never to a category.
      if (catId == null) {
        if (transferId == null && !isTracking && amt > 0) {
          pastInflowByMonth[mKey] = (pastInflowByMonth[mKey] ?? 0.0) + amt;
        }
        continue;
      }
      if (!touchesBudget(transferId, isTracking)) continue;
      (pastActivity[catId] ??= {})[mKey] =
          ((pastActivity[catId]![mKey]) ?? 0.0) + amt;
    }

    // ── CC payment: YNAB-style linked envelope ───────────────────────────────────
    // For any category that has linked_account_id set, its activity is driven
    // entirely by the CC account's transactions:
    //   • CC purchases (amount < 0) → contribute positively (money reserved to pay)
    //   • CC payment transfers (amount > 0) → contribute negatively (card paid off)
    // This REPLACES any direct transaction activity for those categories, in both
    // the current month and every past month — otherwise transactions the user
    // categorised manually before linking would be counted twice.
    if (ccLinkMap.isNotEmpty) {
      final ccAccountIds = ccLinkMap.values.toSet().toList();

      final ccTxResults = await Future.wait([
        // Current-month CC account transactions
        client
            .from('transactions')
            .select('account_id, amount')
            .eq('household_id', householdId)
            .inFilter('account_id', ccAccountIds)
            .gte('date', monthStr)
            .lt('date', nextMonthStr)
            .eq('status', 'confirmed')
            .isFilter('deleted_at', null),
        // Pre-month CC account transactions (carry-forward, bucketed by month)
        client
            .from('transactions')
            .select('account_id, amount, date')
            .eq('household_id', householdId)
            .inFilter('account_id', ccAccountIds)
            .lt('date', monthStr)
            .eq('status', 'confirmed')
            .isFilter('deleted_at', null)
            .limit(_kHistoryRowCap),
      ]);

      if ((ccTxResults[1] as List).length >= _kHistoryRowCap) {
        throw StateError(
          'Credit-card history exceeded $_kHistoryRowCap rows; the payment '
          'envelope would be incomplete.',
        );
      }

      // Accumulate: CC activity = -sum(CC txns) so spending adds, payments deduct.
      // Charges and payments move the envelope in opposite directions, so they
      // are kept apart. Rolling them into one figure made the Activity column
      // read as an inflow whenever the month's spending outran its payments,
      // which is the normal state of a credit card.
      final ccCurReserved = <String, double>{}; // charges  → money set aside
      final ccCurPayment  = <String, double>{}; // payments → money sent to card
      final ccPastAct = <String, Map<String, double>>{}; // accId → 'YYYY-MM' → net
      for (final tx in ccTxResults[0] as List) {
        final aid = tx['account_id'] as String;
        final amt = (tx['amount'] as num).toDouble();
        if (amt < 0) {
          // A charge: negative on the card, so negating gives money to reserve.
          ccCurReserved[aid] = (ccCurReserved[aid] ?? 0.0) - amt;
        } else {
          // A payment or statement credit: reduces what is owed.
          ccCurPayment[aid] = (ccCurPayment[aid] ?? 0.0) - amt;
        }
      }
      for (final tx in ccTxResults[1] as List) {
        final aid  = tx['account_id'] as String;
        final mKey = _monthKeyOf(tx['date'] as String);
        (ccPastAct[aid] ??= {})[mKey] =
            ((ccPastAct[aid]![mKey]) ?? 0.0) - (tx['amount'] as num).toDouble();
      }

      for (final entry in ccLinkMap.entries) {
        final catId = entry.key;
        final accId = entry.value;
        // Activity is payments only, so the column keeps its usual meaning:
        // negative is money leaving. Charges surface as `reserved`.
        activityMap[catId]  = ccCurPayment[accId]  ?? 0.0;
        reservedMap[catId]  = ccCurReserved[accId] ?? 0.0;
        // Carry-forward stays a single net figure — a past month contributes
        // charges minus payments, which is what rolls into the next month.
        pastActivity[catId] = ccPastAct[accId] ?? {};
      }
    }

    // ── Carry-forward: walk month by month, clamping at each boundary ─────────
    // Mirrors v_budget_month_summary in schema.sql — a flat sum is wrong because
    // it lets a single overspend follow the category forever even when the
    // category is set to 'reduce_tbb' (the default), where the shortfall is
    // absorbed by TBB in the month it happens and the next month starts clean.
    final carryForwardMap = <String, double>{};
    // Whatever a category stops carrying has to land somewhere or the books
    // stop balancing: clamping an overspend to 0 without charging TBB would
    // conjure that money out of nothing. Negative = TBB absorbed a shortfall,
    // positive = a zero_out category handed its surplus back.
    double tbbAdjust = 0;
    final allCatIds = {...pastBudget.keys, ...pastActivity.keys};
    for (final catId in allCatIds) {
      final budgets    = pastBudget[catId]   ?? const <String, double>{};
      final activities = pastActivity[catId] ?? const <String, double>{};
      final months     = {...budgets.keys, ...activities.keys}.toList()..sort();

      final rollover  = rolloverMap[catId]  ?? 'rollover';
      final overspend = overspendMap[catId] ?? 'reduce_tbb';
      final retiresAt = inactiveFromMap[catId];

      double running = 0;
      for (final m in months) {
        final endBalance =
            running + (budgets[m] ?? 0.0) + (activities[m] ?? 0.0);
        // Once retired the category holds nothing: whatever it was carrying
        // goes back to the pool in that month, and any later stray activity is
        // settled there too rather than accumulating somewhere invisible.
        final retired = retiresAt != null && m.compareTo(retiresAt) >= 0;
        if (retired || rollover == 'zero_out') {
          // Category never carries: the whole balance returns to the pool.
          tbbAdjust += endBalance;
          running    = 0;
        } else if (overspend == 'reduce_tbb' && endBalance < 0) {
          // Shortfall is absorbed by TBB in the month it happened; the
          // category starts the next month clean.
          tbbAdjust += endBalance;
          running    = 0;
        } else {
          running = endBalance; // carry_forward: the negative follows the category
        }
      }
      carryForwardMap[catId] = running;
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
          .where((c) =>
              (c as Map)['is_hidden'] != true && c['deleted_at'] == null)
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
        final reserved   = reservedMap[catId] ?? 0.0;
        final carry      = carryForwardMap[catId] ?? 0.0;
        final balance    = carry + budgeted + reserved + activity;
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
          carriedIn:           carry,
          reserved:            reserved,
          goal:                goalMap[catId],
          iconCodePoint:       c['icon_codepoint'] as int?,
          ccAccountId:         c['linked_account_id'] as String?,
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
    final incomeTxns = <IncomeTxn>[];
    for (final tx in results[2] as List) {
      final catId      = tx['category_id'] as String?;
      final transferId = tx['transfer_id'] as String?;
      final isTracking = (tx['accounts']   as Map?)?['is_tracking'] as bool? ?? false;
      final amt        = (tx['amount']     as num).toDouble();
      // Exclude transfers and tracking-account transactions — neither is budget
      // income. Also exclude *categorised* inflows (e.g. a refund booked to
      // Groceries): those already raise that category's Available, so counting
      // them here would credit the same money twice.
      if (catId == null && transferId == null && !isTracking && amt > 0) {
        income += amt;
        final payee = tx['payees'] as Map<String, dynamic>?;
        incomeTxns.add(IncomeTxn(
          amount:    amt,
          payeeName: payee?['name'] as String?,
          date:      DateTime.parse(tx['date'] as String),
        ));
      }
    }
    incomeTxns.sort((a, b) => b.date.compareTo(a.date));

    // ── Total assigned this month ────────────────────────────────────────────
    // Summed from budgetMap (already gated on visibleCatIds) rather than from
    // the rendered groups, so this is exactly the figure TBB subtracts even
    // when a group renders empty.
    final totalBudgeted = budgetMap.values.fold(0.0, (s, v) => s + v);

    // ── Actual spending: negative non-transfer budget-account transactions ────
    double totalSpent = 0;
    for (final tx in results[2] as List) {
      final transferId = tx['transfer_id'] as String?;
      final isTracking = (tx['accounts']   as Map?)?['is_tracking'] as bool? ?? false;
      final amt        = (tx['amount']     as num).toDouble();
      // Same rule as category activity: a mortgage or brokerage payment is
      // real spending out of the budget and belongs in this total.
      if (touchesBudget(transferId, isTracking) && amt < 0) totalSpent += amt.abs();
    }

    // ── TBB (cumulative) + carry-forward from previous month ─────────────────
    // Computed here rather than read from v_to_be_budgeted. That view is keyed
    // off `select distinct month from budget_months`, so any month you have not
    // budgeted in yet produces no row at all — and the old code then reported
    // TBB as $0 instead of the surplus actually carried into it. Deriving it
    // from the same rows that build the categories also guarantees the header
    // arithmetic (carried + income − budgeted) matches the total shown.
    // `tbbAdjust` carries the shortfalls TBB absorbed (and any zero_out surplus
    // handed back) during the walk above, which keeps
    //   sum(category balances) + TBB == cash in budget accounts
    // true in every month. Current-month overspending is deliberately *not*
    // charged here: it shows as a red category now and only reaches TBB once
    // the month rolls over, which is what YNAB does.
    final carryForward = pastInflowByMonth.values.fold(0.0, (s, v) => s + v) -
        pastBudget.values.fold(
            0.0, (s, m) => s + m.values.fold(0.0, (s2, v) => s2 + v)) +
        tbbAdjust;
    final tbb = carryForward + income - totalBudgeted;

    return BudgetState(
      month:         month,
      groups:        groups,
      tbb:           tbb,
      income:        income,
      incomeTxns:    incomeTxns,
      totalBudgeted: totalBudgeted,
      totalSpent:    totalSpent,
      carryForward:  carryForward,
    );
  }

  // ignore: library_private_types_in_public_api
  static DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month);

  static String _toMonthString(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-01';

  /// 'YYYY-MM-DD' → 'YYYY-MM'. Sorts lexicographically in chronological order.
  static String _monthKeyOf(String date) => date.substring(0, 7);
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


// ---------------------------------------------------------------------------
// Inactive (hidden) categories — for the reactivate sheet
// ---------------------------------------------------------------------------

class InactiveCategory {
  final String id;
  final String name;
  final String groupName;
  /// First month it stopped applying. Null for categories retired with the
  /// older boolean, which hid them from every month.
  final DateTime? inactiveFrom;
  const InactiveCategory({
    required this.id,
    required this.name,
    required this.groupName,
    this.inactiveFrom,
  });
}

final inactiveCategoriesProvider =
    FutureProvider.autoDispose<List<InactiveCategory>>((ref) async {
  // Re-runs whenever the budget does, so the list updates as soon as a
  // category is activated or deactivated.
  ref.watch(budgetProvider);
  final householdId = await ref.watch(householdIdProvider.future);
  final client      = ref.watch(supabaseProvider);

  final res = await client
      .from('categories')
      .select('id, name, inactive_from, category_groups(name)')
      .eq('household_id', householdId)
      // Dated retirements plus any category hidden by the older boolean.
      .or('is_hidden.eq.true,inactive_from.not.is.null')
      .isFilter('deleted_at', null)
      .order('name');

  return (res as List).map((r) {
    final g = r['category_groups'] as Map<String, dynamic>?;
    return InactiveCategory(
      id:        r['id']   as String,
      name:      r['name'] as String,
      groupName: g?['name'] as String? ?? '',
      inactiveFrom: r['inactive_from'] != null
          ? DateTime.parse(r['inactive_from'] as String)
          : null,
    );
  }).toList();
});
