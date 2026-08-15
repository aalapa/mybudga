import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../shared/models/budget_entry.dart';
import '../../shared/models/transaction.dart';
import '../insights/insights_provider.dart';
import '../transactions/transactions_provider.dart';
import '../insights/payee_pattern.dart';
import '../accounts/accounts_provider.dart';
import '../../core/supabase/supabase_provider.dart';
import 'budget_provider.dart';
import 'category_icons.dart';

// ---------------------------------------------------------------------------

const _kColW      = 82.0; // numeric column width — single-column view
const _kPanelColW = 68.0; // numeric column width — 3-column comparison panels
const _k3ColBreak = 1100.0; // min width to activate 3-column layout
const _kCarrySlotW = 20.0;  // trailing slot for the overspend-carry arrow

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs          = Theme.of(context).colorScheme;
    final budgetAsync = ref.watch(budgetProvider);

    void onCategoryTap(BudgetEntry entry, DateTime month) {
      showModalBottomSheet(
        context:            context,
        isScrollControlled: true,
        useSafeArea:        true,
        builder:            (_) => _CategoryDetailSheet(entry: entry, month: month),
      );
    }

    final wideEnough = MediaQuery.sizeOf(context).width >= _k3ColBreak;
    final prefThreeCol = ref.watch(budgetThreeColPrefProvider);
    final isThreeCol = wideEnough && prefThreeCol;

    return Scaffold(
      backgroundColor: cs.surface,
      body: budgetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text('Could not load budget',
                  style: GoogleFonts.plusJakartaSans(color: cs.onSurfaceVariant)),
              TextButton(
                onPressed: () => ref.invalidate(budgetProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (state) => isThreeCol
            ? _ThreeColumnBudget(state: state)
            : wideEnough
                ? _BudgetSplitView(state: state)
                : _BudgetBody(
                    state:         state,
                    onCategoryTap: onCategoryTap,
                  ),
      ),
      // No FAB: the list ends with an Add Category button, and each group has
      // its own inline add, so a floating one only covered the last row.
    );
  }
}

// ---------------------------------------------------------------------------
// Three-column desktop layout  (prev | current | next month)
// ---------------------------------------------------------------------------

class _ThreeColumnBudget extends ConsumerWidget {
  final BudgetState state; // current month from main provider
  const _ThreeColumnBudget({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs        = Theme.of(context).colorScheme;
    final prevMonth = DateTime(state.month.year, state.month.month - 1);
    final nextMonth = DateTime(state.month.year, state.month.month + 1);
    final prevAsync = ref.watch(budgetForMonthProvider(prevMonth));
    final nextAsync = ref.watch(budgetForMonthProvider(nextMonth));
    final notifier  = ref.read(budgetProvider.notifier);

    return Column(
      children: [
        // ── Shared navigation header ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4), width: 0.5),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => notifier.goToMonth(prevMonth),
                icon: const Icon(Icons.chevron_left),
                style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHigh),
              ),
              // Mirrors the toggle on the right so the chips stay centred.
              const SizedBox(width: 44),
              const Spacer(),
              _MonthChip(
                month: prevMonth, isCurrent: false,
                onTap: () => notifier.goToMonth(prevMonth)),
              const SizedBox(width: 12),
              _MonthChip(month: state.month, isCurrent: true),
              const SizedBox(width: 12),
              _MonthChip(
                month: nextMonth, isCurrent: false,
                onTap: () => notifier.goToMonth(nextMonth)),
              const Spacer(),
              // ── Layout toggle ────────────────────────────────────────────
              // Inside the right chevron, matching the single-month header, so
              // the chevrons stay the outermost controls on both layouts.
              IconButton(
                tooltip: 'Budget + Transactions split view',
                icon: const Icon(Icons.vertical_split_outlined, size: 18),
                onPressed: () => ref
                    .read(budgetThreeColPrefProvider.notifier)
                    .state = false,
                style: IconButton.styleFrom(
                  backgroundColor: cs.surfaceContainerHigh,
                  padding: const EdgeInsets.all(6),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => notifier.goToMonth(nextMonth),
                icon: const Icon(Icons.chevron_right),
                style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHigh),
              ),
            ],
          ),
        ),
        // ── Three panels ─────────────────────────────────────────────────────
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MonthPanel(
                    async: prevAsync, isCurrent: false, month: prevMonth,
                    isPast: true),
              ),
              VerticalDivider(
                  width: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.5)),
              Expanded(
                child: _MonthPanel(
                    async: AsyncData(state), isCurrent: true,
                    month: state.month,
                    onAddCategory: () => _showAddCategorySheet(context, ref)),
              ),
              VerticalDivider(
                  width: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.5)),
              Expanded(
                child: _MonthPanel(
                    async: nextAsync, isCurrent: false, month: nextMonth),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Month chip in the shared nav ─────────────────────────────────────────────

class _MonthChip extends StatelessWidget {
  final DateTime month;
  final bool isCurrent;
  final VoidCallback? onTap;
  const _MonthChip({required this.month, required this.isCurrent, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isCurrent
              ? cs.primaryContainer
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          DateFormat(isCurrent ? 'MMMM yyyy' : 'MMM yyyy').format(month),
          style: GoogleFonts.plusJakartaSans(
            fontSize: isCurrent ? 14 : 12,
            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w500,
            color: isCurrent ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ── One month panel ───────────────────────────────────────────────────────────

class _MonthPanel extends StatelessWidget {
  final AsyncValue<BudgetState> async;
  final bool isCurrent;
  final bool isPast;
  final DateTime month;
  final VoidCallback? onAddCategory;
  const _MonthPanel(
      {required this.async, required this.isCurrent, required this.month,
       this.isPast = false, this.onAddCategory});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inner = switch (async) {
      AsyncLoading() => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(strokeWidth: 2),
          )),
      AsyncError() => Center(
          child: Icon(Icons.error_outline,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4))),
      AsyncData(:final value) => _PanelContent(
          state: value, isCurrent: isCurrent, onAddCategory: onAddCategory),
      _ => const SizedBox.shrink(),
    };
    if (!isPast) return inner;
    // Past months stay de-emphasised, but not so faint that the now-editable
    // budget field is hard to read while typing into it.
    return Opacity(opacity: 0.72, child: inner);
  }
}

// ── Panel content ─────────────────────────────────────────────────────────────

class _PanelContent extends StatefulWidget {
  final BudgetState state;
  final bool isCurrent;
  final VoidCallback? onAddCategory;
  const _PanelContent({required this.state, required this.isCurrent, this.onAddCategory});

  @override
  State<_PanelContent> createState() => _PanelContentState();
}

class _PanelContentState extends State<_PanelContent> {
  /// Groups the user has collapsed; everything else is open, matching the
  /// single-month body.
  final Set<String> _collapsedGroupIds = {};

  void _toggleGroup(String id) => setState(() {
        if (!_collapsedGroupIds.remove(id)) _collapsedGroupIds.add(id);
      });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final fmt   = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final state = widget.state;

    // Flatten groups → (group, entry?) pairs; entries only for the open group.
    final rows = <({BudgetGroupData group, BudgetEntry? entry})>[];
    for (final g in state.groups) {
      rows.add((group: g, entry: null));           // group header always shown
      if (!_collapsedGroupIds.contains(g.id)) {
        for (final e in g.entries) {
          rows.add((group: g, entry: e));
        }
      }
    }

    return CustomScrollView(
      slivers: [
        // ── Panel sub-header: TBB breakdown ───────────────────────────
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: widget.isCurrent
                ? BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: cs.primary.withValues(alpha: 0.25),
                          width: 2),
                    ),
                    color: cs.primaryContainer.withValues(alpha: 0.08),
                  )
                : BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.3)),
                    ),
                  ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Carry-forward from previous month
                if (state.carryForward != 0)
                  _TbbLine(
                    sign:       state.carryForward > 0 ? '+' : '−',
                    value:      state.carryForward.abs(),
                    label:      'Carried from ${DateFormat('MMM').format(DateTime(state.month.year, state.month.month - 1))}',
                    valueColor: state.carryForward > 0 ? context.money.positive : cs.error,
                  ),
                if (state.carryForward != 0) const SizedBox(height: 2),
                // Income line — tappable, expands to show individual transactions
                _IncomeLine(
                  month:      state.month,
                  income:     state.income,
                  txns:       state.incomeTxns,
                ),
                const SizedBox(height: 2),
                // Budgeted line
                _TbbLine(
                  sign:       '−',
                  value:      state.totalBudgeted,
                  label:      'Budgeted in ${DateFormat('MMM').format(state.month)}',
                  valueColor: cs.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                // TBB result pill — closes the carried + income − budgeted sum
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: state.tbb < 0
                          ? cs.errorContainer
                          : cs.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '= ${state.tbb < 0 ? '-' : '+'}${fmt.format(state.tbb.abs())} TBB',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: state.tbb < 0
                            ? cs.onErrorContainer
                            : cs.onTertiaryContainer,
                      ),
                    ),
                  ),
                ),
                // Spending sits outside the equation: it never reaches TBB
                // (money leaves a category, not the unassigned pool), so
                // showing it above the "=" made the sum look broken.
                const SizedBox(height: 6),
                Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.5)),
                const SizedBox(height: 4),
                _TbbLine(
                  sign:       '',
                  value:      state.totalSpent,
                  label:      'Spent in ${DateFormat('MMM').format(state.month)}',
                  valueColor: cs.error.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
        // ── Column labels ─────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _PanelColHeaders(
            totalBudgeted:  state.totalBudgeted,
            totalActivity:  state.groups
                .expand((g) => g.entries)
                .fold(0.0, (s, e) => s + e.activity),
            totalAvailable: state.groups.fold(0.0, (s, g) => s + g.balance),
          ),
        ),
        // ── Rows ─────────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 80),
          sliver: SliverList.builder(
            itemCount: rows.length,
            itemBuilder: (ctx, i) {
              final row = rows[i];
              return row.entry == null
                  ? _PanelGroupRow(
                      group:      row.group,
                      isExpanded: !_collapsedGroupIds.contains(row.group.id),
                      onTap:      () => _toggleGroup(row.group.id),
                    )
                  : _PanelEntryRow(
                      entry:     row.entry!,
                      isCurrent: widget.isCurrent,
                      month:     state.month);
            },
          ),
        ),
        if (widget.onAddCategory != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: widget.onAddCategory,
                    icon:  const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('Add Category'),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                    ),
                  ),
                  Consumer(builder: (ctx, r, _) {
                    final n = r.watch(inactiveCategoriesProvider)
                        .valueOrNull?.length ?? 0;
                    if (n == 0) return const SizedBox.shrink();
                    return TextButton.icon(
                      onPressed: () => _showInactiveCategoriesSheet(ctx, r),
                      icon:  const Icon(Icons.archive_outlined, size: 15),
                      label: Text('Inactive ($n)'),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Column headers for each panel ────────────────────────────────────────────

class _PanelColHeaders extends StatelessWidget {
  final double totalBudgeted;
  final double totalActivity;
  final double totalAvailable;
  const _PanelColHeaders({
    required this.totalBudgeted,
    required this.totalActivity,
    required this.totalAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          const Expanded(child: SizedBox()),
          _PanelColLabel('BUDGET',   bg: cs.primary.withValues(alpha: 0.07),
              total: totalBudgeted, cs: cs),
          _PanelColLabel('ACTIVITY', total: totalActivity, cs: cs),
          _PanelColLabel('AVAIL',    bg: context.money.positive.withValues(alpha: 0.07),
              total: totalAvailable, cs: cs),
          const SizedBox(width: _kCarrySlotW),
        ],
      ),
    );
  }
}

class _PanelColLabel extends StatelessWidget {
  final String text;
  final Color? bg;
  final double? total;
  final ColorScheme cs;
  const _PanelColLabel(this.text, {required this.cs, this.bg, this.total});

  static String _fmtTotal(double v) {
    final abs = v.abs();
    final s = abs >= 1000
        ? '\$${(abs / 1000).toStringAsFixed(1)}k'
        : '\$${abs.toStringAsFixed(0)}';
    return v < 0 ? '-$s' : s;
  }

  @override
  Widget build(BuildContext context) {
    final label = SizedBox(
      width: _kPanelColW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.right,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: cs.onSurfaceVariant,
            ),
          ),
          if (total != null)
            Text(
              _fmtTotal(total!),
              textAlign: TextAlign.right,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: total! < 0 ? cs.error : cs.onSurface,
              ),
            ),
        ],
      ),
    );
    if (bg == null) return label;
    return ColoredBox(color: bg!, child: label);
  }
}

// ── Group header row in panel ─────────────────────────────────────────────────

class _PanelGroupRow extends StatelessWidget {
  final BudgetGroupData group;
  final bool isExpanded;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const _PanelGroupRow({
    required this.group,
    this.isExpanded = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final totalBudgeted  = group.entries.fold(0.0, (s, e) => s + e.budgeted);
    final totalActivity  = group.entries.fold(0.0, (s, e) => s + e.activity);
    final totalAvailable = group.entries.fold(0.0, (s, e) => s + e.balance);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
        color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                group.name.toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: cs.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _PanelNum(totalBudgeted, cs.onSurfaceVariant,
                bg: cs.primary.withValues(alpha: 0.07)),
            _PanelNum(totalActivity, cs.onSurfaceVariant),
            _PanelNum(
              totalAvailable,
              totalAvailable < 0 ? cs.error : cs.onSurfaceVariant,
              bg: context.money.positive.withValues(alpha: 0.07),
            ),
            const SizedBox(width: _kCarrySlotW),
          ],
        ),
      ),
    );
  }
}

// ── Category entry row in panel ───────────────────────────────────────────────

class _PanelEntryRow extends ConsumerWidget {
  final BudgetEntry entry;
  final bool isCurrent;
  final DateTime month;
  const _PanelEntryRow({
    required this.entry,
    required this.isCurrent,
    required this.month,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs         = Theme.of(context).colorScheme;
    final isOverspent = entry.balance < 0;
    final availColor  = isOverspent ? cs.error
        : entry.balance > 0 ? context.money.positive
        : cs.onSurfaceVariant;

    final iconCp = entry.iconCodePoint;

    // The comparison panels previously had no tap handler at all, so goals,
    // rename, icon, delete and Make Inactive were unreachable from here.
    return InkWell(
      onTap: () => showModalBottomSheet(
        context:            context,
        isScrollControlled: true,
        useSafeArea:        true,
        builder: (_) =>
            _CategoryDetailSheet(entry: entry, month: month),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
        child: Row(
        children: [
          // Icon avatar (or CC badge)
          if (entry.isCcPayment)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.credit_card, size: 14, color: cs.primary),
            )
          else if (iconCp != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: iconFromCodePoint(iconCp, size: 15, color: cs.primary),
                ),
              ),
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.categoryName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.showsBudgetProgress)
                  _BatteryBar(
                    budgeted: entry.budgeted,
                    spent:    entry.spent,
                  ),
              ],
            ),
          ),
          // No column tint behind N/A — the shading marks a cell that holds a
          // figure, and a card envelope's never does.
          _tintIfBudgetable(
            entry,
            cs,
            _InlineBudgetAmount(
              entry:      entry,
              month:      month,
              width:      _kPanelColW,
              abbreviate: true,
            ),
          ),
          _PanelNum(entry.activity, cs.onSurfaceVariant),
          Tooltip(
            message: _availBreakdown(entry, month),
            child: _PanelNum(entry.balance, availColor, bold: true,
                bg: context.money.positive.withValues(alpha: 0.07)),
          ),
          // Fixed-width slot so the numeric columns stay tabulated whether or
          // not a given row is overspent.
          SizedBox(
            width: _kCarrySlotW,
            child: isOverspent && !entry.isCcPayment
                ? _CarryOverspendArrow(entry: entry)
                : null,
          ),
          ],
        ),
      ),
    );
  }
}

// ── Right-aligned number cell for panels ─────────────────────────────────────

class _PanelNum extends StatelessWidget {
  final double value;
  final Color color;
  final bool bold;
  final Color? bg;
  const _PanelNum(this.value, this.color, {this.bold = false, this.bg});

  static String _fmt(double v) {
    final abs = v.abs();
    if (abs >= 1000) return '\$${(abs / 1000).toStringAsFixed(1)}k';
    return '\$${abs.toStringAsFixed(0)}';
  }

  /// Same abbreviation the panel columns use, so an editable cell lines up
  /// with the static ones beside it.
  static String fmtAbbrev(double v) => (v < 0 ? '-' : '') + _fmt(v);

  @override
  Widget build(BuildContext context) {
    final label  = (value < 0 ? '-' : '') + _fmt(value);
    final dimmed = value == 0;
    final cell = SizedBox(
      width: _kPanelColW,
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: dimmed ? color.withValues(alpha: 0.3) : color,
        ),
      ),
    );
    return cell;
  }
}

// ---------------------------------------------------------------------------
// Flat-list body — no collapse, inline numbers
// ---------------------------------------------------------------------------

// Drag-proxy decorator: lifts the dragged item with a subtle shadow.
Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final elev = Tween<double>(begin: 0, end: 8).evaluate(
          CurvedAnimation(parent: animation, curve: Curves.easeInOut));
      return Material(
        elevation:    elev,
        shadowColor:  Colors.black38,
        borderRadius: BorderRadius.circular(4),
        child: child,
      );
    },
  );
}

class _BudgetBody extends ConsumerStatefulWidget {
  final BudgetState state;
  final void Function(BudgetEntry, DateTime) onCategoryTap;
  /// When non-null the body is in split-view mode: category taps call this
  /// instead of toggling inline expansion.
  final ValueChanged<BudgetEntry?>? onCategorySelect;

  const _BudgetBody({
    required this.state,
    required this.onCategoryTap,
    this.onCategorySelect,
  });

  @override
  ConsumerState<_BudgetBody> createState() => _BudgetBodyState();
}

class _BudgetBodyState extends ConsumerState<_BudgetBody> {
  /// Non-null while the user is typing a new category name inline.
  String? _inlineGroupId;

  /// Groups the user has collapsed. Everything not in here is open, so a cold
  /// start shows categories rather than a stack of grey bars — and collapsing
  /// one group no longer closes another, which the old single-open accordion
  /// did every time.
  final Set<String> _collapsedGroupIds = {};
  static const _kGroupCollapsedPrefix = 'budget_grp_collapsed_';

  /// The category whose detail panel is currently open (accordion: at most one).
  String? _expandedCategoryId;

  /// Briefly tinted after an attention chip jumps to it, so the row you were
  /// sent to is obvious without navigating anywhere.
  String? _highlightedCategoryId;

  /// Drag handles and long-press reordering only exist in this mode, so the
  /// default row is free of controls for an action taken rarely.
  bool _reorderMode = false;

  void _jumpToCategory(String categoryId) {
    setState(() => _highlightedCategoryId = categoryId);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _highlightedCategoryId = null);
    });
  }

  /// Clears the active inline-add row.
  void _closeInline() => setState(() => _inlineGroupId = null);

  @override
  void initState() {
    super.initState();
    _restoreCollapsed();
  }

  Future<void> _restoreCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = widget.state.groups
        .map((g) => g.id)
        .where((id) => prefs.getBool('$_kGroupCollapsedPrefix$id') ?? false)
        .toSet();
    if (ids.isNotEmpty && mounted) {
      setState(() => _collapsedGroupIds.addAll(ids));
    }
  }

  bool _isCollapsed(String groupId) => _collapsedGroupIds.contains(groupId);

  void _toggleGroup(String groupId) {
    setState(() {
      if (!_collapsedGroupIds.remove(groupId)) {
        _collapsedGroupIds.add(groupId);
        if (_inlineGroupId == groupId) _inlineGroupId = null;
      }
    });
    SharedPreferences.getInstance().then((p) => p.setBool(
        '$_kGroupCollapsedPrefix$groupId', _collapsedGroupIds.contains(groupId)));
  }

  /// Backs the "Collapse all" menu entry.
  void collapseAllGroups() {
    setState(() {
      _collapsedGroupIds
        ..clear()
        ..addAll(widget.state.groups.map((g) => g.id));
      _inlineGroupId = null;
    });
    SharedPreferences.getInstance().then((p) {
      for (final g in widget.state.groups) {
        p.setBool('$_kGroupCollapsedPrefix${g.id}', true);
      }
    });
  }

  /// Toggles a category's expansion, or notifies the split panel.
  void _toggleCategory(String categoryId) {
    if (widget.onCategorySelect != null) {
      final entry = widget.state.groups
          .expand((g) => g.entries)
          .where((e) => e.categoryId == categoryId)
          .firstOrNull;
      widget.onCategorySelect!(entry);
      return;
    }
    setState(() {
      _expandedCategoryId =
          _expandedCategoryId == categoryId ? null : categoryId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state    = widget.state;
    final isWide   = MediaQuery.sizeOf(context).width >= 600;
    final notifier = ref.read(budgetProvider.notifier);

    final header = SliverToBoxAdapter(
      child: _BudgetHeader(
        month:         state.month,
        tbb:           state.tbb,
        income:        state.income,
        incomeTxns:    state.incomeTxns,
        totalBudgeted: state.totalBudgeted,
        totalSpent:    state.totalSpent,
        carryForward:  state.carryForward,
        onPrev: () => notifier.goToMonth(
            DateTime(state.month.year, state.month.month - 1)),
        onNext: () => notifier.goToMonth(
            DateTime(state.month.year, state.month.month + 1)),
        onCollapseAll: collapseAllGroups,
        onEditOrder:   () => setState(() => _reorderMode = true),
        ref: ref,
      ),
    );

    final chips = SliverToBoxAdapter(
      child: isWide
          ? const SizedBox.shrink()
          : _AttentionChips(state: state, onJumpToCategory: _jumpToCategory),
    );

    if (state.groups.isEmpty) {
      return SafeArea(
        child: CustomScrollView(
          slivers: [
            header,
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.category_outlined, size: 56,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text('No categories yet',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text('Tap + Add Category to get started',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Build one sliver per group header, plus category slivers only for the
    // expanded group (accordion: at most one group open at a time).
    final groupSlivers = <Widget>[];
    for (int gi = 0; gi < state.groups.length; gi++) {
      final group          = state.groups[gi];
      final isGroupExpanded = !_isCollapsed(group.id);

      groupSlivers.add(SliverToBoxAdapter(
        child: _GroupHeaderRow(
          group:          group,
          isWide:         isWide,
          ref:            ref,
          isExpanded:     isGroupExpanded,
          onToggle:        () => _toggleGroup(group.id),
          onLongPress:     () => _showGroupActions(context, ref, group),
          onReorderGroups: () =>
              _showReorderGroupsSheet(context, ref, state.groups),
        ),
      ));

      if (isGroupExpanded) {
        groupSlivers.add(SliverReorderableList(
          itemCount:      group.entries.length,
          proxyDecorator: _proxyDecorator,
          onReorder: (oldIdx, newIdx) {
            if (newIdx > oldIdx) newIdx -= 1;
            final reordered = List.of(group.entries);
            reordered.insert(newIdx, reordered.removeAt(oldIdx));
            notifier.reorderCategoriesInGroup(
              group.id,
              reordered.map((e) => e.categoryId).toList(),
            );
          },
          itemBuilder: (ctx, idx) {
            final entry = group.entries[idx];
            // Only draggable in reorder mode: outside it a long-press on a
            // row should do nothing surprising.
            final row = _CategoryTableRow(
                entry:       entry,
                isWide:      isWide,
                reorderMode: _reorderMode,
                highlighted: _highlightedCategoryId == entry.categoryId,
                isExpanded:  widget.onCategorySelect == null &&
                             _expandedCategoryId == entry.categoryId,
                month:       state.month,
                onToggle:    () => _toggleCategory(entry.categoryId),
                onDetailTap: (e, m) => widget.onCategoryTap(e, m),
            );
            return _reorderMode
                ? ReorderableDelayedDragStartListener(
                    key: ValueKey(entry.categoryId), index: idx, child: row)
                : KeyedSubtree(
                    key: ValueKey(entry.categoryId), child: row);
          },
        ));

        // Inline "add category" row — shown directly below the group's categories.
        if (_inlineGroupId == group.id) {
          groupSlivers.add(SliverToBoxAdapter(
            child: _InlineAddRow(
              groupId:  group.id,
              onCancel: _closeInline,
            ),
          ));
        }
      }
    }

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          header,
          if (_reorderMode)
            SliverToBoxAdapter(
              child: Container(
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Drag to reorder',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer)),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _reorderMode = false),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            )
          else
            chips,
          // Column headers are for the wide table only; the mobile row states
          // its own figures in words.
          if (isWide)
          SliverToBoxAdapter(
            child: _ColumnHeaders(
              isWide:         isWide,
              totalBudgeted:  state.totalBudgeted,
              totalActivity:  state.groups
                  .expand((g) => g.entries)
                  .fold(0.0, (s, e) => s + e.activity),
              totalAvailable: state.groups
                  .fold(0.0, (acc, g) => acc + g.balance),
            ),
          ),
          ...groupSlivers,
          // Always-visible "Add category" button at the bottom of the list
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _showAddCategorySheet(context, ref),
                    icon:  const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('Add Category'),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                    ),
                  ),
                  const Spacer(),
                  // Only surfaced when there is something to restore, so an
                  // inactive category is never a dead end.
                  Consumer(builder: (ctx, r, _) {
                    final n = r.watch(inactiveCategoriesProvider)
                        .valueOrNull?.length ?? 0;
                    if (n == 0) return const SizedBox.shrink();
                    return TextButton.icon(
                      onPressed: () => _showInactiveCategoriesSheet(ctx, r),
                      icon:  const Icon(Icons.archive_outlined, size: 15),
                      label: Text('Inactive ($n)'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget header
// ---------------------------------------------------------------------------

/// The Ready-to-Assign hero: one figure, one sentence explaining it, one
/// action. Replaces a bordered card of four ledger lines that stated the
/// arithmetic and left the reader to draw the conclusion.
/// Attention chips: the two things worth acting on, stated as counts.
///
/// Hidden when their count is zero — a row of "0 overspent" chips is noise
/// that trains you to stop reading the row.
/// The controls that used to sit permanently on the budget: reordering,
/// inactive categories, compare months, collapse all.
class _BudgetOverflowMenu extends StatelessWidget {
  final DateTime month;
  final WidgetRef ref;
  final bool showCompare;
  final VoidCallback onCollapseAll;
  final VoidCallback onEditOrder;

  const _BudgetOverflowMenu({
    required this.month,
    required this.ref,
    required this.showCompare,
    required this.onCollapseAll,
    required this.onEditOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer(builder: (ctx, r, _) {
      final inactive = r.watch(inactiveCategoriesProvider).valueOrNull?.length ?? 0;
      return PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz),
        tooltip: 'More',
        onSelected: (v) {
          switch (v) {
            case 'order':    onEditOrder();
            case 'inactive': _showInactiveCategoriesSheet(ctx, r);
            case 'compare':
              r.read(budgetThreeColPrefProvider.notifier).state = true;
            case 'collapse': onCollapseAll();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'order', child: Text('Edit category order')),
          PopupMenuItem(
              value: 'inactive',
              child: Text('Inactive categories${inactive > 0 ? ' ($inactive)' : ''}')),
          if (showCompare)
            const PopupMenuItem(value: 'compare', child: Text('Compare months')),
          const PopupMenuItem(value: 'collapse', child: Text('Collapse all groups')),
        ],
      );
    });
  }
}

class _AttentionChips extends ConsumerWidget {
  final BudgetState state;
  final ValueChanged<String> onJumpToCategory;
  const _AttentionChips({required this.state, required this.onJumpToCategory});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money     = context.money;
    final overspent = state.groups
        .expand((g) => g.entries)
        .where((e) => e.balance < 0)
        .toList();
    final unfunded  = ref.watch(unfundedBillsProvider(state.month));

    if (overspent.isEmpty && unfunded.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 16, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (overspent.isNotEmpty)
            _AttentionChip(
              icon:  Icons.error_outline,
              label: '${overspent.length} overspent',
              tint:  money.negative,
              fill:  0.14,
              border: 0.35,
              onTap: () => onJumpToCategory(overspent.first.categoryId),
            ),
          if (unfunded.isNotEmpty)
            _AttentionChip(
              icon:  Icons.schedule,
              label: '${unfunded.length} '
                  '${unfunded.length == 1 ? 'bill' : 'bills'} unfunded',
              tint:  money.warning,
              fill:  0.12,
              border: 0.32,
              onTap: () => onJumpToCategory(unfunded.first.categoryId),
            ),
        ],
      ),
    );
  }
}

class _AttentionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final double fill;
  final double border;
  final VoidCallback onTap;
  const _AttentionChip({
    required this.icon,
    required this.label,
    required this.tint,
    required this.fill,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          // 44px tall: this is a tap target, not a badge.
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: fill),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: tint.withValues(alpha: border)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: tint),
              const SizedBox(width: 7),
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w600, color: tint)),
            ],
          ),
        ),
      );
}

class _ReadyToAssignHero extends StatelessWidget {
  final double tbb;
  final double income;
  final double totalBudgeted;
  final double carryForward;
  final DateTime month;
  final bool ledgerOpen;
  final VoidCallback onToggleLedger;
  final VoidCallback onGiveItAJob;

  const _ReadyToAssignHero({
    required this.tbb,
    required this.income,
    required this.totalBudgeted,
    required this.carryForward,
    required this.month,
    required this.ledgerOpen,
    required this.onToggleLedger,
    required this.onGiveItAJob,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final money = context.money;
    final neg   = tbb < 0;
    final tint  = neg ? money.negative : cs.primary;
    final f0    = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final f2    = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    // Split the cents so the figure reads as one number rather than a wall
    // of digits at 42px.
    final whole = f2.format(tbb.abs()).split('.');

    final prevMonth = DateFormat('MMMM').format(
        DateTime(month.year, month.month - 1));
    final sentence = neg
        ? "You've given ${f0.format(tbb.abs())} more jobs than you have money."
        : '${f0.format(income)} came in, ${f0.format(totalBudgeted)} has a job'
            '${carryForward != 0 ? ', ${f0.format(carryForward.abs())} carried from $prevMonth' : ''}.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tint.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleLedger,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(neg ? 'OVERBUDGETED BY' : 'READY TO ASSIGN',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: tint,
                        )),
                    const Spacer(),
                    Icon(ledgerOpen ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                  ],
                ),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    text: whole.first,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.5,
                      color: tint,
                      height: 1.05,
                    ),
                    children: [
                      TextSpan(
                        text: '.${whole.length > 1 ? whole[1] : '00'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: tint,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(sentence,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                    )),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: onGiveItAJob,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text('Give it a job',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetHeader extends StatefulWidget {
  final DateTime month;
  final double tbb;
  final double income;
  final List<IncomeTxn> incomeTxns;
  final double totalBudgeted;
  final double totalSpent;
  final double carryForward;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onCollapseAll;
  final VoidCallback onEditOrder;
  final WidgetRef ref;

  const _BudgetHeader({
    required this.month,
    required this.tbb,
    required this.income,
    required this.incomeTxns,
    required this.totalBudgeted,
    required this.totalSpent,
    required this.carryForward,
    required this.onPrev,
    required this.onNext,
    required this.onCollapseAll,
    required this.onEditOrder,
    required this.ref,
  });

  @override
  State<_BudgetHeader> createState() => _BudgetHeaderState();
}

class _BudgetHeaderState extends State<_BudgetHeader> {
  /// The old TBB ledger, one tap away rather than always on screen.
  bool _ledgerOpen = false;

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final isNeg    = widget.tbb < 0;
    final tbbColor = isNeg ? cs.error : cs.primary;
    final fmt      = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          // Chevrons anchor the ends, widget.month and Quick Budget sit centred
          // between them. The layout toggle moves inside the right chevron
          // rather than trailing it, with a matching gap on the left so the
          // centre stays true.
          Builder(builder: (ctx) {
            final showToggle =
                MediaQuery.sizeOf(ctx).width >= _k3ColBreak;
            return Row(
              children: [
                IconButton(
                  onPressed: widget.onPrev,
                  icon: const Icon(Icons.chevron_left),
                  style: IconButton.styleFrom(
                      backgroundColor: cs.surfaceContainerHigh),
                ),
                if (showToggle) const SizedBox(width: 44),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(DateFormat('MMMM yyyy').format(widget.month),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                      TextButton.icon(
                        onPressed: () =>
                            _showQuickBudgetSheet(context, widget.month, widget.ref),
                        icon: Icon(Icons.auto_awesome,
                            size: 15, color: cs.primary),
                        label: Text('Quick Budget',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.primary)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showToggle)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: IconButton(
                      tooltip: 'Compare 3 months',
                      icon: const Icon(Icons.view_column_outlined, size: 18),
                      onPressed: () => widget.ref
                          .read(budgetThreeColPrefProvider.notifier)
                          .state = true,
                      style: IconButton.styleFrom(
                        backgroundColor: cs.surfaceContainerHigh,
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                  ),
                IconButton(
                  onPressed: widget.onNext,
                  icon: const Icon(Icons.chevron_right),
                  style: IconButton.styleFrom(
                      backgroundColor: cs.surfaceContainerHigh),
                ),
                // Everything that used to be a permanent control on the row —
                // reordering, inactive categories, compare, collapse.
                _BudgetOverflowMenu(
                  month:      widget.month,
                  ref:        widget.ref,
                  showCompare: showToggle,
                  onCollapseAll: widget.onCollapseAll,
                  onEditOrder:   widget.onEditOrder,
                ),
              ],
            );
          }),
          const SizedBox(height: 6),

          // ── Ready to assign — the one number this screen is about ────────
          // The old ledger said what happened; it never said what to do. The
          // arithmetic is still here, one tap down.
          _ReadyToAssignHero(
            tbb:           widget.tbb,
            income:        widget.income,
            totalBudgeted: widget.totalBudgeted,
            carryForward:  widget.carryForward,
            month:         widget.month,
            ledgerOpen:    _ledgerOpen,
            onToggleLedger: () => setState(() => _ledgerOpen = !_ledgerOpen),
            onGiveItAJob:  () =>
                _showQuickBudgetSheet(context, widget.month, widget.ref),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !_ledgerOpen
                ? const SizedBox(width: double.infinity)
                : Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.carryForward != 0) ...[
                          _TbbLine(
                            sign:  widget.carryForward > 0 ? '+' : '−',
                            value: widget.carryForward.abs(),
                            label:
                                'Carried from ${DateFormat('MMM').format(DateTime(widget.month.year, widget.month.month - 1))}',
                            valueColor: widget.carryForward > 0
                                ? context.money.positive
                                : context.money.negative,
                          ),
                          const SizedBox(height: 3),
                        ],
                        _IncomeLine(
                          month:  widget.month,
                          income: widget.income,
                          txns:   widget.incomeTxns,
                        ),
                        const SizedBox(height: 3),
                        _TbbLine(
                          sign:  '−',
                          value: widget.totalBudgeted,
                          label:
                              'Budgeted in ${DateFormat('MMM').format(widget.month)}',
                          valueColor: cs.onSurfaceVariant,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Divider(
                              height: 1,
                              color:
                                  cs.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        _TbbLine(
                          sign:  '',
                          value: widget.totalSpent,
                          label:
                              'Spent in ${DateFormat('MMM').format(widget.month)}',
                          valueColor: context.money.negative
                              .withValues(alpha: 0.85),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Single breakdown line: sign · formatted amount · label ────────────────────

// ---------------------------------------------------------------------------
// Income line — tappable row that expands to list individual income txns
// ---------------------------------------------------------------------------

class _IncomeLine extends StatefulWidget {
  final DateTime       month;
  final double         income;
  final List<IncomeTxn> txns;

  const _IncomeLine({
    required this.month,
    required this.income,
    required this.txns,
  });

  @override
  State<_IncomeLine> createState() => _IncomeLineState();
}

class _IncomeLineState extends State<_IncomeLine> {
  bool _expanded = false;

  static final _fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  static final _dateFmt = DateFormat('MMM d');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: widget.txns.isEmpty
              ? null
              : () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Income for ${DateFormat('MMM').format(widget.month)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 14,
                child: Text(
                  '+',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.money.positive.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Text(
                _fmt.format(widget.income),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.money.positive,
                ),
              ),
              if (widget.txns.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: AnimatedRotation(
                    turns:    _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size:  14,
                      color: context.money.positive.withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedCrossFade(
          crossFadeState: _expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 200),
          firstChild: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Column(
              children: widget.txns.map((t) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          t.payeeName ?? 'Income',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _dateFmt.format(t.date),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _fmt.format(t.amount),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.money.positive,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _TbbLine extends StatelessWidget {
  final String sign;
  final double value;
  final String label;
  final Color  valueColor;

  const _TbbLine({
    required this.sign,
    required this.value,
    required this.label,
    required this.valueColor,
  });

  static final _fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: cs.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 14,
          child: Text(sign,
              textAlign: TextAlign.right,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: valueColor.withValues(alpha: 0.7))),
        ),
        Text(
          _fmt.format(value),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor),
        ),
      ],
    );
  }
}

/// Spells out how Available was reached. Available is
/// carried-in + budgeted + activity, but only the last two have columns, so
/// a row with a carry-in looks like broken arithmetic without this.
String _availBreakdown(BudgetEntry e, DateTime month) {
  final f  = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final prev = DateFormat('MMM').format(DateTime(month.year, month.month - 1));
  final b = StringBuffer();
  if (e.carriedIn != 0) {
    b.write('${f.format(e.carriedIn)} carried in from $prev\n');
  }
  b.write('${e.budgeted < 0 ? '−' : '+'} ${f.format(e.budgeted.abs())} budgeted\n');
  if (e.reserved != 0) {
    b.write('+ ${f.format(e.reserved)} set aside by card charges\n');
  }
  if (e.activity != 0 || e.reserved == 0) {
    b.write('${e.activity < 0 ? '−' : '+'} ${f.format(e.activity.abs())} '
        '${e.isCcPayment ? 'paid to card' : e.activity < 0 ? 'spent' : 'inflow'}\n');
  }
  b.write('= ${f.format(e.balance)} available');
  return b.toString();
}

/// Asks which month a category stops applying, defaulting to the month being
/// viewed. Returned as the first of that month.
Future<DateTime?> _pickInactiveMonth(
    BuildContext context, DateTime viewedMonth) async {
  final now = DateTime.now();
  final options = List.generate(
      13, (i) => DateTime(viewedMonth.year, viewedMonth.month - 3 + i));
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text('Inactive from',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 320,
          height: 320,
          child: ListView.builder(
            itemCount: options.length,
            itemBuilder: (_, i) {
              final m         = options[i];
              final isDefault = m.year == viewedMonth.year &&
                                m.month == viewedMonth.month;
              final isFuture  = m.isAfter(DateTime(now.year, now.month));
              return ListTile(
                dense: true,
                title: Text(DateFormat('MMMM yyyy').format(m),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight:
                          isDefault ? FontWeight.w700 : FontWeight.w500,
                      color: isFuture ? cs.onSurfaceVariant : cs.onSurface,
                    )),
                trailing: isDefault
                    ? Text('viewing',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: cs.primary))
                    : null,
                onTap: () => Navigator.pop(ctx, m),
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
        ],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Inactive categories sheet — browse and reactivate
// ---------------------------------------------------------------------------

void _showInactiveCategoriesSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    builder:            (_) => const _InactiveCategoriesSheet(),
  );
}

class _InactiveCategoriesSheet extends ConsumerWidget {
  const _InactiveCategoriesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs    = Theme.of(context).colorScheme;
    final async = ref.watch(inactiveCategoriesProvider);

    return Container(
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Inactive Categories',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20, fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(
            'Hidden from the budget and the transaction picker. '
            'History is kept, and any leftover balance returned to '
            'To Be Budgeted.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load: $e',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.error)),
              ),
              data: (cats) => cats.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('No inactive categories.',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, color: cs.onSurfaceVariant)),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount:  cats.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.4)),
                      itemBuilder: (ctx, i) {
                        final c = cats[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.name,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface)),
                          subtitle: Text(
                            [
                              if (c.groupName.isNotEmpty) c.groupName,
                              if (c.inactiveFrom != null)
                                'inactive from '
                                    '${DateFormat('MMM yyyy').format(c.inactiveFrom!)}',
                            ].join('  ·  '),
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                          trailing: TextButton.icon(
                            onPressed: () => ref
                                .read(budgetProvider.notifier)
                                .setCategoryInactiveFrom(c.id, null),
                            icon:  const Icon(Icons.undo, size: 15),
                            label: const Text('Reactivate'),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a budget cell in the column tint, except for card envelopes whose
/// cell reads N/A — shading an unfillable cell implies a figure belongs there.
Widget _tintIfBudgetable(BudgetEntry entry, ColorScheme cs, Widget child) =>
    entry.ccAccountId != null
        ? child
        : ColoredBox(color: cs.primary.withValues(alpha: 0.07), child: child);

// ---------------------------------------------------------------------------
// Overspend carry arrow — inline toggle on an overspent category row
// ---------------------------------------------------------------------------

/// Appears on the row only while a category is overspent, because that is the
/// only time the setting changes anything.
///
/// Off (the default): the shortfall is covered by To Be Budgeted when the month
/// rolls over, and the category starts next month clean.
/// On: the negative balance follows the category into next month instead.
class _CarryOverspendArrow extends ConsumerWidget {
  final BudgetEntry entry;
  const _CarryOverspendArrow({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final on = entry.carryOverspend;

    return Tooltip(
      message: on
          ? 'Overspending carries into next month.\nTap to cover it from To Be Budgeted instead.'
          : 'Overspending is covered by To Be Budgeted.\nTap to carry it into next month instead.',
      child: InkWell(
        onTap: () => ref
            .read(budgetProvider.notifier)
            .setCarryOverspend(entry.categoryId, !on),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: on ? cs.error.withValues(alpha: 0.18) : null,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: on
                    ? cs.error.withValues(alpha: 0.55)
                    : cs.onSurfaceVariant.withValues(alpha: 0.35),
                width: 0.9,
              ),
            ),
            child: Icon(
              Icons.east,
              size: 12,
              color: on ? cs.error : cs.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CC account link tile — shown in CC payment category detail sheet
// ---------------------------------------------------------------------------

class _CcAccountLinkTile extends ConsumerWidget {
  final BudgetEntry entry;
  final WidgetRef ref;
  const _CcAccountLinkTile({required this.entry, required this.ref});

  Future<void> _linkAccount(BuildContext context, String accountId) async {
    final client = ref.read(supabaseProvider);
    await client
        .from('categories')
        .update({'linked_account_id': accountId})
        .eq('id', entry.categoryId);
    ref.invalidate(budgetProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs       = Theme.of(context).colorScheme;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final ccAccounts = accounts
        .where((a) => a.isCreditCard && !a.isTracking)
        .toList();

    if (ccAccounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'No credit card accounts found. Add one in Accounts.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: cs.onSurfaceVariant),
        ),
      );
    }

    final linkedAccount = entry.ccAccountId != null
        ? ccAccounts.where((a) => a.id == entry.ccAccountId).firstOrNull
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: entry.ccAccountId != null
            ? cs.primaryContainer.withValues(alpha: 0.3)
            : cs.errorContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.ccAccountId != null
              ? cs.primary.withValues(alpha: 0.25)
              : cs.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            entry.ccAccountId != null
                ? Icons.link_rounded
                : Icons.link_off_rounded,
            size: 18,
            color: entry.ccAccountId != null ? cs.primary : cs.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.ccAccountId != null ? 'Linked CC account' : 'Not linked to a CC account',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: entry.ccAccountId != null ? cs.primary : cs.error,
                  ),
                ),
                if (linkedAccount != null)
                  Text(
                    linkedAccount.displayName,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: cs.onSurface),
                  )
                else
                  Text(
                    'Link it so spending on the card auto-fills this envelope',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.edit_outlined, size: 16,
                color: cs.onSurfaceVariant),
            tooltip: 'Link to account',
            onSelected: (id) => _linkAccount(context, id),
            itemBuilder: (_) => ccAccounts
                .map((a) => PopupMenuItem<String>(
                      value: a.id,
                      child: Row(
                        children: [
                          Icon(Icons.credit_card_outlined,
                              size: 16, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(a.displayName,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Battery-style budget consumption indicator
// ---------------------------------------------------------------------------

/// Thin horizontal battery bar showing how much of the budget has been spent.
///
/// Colour bands:
///   < 80 %   → green
///   80–100 % → amber
///   > 100 %  → red (overspent)
///
/// Hidden when [budgeted] ≤ 0 (no budget set for this category).
class _BatteryBar extends StatelessWidget {
  final double budgeted;
  final double spent; // entry.spent — always ≥ 0

  const _BatteryBar({required this.budgeted, required this.spent});

  @override
  Widget build(BuildContext context) {
    if (budgeted <= 0) return const SizedBox.shrink();

    final cs  = Theme.of(context).colorScheme;
    final pct = spent / budgeted; // may exceed 1.0

    final Color fill;
    if (pct > 1.0) {
      fill = context.money.negative;
    } else if (pct >= 0.8) {
      fill = context.money.warning;
    } else {
      fill = context.money.positive;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 5, right: 2),
      child: SizedBox(
        height: 5,
        child: CustomPaint(
          painter: _BatteryPainter(
            fillPct:   pct.clamp(0.0, 1.0),
            fillColor: fill,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final double fillPct;   // 0.0 – 1.0
  final Color  fillColor;

  const _BatteryPainter({required this.fillPct, required this.fillColor});

  static const _termW = 3.0;
  static const _termH = 3.0;
  static const _gap   = 1.0;
  static const _r     = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyW = size.width - _termW - _gap;
    final bodyH = size.height;

    // Track — empty battery body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, bodyW, bodyH), const Radius.circular(_r)),
      Paint()
        ..color = fillColor.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );

    // Fill
    if (fillPct > 0) {
      final fw = ((bodyW - 2) * fillPct).clamp(0.0, bodyW - 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(1, 1, fw, bodyH - 2),
            const Radius.circular(_r - 1)),
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.fill,
      );
    }

    // Outline
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, bodyW, bodyH), const Radius.circular(_r)),
      Paint()
        ..color = fillColor.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );

    // Terminal bump (+ end)
    final tY = (bodyH - _termH) / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(bodyW + _gap, tY, _termW, _termH),
          const Radius.circular(1)),
      Paint()
        ..color = fillColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.fillPct != fillPct || old.fillColor != fillColor;
}

// ---------------------------------------------------------------------------
// Column headers
// ---------------------------------------------------------------------------

class _ColumnHeaders extends StatelessWidget {
  final bool   isWide;
  final double totalBudgeted;
  final double totalActivity;
  final double totalAvailable;

  const _ColumnHeaders({
    required this.isWide,
    required this.totalBudgeted,
    required this.totalActivity,
    required this.totalAvailable,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('CATEGORY',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: cs.onSurfaceVariant,
                )),
          ),
          // Column tints removed: a named header does that job without
          // colouring every cell beneath it.
          _ColLabel('ASSIGNED', total: totalBudgeted,  cs: cs),
          _ColLabel('SPENT',    total: totalActivity,  cs: cs),
          _ColLabel('LEFT',     total: totalAvailable, cs: cs),
        ],
      ),
    );
  }
}

class _ColLabel extends StatelessWidget {
  final String text;
  final Color? bg;
  final double? total;
  final ColorScheme cs;
  const _ColLabel(this.text, {required this.cs, this.bg, this.total});

  static String _fmtTotal(double v) {
    final abs = v.abs();
    final s = abs >= 1000
        ? '\$${(abs / 1000).toStringAsFixed(1)}k'
        : '\$${abs.toStringAsFixed(0)}';
    return v < 0 ? '-$s' : s;
  }

  @override
  Widget build(BuildContext context) {
    final Widget label = SizedBox(
      width: _kColW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.right,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.6,
            ),
          ),
          if (total != null)
            Text(
              _fmtTotal(total!),
              textAlign: TextAlign.right,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: total! < 0 ? cs.error : cs.onSurface,
              ),
            ),
        ],
      ),
    );
    if (bg == null) return label;
    return ColoredBox(color: bg!, child: label);
  }
}

// ---------------------------------------------------------------------------
// Group header row
// ---------------------------------------------------------------------------

class _GroupHeaderRow extends StatelessWidget {
  final BudgetGroupData group;
  final bool isWide;
  final WidgetRef ref;
  final bool isExpanded;
  /// Toggles the group open/closed.
  final VoidCallback? onToggle;
  /// Long-press → opens rename / delete menu.
  final VoidCallback? onLongPress;
  /// Opens the "Reorder Groups" sheet.
  final VoidCallback? onReorderGroups;

  const _GroupHeaderRow({
    required this.group,
    required this.isWide,
    required this.ref,
    this.isExpanded = false,
    this.onToggle,
    this.onLongPress,
    this.onReorderGroups,
  });

  @override
  Widget build(BuildContext context) {
    final cs             = Theme.of(context).colorScheme;
    final groupBudgeted  = group.entries.fold(0.0, (s, e) => s + e.budgeted);
    final groupActivity  = group.entries.fold(0.0, (s, e) => s + e.activity);
    final groupAvailable = group.balance;

    return InkWell(
      onTap: onToggle,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 9, 16, 9),
        child: Row(
          children: [
            // Drag handle — tapping opens the "Reorder Groups" sheet.
            GestureDetector(
              onTap: onReorderGroups,
              child: Tooltip(
                message: 'Reorder groups',
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.drag_handle,
                    size: 18,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ),
            // Group name
            Expanded(
              child: Row(
                children: [
                  Text(
                    group.name.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (group.hasOverspend) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.warning_amber_rounded, size: 13, color: cs.error),
                  ],
                ],
              ),
            ),
            // Numeric columns on wide only. On mobile the group states its
            // remaining balance in words and leaves the arithmetic to the rows.
            if (isWide) ...[
              _NumCell(groupBudgeted, cs.onSurfaceVariant, bold: true),
              _NumCell(groupActivity, cs.onSurfaceVariant, bold: true),
              _NumCell(
                groupAvailable,
                groupAvailable < 0 ? context.money.negative : cs.onSurfaceVariant,
                bold: true,
              ),
            ] else ...[
              Text(
                '${NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(groupAvailable)} left',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: groupAvailable < 0
                      ? context.money.negative
                      : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: cs.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category table row
// ---------------------------------------------------------------------------

/// Icon avatar for a category row. The code point already existed and was only
/// being drawn in the desktop panels.
/// Named actions on an overspent row, replacing an unlabelled arrow.
class _OverspendActions extends ConsumerWidget {
  final BudgetEntry entry;
  final DateTime month;
  const _OverspendActions({required this.entry, required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = context.money;
    final f2    = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final short = f2.format(entry.balance.abs());
    final tbb   = ref.watch(budgetProvider).valueOrNull?.tbb ?? 0;
    final canCover = tbb > 0;
    final nextMonth = DateFormat('MMM')
        .format(DateTime(month.year, month.month + 1));

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Tooltip(
            message: canCover
                ? 'Move $short from Ready to Assign'
                : 'Nothing left in Ready to Assign to move',
            child: _OverspendChip(
              label: 'Cover $short',
              tint:  money.positive,
              enabled: canCover,
              onTap: !canCover
                  ? null
                  // Assigning the shortfall on top of what is already there is
                  // exactly what "cover it" means in envelope terms.
                  : () => ref.read(budgetProvider.notifier).setBudgeted(
                        entry.categoryId,
                        entry.budgeted + entry.balance.abs(),
                        month: month,
                      ),
            ),
          ),
          _OverspendChip(
            label: entry.carryOverspend
                ? 'Carrying to $nextMonth'
                : 'Carry to $nextMonth',
            tint: money.warning,
            enabled: !entry.carryOverspend,
            onTap: entry.carryOverspend
                ? null
                : () => ref
                    .read(budgetProvider.notifier)
                    .setCarryOverspend(entry.categoryId, true),
          ),
        ],
      ),
    );
  }
}

class _OverspendChip extends StatelessWidget {
  final String label;
  final Color tint;
  final bool enabled;
  final VoidCallback? onTap;
  const _OverspendChip({
    required this.label,
    required this.tint,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = enabled ? tint : tint.withValues(alpha: 0.4);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      ),
    );
  }
}

class _CategoryAvatar extends StatelessWidget {
  final BudgetEntry entry;
  const _CategoryAvatar({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cp = entry.iconCodePoint;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: entry.isCcPayment
            ? Icon(Icons.credit_card, size: 20, color: cs.primary)
            : cp != null
                ? iconFromCodePoint(cp, size: 20, color: cs.onSurfaceVariant)
                : Icon(Icons.category, size: 20, color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// The three lines of a mobile category row: name and what is left, then the
/// same figures as a sentence, then progress.
///
/// The middle line restores the Activity number, which the old narrow layout
/// dropped entirely — mobile could see budgeted and remaining but never what
/// had actually been spent.
class _CategoryRowBody extends StatelessWidget {
  final BudgetEntry entry;
  const _CategoryRowBody({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final money = context.money;
    final f0    = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final over  = entry.balance < 0;
    final spent = entry.spent;
    final amountColor = over
        ? money.negative
        : entry.balance > 0
            ? money.positive
            : cs.onSurfaceVariant.withValues(alpha: 0.8);

    final String detail;
    if (entry.isCcPayment) {
      detail = '${f0.format(entry.reserved)} set aside';
    } else if (entry.budgeted == 0 && spent == 0) {
      detail = 'Nothing spent yet';
    } else if (entry.balance == 0 && spent > 0) {
      detail = 'All ${f0.format(spent)} spent';
    } else {
      detail = '${f0.format(spent)} of ${f0.format(entry.budgeted)} spent';
    }

    final pct = entry.budgeted > 0 ? (spent / entry.budgeted) : 0.0;
    final barColor = pct >= 1.0
        ? money.negative
        : pct >= 0.8
            ? money.warning
            : money.positive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(entry.categoryName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ),
            if (entry.goal != null) ...[
              const SizedBox(width: 5),
              Icon(Icons.flag_outlined, size: 13, color: money.positive),
            ],
            const Spacer(),
            const SizedBox(width: 8),
            Text(f0.format(entry.balance),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: amountColor)),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Expanded(
              child: Text(detail,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: over
                          ? money.negative
                          : cs.onSurfaceVariant.withValues(alpha: 0.65))),
            ),
            const SizedBox(width: 8),
            Text(over ? 'over' : 'left',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: over
                        ? money.negative
                        : cs.onSurfaceVariant.withValues(alpha: 0.55))),
          ],
        ),
        if (entry.showsBudgetProgress) ...[
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: cs.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryTableRow extends ConsumerWidget {
  final BudgetEntry entry;
  final bool isWide;
  /// Drag handles appear only in reorder mode (T5); otherwise they are
  /// permanent chrome for an action taken once in a while.
  final bool reorderMode;
  /// Briefly tinted after an attention chip jumped here.
  final bool highlighted;
  final bool isExpanded;
  final DateTime month;
  final VoidCallback onToggle;
  final void Function(BudgetEntry, DateTime) onDetailTap;

  const _CategoryTableRow({
    required this.entry,
    required this.isWide,
    this.reorderMode = false,
    this.highlighted = false,
    required this.isExpanded,
    required this.month,
    required this.onToggle,
    required this.onDetailTap,
  });

  String get _monthKey =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs          = Theme.of(context).colorScheme;
    final isOverspent = entry.balance < 0;
    final isFullyUsed = entry.balance == 0 && entry.spent > 0;
    final availColor  = isOverspent  ? cs.error
        : isFullyUsed               ? cs.onSurfaceVariant
        : entry.balance > 0         ? context.money.positive
        :                             cs.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Main row ──────────────────────────────────────────
        InkWell(
          onTap: onToggle,
          child: isWide
              // Wide keeps the table: named columns carry the meaning there.
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
                  child: Row(
                    children: [
                      if (reorderMode)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(Icons.drag_handle,
                              size: 16,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.28)),
                        ),
                      if (entry.isCcPayment)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.credit_card,
                              size: 13, color: cs.primary),
                        ),
                      if (entry.goal != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Icon(Icons.flag_outlined,
                              size: 12, color: context.money.positive),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(entry.categoryName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: cs.onSurface,
                                )),
                            if (entry.showsBudgetProgress)
                              _BatteryBar(
                                  budgeted: entry.budgeted, spent: entry.spent),
                          ],
                        ),
                      ),
                      _InlineBudgetAmount(entry: entry),
                      _NumCell(entry.activity, cs.onSurfaceVariant),
                      Tooltip(
                        message: _availBreakdown(entry, month),
                        child: _NumCell(entry.balance, availColor, bold: true),
                      ),
                      const SizedBox(width: 4),
                      Icon(isExpanded ? Icons.expand_less : Icons.expand_more,
                          size: 16,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                    ],
                  ),
                )
              // Narrow reads as a sentence rather than a table line: what the
              // category is, what is left, and how much of it has gone.
              : Container(
                  margin: (isOverspent || highlighted)
                      ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
                      : EdgeInsets.zero,
                  padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
                  decoration: (isOverspent || highlighted)
                      ? BoxDecoration(
                          color: highlighted
                              ? cs.primary.withValues(alpha: 0.10)
                              : context.money.negative
                                  .withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                        )
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CategoryAvatar(entry: entry),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _CategoryRowBody(entry: entry),
                            // The old affordance here was a 15px unlabelled
                            // arrow. Naming both options, with the amount in
                            // them, is the whole fix.
                            if (isOverspent && !entry.isCcPayment)
                              _OverspendActions(entry: entry, month: month),
                          ],
                        ),
                      ),
                      if (reorderMode) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.drag_handle,
                            size: 18,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                      ],
                    ],
                  ),
                ),
        ),
        // ── Expanded transactions panel ───────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeInOut,
          child: isExpanded
              ? _CategoryTxPanel(
                  entry:     entry,
                  month:     month,
                  monthKey:  _monthKey,
                  onEditTap: () => onDetailTap(entry, month),
                )
              : const SizedBox.shrink(),
        ),
        Divider(
          height: 1,
          indent: 20,
          color: cs.outlineVariant.withValues(alpha: 0.35),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Inline budget-amount editor
// ---------------------------------------------------------------------------

/// Shows the budgeted amount as a tappable number.
/// Tapping it replaces the display with a text field for immediate editing.
///
/// [compact] = true → slim `_NumCell`-style (used in the main row on wide screens).
/// [compact] = false → labelled row (used inside the expanded panel).
class _InlineBudgetAmount extends ConsumerStatefulWidget {
  final BudgetEntry entry;
  final bool compact;
  /// Month this cell writes to. The 3-column view renders three panels at
  /// once, so the notifier's "current" month is not necessarily this one.
  final DateTime? month;
  /// Width of the compact cell — narrower in the 3-column panels.
  final double width;
  /// Abbreviate the *displayed* value ($1.2k) to match the neighbouring
  /// panel columns. Editing always uses full precision.
  final bool abbreviate;

  const _InlineBudgetAmount({
    required this.entry,
    this.compact = true,
    this.month,
    this.width = _kColW,
    this.abbreviate = false,
  });

  @override
  ConsumerState<_InlineBudgetAmount> createState() =>
      _InlineBudgetAmountState();
}

class _InlineBudgetAmountState extends ConsumerState<_InlineBudgetAmount> {
  bool _editing = false;
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _cancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    final v = widget.entry.budgeted;
    _ctrl.text = v == 0 ? '' : v.toStringAsFixed(2);
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.requestFocus();
        _ctrl.selection =
            TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
      }
    });
  }

  void _cancel() => setState(() => _editing = false);

  Future<void> _save() async {
    final amount =
        double.tryParse(_ctrl.text.trim().replaceAll(',', '')) ?? 0.0;
    await ref
        .read(budgetProvider.notifier)
        .setBudgeted(widget.entry.categoryId, amount, month: widget.month);
    if (mounted) setState(() => _editing = false);
  }

  // ── Compact mode (row cell) ────────────────────────────────────────────────

  Widget _buildCompact(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    if (_editing) {
      return SizedBox(
        width: widget.width,
        child: TextField(
          controller:     _ctrl,
          focusNode:      _focus,
          textAlign:      TextAlign.right,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onSubmitted:    (_) => _save(),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, fontWeight: FontWeight.w500, color: cs.onSurface),
          decoration: InputDecoration(
            prefixText:  '\$',
            prefixStyle: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: cs.primary),
            isDense:        true,
            contentPadding: const EdgeInsets.symmetric(
                vertical: 5, horizontal: 4),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  BorderSide(color: cs.primary.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
          ),
        ),
      );
    }

    // A card-linked envelope is funded by the card's charges, never by
    // assignment, so there is nothing to edit here.
    if (widget.entry.ccAccountId != null) {
      return Tooltip(
        message: 'Funded automatically by charges on the linked card',
        child: SizedBox(
          width: widget.width,
          child: Text(
            'N/A',
            textAlign: TextAlign.right,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _startEdit,
      // Without this the hit test defers to the child, so only the digits
      // themselves respond — the rest of the right-aligned cell reads as
      // dead space and the number looks uneditable.
      behavior: HitTestBehavior.opaque,
      child: Tooltip(
        message: 'Tap to edit budgeted amount',
        child: SizedBox(
          width: widget.width,
          child: Text(
            widget.abbreviate
                ? _PanelNum.fmtAbbrev(widget.entry.budgeted)
                : fmt.format(widget.entry.budgeted),
            textAlign: TextAlign.right,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
              decoration:      TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: cs.primary.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  // ── Panel mode (labelled row inside expanded panel) ────────────────────────

  Widget _buildPanel(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 2),
      child: Row(
        children: [
          Text('Budgeted',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
          const Spacer(),
          if (_editing) ...[
            SizedBox(
              width: 120,
              child: TextField(
                controller:     _ctrl,
                focusNode:      _focus,
                textAlign:      TextAlign.right,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted:    (_) => _save(),
                autofocus:      true,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
                decoration: InputDecoration(
                  prefixText:  '\$',
                  prefixStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 14, color: cs.primary),
                  isDense:        true,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 6, horizontal: 6),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                        color: cs.primary.withValues(alpha: 0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: cs.primary, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Confirm
            InkWell(
              onTap: _save,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.check, size: 18, color: cs.primary),
              ),
            ),
            // Cancel
            InkWell(
              onTap: _cancel,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ),
          ] else
            GestureDetector(
              onTap: _startEdit,
              child: Tooltip(
                message: 'Tap to edit',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: cs.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fmt.format(widget.entry.budgeted),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit,
                          size: 12,
                          color: cs.primary.withValues(alpha: 0.7)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.compact ? _buildCompact(context) : _buildPanel(context);
}

// ---------------------------------------------------------------------------
// Inline "add category" row (appears below a group's categories on + tap)
// ---------------------------------------------------------------------------

class _InlineAddRow extends ConsumerStatefulWidget {
  final String groupId;
  final VoidCallback onCancel;

  const _InlineAddRow({required this.groupId, required this.onCancel});

  @override
  ConsumerState<_InlineAddRow> createState() => _InlineAddRowState();
}

class _InlineAddRowState extends ConsumerState<_InlineAddRow> {
  final _ctrl  = TextEditingController();
  final _focus = FocusNode();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Handle Escape key to cancel.
    _focus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onCancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    // Auto-focus once the frame is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      widget.onCancel();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(budgetProvider.notifier).addCategory(
        name:    name,
        groupId: widget.groupId,
      );
      widget.onCancel(); // dismiss after successful save
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not add category: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surfaceContainerHigh,
      padding: const EdgeInsets.fromLTRB(36, 6, 8, 6),
      child: Row(
        children: [
          Icon(Icons.subdirectory_arrow_right,
              size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.35)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller:      _ctrl,
              focusNode:       _focus,
              enabled:         !_saving,
              style:           GoogleFonts.plusJakartaSans(fontSize: 14),
              textInputAction: TextInputAction.done,
              onSubmitted:     (_) => _submit(),
              onChanged:       (_) => setState(() {}),
              decoration: InputDecoration(
                hintText:       'Category name',
                hintStyle:      GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
                border:         InputBorder.none,
                isDense:        true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_saving)
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            // Confirm
            InkWell(
              onTap: _ctrl.text.trim().isNotEmpty ? _submit : null,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.check,
                    size: 18,
                    color: _ctrl.text.trim().isNotEmpty
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.3)),
              ),
            ),
            // Cancel
            InkWell(
              onTap: widget.onCancel,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close,
                    size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expanded transactions panel
// ---------------------------------------------------------------------------

// ── Sort order for a category's transaction list ─────────────────────────────

enum _TxSort {
  dateDesc, dateAsc, amountDesc, amountAsc;

  bool get isDate   => this == dateDesc   || this == dateAsc;
  bool get isAmount => this == amountDesc || this == amountAsc;
  bool get isDesc   => this == dateDesc   || this == amountDesc;
}

/// Per-category so sorting one list does not reorder another, and so the
/// choice survives collapsing and reopening the row.
final _catTxSortProvider =
    StateProvider.family<_TxSort, String>((ref, _) => _TxSort.dateDesc);

List<CategoryTransaction> _sortTxs(List<CategoryTransaction> txs, _TxSort s) {
  final out = [...txs];
  switch (s) {
    case _TxSort.dateDesc:   out.sort((a, b) => b.date.compareTo(a.date));
    case _TxSort.dateAsc:    out.sort((a, b) => a.date.compareTo(b.date));
    // By magnitude: these lists are almost all expenses, so "largest spend
    // first" is the useful reading, and a stray refund sorts by size too.
    case _TxSort.amountDesc: out.sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
    case _TxSort.amountAsc:  out.sort((a, b) => a.amount.abs().compareTo(b.amount.abs()));
  }
  return out;
}

class _TxSortChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool desc;
  final VoidCallback onTap;
  const _TxSortChip({
    required this.label,
    required this.active,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 2),
              Icon(desc ? Icons.arrow_downward : Icons.arrow_upward,
                  size: 11, color: cs.primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryTxPanel extends ConsumerWidget {
  final BudgetEntry entry;
  final DateTime month;
  final String monthKey;
  final VoidCallback onEditTap;

  const _CategoryTxPanel({
    required this.entry,
    required this.month,
    required this.monthKey,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs     = Theme.of(context).colorScheme;
    final txAsync = ref.watch(
        categoryTransactionsProvider((entry.categoryId, monthKey)));
    final sort    = ref.watch(_catTxSortProvider(entry.categoryId));

    return Container(
      color: cs.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Carried-in line ──
          // Available = carried-in + budgeted + activity, but only the latter
          // two get columns; without this the row reads as bad arithmetic.
          if (entry.carriedIn != 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Carried in from '
                    '${DateFormat('MMM').format(DateTime(month.year, month.month - 1))}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    NumberFormat.currency(symbol: '\$', decimalDigits: 2)
                        .format(entry.carriedIn),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: entry.carriedIn < 0 ? cs.error : context.money.positive,
                    ),
                  ),
                ],
              ),
            ),
          // ── Inline budget editor (primary on narrow, secondary on wide) ──
          _InlineBudgetAmount(entry: entry, compact: false),
          // ── Transaction list ──
          txAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Error loading transactions',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.error)),
            ),
            data: (txs) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (txs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                    child: Text(
                      'No transactions this month',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 2, 12, 2),
                    child: Row(
                      children: [
                        Text('Sort',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: cs.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            )),
                        const SizedBox(width: 6),
                        _TxSortChip(
                          label:  'Date',
                          active: sort.isDate,
                          desc:   sort.isDesc,
                          onTap: () => ref
                              .read(_catTxSortProvider(entry.categoryId).notifier)
                              .state = sort == _TxSort.dateDesc
                                  ? _TxSort.dateAsc
                                  : _TxSort.dateDesc,
                        ),
                        _TxSortChip(
                          label:  'Amount',
                          active: sort.isAmount,
                          desc:   sort.isDesc,
                          onTap: () => ref
                              .read(_catTxSortProvider(entry.categoryId).notifier)
                              .state = sort == _TxSort.amountDesc
                                  ? _TxSort.amountAsc
                                  : _TxSort.amountDesc,
                        ),
                      ],
                    ),
                  ),
                  ..._sortTxs(txs, sort).map((tx) => _CategoryTxRow(tx: tx)),
                ],
                // ── Insight card (Path C) ──────────────────────────────────
                _PatternInsightCard(entry: entry, txs: txs),
              ],
            ),
          ),
          // ── Action buttons ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            // Wrap rather than Row: five actions overflow a narrow screen.
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _PanelAction(
                  icon: Icons.drive_file_rename_outline,
                  label: 'Rename',
                  onTap: () => _showRenameCategoryDialog(context, ref, entry),
                ),
                _PanelAction(
                  icon: entry.iconCodePoint != null
                      ? Icons.emoji_emotions_outlined
                      : Icons.add_reaction_outlined,
                  label: 'Icon',
                  onTap: () => _showCategoryIconPicker(context, ref, entry),
                ),
                if (!entry.isCcPayment)
                  _PanelAction(
                    icon: Icons.archive_outlined,
                    label: 'Inactive',
                    onTap: () async {
                      final from = await _pickInactiveMonth(context, month);
                      if (from == null) return;
                      await ref
                          .read(budgetProvider.notifier)
                          .setCategoryInactiveFrom(entry.categoryId, from);
                    },
                  ),
                _PanelAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  onTap: () => _showDeleteCategoryDialog(context, ref, entry),
                  isDestructive: true,
                ),
                _PanelAction(
                  icon: Icons.tune_outlined,
                  label: 'More',
                  onTap: onEditTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single transaction row inside the expanded panel
// ---------------------------------------------------------------------------

class _CategoryTxRow extends StatelessWidget {
  final CategoryTransaction tx;
  const _CategoryTxRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final isIncome = tx.amount > 0;
    final fmt      = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 7, 16, 7),
      child: Row(
        children: [
          Text(
            DateFormat('MMM d').format(tx.date),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              tx.payee.isNotEmpty ? tx.payee : tx.accountName,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: cs.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            isIncome
                ? '+${fmt.format(tx.amount)}'
                : fmt.format(tx.amount.abs()),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isIncome ? context.money.positive : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payee pattern insight card — Path C
// ---------------------------------------------------------------------------

class _PatternInsightCard extends ConsumerWidget {
  final BudgetEntry entry;
  final List<CategoryTransaction> txs;

  const _PatternInsightCard({required this.entry, required this.txs});

  /// Most-visited payee this month (by visit count).
  String? _dominantPayee() {
    if (txs.isEmpty) return null;
    final counts = <String, int>{};
    for (final t in txs) {
      if (t.payee.isNotEmpty) counts[t.payee] = (counts[t.payee] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payee = _dominantPayee();
    if (payee == null) return const SizedBox.shrink();

    final patternAsync = ref.watch(payeePatternProvider(payee));

    return patternAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (e, _) => const SizedBox.shrink(),
      data:    (p) => p.confidence == PatternConfidence.none
          ? const SizedBox.shrink()
          : _InsightCardContent(pattern: p, entry: entry),
    );
  }
}

class _InsightCardContent extends StatelessWidget {
  final PayeePattern pattern;
  final BudgetEntry entry;

  const _InsightCardContent({required this.pattern, required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    // Budget maths — based on this category's envelope
    final budgetRemaining = (entry.budgeted - entry.activity.abs())
        .clamp(0.0, double.infinity);
    final recommended = pattern.recommendedSpend(budgetRemaining);

    // Icon + headline based on confidence
    final (icon, headline) = switch (pattern.confidence) {
      PatternConfidence.established => (
          '🛒',
          pattern.typicalDayName != null
              ? '${pattern.payeeName} every ${pattern.typicalDayName}'
              : '${pattern.payeeName} · ${pattern.frequency?.shortLabel ?? 'regular'}',
        ),
      PatternConfidence.tentative => (
          '📊',
          'Early pattern · ${pattern.payeeName}',
        ),
      _ => ('📊', pattern.payeeName),
    };

    return Container(
      margin:  const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color:        cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Headline ──
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  headline,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Stats row ──
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              _Stat('Visit ${pattern.visitsThisMonth} this month',
                  cs.onSurfaceVariant),
              _Stat('avg ${fmt.format(pattern.avgSpend)}/visit',
                  cs.onSurfaceVariant),
              if (pattern.projectedVisitsLeft != null)
                _Stat(
                  '~${pattern.projectedVisitsLeft} left this month',
                  cs.onSurfaceVariant,
                ),
              if (pattern.confidence == PatternConfidence.tentative)
                _Stat('(still learning)', cs.onSurfaceVariant,
                    italic: true),
            ],
          ),

          // ── Recommendation ──
          if (recommended != null) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: cs.primary.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Keep next visit under',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color:        cs.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    fmt.format(recommended),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (budgetRemaining > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${fmt.format(budgetRemaining)} remaining in ${entry.categoryName}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String text;
  final Color color;
  final bool italic;

  const _Stat(this.text, this.color, {this.italic = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 11,
        color: color,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Numeric cell — right-aligned, fixed width
// ---------------------------------------------------------------------------

class _NumCell extends StatelessWidget {
  final double value;
  final Color color;
  final bool bold;

  const _NumCell(this.value, this.color, {this.bold = false});

  static String _fmt(double v) {
    final abs = v.abs();
    if (abs >= 1000) return '\$${(abs / 1000).toStringAsFixed(1)}k';
    return '\$${abs.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final label    = (value < 0 ? '-' : '') + _fmt(value);
    final dimmed   = value == 0;
    final fgColor  = dimmed ? color.withValues(alpha: 0.35) : color;

    final cell = SizedBox(
      width: _kColW,
      child: Text(
        label,
        textAlign: TextAlign.right,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: fgColor,
        ),
      ),
    );
    return cell;
  }
}

// ---------------------------------------------------------------------------
// Category detail sheet
// ---------------------------------------------------------------------------

class _CategoryDetailSheet extends ConsumerStatefulWidget {
  final BudgetEntry entry;
  final DateTime month;
  const _CategoryDetailSheet({required this.entry, required this.month});

  @override
  ConsumerState<_CategoryDetailSheet> createState() =>
      _CategoryDetailSheetState();
}

class _CategoryDetailSheetState extends ConsumerState<_CategoryDetailSheet> {
  late bool _carryOverspend = widget.entry.carryOverspend;
  bool _saving = false;
  late final TextEditingController _budgetCtrl;

  @override
  void initState() {
    super.initState();
    _budgetCtrl = TextEditingController(
      text: widget.entry.budgeted != 0
          ? widget.entry.budgeted.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _budgetCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveBudget() async {
    final text = _budgetCtrl.text.trim().replaceAll(',', '');
    final val  = text.isEmpty ? 0.0 : double.tryParse(text);
    if (val == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(budgetProvider.notifier)
          .setBudgeted(widget.entry.categoryId, val);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleCarryOverspend(bool v) async {
    setState(() => _carryOverspend = v);
    await ref.read(budgetProvider.notifier)
        .setCarryOverspend(widget.entry.categoryId, v);
  }

  @override
  Widget build(BuildContext context) {
    // Re-read the entry from the provider each build. The copy passed at
    // construction is a snapshot, so renaming or re-linking from inside this
    // sheet left it showing the old values until it was closed and reopened.
    final entry = ref.watch(budgetProvider).valueOrNull?.groups
            .expand((g) => g.entries)
            .where((e) => e.categoryId == widget.entry.categoryId)
            .firstOrNull ??
        widget.entry;
    final cs          = Theme.of(context).colorScheme;
    final fmt         = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final isOverspent = entry.balance < 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        // Capped and scrollable: this sheet has outgrown a phone screen
        // (stats, progress, CC link, budget field, goal card, Make Inactive,
        // carry toggle) and an unscrolled Column silently clipped everything
        // below the fold — including Make Inactive.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color:        cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(entry.categoryName,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 24),

            // Stats row
            Row(
              children: [
                if (entry.carriedIn != 0)
                  _StatCell(
                    label: 'Carried in',
                    value: fmt.format(entry.carriedIn),
                    color: entry.carriedIn < 0 ? cs.error : context.money.positive,
                  ),
                _StatCell(
                  label: 'Budgeted',
                  value: entry.ccAccountId != null
                      ? 'N/A'
                      : fmt.format(entry.budgeted),
                  color: entry.ccAccountId != null ? cs.onSurfaceVariant : cs.primary,
                ),
                // A CC envelope is filled by card spending rather than drained
                // by it, so "Spent" would always read $0 here.
                entry.isCcPayment
                    ? _StatCell(label: 'Reserved', value: fmt.format(entry.reserved), color: cs.onSurface)
                    : _StatCell(label: 'Spent',    value: fmt.format(entry.spent),    color: cs.onSurface),
                _StatCell(
                  label: isOverspent ? 'Overspent' : 'Remaining',
                  value: fmt.format(entry.balance.abs()),
                  color: isOverspent ? cs.error : context.money.positive,
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (entry.showsBudgetProgress) ...[
              SizedBox(
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (entry.spent / entry.budgeted).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(isOverspent ? cs.error : cs.primary),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // CC payment link section — shown for CC payment envelopes
            if (entry.isCcPayment) ...[
              _CcAccountLinkTile(entry: entry, ref: ref),
              const SizedBox(height: 16),
            ],

            // A card-linked envelope has no Budget field: charging the card is
            // what funds it, and assigning on top would fund the same bill
            // twice. Debt from before budgeting lives in its own category.
            if (entry.ccAccountId != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.bolt_outlined, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Funded automatically. Spending on this card moves '
                        'money here from whichever category you charged, so '
                        'there is nothing to assign.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              TextField(
                controller: _budgetCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                onSubmitted: (_) => _saveBudget(),
                decoration: const InputDecoration(
                  labelText: 'Budget amount',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _saveBudget,
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
              const SizedBox(height: 16),
            ],

            // Goal section
            if (entry.goal != null)
              _GoalDetailCard(
                goal:   entry.goal!,
                entry:  entry,
                month:  widget.month,
                onEdit: () => _showSetGoalSheet(
                    context, entry, widget.month, ref),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _showSetGoalSheet(
                    context, entry, widget.month, ref),
                icon:  const Icon(Icons.flag_outlined, size: 16),
                label: Text('Set a Goal',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            const SizedBox(height: 16),

            // Manage actions. This sheet is the only surface reachable from
            // the 3-column view, so it carries the full set — previously
            // Rename, Icon and Delete lived solely in the expanded row, which
            // exists only in the single-month layout.
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _PanelAction(
                  icon:  Icons.drive_file_rename_outline,
                  label: 'Rename',
                  onTap: () => _showRenameCategoryDialog(
                      context, ref, entry),
                ),
                _PanelAction(
                  icon: entry.iconCodePoint != null
                      ? Icons.emoji_emotions_outlined
                      : Icons.add_reaction_outlined,
                  label: 'Icon',
                  onTap: () => _showCategoryIconPicker(
                      context, ref, entry),
                ),
                _PanelAction(
                  icon:  Icons.delete_outline,
                  label: 'Delete',
                  isDestructive: true,
                  onTap: () async {
                    final deleted = await _showDeleteCategoryDialog(
                        context, ref, entry);
                    if (deleted && context.mounted) Navigator.pop(context);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Make inactive — keeps history, returns any balance to TBB
            if (!entry.isCcPayment) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final from = await _pickInactiveMonth(context, widget.month);
                  if (from == null) return;
                  await ref
                      .read(budgetProvider.notifier)
                      .setCategoryInactiveFrom(entry.categoryId, from);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.archive_outlined, size: 16),
                label: Text('Make Inactive',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose the month it stops applying. Earlier months keep '
                'showing it with their history; from that month on it leaves '
                'the budget and the transaction picker, and any leftover '
                'balance returns to To Be Budgeted.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
            ],

            // Carry overspend toggle
            if (!entry.isCcPayment)
              SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    color:        cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SwitchListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: Text('Carry overspending to next month',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface)),
                    subtitle: Text(
                      _carryOverspend
                          ? "Overspending reduces next month's category balance"
                          : "Overspending reduces this month's TBB",
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    value:           _carryOverspend,
                    onChanged:       _toggleCarryOverspend,
                    activeThumbColor: cs.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Goal detail card
// ---------------------------------------------------------------------------

class _GoalDetailCard extends StatelessWidget {
  final BudgetGoal goal;
  final BudgetEntry entry;
  final DateTime month;
  final VoidCallback onEdit;

  const _GoalDetailCard({
    required this.goal,
    required this.entry,
    required this.month,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final fmt        = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final fmtDec     = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final savedSoFar = entry.balance.clamp(0.0, double.infinity);
    final onTrack    = goal.isOnTrack(month, entry.budgeted, savedSoFar);
    final trackColor = onTrack ? context.money.positive : cs.error;
    final monthsLeft = goal.monthsRemaining(month);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        trackColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: trackColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 16, color: trackColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  goal.targetDate != null
                      ? 'Goal · ${fmt.format(goal.targetAmount)} by ${goal.targetDateLabel()}'
                      : 'Goal · ${fmt.format(goal.targetAmount)}/month',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: trackColor),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        trackColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(onTrack ? 'On Track' : 'Behind',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: trackColor)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: goal.progressPercent(savedSoFar),
              minHeight: 8,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(trackColor),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _GoalStat(label: 'Saved',     value: fmt.format(savedSoFar)),
              _GoalStat(label: 'Remaining', value: fmt.format(goal.targetAmount - savedSoFar)),
              _GoalStat(label: 'Monthly',   value: fmtDec.format(goal.monthlyNeeded(month, savedSoFar))),
              if (monthsLeft > 0)
                _GoalStat(label: 'Months left', value: '$monthsLeft'),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon:  const Icon(Icons.edit_outlined, size: 14),
            label: Text('Edit Goal', style: GoogleFonts.plusJakartaSans(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalStat extends StatelessWidget {
  final String label;
  final String value;
  const _GoalStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 10, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Set Goal sheet
// ---------------------------------------------------------------------------

void _showSetGoalSheet(
  BuildContext context,
  BudgetEntry entry,
  DateTime month,
  WidgetRef ref,
) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    builder:            (_) => _SetGoalSheet(entry: entry, month: month, ref: ref),
  );
}

class _SetGoalSheet extends StatefulWidget {
  final BudgetEntry entry;
  final DateTime month;
  final WidgetRef ref;
  const _SetGoalSheet({required this.entry, required this.month, required this.ref});

  @override
  State<_SetGoalSheet> createState() => _SetGoalSheetState();
}

class _SetGoalSheetState extends State<_SetGoalSheet> {
  late GoalType _type;
  late final TextEditingController _amountCtrl;
  late DateTime _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.entry.goal;
    _type       = existing?.type ?? GoalType.targetByDate;
    _amountCtrl = TextEditingController(
      text: existing != null ? existing.targetAmount.toStringAsFixed(2) : '',
    );
    _targetDate = existing?.targetDate ?? DateTime(DateTime.now().year, 12);
  }

  @override
  void dispose() { _amountCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final val = double.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (val == null || val <= 0) return;
    setState(() => _saving = true);
    try {
      await widget.ref.read(budgetProvider.notifier).saveGoal(
        categoryId:    widget.entry.categoryId,
        type:          _type,
        targetAmount:  val,
        targetDate:    _type == GoalType.targetByDate ? _targetDate : null,
        monthlyAmount: _type != GoalType.targetByDate ? val : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        // Scrollable + capped: with the keyboard up this sheet exceeds the
        // viewport, and an unscrolled Column clips whatever falls below.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color:        cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 20, color: context.money.positive),
                const SizedBox(width: 8),
                Text('Set a Goal',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 24),

            Text('GOAL TYPE',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            _SegmentGroup<GoalType>(
              options: const [
                (GoalType.targetByDate,    'Target by Date',   Icons.event),
                (GoalType.monthlySavings,  'Monthly Savings',  Icons.repeat),
                (GoalType.monthlySpending, 'Monthly Spending', Icons.shopping_bag_outlined),
              ],
              selected:  _type,
              onChanged: (v) => setState(() => _type = v),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _type == GoalType.targetByDate ? 'Target amount' : 'Monthly amount',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 16),

            if (_type == GoalType.targetByDate) ...[
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context:              context,
                    initialDate:          _targetDate,
                    firstDate:            DateTime.now(),
                    lastDate:             DateTime(DateTime.now().year + 10),
                    initialDatePickerMode: DatePickerMode.year,
                  );
                  if (picked != null) setState(() => _targetDate = picked);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color:        cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Target: ${DateFormat('MMMM yyyy').format(_targetDate)}',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, color: cs.onSurface),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
              if (_amountCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 12),
                _MonthlyNeededPreview(
                  targetAmount: double.tryParse(_amountCtrl.text) ?? 0,
                  targetDate:   _targetDate,
                ),
              ],
            ],

            const SizedBox(height: 28),
            FilledButton(
              onPressed: (_amountCtrl.text.trim().isNotEmpty && !_saving) ? _save : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : Text('Save Goal',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _MonthlyNeededPreview extends StatelessWidget {
  final double targetAmount;
  final DateTime targetDate;
  const _MonthlyNeededPreview({required this.targetAmount, required this.targetDate});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final now    = DateTime.now();
    final months = (targetDate.year - now.year) * 12 + (targetDate.month - now.month);
    if (months <= 0) return const SizedBox.shrink();
    final monthly = targetAmount / months;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 14, color: cs.primary),
          const SizedBox(width: 8),
          Text('Budget ${fmt.format(monthly)}/month for $months months',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Budget sheet
// ---------------------------------------------------------------------------

void _showQuickBudgetSheet(BuildContext context, DateTime month, WidgetRef ref) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    builder:            (_) => _QuickBudgetSheet(month: month, ref: ref),
  );
}

// Use public enums from budget_provider.dart
typedef _QuickBudgetStrategy = QuickBudgetStrategy;
typedef _QuickBudgetScope    = QuickBudgetScope;

class _QuickBudgetSheet extends StatefulWidget {
  final DateTime month;
  final WidgetRef ref;
  const _QuickBudgetSheet({required this.month, required this.ref});

  @override
  State<_QuickBudgetSheet> createState() => _QuickBudgetSheetState();
}

class _QuickBudgetSheetState extends State<_QuickBudgetSheet> {
  _QuickBudgetStrategy _strategy = _QuickBudgetStrategy.lastMonth;
  _QuickBudgetScope    _scope    = _QuickBudgetScope.thisMonth;
  bool _applying = false;

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      await widget.ref.read(budgetProvider.notifier).applyQuickBudget(
        strategy:  _strategy,
        scope:     _scope,
        baseMonth: widget.month,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _applying = false);
      }
    }
  }

  String get _strategyLabel => switch (_strategy) {
    _QuickBudgetStrategy.currentMonth    => "Copy this month's budgeted amounts",
    _QuickBudgetStrategy.lastMonth       => "Copy last month's budgeted amounts",
    _QuickBudgetStrategy.averageSpending => 'Average of last 3 months actual spending',
    _QuickBudgetStrategy.coverSpending   => "Match this month's actual spending",
  };

  String get _applyLabel => switch (_scope) {
    _QuickBudgetScope.thisMonth => 'Apply to ${DateFormat('MMMM').format(widget.month)}',
    _QuickBudgetScope.next3     => 'Apply to next 3 months',
    _QuickBudgetScope.next6     => 'Apply to next 6 months',
    _QuickBudgetScope.next12    => 'Apply to next 12 months',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        // Scrollable + capped: with the keyboard up this sheet exceeds the
        // viewport, and an unscrolled Column clips whatever falls below.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color:        cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text('Quick Budget',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 24),

            Text('BUDGET BASED ON',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            _SegmentGroup<_QuickBudgetStrategy>(
              options: const [
                (_QuickBudgetStrategy.currentMonth,    'This Month',   Icons.today),
                (_QuickBudgetStrategy.lastMonth,       'Last Month',   Icons.history),
                (_QuickBudgetStrategy.averageSpending, '3-Mo Avg',     Icons.show_chart),
                (_QuickBudgetStrategy.coverSpending,   'Cover Spent',  Icons.check_circle_outline),
              ],
              selected:  _strategy,
              onChanged: (v) => setState(() => _strategy = v),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(_strategyLabel,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(height: 24),

            Text('APPLY TO',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant, letterSpacing: 0.8)),
            const SizedBox(height: 10),
            _SegmentGroup<_QuickBudgetScope>(
              options: const [
                (_QuickBudgetScope.thisMonth, 'This Month', null),
                (_QuickBudgetScope.next3,     'Next 3',     null),
                (_QuickBudgetScope.next6,     'Next 6',     null),
                (_QuickBudgetScope.next12,    'Next 12',    null),
              ],
              selected:  _scope,
              onChanged: (v) => setState(() => _scope = v),
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _applying ? null : _apply,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _applying
                  ? SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary))
                  : Text(_applyLabel,
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Category sheet
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Group actions — rename / delete
// ---------------------------------------------------------------------------

void _showGroupActions(
    BuildContext context, WidgetRef ref, BudgetGroupData group) {
  final cs = Theme.of(context).colorScheme;
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              group.name,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: cs.onSurface),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.drive_file_rename_outline, color: cs.primary),
            title: Text('Rename group',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500)),
            onTap: () {
              Navigator.pop(context);
              _showRenameGroupDialog(context, ref, group);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: cs.error),
            title: Text('Delete group',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w500, color: cs.error)),
            onTap: () {
              Navigator.pop(context);
              _showDeleteGroupDialog(context, ref, group);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _showRenameGroupDialog(
    BuildContext context, WidgetRef ref, BudgetGroupData group) {
  final ctrl = TextEditingController(text: group.name);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Rename group',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Group name'),
        onSubmitted: (_) async {
          if (ctrl.text.trim().isEmpty) return;
          await ref.read(budgetProvider.notifier).renameGroup(group.id, ctrl.text);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            if (ctrl.text.trim().isEmpty) return;
            await ref.read(budgetProvider.notifier).renameGroup(group.id, ctrl.text);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

void _showDeleteGroupDialog(
    BuildContext context, WidgetRef ref, BudgetGroupData group) {
  final hasCategories = group.entries.isNotEmpty;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${group.name}"?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: Text(
        hasCategories
            ? 'This will also delete all ${group.entries.length} '
                'categories in this group. Transactions will become '
                'uncategorized. This cannot be undone.'
            : 'The group will be permanently removed.',
        style: GoogleFonts.plusJakartaSans(fontSize: 14),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () async {
            await ref.read(budgetProvider.notifier).deleteGroup(group.id);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Category rename / delete
// ---------------------------------------------------------------------------

void _showCategoryIconPicker(
    BuildContext context, WidgetRef ref, BudgetEntry entry) async {
  final picked = await showModalBottomSheet<int?>(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _IconPickerSheet(selected: entry.iconCodePoint),
  );
  if (!context.mounted) return;
  // null means "Remove" was tapped; skip update if sheet was dismissed without picking
  if (picked != null || entry.iconCodePoint != null) {
    await ref.read(budgetProvider.notifier).updateCategoryIcon(entry.categoryId, picked);
  }
}

void _showRenameCategoryDialog(
    BuildContext context, WidgetRef ref, BudgetEntry entry) {
  final ctrl = TextEditingController(text: entry.categoryName);
  var iconCp = entry.iconCodePoint;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlgState) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text('Edit category',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus:  true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Category name'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Icon',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showModalBottomSheet<int?>(
                        context:         context,
                        isScrollControlled: true,
                        backgroundColor:  Colors.transparent,
                        builder: (_) => _IconPickerSheet(selected: iconCp),
                      );
                      if (!ctx.mounted) return;
                      setDlgState(() => iconCp = picked);
                    },
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: iconCp != null
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: iconCp != null
                              ? cs.primary.withValues(alpha: 0.4)
                              : cs.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Center(
                        child: iconCp != null
                            ? iconFromCodePoint(iconCp!, size: 20, color: cs.primary)
                            : Icon(Icons.add_reaction_outlined, size: 18,
                                color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                  if (iconCp != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setDlgState(() => iconCp = null),
                      child: Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (ctrl.text.trim().isEmpty) return;
                await ref
                    .read(budgetProvider.notifier)
                    .renameCategory(entry.categoryId, ctrl.text);
                await ref
                    .read(budgetProvider.notifier)
                    .updateCategoryIcon(entry.categoryId, iconCp);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
}

/// Resolves true when the category was deleted, so a caller showing this from
/// inside a sheet can dismiss itself rather than sit on a dead category.
Future<bool> _showDeleteCategoryDialog(
    BuildContext context, WidgetRef ref, BudgetEntry entry) async {
  final deleted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "${entry.categoryName}"?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
      content: Text(
        'Existing transactions will become uncategorized. '
        'This cannot be undone.',
        style: GoogleFonts.plusJakartaSans(fontSize: 14),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () async {
            await ref
                .read(budgetProvider.notifier)
                .deleteCategory(entry.categoryId);
            if (ctx.mounted) Navigator.pop(ctx, true);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return deleted ?? false;
}

// ---------------------------------------------------------------------------
// Small action button used in the expanded category panel
// ---------------------------------------------------------------------------

class _PanelAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _PanelAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final color = isDestructive ? cs.error : cs.primary;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reorder Groups sheet
// ---------------------------------------------------------------------------

void _showReorderGroupsSheet(
    BuildContext context, WidgetRef ref, List<BudgetGroupData> groups) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    builder:            (_) => _ReorderGroupsSheet(groups: groups, ref: ref),
  );
}

class _ReorderGroupsSheet extends StatefulWidget {
  final List<BudgetGroupData> groups;
  final WidgetRef ref;
  const _ReorderGroupsSheet({required this.groups, required this.ref});

  @override
  State<_ReorderGroupsSheet> createState() => _ReorderGroupsSheetState();
}

class _ReorderGroupsSheetState extends State<_ReorderGroupsSheet> {
  late List<BudgetGroupData> _groups;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groups = List.of(widget.groups);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.ref.read(budgetProvider.notifier).reorderGroups(_groups);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save order: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Sheet handle ───────────────────────────────────────────────────
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text('Reorder Groups',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              const Spacer(),
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text('Cancel',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // ── Draggable group list ───────────────────────────────────────────
        SizedBox(
          // Cap height so it doesn't overflow on phones with many groups.
          height: (_groups.length * 56.0).clamp(56.0, 360.0),
          child: ReorderableListView.builder(
            itemCount: _groups.length,
            buildDefaultDragHandles: false,
            onReorder: (oldIdx, newIdx) {
              setState(() {
                if (newIdx > oldIdx) newIdx -= 1;
                _groups.insert(newIdx, _groups.removeAt(oldIdx));
              });
            },
            itemBuilder: (ctx, i) {
              final group = _groups[i];
              return ListTile(
                key: ValueKey(group.id),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: Icon(Icons.drag_handle,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.55)),
                ),
                title: Text(group.name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${group.entries.length} '
                  '${group.entries.length == 1 ? 'category' : 'categories'}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
              );
            },
          ),
        ),
        // ── Save button ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Save Order',
                      style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

void _showAddCategorySheet(BuildContext context, WidgetRef ref, {String? initialGroupId}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    builder:            (_) => _AddCategorySheet(ref: ref, initialGroupId: initialGroupId),
  );
}

class _AddCategorySheet extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final String? initialGroupId;
  const _AddCategorySheet({required this.ref, this.initialGroupId});

  @override
  ConsumerState<_AddCategorySheet> createState() => _AddCategorySheetState();
}

class _AddCategorySheetState extends ConsumerState<_AddCategorySheet> {
  final _nameCtrl  = TextEditingController();
  final _groupCtrl = TextEditingController();

  late String? _selectedGroupId = widget.initialGroupId;
  bool _creatingGroup = false;
  bool _saving        = false;
  int? _iconCodePoint;        // null = no icon chosen yet
  bool _iconManuallyPicked = false; // user overrode the suggestion

  @override
  void dispose() {
    _nameCtrl.dispose();
    _groupCtrl.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _nameCtrl.text.trim().isNotEmpty &&
      (_selectedGroupId != null ||
          (_creatingGroup && _groupCtrl.text.trim().isNotEmpty)) &&
      !_saving;

  void _onNameChanged() {
    if (!_iconManuallyPicked) {
      final suggested = suggestCategoryIcon(_nameCtrl.text);
      if (suggested != _iconCodePoint) setState(() => _iconCodePoint = suggested);
    } else {
      setState(() {});
    }
  }

  Future<void> _pickIcon(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final picked = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _IconPickerSheet(selected: _iconCodePoint),
    );
    if (!mounted) return;
    setState(() {
      _iconCodePoint     = picked;
      _iconManuallyPicked = true;
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final String groupId;
      if (_creatingGroup) {
        groupId = await widget.ref.read(budgetProvider.notifier)
            .addGroup(_groupCtrl.text.trim());
      } else {
        groupId = _selectedGroupId!;
      }
      await widget.ref.read(budgetProvider.notifier).addCategory(
        name:          _nameCtrl.text.trim(),
        groupId:       groupId,
        iconCodePoint: _iconCodePoint,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final groups = ref.watch(budgetProvider).valueOrNull?.groups ?? [];
    final nonCC  = groups
        .where((g) => !g.entries.any((e) => e.isCcPayment))
        .toList();

    if (_selectedGroupId == null && nonCC.isNotEmpty && !_creatingGroup) {
      _selectedGroupId = nonCC.first.id;
    }

    final hasIcon = _iconCodePoint != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        // Scrollable + capped: with the keyboard up this sheet exceeds the
        // viewport, and an unscrolled Column clips whatever falls below.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color:        cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('New Category',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 24),

            // ── Name + icon row ───────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => _onNameChanged(),
                    decoration: const InputDecoration(labelText: 'Category name'),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _pickIcon(context),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: hasIcon
                          ? cs.primaryContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: hasIcon
                            ? cs.primary.withValues(alpha: 0.4)
                            : cs.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: hasIcon
                          ? iconFromCodePoint(_iconCodePoint!, size: 22, color: cs.primary)
                          : Icon(Icons.add_reaction_outlined, size: 20,
                              color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
            if (hasIcon)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(_iconManuallyPicked ? 'Tap to change' : 'Auto-suggested · tap to change',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            const SizedBox(height: 16),

            if (!_creatingGroup)
              DropdownButtonFormField<String>(
                initialValue:  _selectedGroupId,
                decoration:    const InputDecoration(labelText: 'Category group'),
                dropdownColor: cs.surfaceContainerHighest,
                items: [
                  ...nonCC.map((g) => DropdownMenuItem(
                        value: g.id,
                        child: Text(g.name,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                      )),
                  DropdownMenuItem(
                    value: '__new__',
                    child: Text('+ New group...',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, color: cs.primary)),
                  ),
                ],
                onChanged: (v) {
                  if (v == '__new__') {
                    setState(() { _creatingGroup = true; _selectedGroupId = null; });
                  } else {
                    setState(() => _selectedGroupId = v);
                  }
                },
              )
            else
              TextField(
                controller: _groupCtrl,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'New group name',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _creatingGroup = false),
                  ),
                ),
              ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : Text('Add Category',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Icon picker sheet
// ---------------------------------------------------------------------------

class _IconPickerSheet extends StatelessWidget {
  final int? selected;
  const _IconPickerSheet({this.selected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color:        cs.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Choose an icon',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 17, fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
              ),
              if (selected != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text('Remove', style: TextStyle(color: cs.error)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap:  true,
            physics:     const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: kPickableIcons.length,
            itemBuilder: (ctx, i) {
              final (iconData, label) = kPickableIcons[i];
              final cp         = iconData.codePoint;
              final isSelected = cp == selected;

              return GestureDetector(
                onTap: () => Navigator.pop(context, cp),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: cs.primary, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(iconData, size: 24,
                          color: isSelected ? cs.primary : cs.onSurfaceVariant),
                      const SizedBox(height: 4),
                      Text(label,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              color: isSelected ? cs.primary : cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared segment selector
// ---------------------------------------------------------------------------

class _SegmentGroup<T> extends StatelessWidget {
  final List<(T, String, IconData?)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const _SegmentGroup({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: options.map((opt) {
        final (value, label, icon) = opt;
        final isSelected = selected == value;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? Border.all(color: cs.primary.withValues(alpha: 0.5))
                    : null,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16,
                        color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                    const SizedBox(height: 4),
                  ],
                  Text(label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat cell (used in detail sheet)
// ---------------------------------------------------------------------------

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCell({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop split view — budget left, category transactions right
// ---------------------------------------------------------------------------

class _BudgetSplitView extends ConsumerStatefulWidget {
  final BudgetState state;
  const _BudgetSplitView({required this.state});

  @override
  ConsumerState<_BudgetSplitView> createState() => _BudgetSplitViewState();
}

class _BudgetSplitViewState extends ConsumerState<_BudgetSplitView> {
  BudgetEntry? _selected;

  /// The panel is always populated: an empty "Select a category" pane was
  /// half the screen saying nothing. Falls back to the first category until
  /// one is chosen.
  BudgetEntry? _effectiveSelection(BudgetState state) {
    if (_selected != null) return _selected;
    for (final g in state.groups) {
      if (g.entries.isNotEmpty) return g.entries.first;
    }
    return null;
  }

  void _onSelect(BudgetEntry? entry) => setState(() {
    // Tap same category again → deselect
    _selected = _selected?.categoryId == entry?.categoryId ? null : entry;
  });

  void _onDetailTap(BudgetEntry entry, DateTime month) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _CategoryDetailSheet(entry: entry, month: month),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        // The budget list keeps the full width until a category is selected.
        // The detail panel used to be built unconditionally, so its "Select a
        // category" placeholder sat here claiming half the screen with nothing
        // in it.
        Expanded(
          child: _BudgetBody(
            state:            widget.state,
            onCategoryTap:    _onDetailTap,
            onCategorySelect: _onSelect,
          ),
        ),
        // Right: the selected category, always present.
        Builder(builder: (_) {
          final sel = _effectiveSelection(widget.state);
          if (sel == null) return const SizedBox.shrink();
          return Row(
            children: [
              VerticalDivider(
                  width: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
              SizedBox(
                width: 360,
                child: _CategorySplitPanel(
                  entry:        sel,
                  currentMonth: widget.state.month,
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Right-side panel — transactions for the selected category
// ---------------------------------------------------------------------------

/// Turns the panel's figures into a rate: what is left, over how many days,
/// is a number you can act on today.
class _PanelPaceLine extends StatelessWidget {
  final BudgetEntry entry;
  final DateTime month;
  final int txnCount;
  const _PanelPaceLine({
    required this.entry,
    required this.month,
    required this.txnCount,
  });

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final f2  = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final now = DateTime.now();

    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final isCurrentMonth =
        month.year == now.year && month.month == now.month;
    final daysLeft = isCurrentMonth ? (lastDay - now.day) : 0;

    final parts = <String>[
      '${f2.format(entry.spent)} spent over $txnCount '
          '${txnCount == 1 ? 'transaction' : 'transactions'}',
      if (isCurrentMonth)
        '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left in '
            '${DateFormat('MMMM').format(month)}',
    ];

    // Only meaningful while there is money left and month remaining.
    if (isCurrentMonth && daysLeft > 0 && entry.balance > 0) {
      parts.add('about ${f2.format(entry.balance / daysLeft)} a day keeps you inside');
    }

    return Text('${parts.join(' · ')}.',
        style: GoogleFonts.plusJakartaSans(
            fontSize: 12, height: 1.5, color: cs.onSurfaceVariant));
  }
}

/// Same category, same point last month.
/// Where this month's spending sits against the same category's own history —
/// last month, the 3-month average and the 12-month average, all on one set of
/// axes so they can actually be compared rather than remembered between taps.
///
/// The sentence stays: a chart shows the shape, but the number is what people
/// read first.
class _SpendPacePanel extends ConsumerWidget {
  final BudgetEntry entry;
  final DateTime month;
  const _SpendPacePanel({required this.entry, required this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs    = Theme.of(context).colorScheme;
    final money = context.money;
    final f0    = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final async = ref.watch(spendPaceProvider((entry.categoryId, month)));

    return async.maybeWhen(
      orElse: () => const SizedBox.shrink(),
      data: (pace) {
        if (!pace.hasHistory) return const SizedBox.shrink();

        final last    = pace.lastMonth;
        final soFar   = pace.currentSoFar;
        final lastNow = last?.at(pace.todayDay - 1) ?? 0;
        final diff    = soFar - lastNow;
        final lighter = diff < 0;

        // The line is coloured by the same comparison the sentence makes, so
        // text and chart never tell different stories.
        final currentColor = last == null || !last.hasSpend
            ? cs.primary
            : (lighter ? money.positive : money.warning);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SPENDING PACE',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            if (last != null && last.hasSpend)
              Text.rich(
                TextSpan(
                  text: "You'd spent ${f0.format(lastNow)} by this point in "
                      '${last.label}. ',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: diff.abs() < 1
                          ? "You're level so far."
                          : "You're ${f0.format(diff.abs())} "
                              '${lighter ? 'lighter' : 'heavier'} so far.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: lighter ? money.positive : money.warning,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              height: 152,
              child: LayoutBuilder(
                builder: (context, c) => CustomPaint(
                  size: Size(c.maxWidth, 152),
                  painter: _PaceChartPainter(
                    pace:         pace,
                    currentColor: currentColor,
                    baseColor:    cs.onSurfaceVariant,
                    gridColor:    cs.outlineVariant,
                    monthLabel:   DateFormat('MMMM').format(month),
                    fmt:          f0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _PaceLegend(
                    color: currentColor,
                    label: DateFormat('MMM').format(month),
                    value: f0.format(soFar),
                    bold:  true),
                for (var i = 0; i < pace.series.length; i++)
                  if (pace.series[i].hasSpend)
                    _PaceLegend(
                      color: cs.onSurfaceVariant
                          .withValues(alpha: _PaceChartPainter.alphas[i]),
                      label: pace.series[i].label,
                      value: f0.format(pace.series[i].total),
                    ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _PaceLegend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final bool bold;
  const _PaceLegend({
    required this.color,
    required this.label,
    required this.value,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 14,
            height: 2.5,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text('$label ',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: cs.onSurfaceVariant)),
        Text(value,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
      ],
    );
  }
}

/// Cumulative spend curves on a shared day-of-month axis.
///
/// History lines are solid up to today and dotted past it: the solid part is
/// the like-for-like comparison, the dotted part is where that month went on to
/// finish. Drawing the whole line solid would invite reading a full month
/// against a part month.
class _PaceChartPainter extends CustomPainter {
  final SpendPace pace;
  final Color currentColor;
  final Color baseColor;
  final Color gridColor;
  final String monthLabel;
  final NumberFormat fmt;

  /// Recency as opacity: last month reads strongest, the 12-month average
  /// faintest. Three separate hues would be a colour puzzle for what is
  /// really one ordered idea.
  static const alphas = [0.85, 0.5, 0.3];
  static const widths = [1.7, 1.45, 1.3];

  _PaceChartPainter({
    required this.pace,
    required this.currentColor,
    required this.baseColor,
    required this.gridColor,
    required this.monthLabel,
    required this.fmt,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const topPad = 10.0, bottomPad = 20.0, rightPad = 6.0;
    final plotH = size.height - topPad - bottomPad;
    final plotW = size.width - rightPad;
    final days  = pace.daysInMonth;
    if (days < 2 || plotH <= 0) return;

    var maxV = 0.0;
    for (var i = 0; i < pace.todayDay; i++) {
      if (pace.current[i] > maxV) maxV = pace.current[i];
    }
    for (final s in pace.series) {
      if (s.total > maxV) maxV = s.total;
    }
    if (maxV <= 0) return;
    maxV *= 1.14; // headroom for the finish label

    double dx(int i) => plotW * i / (days - 1);
    double dy(double v) => topPad + plotH * (1 - v / maxV);

    // Baseline.
    canvas.drawLine(Offset(0, topPad + plotH), Offset(plotW, topPad + plotH),
        Paint()..color = gridColor..strokeWidth = 1);

    // Where last month finished — the bar to beat, readable at any x rather
    // than only at the right edge.
    final last = pace.lastMonth;
    if (last != null && last.hasSpend) {
      final y = dy(last.total);
      _dashLine(canvas, Offset(0, y), Offset(plotW, y),
          Paint()
            ..color = baseColor.withValues(alpha: 0.38)
            ..strokeWidth = 1,
          on: 2.5, off: 3.5);
      _label(canvas, '${last.label} finished ${fmt.format(last.total)}',
          Offset(plotW, y - 12), baseColor.withValues(alpha: 0.75), 9.5,
          alignRight: true);
    }

    // Today.
    final tx = dx(pace.todayDay - 1);
    if (pace.todayDay < days) {
      _dashLine(canvas, Offset(tx, topPad), Offset(tx, topPad + plotH),
          Paint()
            ..color = baseColor.withValues(alpha: 0.22)
            ..strokeWidth = 1,
          on: 3, off: 4);
    }

    // History, faintest first so last month sits on top.
    for (var i = pace.series.length - 1; i >= 0; i--) {
      final s = pace.series[i];
      if (!s.hasSpend) continue;
      final paint = Paint()
        ..color = baseColor.withValues(alpha: alphas[i])
        ..strokeWidth = widths[i]
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final solid = Path();
      for (var d = 0; d < pace.todayDay; d++) {
        final p = Offset(dx(d), dy(s.at(d)));
        d == 0 ? solid.moveTo(p.dx, p.dy) : solid.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(solid, paint);

      if (pace.todayDay < days) {
        final future = Path();
        for (var d = pace.todayDay - 1; d < days; d++) {
          final p = Offset(dx(d), dy(s.at(d)));
          d == pace.todayDay - 1
              ? future.moveTo(p.dx, p.dy)
              : future.lineTo(p.dx, p.dy);
        }
        _dashPath(canvas, future, paint);
      }
    }

    // This month, on top, solid, no projection — we do not know the rest.
    final cur = Path();
    for (var d = 0; d < pace.todayDay; d++) {
      final p = Offset(dx(d), dy(pace.current[d]));
      d == 0 ? cur.moveTo(p.dx, p.dy) : cur.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        cur,
        Paint()
          ..color = currentColor
          ..strokeWidth = 2.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    final head = Offset(tx, dy(pace.current[pace.todayDay - 1]));
    canvas.drawCircle(head, 4.2, Paint()..color = currentColor);

    // Day-of-month axis.
    final mid = (days / 2).round();
    for (final d in {1, mid, days}) {
      _label(canvas, '$d', Offset(dx(d - 1), topPad + plotH + 5),
          baseColor.withValues(alpha: 0.7), 9.5,
          center: d != 1 && d != days, alignRight: d == days);
    }
  }

  void _dashLine(Canvas c, Offset a, Offset b, Paint p,
      {double on = 4, double off = 4}) {
    _dashPath(c, Path()..moveTo(a.dx, a.dy)..lineTo(b.dx, b.dy), p,
        on: on, off: off);
  }

  void _dashPath(Canvas c, Path path, Paint p,
      {double on = 3.5, double off = 3.5}) {
    for (final m in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < m.length) {
        final next = dist + on < m.length ? dist + on : m.length;
        c.drawPath(m.extractPath(dist, next), p);
        dist = next + off;
      }
    }
  }

  void _label(Canvas c, String text, Offset at, Color color, double size,
      {bool alignRight = false, bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: GoogleFonts.plusJakartaSans(
              fontSize: size, fontWeight: FontWeight.w600, color: color)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    else if (center) dx -= tp.width / 2;
    tp.paint(c, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(_PaceChartPainter old) =>
      old.pace != pace || old.currentColor != currentColor;
}

class _CategorySplitPanel extends ConsumerWidget {
  final BudgetEntry? entry;
  final DateTime     currentMonth;
  const _CategorySplitPanel({this.entry, required this.currentMonth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    if (entry == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined,
                size: 56,
                color: cs.onSurfaceVariant.withValues(alpha: 0.25)),
            const SizedBox(height: 16),
            Text('Select a category',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.45))),
            const SizedBox(height: 4),
            Text('to see its transactions here',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.35))),
          ],
        ),
      );
    }

    final allTxns = ref.watch(transactionsProvider).valueOrNull ?? [];
    final txns    = allTxns.where((t) =>
        t.categoryId == entry!.categoryId &&
        t.date.year  == currentMonth.year  &&
        t.date.month == currentMonth.month &&
        !t.isPendingReview).toList();

    final pct    = entry!.budgeted > 0
        ? (entry!.spent / entry!.budgeted).clamp(0.0, 1.0)
        : 0.0;
    final isOver = entry!.balance < 0;
    final barColor = isOver ? cs.error : context.money.positive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Category summary ─────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.35), width: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(entry!.categoryName,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 22, fontWeight: FontWeight.w800,
                            color: cs.onSurface)),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: cs.error, size: 20),
                    tooltip: 'Delete category',
                    onPressed: () => _showDeleteCategoryDialog(context, ref, entry!),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(fmt.format(entry!.spent),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: isOver ? cs.error : cs.onSurface)),
                  Text(' spent of ${fmt.format(entry!.budgeted)}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, color: cs.onSurfaceVariant)),
                  const Spacer(),
                  Text(
                    isOver
                        ? '${fmt.format(entry!.balance.abs())} over'
                        : '${fmt.format(entry!.balance)} left',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: isOver ? cs.error : context.money.positive),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
              const SizedBox(height: 10),
              // What the numbers above actually mean for the rest of the month.
              _PanelPaceLine(entry: entry!, month: currentMonth, txnCount: txns.length),
              const SizedBox(height: 12),
              _SpendPacePanel(entry: entry!, month: currentMonth),
            ],
          ),
        ),
        // ── Month label ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(DateFormat('MMMM yyyy').format(currentMonth).toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant, letterSpacing: 0.8)),
        ),
        // ── Transaction list ─────────────────────────────────────────────────
        Expanded(
          child: txns.isEmpty
              ? Center(
                  child: Text(
                      'No transactions in ${DateFormat('MMMM').format(currentMonth)}',
                      style: GoogleFonts.plusJakartaSans(
                          color: cs.onSurfaceVariant)))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  itemCount: txns.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1, indent: 52,
                      color: cs.outlineVariant.withValues(alpha: 0.3)),
                  itemBuilder: (_, i) => _SplitTxRow(tx: txns[i]),
                ),
        ),
      ],
    );
  }
}

class _SplitTxRow extends StatelessWidget {
  final Transaction tx;
  const _SplitTxRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                (tx.account?.displayName.isNotEmpty == true
                    ? tx.account!.displayName[0]
                    : '?').toUpperCase(),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tx.displayPayee.isNotEmpty
                      ? tx.displayPayee
                      : tx.account?.displayName ?? '—',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: cs.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(DateFormat('MMM d').format(tx.date),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            '${tx.amount < 0 ? '-' : '+'}${fmt.format(tx.amount.abs())}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: tx.amount < 0 ? cs.onSurface : context.money.positive),
          ),
        ],
      ),
    );
  }
}
