import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../shared/models/scheduled_transaction.dart';
import '../../shared/models/account.dart';
import '../../shared/providers/categories_provider.dart';
import '../accounts/accounts_provider.dart';
import '../emi/emi_screen.dart' show EmiSection, showSetupEmiSheet;
import '../insights/notification_service.dart';
import 'bill_reminders_provider.dart';
import 'cashflow_provider.dart';

// ---------------------------------------------------------------------------

class CashflowScreen extends ConsumerStatefulWidget {
  const CashflowScreen({super.key});

  @override
  ConsumerState<CashflowScreen> createState() => _CashflowScreenState();
}

class _CashflowScreenState extends ConsumerState<CashflowScreen> {
  int  _days    = 30;
  bool _compact = true;

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final state = ref.watch(cashflowProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text('Error: $e')),
        data:    (s) => _CashflowBody(
          state:            s,
          days:             _days,
          compact:          _compact,
          onDaysChanged:    (d) => setState(() => _days = d),
          onCompactChanged: (c) => setState(() => _compact = c),
          ref:              ref,
        ),
      ),
      floatingActionButton: MediaQuery.sizeOf(context).width >= 800
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddOptions(context, ref),
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
  final bool compact;
  final ValueChanged<int> onDaysChanged;
  final ValueChanged<bool> onCompactChanged;
  final WidgetRef ref;

  const _CashflowBody({
    required this.state,
    required this.days,
    required this.compact,
    required this.onDaysChanged,
    required this.onCompactChanged,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final fmt      = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final today    = DateTime.now();
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];

    // Build projected entries
    final dayRows = _buildDayRows(state, today, days, accounts);

    // Overdue: scheduled items whose next_date has already passed
    final todayNorm = DateTime(today.year, today.month, today.day);
    final overdue = state.scheduled
        .where((st) => st.nextDate.isBefore(todayNorm))
        .toList()
        ..sort((a, b) => a.nextDate.compareTo(b.nextDate));

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
                    IconButton(
                      icon: Icon(
                        compact
                            ? Icons.view_agenda_outlined
                            : Icons.view_stream_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                      tooltip: compact ? 'Show details' : 'Compact view',
                      onPressed: () => onCompactChanged(!compact),
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

          // EMI plans section — horizontal cards, collapsed when empty
          const EmiSection(),

          // Overdue section — shown above the timeline when items exist
          if (overdue.isNotEmpty)
            _OverdueSection(overdueItems: overdue, ref: ref),

          // Timeline
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
              itemCount: dayRows.length,
              itemBuilder: (context, i) {
                final day = dayRows[i];
                return day.hasEvents
                    ? _EventDayRow(day: day, ref: ref, maxBalance: maxBalance, compact: compact)
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
    List<Account> accounts,
  ) {
    final isDoomsday = days == _ddSentinel;
    final maxDays    = isDoomsday ? 365 : days;

    // Only scheduled transactions from liquid accounts affect cash
    final cashScheduled =
        state.scheduled.where((st) => st.isCashAccount).toList();

    final cutoff = today.add(Duration(days: maxDays));
    final entries = <_ProjectedEntry>[];

    for (final st in cashScheduled) {
      // Resolve TO account name from local accounts list (join removed from query)
      final toAccountName = st.isTransfer && st.transferToAccountId != null
          ? accounts
              .where((a) => a.id == st.transferToAccountId)
              .firstOrNull
              ?.displayName
          : null;

      for (final date in st.occurrencesUntil(today, cutoff)) {
        entries.add(_ProjectedEntry(
          scheduledTx: st,
          date:        date,
          payee:       st.isTransfer
              ? (st.payeeName?.isNotEmpty == true
                  ? st.payeeName!
                  : 'Transfer')
              : (st.payeeName ?? st.memo ?? 'Scheduled'),
          accountName: st.accountName,
          amount:      st.amount,
          isIncome:    !st.isTransfer && st.amount > 0,
          category:    st.isTransfer
              ? '→ ${toAccountName ?? 'account'}'
              : st.categoryName,
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

class _CashflowTile extends ConsumerWidget {
  final _ProjectedEntry entry;
  final bool isDanger;
  final bool isOdd;
  final WidgetRef ref;

  const _CashflowTile({
    required this.entry,
    required this.isDanger,
    required this.ref,
    this.isOdd = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef wRef) {
    final cs           = Theme.of(context).colorScheme;
    final fmt          = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final amountColor  = entry.isIncome ? cs.tertiary : cs.onSurface;
    final balanceColor = isDanger ? cs.error : cs.onSurfaceVariant;
    final hasReminder  = wRef.watch(billRemindersProvider)
        .contains(entry.scheduledTx.id);

    final zebraColor = isOdd
        ? cs.onSurface.withValues(alpha: 0.04)
        : Colors.transparent;

    return InkWell(
      onTap: () => showAddScheduledSheet(context, ref, prefill: entry.scheduledTx),
      onLongPress: () => _showTileActions(context, ref, entry),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: isDanger
              ? cs.surfaceContainerHigh
              : cs.surfaceContainerHigh.withValues(alpha: 1.0),
          borderRadius: BorderRadius.circular(12),
          border: isDanger ? Border.all(color: cs.error.withValues(alpha: 0.3)) : null,
        ),
        foregroundDecoration: BoxDecoration(
          color: zebraColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (entry.scheduledTx.isTransfer
                          ? cs.secondary
                          : entry.isIncome ? cs.tertiary : cs.primary)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  entry.scheduledTx.isTransfer
                      ? Icons.compare_arrows_rounded
                      : entry.isIncome
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                  size: 17,
                  color: entry.scheduledTx.isTransfer
                      ? cs.secondary
                      : entry.isIncome ? cs.tertiary : cs.primary,
                ),
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.payee,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14, fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasReminder) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.notifications_active_outlined,
                              size: 13, color: cs.primary),
                        ],
                      ],
                    ),
                    Text(
                      entry.scheduledTx.needsAccount
                          ? entry.category != null
                              ? 'Account TBD · ${entry.category}'
                              : 'Account TBD'
                          : entry.category != null
                              ? '${entry.accountName} · ${entry.category}'
                              : (entry.accountName ?? ''),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: entry.scheduledTx.needsAccount
                            ? cs.primary
                            : cs.onSurfaceVariant,
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
  final bool compact;
  const _EventDayRow({
    required this.day,
    required this.ref,
    required this.maxBalance,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildFull(context);
  }

  Widget _buildCompact(BuildContext context) {
    final cs         = Theme.of(context).colorScheme;
    final fmt        = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final now        = DateTime.now();
    final isToday    = _sameDay(day.date, now);
    final isTomorrow = _sameDay(day.date, now.add(const Duration(days: 1)));
    final hasIncome  = day.events.any((e) => e.isIncome);
    final hasExpense = day.events.any((e) => !e.isIncome);

    final dateLabel = isToday
        ? 'Today'
        : isTomorrow
            ? 'Tmrw'
            : DateFormat('MMM d').format(day.date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              dateLabel,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                color: isToday ? cs.primary : cs.onSurface,
              ),
            ),
          ),
          if (hasExpense)
            Text(
              '−',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w800, color: cs.primary,
              ),
            ),
          if (hasIncome)
            Text(
              '+',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w800, color: cs.tertiary,
              ),
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
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

  Widget _buildFull(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final now = DateTime.now();
    final isToday    = _sameDay(day.date, now);
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
        ...day.events.asMap().entries.map((en) => _CashflowTile(
              entry:    en.value,
              isDanger: en.value.runningBalance < 500,
              isOdd:    en.key.isOdd,
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
  final String? accountName;
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
// Cashflow tile long-press actions
// ---------------------------------------------------------------------------

void _showTileActions(
    BuildContext context, WidgetRef ref, _ProjectedEntry entry) {
  final cs = Theme.of(context).colorScheme;
  final st = entry.scheduledTx;

  showModalBottomSheet<void>(
    context:     context,
    useSafeArea: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
          const SizedBox(height: 4),
          ListTile(
            leading: Icon(Icons.check_circle_outline, color: cs.tertiary),
            title: Text('Enter transaction',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            subtitle: Text(
              st.needsAccount
                  ? 'Choose account & confirm actual amount'
                  : 'Confirm amount & date, then record to ${st.accountName}',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: cs.onSurfaceVariant),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _showConfirmPaymentSheet(context, ref, entry);
            },
          ),
          ListTile(
            leading: Icon(Icons.edit_outlined, color: cs.onSurfaceVariant),
            title: Text('Edit',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(ctx);
              showAddScheduledSheet(context, ref, prefill: st);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Add options picker (Bill or EMI)
// ---------------------------------------------------------------------------

void _showAddOptions(BuildContext context, WidgetRef ref) {
  final cs = Theme.of(context).colorScheme;
  showModalBottomSheet(
    context:         context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant, borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.event_repeat, color: cs.onPrimaryContainer),
            ),
            title: const Text('Add Bill / Schedule'),
            subtitle: const Text('Recurring income or expense reminder'),
            onTap: () {
              Navigator.pop(ctx);
              showAddScheduledSheet(context, ref, prefill: null);
            },
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.secondaryContainer,
              child: Icon(Icons.credit_score, color: cs.onSecondaryContainer),
            ),
            title: const Text('Set Up EMI'),
            subtitle: const Text('CC purchase split into monthly installments'),
            onTap: () {
              Navigator.pop(ctx);
              showSetupEmiSheet(context, ref);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
}

// Add scheduled transaction sheet
// ---------------------------------------------------------------------------

void showAddScheduledSheet(
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

  bool   _isIncome        = false;
  bool   _isTransfer      = false;
  bool   _incomeNextMonth = false;
  bool   _accountTbd      = false; // pick FROM account at payment time
  String? _accountId;
  String? _toAccountId;   // transfer destination (TO account)
  String? _categoryId;
  String? _categoryName;
  ScheduledFrequency _frequency = ScheduledFrequency.monthly;
  DateTime _nextDate  = DateTime.now();
  bool _remindMe      = false;
  bool _saving        = false;

  // Enter-now (edit mode only) — record this occurrence as a transaction.
  bool     _enterNow  = false;
  DateTime _enterDate = DateTime.now();

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
      _accountTbd      = p.accountId == null;
      _isTransfer      = p.isTransfer;
      _toAccountId     = p.transferToAccountId;
      _categoryId      = p.categoryId;
      _categoryName    = p.categoryName;
      _frequency       = p.frequency;
      _nextDate        = p.nextDate;
      _isIncome        = p.isIncome;
      _remindMe        = widget.widgetRef.read(billRemindersProvider).contains(p.id);
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
    final cs        = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // 'skip' = skip this occurrence only, 'all' = delete entire schedule
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remove scheduled transaction?'),
        content: const Text(
          'Skip just this occurrence and keep future ones, '
          'or delete the entire schedule?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'skip'),
            child: const Text('Skip this one'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, 'all'),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      if (choice == 'skip') {
        await ref.read(cashflowProvider.notifier).markAsPaid(widget.prefill!.id);
      } else {
        await ref.read(cashflowProvider.notifier).deleteScheduled(widget.prefill!.id);
      }
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: cs.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final budgetAccounts = accounts
        .where((a) => !a.isTracking && a.type != AccountType.investment && a.type != AccountType.loan)
        .toList();
    // Transfer destination: any account except the selected FROM account.
    final toAccounts = accounts
        .where((a) => a.id != _accountId)
        .toList();

    if (_accountId == null && !_accountTbd && budgetAccounts.isNotEmpty) {
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
                      // Expense / Income / Transfer
                      Row(
                        children: [
                          _TypeChip(
                            label: 'Expense',
                            selected: !_isIncome && !_isTransfer,
                            onTap: () => setState(() {
                              _isIncome    = false;
                              _isTransfer  = false;
                              _incomeNextMonth = false;
                            }),
                          ),
                          const SizedBox(width: 8),
                          _TypeChip(
                            label: 'Income',
                            selected: _isIncome && !_isTransfer,
                            onTap: () => setState(() {
                              _isIncome   = true;
                              _isTransfer = false;
                            }),
                          ),
                          const SizedBox(width: 8),
                          _TypeChip(
                            label: 'Transfer',
                            selected: _isTransfer,
                            onTap: () => setState(() {
                              _isTransfer      = true;
                              _isIncome        = false;
                              _incomeNextMonth = false;
                              _accountTbd      = true; // FROM is TBD by default
                              _accountId       = null;
                            }),
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

                      // Transfer: TO account picker
                      if (_isTransfer) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _toAccountId,
                          decoration: const InputDecoration(
                            labelText: 'To account',
                            helperText: 'The account receiving the money (e.g. credit card)',
                          ),
                          dropdownColor: cs.surfaceContainerHighest,
                          items: toAccounts.map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(a.displayName,
                                style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                          )).toList(),
                          onChanged: (v) => setState(() => _toAccountId = v),
                          validator: (v) => _isTransfer && v == null ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                      ],

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

                      // Payee (not shown for transfers — TO account serves as destination)
                      if (!_isTransfer) ...[
                        TextFormField(
                          controller: _payeeCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Payee'),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Account — fixed or TBD
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Pick account at payment time',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: _accountTbd
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: _accountTbd
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant),
                        ),
                        subtitle: _accountTbd
                            ? Text(
                                'You\'ll choose the account when you confirm payment',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: cs.onSurfaceVariant),
                              )
                            : null,
                        value: _accountTbd,
                        onChanged: (v) => setState(() {
                          _accountTbd = v;
                          if (v) _accountId = null;
                        }),
                      ),
                      if (!_accountTbd) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: const ValueKey('account_picker'),
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
                      ],
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
                      const SizedBox(height: 14),

                      // Remind me toggle
                      Container(
                        decoration: BoxDecoration(
                          color: _remindMe
                              ? cs.primaryContainer.withValues(alpha: 0.4)
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: _remindMe
                              ? Border.all(
                                  color: cs.primary.withValues(alpha: 0.35))
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile.adaptive(
                              contentPadding:
                                  const EdgeInsets.fromLTRB(14, 4, 8, 4),
                              secondary: Icon(
                                Icons.notifications_outlined,
                                size: 18,
                                color: _remindMe
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              title: Text(
                                'Remind me 1 day before',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: _remindMe
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: _remindMe
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                              value: _remindMe,
                              onChanged: (v) =>
                                  setState(() => _remindMe = v),
                            ),
                            if (_remindMe) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    14, 0, 14, 12),
                                child: Row(
                                  children: [
                                    Icon(Icons.alarm_outlined,
                                        size: 13, color: cs.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Reminder on ${DateFormat('MMM d').format(_nextDate.subtract(const Duration(days: 1)))} at 9 am',
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 12,
                                          color: cs.primary,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Enter-now toggle (edit only, not for transfers) ───
                      if (_isEditing && !_isTransfer &&
                          !_accountTbd && _accountId != null) ...[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _enterNow
                                ? cs.primaryContainer.withValues(alpha: 0.35)
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border: _enterNow
                                ? Border.all(
                                    color: cs.primary.withValues(alpha: 0.3))
                                : null,
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.add_circle_outline,
                                      size: 16,
                                      color: _enterNow
                                          ? cs.primary
                                          : cs.onSurfaceVariant),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Also record as transaction now',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: _enterNow
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: _enterNow
                                            ? cs.onSurface
                                            : cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  Switch.adaptive(
                                    value: _enterNow,
                                    onChanged: (v) =>
                                        setState(() => _enterNow = v),
                                  ),
                                ],
                              ),
                              if (_enterNow) ...[
                                const SizedBox(height: 8),
                                InkWell(
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _enterDate,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now()
                                          .add(const Duration(days: 30)),
                                    );
                                    if (picked != null) {
                                      setState(() => _enterDate = picked);
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.calendar_today_outlined,
                                            size: 13, color: cs.primary),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Transaction date: ${DateFormat('MMM d, yyyy').format(_enterDate)}',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 12,
                                            color: cs.onSurface,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      const SizedBox(height: 8),

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
                                  _enterNow ? 'Save & Enter' : 'Save',
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
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setLocal) {
          var query = '';
          return StatefulBuilder(
            builder: (_, setSearch) {
              final filtered = query.isEmpty
                  ? groups
                  : groups
                      .map((g) {
                        final cats = g.categories
                            .where((c) => c.name.toLowerCase()
                                .contains(query.toLowerCase()))
                            .toList();
                        return cats.isEmpty ? null : (group: g, cats: cats);
                      })
                      .whereType<({dynamic group, List<dynamic> cats})>()
                      .map((x) => x.group)
                      .toList();

              return DraggableScrollableSheet(
                initialChildSize: 0.7,
                minChildSize:     0.4,
                maxChildSize:     0.9,
                builder: (ctx, scrollCtrl) => Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
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
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Select Category',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            TextField(
                              autofocus: true,
                              onChanged: (v) =>
                                  setSearch(() => query = v),
                              decoration: InputDecoration(
                                hintText: 'Search categories…',
                                prefixIcon: const Icon(
                                    Icons.search, size: 18),
                                suffixIcon: query.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                            Icons.close, size: 16),
                                        onPressed: () =>
                                            setSearch(() => query = ''),
                                      )
                                    : null,
                                isDense: true,
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          controller: scrollCtrl,
                          children: [
                            if (query.isEmpty)
                              ListTile(
                                title: Text('No category',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14)),
                                onTap: () {
                                  setState(() {
                                    _categoryId   = null;
                                    _categoryName = null;
                                  });
                                  Navigator.pop(ctx);
                                },
                              ),
                            for (final g in filtered) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 12, 16, 4),
                                child: Text(
                                  g.name.toUpperCase(),
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurfaceVariant,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              for (final cat in g.categories
                                  .where((c) => query.isEmpty ||
                                      c.name.toLowerCase().contains(
                                          query.toLowerCase())))
                                ListTile(
                                  dense: true,
                                  title: Text(cat.name,
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14)),
                                  trailing: _categoryId == cat.id
                                      ? Icon(Icons.check,
                                          color: cs.primary, size: 18)
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
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_accountTbd && _accountId == null) return;

    setState(() => _saving = true);
    try {
      final raw       = double.parse(_amountCtrl.text.trim());
      final amount    = _isTransfer || !_isIncome ? -raw.abs() : raw.abs();
      final memo      = _memoCtrl.text.trim().isEmpty ? null : _memoCtrl.text.trim();
      final accountId = _accountTbd ? null : _accountId;

      String savedId;
      if (_isEditing) {
        savedId = widget.prefill!.id;
        await ref.read(cashflowProvider.notifier).updateScheduled(
          savedId,
          accountId:            accountId,
          amount:               amount,
          frequency:            _frequency,
          nextDate:             _nextDate,
          payeeName:            _payeeCtrl.text.trim(),
          categoryId:           _isTransfer ? null : _categoryId,
          memo:                 memo,
          isTransfer:           _isTransfer,
          transferToAccountId:  _isTransfer ? _toAccountId : null,
        );
        // If the user toggled "Also record as transaction now", enter it.
        if (_enterNow && !_accountTbd && _accountId != null) {
          await ref.read(cashflowProvider.notifier).enterNow(
            scheduledId:     savedId,
            accountId:       _accountId!,
            amount:          amount,
            date:            _enterDate,
            frequency:       _frequency,
            currentNextDate: _nextDate,
            payeeName:       _payeeCtrl.text.trim(),
            categoryId:      _isTransfer ? null : _categoryId,
            memo:            memo,
          );
        }
      } else {
        savedId = await ref.read(cashflowProvider.notifier).addScheduled(
          accountId:            accountId,
          amount:               amount,
          frequency:            _frequency,
          nextDate:             _nextDate,
          payeeName:            _payeeCtrl.text.trim(),
          categoryId:           _isTransfer ? null : _categoryId,
          memo:                 memo,
          isTransfer:           _isTransfer,
          transferToAccountId:  _isTransfer ? _toAccountId : null,
        );
      }

      // Persist reminder preference and schedule/cancel the notification.
      await ref.read(billRemindersProvider.notifier)
          .setEnabled(savedId, enabled: _remindMe);
      if (_remindMe) {
        await NotificationService.instance.scheduleBillReminder(
          scheduledTxId: savedId,
          payee:         _payeeCtrl.text.trim().isNotEmpty
              ? _payeeCtrl.text.trim()
              : (memo ?? 'Bill'),
          amount:        amount,
          dueDate:       _nextDate,
        );
      } else {
        await NotificationService.instance.cancelBillReminder(savedId);
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
// Confirm payment sheet — for account-less scheduled bills
// ---------------------------------------------------------------------------

void _showConfirmPaymentSheet(
    BuildContext context, WidgetRef ref, _ProjectedEntry entry) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _ConfirmPaymentSheet(entry: entry, widgetRef: ref),
  );
}

class _ConfirmPaymentSheet extends ConsumerStatefulWidget {
  final _ProjectedEntry entry;
  final WidgetRef widgetRef;
  const _ConfirmPaymentSheet({required this.entry, required this.widgetRef});

  @override
  ConsumerState<_ConfirmPaymentSheet> createState() => _ConfirmPaymentSheetState();
}

class _ConfirmPaymentSheetState extends ConsumerState<_ConfirmPaymentSheet> {
  final _amountCtrl = TextEditingController();
  String? _accountId;
  DateTime _date = DateTime.now();
  bool _saving   = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = widget.entry.amount.abs().toStringAsFixed(2);
    // Pre-fill FROM account if already set on the scheduled transaction
    _accountId = widget.entry.scheduledTx.accountId;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final checkingAccounts = accounts
        .where((a) => !a.isTracking &&
            (a.type == AccountType.checking ||
             a.type == AccountType.savings ||
             a.type == AccountType.cash))
        .toList();

    if (_accountId == null && checkingAccounts.isNotEmpty) {
      _accountId = checkingAccounts.first.id;
    }

    final st  = widget.entry.scheduledTx;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    final toAccountName = st.isTransfer && st.transferToAccountId != null
        ? accounts
            .where((a) => a.id == st.transferToAccountId)
            .firstOrNull
            ?.displayName
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  st.isTransfer
                      ? Icons.compare_arrows_rounded
                      : Icons.check_circle_outline,
                  size: 20, color: cs.tertiary),
                const SizedBox(width: 8),
                Text(
                  st.isTransfer ? 'Confirm Transfer' : 'Confirm Payment',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              st.isTransfer
                  ? '→ ${toAccountName ?? 'account'}'
                  : (widget.entry.payee.isNotEmpty
                      ? widget.entry.payee
                      : (st.memo ?? 'Bill')),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),

            // Amount — editable
            TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              decoration: InputDecoration(
                labelText: 'Actual amount',
                prefixText: '\$ ',
                helperText: 'Forecast was ${fmt.format(widget.entry.amount.abs())}',
              ),
            ),
            const SizedBox(height: 16),

            // FROM account picker
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              decoration: InputDecoration(
                labelText: st.isTransfer ? 'Pay from account' : 'Account',
              ),
              dropdownColor: cs.surfaceContainerHighest,
              items: checkingAccounts.map((a) => DropdownMenuItem(
                value: a.id,
                child: Text(a.displayName,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14)),
              )).toList(),
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 16),

            // Date
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context:     context,
                  initialDate: _date,
                  firstDate:   DateTime.now().subtract(const Duration(days: 31)),
                  lastDate:    DateTime.now().add(const Duration(days: 7)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Payment date'),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('MMM d, yyyy').format(_date),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, color: cs.onSurface),
                      ),
                    ),
                    Icon(Icons.calendar_today_outlined,
                        size: 16, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_saving || _accountId == null) ? null : _confirm,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? const SizedBox(
                        height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Confirm & Record',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm() async {
    final raw = double.tryParse(_amountCtrl.text.trim());
    if (raw == null || _accountId == null) return;

    final actualAmount = widget.entry.scheduledTx.isIncome ? raw.abs() : -raw.abs();

    setState(() => _saving = true);
    try {
      await ref.read(cashflowProvider.notifier).confirmPayment(
        widget.entry.scheduledTx.id,
        accountId:    _accountId!,
        actualAmount: actualAmount,
        date:         _date,
      );
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
// Overdue section
// ---------------------------------------------------------------------------

class _OverdueSection extends StatelessWidget {
  final List<ScheduledTransaction> overdueItems;
  final WidgetRef ref;

  const _OverdueSection({required this.overdueItems, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.error.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 14, color: cs.error),
                  const SizedBox(width: 6),
                  Text(
                    'OVERDUE',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: cs.error,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${overdueItems.length} ${overdueItems.length == 1 ? 'item' : 'items'} not entered',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: cs.error.withValues(alpha: 0.2)),
            ...overdueItems.map(
              (st) => _OverdueTile(st: st, ref: ref),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Overdue tile
// ---------------------------------------------------------------------------

class _OverdueTile extends StatelessWidget {
  final ScheduledTransaction st;
  final WidgetRef ref;

  const _OverdueTile({required this.st, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final today   = DateTime.now();
    final todayN  = DateTime(today.year, today.month, today.day);
    final stN     = DateTime(st.nextDate.year, st.nextDate.month, st.nextDate.day);
    final daysLate = todayN.difference(stN).inDays;

    final name = (st.payeeName?.isNotEmpty == true)
        ? st.payeeName!
        : (st.memo ?? 'Scheduled');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          // Icon
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              st.isTransfer
                  ? Icons.compare_arrows_rounded
                  : st.isIncome
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
              size: 16,
              color: cs.error,
            ),
          ),
          const SizedBox(width: 10),

          // Name + days overdue
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${DateFormat('MMM d').format(st.nextDate)} · '
                  '$daysLate day${daysLate != 1 ? 's' : ''} overdue',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: cs.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Amount
          Text(
            fmt.format(st.amount.abs()),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(width: 10),

          // Action buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Enter
              GestureDetector(
                onTap: () => _onEnter(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Enter',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Skip
              GestureDetector(
                onTap: () => _onSkip(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Skip',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.error,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _onEnter(BuildContext context) {
    // Wrap the scheduled transaction in a projected entry so existing sheets
    // can be reused without duplication.
    final entry = _ProjectedEntry(
      scheduledTx: st,
      date:        st.nextDate,
      payee:       (st.payeeName?.isNotEmpty == true)
          ? st.payeeName!
          : (st.memo ?? 'Scheduled'),
      accountName: st.accountName,
      amount:      st.amount,
      isIncome:    !st.isTransfer && st.amount > 0,
      category:    st.categoryName,
    );

    if (st.needsAccount) {
      // No account set (or transfer) — sheet lets user pick account / confirm.
      _showConfirmPaymentSheet(context, ref, entry);
    } else {
      // Account is known — create the transaction immediately and advance the
      // schedule.  confirmPayment() writes the row + calls invalidateSelf().
      ref.read(cashflowProvider.notifier).confirmPayment(
        st.id,
        accountId:    st.accountId!,
        actualAmount: st.amount,
        date:         DateTime.now(),
      ).ignore();
    }
  }

  Future<void> _onSkip(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Skip this occurrence?'),
        content: const Text(
          'The missed payment will be dismissed. Future scheduled '
          'occurrences will continue as normal.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(cashflowProvider.notifier).markAsPaid(st.id);
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
