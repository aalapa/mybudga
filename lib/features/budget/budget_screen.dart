import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../shared/models/budget_entry.dart';
import 'budget_provider.dart';

// ---------------------------------------------------------------------------

const _kColW = 82.0; // fixed width per numeric column

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
        data: (state) => _BudgetBody(
          state:         state,
          ref:           ref,
          onCategoryTap: onCategoryTap,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddCategorySheet(context, ref),
        icon:  const Icon(Icons.add),
        label: Text('Add Category',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Flat-list body — no collapse, inline numbers
// ---------------------------------------------------------------------------

sealed class _BudgetRow {}

class _GroupRow extends _BudgetRow {
  final BudgetGroupData group;
  _GroupRow(this.group);
}

class _EntryRow extends _BudgetRow {
  final BudgetEntry entry;
  _EntryRow(this.entry);
}

class _BudgetBody extends StatelessWidget {
  final BudgetState state;
  final WidgetRef ref;
  final void Function(BudgetEntry, DateTime) onCategoryTap;

  const _BudgetBody({required this.state, required this.ref, required this.onCategoryTap});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    final header = SliverToBoxAdapter(
      child: _BudgetHeader(
        month:  state.month,
        tbb:    state.tbb,
        onPrev: () => ref.read(budgetProvider.notifier)
            .goToMonth(DateTime(state.month.year, state.month.month - 1)),
        onNext: () => ref.read(budgetProvider.notifier)
            .goToMonth(DateTime(state.month.year, state.month.month + 1)),
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

    // Flatten groups → entries into a single linear list
    final rows = <_BudgetRow>[];
    for (final group in state.groups) {
      rows.add(_GroupRow(group));
      for (final entry in group.entries) {
        rows.add(_EntryRow(entry));
      }
    }

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          header,
          if (isWide)
            SliverToBoxAdapter(child: _ColumnHeaders()),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 100),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) => switch (rows[i]) {
                _GroupRow(:final group) => _GroupHeaderRow(
                    group:  group,
                    isWide: isWide,
                    ref:    ref,
                  ),
                _EntryRow(:final entry) => _CategoryTableRow(
                    entry:  entry,
                    isWide: isWide,
                    onTap:  () => onCategoryTap(entry, state.month),
                  ),
              },
            ),
          ),
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
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final WidgetRef ref;

  const _BudgetHeader({
    required this.month,
    required this.tbb,
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
            ],
          ),
          TextButton.icon(
            onPressed: () => _showQuickBudgetSheet(context, month, ref),
            icon:  Icon(Icons.auto_awesome, size: 15, color: cs.primary),
            label: Text('Quick Budget',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color:        tbbColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(32),
              border:       Border.all(color: tbbColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isNeg ? Icons.warning_amber_rounded : Icons.savings_outlined,
                  size: 16, color: tbbColor,
                ),
                const SizedBox(width: 6),
                Text('${fmt.format(tbb)} to assign',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w700, color: tbbColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Column headers (wide screens only)
// ---------------------------------------------------------------------------

class _ColumnHeaders extends StatelessWidget {
  const _ColumnHeaders();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 6, 16, 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          const Expanded(child: SizedBox()),
          _ColLabel('BUDGETED'),
          _ColLabel('ACTIVITY'),
          _ColLabel('AVAILABLE'),
        ],
      ),
    );
  }
}

class _ColLabel extends StatelessWidget {
  final String text;
  const _ColLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kColW,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group header row
// ---------------------------------------------------------------------------

class _GroupHeaderRow extends StatelessWidget {
  final BudgetGroupData group;
  final bool isWide;
  final WidgetRef ref;

  const _GroupHeaderRow({
    required this.group,
    required this.isWide,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final cs             = Theme.of(context).colorScheme;
    final groupBudgeted  = group.entries.fold(0.0, (s, e) => s + e.budgeted);
    final groupActivity  = group.entries.fold(0.0, (s, e) => s + e.activity);
    final groupAvailable = group.balance;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Row(
        children: [
          // Group name + [+] button
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
                const SizedBox(width: 6),
                InkWell(
                  onTap: () =>
                      _showAddCategorySheet(context, ref, initialGroupId: group.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(Icons.add, size: 13, color: cs.onSurfaceVariant),
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
          if (isWide) ...[
            _NumCell(groupBudgeted, cs.onSurfaceVariant, bold: true),
            _NumCell(groupActivity, cs.onSurfaceVariant, bold: true),
          ],
          _NumCell(
            groupAvailable,
            groupAvailable < 0 ? cs.error : cs.onSurfaceVariant,
            bold: true,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category table row
// ---------------------------------------------------------------------------

class _CategoryTableRow extends StatelessWidget {
  final BudgetEntry entry;
  final bool isWide;
  final VoidCallback onTap;

  const _CategoryTableRow({
    required this.entry,
    required this.isWide,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs          = Theme.of(context).colorScheme;
    final isOverspent = entry.balance < 0;
    final isFullyUsed = entry.balance == 0 && entry.spent > 0;
    final availColor  = isOverspent ? cs.error
        : isFullyUsed               ? cs.onSurfaceVariant
        : entry.balance > 0         ? cs.tertiary
        :                             cs.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
            child: Row(
              children: [
                // Leading icons
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
                // Category name
                Expanded(
                  child: Text(
                    entry.categoryName,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                // Budgeted + Activity (wide only)
                if (isWide) ...[
                  _NumCell(entry.budgeted, cs.onSurface),
                  _NumCell(entry.activity, cs.onSurfaceVariant),
                ],
                // Available
                _NumCell(entry.balance, availColor, bold: true),
              ],
            ),
          ),
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

    return SizedBox(
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
                _StatCell(label: 'Spent',    value: fmt.format(widget.entry.spent),           color: cs.onSurface),
                _StatCell(
                  label: isOverspent ? 'Overspent' : 'Remaining',
                  value: fmt.format(widget.entry.balance.abs()),
                  color: isOverspent ? cs.error : cs.tertiary,
                ),
              ],
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: widget.entry.budgeted > 0
                      ? (widget.entry.spent / widget.entry.budgeted).clamp(0.0, 1.0)
                      : 0.0,
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(isOverspent ? cs.error : cs.primary),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Budget amount input
            TextField(
              controller: _budgetCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

enum _QuickBudgetStrategy { lastMonth, averageSpending, coverSpending }
enum _QuickBudgetScope    { thisMonth, next3, next6, next12 }

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

  String get _strategyLabel => switch (_strategy) {
    _QuickBudgetStrategy.lastMonth       => "Last month's budgeted amounts",
    _QuickBudgetStrategy.averageSpending => 'Average spending (last 3 months)',
    _QuickBudgetStrategy.coverSpending   => "Cover this month's spending",
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
                (_QuickBudgetStrategy.lastMonth,       'Last Month',   Icons.history),
                (_QuickBudgetStrategy.averageSpending, '3-Mo Average', Icons.show_chart),
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
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: Text(_applyLabel,
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
        name:    _nameCtrl.text.trim(),
        groupId: groupId,
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

            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Category name'),
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
