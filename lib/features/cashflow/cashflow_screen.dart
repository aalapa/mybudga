import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../shared/models/scheduled_transaction.dart';
import '../../shared/models/account.dart';
import '../../shared/providers/categories_provider.dart';
import '../accounts/accounts_provider.dart';
import 'cashflow_provider.dart';

// ---------------------------------------------------------------------------

class CashflowScreen extends ConsumerStatefulWidget {
  const CashflowScreen({super.key});

  @override
  ConsumerState<CashflowScreen> createState() => _CashflowScreenState();
}

class _CashflowScreenState extends ConsumerState<CashflowScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final state = ref.watch(cashflowProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (s) => _CashflowBody(state: s, days: _days, onDaysChanged: (d) => setState(() => _days = d), ref: ref),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddScheduledSheet(context, ref, prefill: null),
        backgroundColor: cs.primary,
        child: Icon(Icons.add, color: cs.onPrimary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _CashflowBody extends StatelessWidget {
  final CashflowState state;
  final int days;
  final ValueChanged<int> onDaysChanged;
  final WidgetRef ref;

  const _CashflowBody({
    required this.state,
    required this.days,
    required this.onDaysChanged,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final today   = DateTime.now();

    // Build projected entries
    final dayRows = _buildDayRows(state, today, days);

    final isDoomsday = days == _CashflowBody._ddSentinel;

    // Peak balance across the projection — used as the 100% reference for bars
    double maxBalance = state.startingBalance;
    for (final d in dayRows) {
      if (d.endBalance > maxBalance) maxBalance = d.endBalance;
    }

    final lowest = dayRows.isEmpty
        ? state.startingBalance
        : dayRows.map((d) => d.endBalance).reduce((a, b) => a < b ? a : b);
    final isDanger = lowest < 500;

    // DD mode: find how many days until balance goes negative
    final negIdx = isDoomsday
        ? dayRows.indexWhere((d) => d.endBalance < 0)
        : -1;
    final runwayLabel = negIdx >= 0
        ? 'Day $negIdx · ${DateFormat('MMM d').format(dayRows[negIdx].date)}'
        : '365+ days safe';

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                // Title row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cashflow',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface,
                            ),
                          ),
                          Text(
                            'Checking & savings accounts',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Balance cards
                Row(
                  children: [
                    _BalanceCard(
                      label: 'Today',
                      value: fmt.format(state.startingBalance),
                      color: cs.primary,
                      icon: Icons.account_balance_outlined,
                    ),
                    const SizedBox(width: 10),
                    isDoomsday
                        ? _BalanceCard(
                            label: 'Goes negative',
                            value: runwayLabel,
                            color: negIdx >= 0 ? cs.error : cs.tertiary,
                            icon:  negIdx >= 0
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            isWarning: negIdx >= 0,
                          )
                        : _BalanceCard(
                            label: 'Lowest in ${days}d',
                            value: fmt.format(lowest),
                            color: isDanger ? cs.error : cs.tertiary,
                            icon:  isDanger
                                ? Icons.warning_amber_rounded
                                : Icons.trending_down,
                            isWarning: isDanger,
                          ),
                  ],
                ),
                const SizedBox(height: 14),

                // Day range toggle
                Row(
                  children: [
                    (30,  '30d'),
                    (60,  '60d'),
                    (90,  '90d'),
                    (_CashflowBody._ddSentinel, 'DD'),
                  ].map(((int, String) opt) {
                    final (value, label) = opt;
                    final selected  = days == value;
                    final isDdChip  = value == _CashflowBody._ddSentinel;
                    final chipColor = isDdChip && selected ? cs.error : cs.primary;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => onDaysChanged(value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? (isDdChip
                                    ? cs.errorContainer
                                    : cs.primaryContainer)
                                : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                            border: selected
                                ? Border.all(color: chipColor.withValues(alpha: 0.4))
                                : null,
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected
                                  ? (isDdChip
                                      ? cs.onErrorContainer
                                      : cs.onPrimaryContainer)
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // Timeline
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              itemCount: dayRows.length,
              itemBuilder: (context, i) {
                final day = dayRows[i];
                return day.hasEvents
                    ? _EventDayRow(day: day, ref: ref, maxBalance: maxBalance)
                    : _EmptyDayRow(day: day, maxBalance: maxBalance);
              },
            ),
          ),
        ],
      ),
    );
  }

  // days == -1 signals "Doomsday" mode: project up to 365 days,
  // stop at the first day the balance goes negative.
  static const int _ddSentinel = -1;

  static List<_DayData> _buildDayRows(
    CashflowState state,
    DateTime today,
    int days,
  ) {
    final isDoomsday = days == _ddSentinel;
    final maxDays    = isDoomsday ? 365 : days;

    // Only scheduled transactions from liquid accounts affect cash
    final cashScheduled =
        state.scheduled.where((st) => st.isCashAccount).toList();

    final cutoff = today.add(Duration(days: maxDays));
    final entries = <_ProjectedEntry>[];

    for (final st in cashScheduled) {
      for (final date in st.occurrencesUntil(today, cutoff)) {
        entries.add(_ProjectedEntry(
          scheduledTx: st,
          date:        date,
          payee:       st.payeeName ?? st.memo ?? 'Scheduled',
          accountName: st.accountName,
          amount:      st.amount,
          isIncome:    st.amount > 0,
          category:    st.categoryName,
        ));
      }
    }

    entries.sort((a, b) => a.date.compareTo(b.date));

    double running = state.startingBalance;
    for (final e in entries) {
      running += e.amount;
      e.runningBalance = running;
    }

    final todayNorm = DateTime(today.year, today.month, today.day);
    double dayBalance = state.startingBalance;

    final allRows = List.generate(maxDays, (i) {
      final day      = todayNorm.add(Duration(days: i));
      final dayEvts  = entries.where((e) => _sameDay(e.date, day)).toList();
      if (dayEvts.isNotEmpty) dayBalance = dayEvts.last.runningBalance;
      return _DayData(date: day, events: dayEvts, endBalance: dayBalance);
    });

    if (isDoomsday) {
      // Trim to include up to (and including) the first negative-balance day
      final negIdx = allRows.indexWhere((d) => d.endBalance < 0);
      return negIdx >= 0 ? allRows.sublist(0, negIdx + 1) : allRows;
    }

    return allRows;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ---------------------------------------------------------------------------
// Balance card
// ---------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isWarning;

  const _BalanceCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: isWarning ? Border.all(color: color.withValues(alpha: 0.4)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w800, color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cashflow tile
// ---------------------------------------------------------------------------

class _CashflowTile extends StatelessWidget {
  final _ProjectedEntry entry;
  final bool isDanger;
  final WidgetRef ref;

  const _CashflowTile({
    required this.entry,
    required this.isDanger,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final fmt          = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final amountColor  = entry.isIncome ? cs.tertiary : cs.onSurface;
    final balanceColor = isDanger ? cs.error : cs.onSurfaceVariant;

    return InkWell(
      onTap: () => _showAddScheduledSheet(context, ref, prefill: entry.scheduledTx),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: isDanger ? Border.all(color: cs.error.withValues(alpha: 0.3)) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (entry.isIncome ? cs.tertiary : cs.primary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  entry.isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  size: 17,
                  color: entry.isIncome ? cs.tertiary : cs.primary,
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.payee,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface,
                      ),
                    ),
                    Text(
                      entry.category != null
                          ? '${entry.accountName} · ${entry.category}'
                          : entry.accountName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    entry.isIncome
                        ? '+${fmt.format(entry.amount)}'
                        : fmt.format(entry.amount),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700, color: amountColor,
                    ),
                  ),
                  Row(
                    children: [
                      if (isDanger)
                        Padding(
                          padding: const EdgeInsets.only(right: 3),
                          child: Icon(Icons.warning_amber_rounded, size: 11, color: cs.error),
                        ),
                      Text(
                        fmt.format(entry.runningBalance),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, fontWeight: FontWeight.w600, color: balanceColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Day data model
// ---------------------------------------------------------------------------

class _DayData {
  final DateTime date;
  final List<_ProjectedEntry> events;
  final double endBalance;
  const _DayData({required this.date, required this.events, required this.endBalance});
  bool get hasEvents => events.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Day row — no events
// ---------------------------------------------------------------------------

class _EmptyDayRow extends StatelessWidget {
  final _DayData day;
  final double maxBalance;
  const _EmptyDayRow({required this.day, required this.maxBalance});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final isToday = _sameDay(day.date, DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              isToday ? 'Today' : DateFormat('MMM d').format(day.date),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                color: isToday
                    ? cs.primary
                    : cs.onSurfaceVariant.withValues(alpha: 0.55),
              ),
            ),
          ),
          // ── Balance bar fills the dead space ──────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _BalanceBar(
                balance:    day.endBalance,
                maxBalance: maxBalance,
                height:     5,
              ),
            ),
          ),
          Text(
            fmt.format(day.endBalance),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: day.endBalance < 500
                  ? cs.error.withValues(alpha: 0.7)
                  : cs.onSurfaceVariant.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ---------------------------------------------------------------------------
// Day row — has events
// ---------------------------------------------------------------------------

class _EventDayRow extends StatelessWidget {
  final _DayData day;
  final WidgetRef ref;
  final double maxBalance;
  const _EventDayRow({required this.day, required this.ref, required this.maxBalance});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final now = DateTime.now();
    final isToday = _sameDay(day.date, now);
    final isTomorrow = _sameDay(day.date, now.add(const Duration(days: 1)));

    final label = isToday
        ? 'Today · ${DateFormat('MMM d').format(day.date)}'
        : isTomorrow
            ? 'Tomorrow · ${DateFormat('MMM d').format(day.date)}'
            : DateFormat('EEE · MMM d').format(day.date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isToday ? cs.primary : cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...day.events.map((e) => _CashflowTile(
              entry:    e,
              isDanger: e.runningBalance < 500,
              ref:      ref,
            )),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
          child: Row(
            children: [
              Text(
                'Balance',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                ),
              ),
              // ── Bar between label and amount ─────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: _BalanceBar(
                    balance:    day.endBalance,
                    maxBalance: maxBalance,
                    height:     4,
                  ),
                ),
              ),
              Text(
                fmt.format(day.endBalance),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: day.endBalance < 500 ? cs.error : cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ---------------------------------------------------------------------------
// Balance bar — fills the space between date label and balance number
// ---------------------------------------------------------------------------

class _BalanceBar extends StatelessWidget {
  final double balance;
  final double maxBalance; // peak balance in the projection — sets the 100% mark
  final double height;

  const _BalanceBar({
    required this.balance,
    required this.maxBalance,
    this.height = 5,
  });

  Color _fillColor(ColorScheme cs) {
    if (balance <= 0) return cs.error;
    if (maxBalance <= 0) return cs.tertiary;
    // Amber when below 25 % of the peak balance in the period
    if (balance / maxBalance < 0.25) return const Color(0xFFFFB300);
    return cs.tertiary; // green
  }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final fraction = maxBalance > 0
        ? (balance / maxBalance).clamp(0.0, 1.0)
        : 0.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: [
          // Track
          Container(
            height: height,
            color: cs.surfaceContainerHigh,
          ),
          // Fill
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: _fillColor(cs),
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Projected entry (display model)
// ---------------------------------------------------------------------------

class _ProjectedEntry {
  final ScheduledTransaction scheduledTx;
  final DateTime date;
  final String payee;
  final String accountName;
  final double amount;
  final bool isIncome;
  final String? category;
  double runningBalance = 0;

  _ProjectedEntry({
    required this.scheduledTx,
    required this.date,
    required this.payee,
    required this.accountName,
    required this.amount,
    required this.isIncome,
    this.category,
  });
}

// ---------------------------------------------------------------------------
// Add scheduled transaction sheet
// ---------------------------------------------------------------------------

void _showAddScheduledSheet(
  BuildContext context,
  WidgetRef ref, {
  ScheduledTransaction? prefill,
}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _AddScheduledSheet(prefill: prefill, widgetRef: ref),
  );
}

class _AddScheduledSheet extends ConsumerStatefulWidget {
  final ScheduledTransaction? prefill;
  final WidgetRef widgetRef;
  const _AddScheduledSheet({this.prefill, required this.widgetRef});

  @override
  ConsumerState<_AddScheduledSheet> createState() => _AddScheduledSheetState();
}

class _AddScheduledSheetState extends ConsumerState<_AddScheduledSheet> {
  final _formKey       = GlobalKey<FormState>();
  final _payeeCtrl     = TextEditingController();
  final _amountCtrl    = TextEditingController();
  final _memoCtrl      = TextEditingController();

  bool   _isIncome       = false;
  bool   _incomeNextMonth = false;
  String? _accountId;
  String? _categoryId;
  String? _categoryName;
  ScheduledFrequency _frequency = ScheduledFrequency.monthly;
  DateTime _nextDate  = DateTime.now();
  bool _saving        = false;

  bool get _isEditing => widget.prefill != null;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null) {
      _amountCtrl.text = p.amount.abs().toStringAsFixed(2);
      _payeeCtrl.text  = p.payeeName ?? '';
      _memoCtrl.text   = p.memo ?? '';
      _accountId       = p.accountId;
      _categoryId      = p.categoryId;
      _categoryName    = p.categoryName;
      _frequency       = p.frequency;
      _nextDate        = p.nextDate;
      _isIncome        = p.isIncome;
      // Detect if existing income is set to next month
      final now = DateTime.now();
      if (p.isIncome &&
          (p.nextDate.year > now.year ||
              (p.nextDate.year == now.year && p.nextDate.month > now.month))) {
        _incomeNextMonth = true;
      }
    }
  }

  @override
  void dispose() {
    _payeeCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final cs = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete scheduled transaction?'),
        content: const Text('This will remove all future occurrences.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await ref.read(cashflowProvider.notifier).deleteScheduled(widget.prefill!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final budgetAccounts = accounts
        .where((a) => !a.isTracking && a.type != AccountType.investment && a.type != AccountType.loan)
        .toList();

    if (_accountId == null && budgetAccounts.isNotEmpty) {
      _accountId = budgetAccounts.first.id;
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    _isEditing ? 'Edit Scheduled' : 'Add Scheduled Transaction',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (_isEditing)
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: cs.error),
                      onPressed: _delete,
                      tooltip: 'Delete',
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(
                  20, 8, 20,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Income / Expense toggle
                      Row(
                        children: [
                          _TypeChip(
                            label: 'Expense',
                            selected: !_isIncome,
                            onTap: () => setState(() {
                              _isIncome = false;
                              _incomeNextMonth = false;
                            }),
                          ),
                          const SizedBox(width: 8),
                          _TypeChip(
                            label: 'Income',
                            selected: _isIncome,
                            onTap: () => setState(() => _isIncome = true),
                          ),
                        ],
                      ),

                      // Income availability — only shown when Income is selected
                      if (_isIncome) ...[
                        const SizedBox(height: 12),
                        Center(
                          child: SegmentedButton<bool>(
                            style: SegmentedButton.styleFrom(
                              textStyle: GoogleFonts.plusJakartaSans(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                              visualDensity: VisualDensity.compact,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: false,
                                icon: Icon(Icons.calendar_today, size: 13),
                                label: Text('This month'),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: Icon(Icons.calendar_month, size: 13),
                                label: Text('Next month'),
                              ),
                            ],
                            selected: {_incomeNextMonth},
                            onSelectionChanged: (s) {
                              final next = s.first;
                              final now  = DateTime.now();
                              setState(() {
                                _incomeNextMonth = next;
                                if (next) {
                                  // Shift nextDate to the same day in next month
                                  // (clamped to 28 so Feb never overflows).
                                  final day = _nextDate.day.clamp(1, 28);
                                  _nextDate = DateTime(now.year, now.month + 1, day);
                                }
                              });
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Amount
                      TextFormField(
                        controller:  _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixText: '\$ ',
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) return 'Invalid number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Payee
                      TextFormField(
                        controller: _payeeCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Payee'),
                      ),
                      const SizedBox(height: 14),

                      // Account picker
                      DropdownButtonFormField<String>(
                        initialValue: _accountId,
                        decoration: const InputDecoration(labelText: 'Account'),
                        dropdownColor: cs.surfaceContainerHighest,
                        items: budgetAccounts.map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.displayName,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                        )).toList(),
                        onChanged: (v) => setState(() => _accountId = v),
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),

                      // Category picker
                      GestureDetector(
                        onTap: () => _pickCategory(context),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Category (optional)'),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _categoryName ?? 'No category',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: _categoryName != null
                                        ? cs.onSurface
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right, size: 18, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Frequency
                      DropdownButtonFormField<ScheduledFrequency>(
                        initialValue: _frequency,
                        decoration: const InputDecoration(labelText: 'Frequency'),
                        dropdownColor: cs.surfaceContainerHighest,
                        items: ScheduledFrequency.values.map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(f.label,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                        )).toList(),
                        onChanged: (v) { if (v != null) setState(() => _frequency = v); },
                      ),
                      const SizedBox(height: 14),

                      // Next date
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context:     context,
                            initialDate: _nextDate,
                            firstDate:   DateTime.now().subtract(const Duration(days: 365)),
                            lastDate:    DateTime.now().add(const Duration(days: 365 * 5)),
                          );
                          if (picked != null) setState(() => _nextDate = picked);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Next date'),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat('MMM d, yyyy').format(_nextDate),
                                  style: GoogleFonts.plusJakartaSans(fontSize: 14, color: cs.onSurface),
                                ),
                              ),
                              Icon(Icons.calendar_today_outlined, size: 16, color: cs.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Memo
                      TextFormField(
                        controller: _memoCtrl,
                        decoration: const InputDecoration(labelText: 'Memo (optional)'),
                      ),
                      const SizedBox(height: 28),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  height: 18, width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(
                                  'Save',
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCategory(BuildContext context) async {
    final cs     = Theme.of(context).colorScheme;
    final groups = ref.read(categoriesProvider).valueOrNull ?? [];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize:     0.4,
        maxChildSize:     0.9,
        builder: (ctx, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Select Category',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    ListTile(
                      title: Text('No category',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                      onTap: () {
                        setState(() { _categoryId = null; _categoryName = null; });
                        Navigator.pop(ctx);
                      },
                    ),
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          g.name.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10, fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant, letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      for (final cat in g.categories)
                        ListTile(
                          dense: true,
                          title: Text(cat.name,
                              style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                          trailing: _categoryId == cat.id
                              ? Icon(Icons.check, color: cs.primary, size: 18)
                              : null,
                          onTap: () {
                            setState(() {
                              _categoryId   = cat.id;
                              _categoryName = cat.name;
                            });
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) return;

    setState(() => _saving = true);
    try {
      final raw    = double.parse(_amountCtrl.text.trim());
      final amount = _isIncome ? raw.abs() : -raw.abs();
      final memo   = _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim();

      if (_isEditing) {
        await ref.read(cashflowProvider.notifier).updateScheduled(
          widget.prefill!.id,
          accountId:  _accountId!,
          amount:     amount,
          frequency:  _frequency,
          nextDate:   _nextDate,
          payeeName:  _payeeCtrl.text.trim(),
          categoryId: _categoryId,
          memo:       memo,
        );
      } else {
        await ref.read(cashflowProvider.notifier).addScheduled(
          accountId:  _accountId!,
          amount:     amount,
          frequency:  _frequency,
          nextDate:   _nextDate,
          payeeName:  _payeeCtrl.text.trim(),
          categoryId: _categoryId,
          memo:       memo,
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Type chip
// ---------------------------------------------------------------------------

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: selected ? Border.all(color: cs.primary.withValues(alpha: 0.5)) : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
