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
        builder:            (_) => _CategoryDetailSheet(entry: entry, month: month, ref: ref),
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
      // FAB only on mobile — desktop uses group [+] buttons or split view
      floatingActionButton: (isThreeCol || wideEnough) ? null : FloatingActionButton.extended(
        onPressed: () => _showAddCategorySheet(context, ref),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        icon:  const Icon(Icons.add),
        label: const Text('Add Category'),
      ),
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
              IconButton(
                onPressed: () => notifier.goToMonth(nextMonth),
                icon: const Icon(Icons.chevron_right),
                style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHigh),
              ),
              const SizedBox(width: 8),
              // ── Layout toggle ────────────────────────────────────────────
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
    return Opacity(opacity: 0.52, child: inner);
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
  /// Only one group is open at a time; null = all collapsed.
  String? _expandedGroupId;

  void _toggleGroup(String id) => setState(() {
        _expandedGroupId = _expandedGroupId == id ? null : id;
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
      if (_expandedGroupId == g.id) {
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
                    valueColor: state.carryForward > 0 ? cs.tertiary : cs.error,
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
                      isExpanded: _expandedGroupId == row.group.id,
                      onTap:      () => _toggleGroup(row.group.id),
                    )
                  : _PanelEntryRow(
                      entry: row.entry!, isCurrent: widget.isCurrent);
            },
          ),
        ),
        if (widget.onAddCategory != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextButton.icon(
                onPressed: widget.onAddCategory,
                icon:  const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add Category'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
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
          _PanelColLabel('AVAIL',    bg: cs.tertiary.withValues(alpha: 0.07),
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
              bg: cs.tertiary.withValues(alpha: 0.07),
            ),
            const SizedBox(width: _kCarrySlotW),
          ],
        ),
      ),
    );
  }
}

// ── Category entry row in panel ───────────────────────────────────────────────

class _PanelEntryRow extends StatelessWidget {
  final BudgetEntry entry;
  final bool isCurrent;
  const _PanelEntryRow({required this.entry, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final isOverspent = entry.balance < 0;
    final availColor  = isOverspent ? cs.error
        : entry.balance > 0 ? cs.tertiary
        : cs.onSurfaceVariant;

    final iconCp = entry.iconCodePoint;

    return Padding(
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
          _PanelNum(entry.budgeted, cs.onSurface,
              bg: cs.primary.withValues(alpha: 0.07)),
          _PanelNum(entry.activity, cs.onSurfaceVariant),
          _PanelNum(entry.balance, availColor, bold: true,
              bg: cs.tertiary.withValues(alpha: 0.07)),
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
    if (bg == null) return cell;
    return ColoredBox(color: bg!, child: cell);
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

  /// Only one group is expanded at a time; null = all collapsed.
  String? _expandedGroupId;

  /// The category whose detail panel is currently open (accordion: at most one).
  String? _expandedCategoryId;

  /// Clears the active inline-add row.
  void _closeInline() => setState(() => _inlineGroupId = null);

  /// Toggles a group open/closed. Opening a group closes any other open group
  /// and collapses any previously expanded category row.
  void _toggleGroup(String groupId) => setState(() {
        if (_expandedGroupId == groupId) {
          _expandedGroupId = null;
          _inlineGroupId   = null;
        } else {
          _expandedGroupId    = groupId;
          _expandedCategoryId = null; // close any open category detail
          if (_inlineGroupId != groupId) _inlineGroupId = null;
        }
      });

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
        ref: ref,
      ),
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
      final isGroupExpanded = _expandedGroupId == group.id;

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
            return ReorderableDelayedDragStartListener(
              key:   ValueKey(entry.categoryId),
              index: idx,
              child: _CategoryTableRow(
                entry:       entry,
                isWide:      isWide,
                isExpanded:  widget.onCategorySelect == null &&
                             _expandedCategoryId == entry.categoryId,
                month:       state.month,
                onToggle:    () => _toggleCategory(entry.categoryId),
                onDetailTap: (e, m) => widget.onCategoryTap(e, m),
              ),
            );
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
              child: TextButton.icon(
                onPressed: () => _showAddCategorySheet(context, ref),
                icon:  const Icon(Icons.add_circle_outline, size: 16),
                label: const Text('Add Category'),
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                ),
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

class _BudgetHeader extends StatelessWidget {
  final DateTime month;
  final double tbb;
  final double income;
  final List<IncomeTxn> incomeTxns;
  final double totalBudgeted;
  final double totalSpent;
  final double carryForward;
  final VoidCallback onPrev;
  final VoidCallback onNext;
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
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final isNeg    = tbb < 0;
    final tbbColor = isNeg ? cs.error : cs.primary;
    final fmt      = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
                style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHigh),
              ),
              Text(DateFormat('MMMM yyyy').format(month),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
                style: IconButton.styleFrom(backgroundColor: cs.surfaceContainerHigh),
              ),
              // Switch to 3-col on wide screens
              if (MediaQuery.sizeOf(context).width >= _k3ColBreak)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    tooltip: 'Compare 3 months',
                    icon: const Icon(Icons.view_column_outlined, size: 18),
                    onPressed: () => ref
                        .read(budgetThreeColPrefProvider.notifier)
                        .state = true,
                    style: IconButton.styleFrom(
                      backgroundColor: cs.surfaceContainerHigh,
                      padding: const EdgeInsets.all(6),
                    ),
                  ),
                ),
            ],
          ),
          TextButton.icon(
            onPressed: () => _showQuickBudgetSheet(context, month, ref),
            icon:  Icon(Icons.auto_awesome, size: 15, color: cs.primary),
            label: Text('Quick Budget',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
          ),
          const SizedBox(height: 6),

          // ── TBB breakdown card ─────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color:        tbbColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border:       Border.all(color: tbbColor.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Breakdown lines ──────────────────────────────────────────
                if (carryForward != 0) ...[
                  _TbbLine(
                    sign:       carryForward > 0 ? '+' : '−',
                    value:      carryForward.abs(),
                    label:      'Carried from ${DateFormat('MMM').format(DateTime(month.year, month.month - 1))}',
                    valueColor: carryForward > 0 ? cs.tertiary : cs.error,
                  ),
                  const SizedBox(height: 3),
                ],
                _IncomeLine(
                  month:  month,
                  income: income,
                  txns:   incomeTxns,
                ),
                const SizedBox(height: 3),
                _TbbLine(
                  sign:  '−',
                  value: totalBudgeted,
                  label: 'Budgeted in ${DateFormat('MMM').format(month)}',
                  valueColor: cs.onSurfaceVariant,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Divider(
                    height: 1,
                    color: tbbColor.withValues(alpha: 0.25),
                  ),
                ),
                // ── TBB total line ───────────────────────────────────────────
                Row(
                  children: [
                    Text('=  ',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: tbbColor.withValues(alpha: 0.6))),
                    Icon(
                      isNeg
                          ? Icons.warning_amber_rounded
                          : Icons.savings_outlined,
                      size: 14, color: tbbColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      fmt.format(tbb),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: tbbColor),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isNeg ? 'overbudgeted' : 'ready to assign',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: tbbColor.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
                // Spending sits outside the equation: it never reaches TBB
                // (money leaves a category, not the unassigned pool), so
                // showing it above the "=" made the sum look broken.
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                _TbbLine(
                  sign:  '',
                  value: totalSpent,
                  label: 'Spent in ${DateFormat('MMM').format(month)}',
                  valueColor: cs.error.withValues(alpha: 0.8),
                ),
              ],
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
                    color: cs.tertiary.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Text(
                _fmt.format(widget.income),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.tertiary,
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
                      color: cs.tertiary.withValues(alpha: 0.7),
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
                          color: cs.tertiary,
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
      fill = cs.error;
    } else if (pct >= 0.8) {
      fill = const Color(0xFFF57F17); // amber 800
    } else {
      fill = const Color(0xFF2E7D32); // green 800
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
          const Expanded(child: SizedBox()),
          _ColLabel(isWide ? 'BUDGETED' : 'BUDGET',
              bg: cs.primary.withValues(alpha: 0.07),
              total: totalBudgeted, cs: cs),
          if (isWide) _ColLabel('ACTIVITY', total: totalActivity, cs: cs),
          _ColLabel(isWide ? 'AVAILABLE' : 'AVAIL',
              bg: cs.tertiary.withValues(alpha: 0.07),
              total: totalAvailable, cs: cs),
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
            // Numeric columns
            _NumCell(groupBudgeted, cs.onSurfaceVariant, bold: true,
                bg: cs.primary.withValues(alpha: 0.07)),
            if (isWide) _NumCell(groupActivity, cs.onSurfaceVariant, bold: true),
            _NumCell(
              groupAvailable,
              groupAvailable < 0 ? cs.error : cs.onSurfaceVariant,
              bold: true,
              bg: cs.tertiary.withValues(alpha: 0.07),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category table row
// ---------------------------------------------------------------------------

class _CategoryTableRow extends ConsumerWidget {
  final BudgetEntry entry;
  final bool isWide;
  final bool isExpanded;
  final DateTime month;
  final VoidCallback onToggle;
  final void Function(BudgetEntry, DateTime) onDetailTap;

  const _CategoryTableRow({
    required this.entry,
    required this.isWide,
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
        : entry.balance > 0         ? cs.tertiary
        :                             cs.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Main row ──────────────────────────────────────────
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
            child: Row(
              children: [
                // Drag handle — long-press anywhere on the row to reorder
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.drag_handle,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.28),
                  ),
                ),
                if (entry.isCcPayment)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.credit_card, size: 13, color: cs.primary),
                  ),
                if (entry.goal != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Icon(Icons.flag_outlined, size: 12, color: cs.tertiary),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.categoryName,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      if (entry.showsBudgetProgress)
                        _BatteryBar(
                          budgeted: entry.budgeted,
                          spent:    entry.spent,
                        ),
                    ],
                  ),
                ),
                if (isWide) ...[
                  // Tapping the budgeted cell edits it inline.
                  ColoredBox(
                    color: cs.primary.withValues(alpha: 0.07),
                    child: _InlineBudgetAmount(entry: entry),
                  ),
                  _NumCell(entry.activity, cs.onSurfaceVariant),
                ] else
                  _NumCell(entry.budgeted, cs.onSurface,
                      bg: cs.primary.withValues(alpha: 0.07)),
                _NumCell(entry.balance, availColor, bold: true,
                    bg: cs.tertiary.withValues(alpha: 0.07)),
                if (isOverspent && !entry.isCcPayment)
                  _CarryOverspendArrow(entry: entry)
                else
                  const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                ),
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

  const _InlineBudgetAmount({required this.entry, this.compact = true});

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
        .setBudgeted(widget.entry.categoryId, amount);
    if (mounted) setState(() => _editing = false);
  }

  // ── Compact mode (row cell) ────────────────────────────────────────────────

  Widget _buildCompact(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    if (_editing) {
      return SizedBox(
        width: _kColW,
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

    return GestureDetector(
      onTap: _startEdit,
      child: Tooltip(
        message: 'Tap to edit budgeted amount',
        child: SizedBox(
          width: _kColW,
          child: Text(
            fmt.format(widget.entry.budgeted),
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

    return Container(
      color: cs.surfaceContainerHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                else
                  ...txs.map((tx) => _CategoryTxRow(tx: tx)),
                // ── Insight card (Path C) ──────────────────────────────────
                _PatternInsightCard(entry: entry, txs: txs),
              ],
            ),
          ),
          // ── Action buttons ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                _PanelAction(
                  icon: Icons.drive_file_rename_outline,
                  label: 'Rename',
                  onTap: () => _showRenameCategoryDialog(context, ref, entry),
                ),
                const SizedBox(width: 4),
                _PanelAction(
                  icon: entry.iconCodePoint != null
                      ? Icons.emoji_emotions_outlined
                      : Icons.add_reaction_outlined,
                  label: 'Icon',
                  onTap: () => _showCategoryIconPicker(context, ref, entry),
                ),
                const SizedBox(width: 4),
                _PanelAction(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  onTap: () => _showDeleteCategoryDialog(context, ref, entry),
                  isDestructive: true,
                ),
                const Spacer(),
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
              color: isIncome ? cs.tertiary : cs.onSurface,
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
  final Color? bg;

  const _NumCell(this.value, this.color, {this.bold = false, this.bg});

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
    if (bg == null) return cell;
    return ColoredBox(color: bg!, child: cell);
  }
}

// ---------------------------------------------------------------------------
// Category detail sheet
// ---------------------------------------------------------------------------

class _CategoryDetailSheet extends StatefulWidget {
  final BudgetEntry entry;
  final DateTime month;
  final WidgetRef ref;
  const _CategoryDetailSheet({required this.entry, required this.month, required this.ref});

  @override
  State<_CategoryDetailSheet> createState() => _CategoryDetailSheetState();
}

class _CategoryDetailSheetState extends State<_CategoryDetailSheet> {
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
      await widget.ref.read(budgetProvider.notifier)
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
    await widget.ref.read(budgetProvider.notifier)
        .setCarryOverspend(widget.entry.categoryId, v);
  }

  @override
  Widget build(BuildContext context) {
    final cs          = Theme.of(context).colorScheme;
    final fmt         = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final isOverspent = widget.entry.balance < 0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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

            Text(widget.entry.categoryName,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 24),

            // Stats row
            Row(
              children: [
                _StatCell(label: 'Budgeted', value: fmt.format(widget.entry.budgeted),       color: cs.primary),
                // A CC envelope is filled by card spending rather than drained
                // by it, so "Spent" would always read $0 here.
                widget.entry.isCcPayment
                    ? _StatCell(label: 'Reserved', value: fmt.format(widget.entry.reserved), color: cs.onSurface)
                    : _StatCell(label: 'Spent',    value: fmt.format(widget.entry.spent),    color: cs.onSurface),
                _StatCell(
                  label: isOverspent ? 'Overspent' : 'Remaining',
                  value: fmt.format(widget.entry.balance.abs()),
                  color: isOverspent ? cs.error : cs.tertiary,
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (widget.entry.showsBudgetProgress) ...[
              SizedBox(
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (widget.entry.spent / widget.entry.budgeted).clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(isOverspent ? cs.error : cs.primary),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // CC payment link section — shown for CC payment envelopes
            if (widget.entry.isCcPayment) ...[
              _CcAccountLinkTile(entry: widget.entry, ref: widget.ref),
              const SizedBox(height: 16),
            ],

            // Budget amount input (extra amount beyond auto-reserved, e.g. to pay off old debt)
            TextField(
              controller: _budgetCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              onSubmitted: (_) => _saveBudget(),
              decoration: InputDecoration(
                labelText: widget.entry.isCcPayment
                    ? 'Extra budget (e.g. to pay down old debt)'
                    : 'Budget amount',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _saveBudget,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
            const SizedBox(height: 16),

            // Goal section
            if (widget.entry.goal != null)
              _GoalDetailCard(
                goal:   widget.entry.goal!,
                entry:  widget.entry,
                month:  widget.month,
                onEdit: () => _showSetGoalSheet(
                    context, widget.entry, widget.month, widget.ref),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _showSetGoalSheet(
                    context, widget.entry, widget.month, widget.ref),
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

            // Carry overspend toggle
            if (!widget.entry.isCcPayment)
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
    final trackColor = onTrack ? cs.tertiary : cs.error;
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
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
                Icon(Icons.flag_outlined, size: 20, color: cs.tertiary),
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
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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

void _showDeleteCategoryDialog(
    BuildContext context, WidgetRef ref, BudgetEntry entry) {
  showDialog(
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () async {
            await ref
                .read(budgetProvider.notifier)
                .deleteCategory(entry.categoryId);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Delete'),
        ),
      ],
    ),
  );
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
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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

  void _onSelect(BudgetEntry? entry) => setState(() {
    // Tap same category again → deselect
    _selected = _selected?.categoryId == entry?.categoryId ? null : entry;
  });

  void _onDetailTap(BudgetEntry entry, DateTime month) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _CategoryDetailSheet(entry: entry, month: month, ref: ref),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        // Left: budget panel (fixed 520px so the list reads comfortably)
        SizedBox(
          width: 520,
          child: _BudgetBody(
            state:            widget.state,
            onCategoryTap:    _onDetailTap,
            onCategorySelect: _onSelect,
          ),
        ),
        VerticalDivider(
            width: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
        // Right: transaction detail panel
        Expanded(
          child: _CategorySplitPanel(
            entry:        _selected,
            currentMonth: widget.state.month,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Right-side panel — transactions for the selected category
// ---------------------------------------------------------------------------

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
    final barColor = isOver ? cs.error : cs.tertiary;

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
                        color: isOver ? cs.error : cs.tertiary),
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
                color: tx.amount < 0 ? cs.onSurface : cs.tertiary),
          ),
        ],
      ),
    );
  }
}
