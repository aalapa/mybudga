import '../insights/payee_pattern.dart';
import '../accounts/account_labels_provider.dart' show accountLabelsProvider;
import 'dart:ui' as ui;
import '../../core/theme/semantic_colors.dart';
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
import '../../shared/models/category.dart';

// ---------------------------------------------------------------------------

class CashflowScreen extends ConsumerStatefulWidget {
  const CashflowScreen({super.key});

  @override
  ConsumerState<CashflowScreen> createState() => _CashflowScreenState();
}

class _CashflowScreenState extends ConsumerState<CashflowScreen> {
  int  _days    = 30;

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
          onDaysChanged:    (d) => setState(() => _days = d),
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
    final cs       = Theme.of(context).colorScheme;
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


    // DD mode: find how many days until balance goes negative
    final negIdx = isDoomsday
        ? dayRows.indexWhere((d) => d.endBalance < 0)
        : -1;

    return SafeArea(
      // One scroll view rather than fixed blocks above a scrolling list: the
      // verdict and the chart are read once and then want to be out of the
      // way, and on a phone they were taking roughly half the screen for the
      // whole session.
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
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
                    // Was a compact/detail toggle; since the chart became the
                    // compact view it switched between two identical lists.
                    IconButton(
                      icon: Icon(Icons.event_repeat, color: cs.onSurfaceVariant),
                      tooltip: 'Scheduled transactions',
                      onPressed: () => _showScheduledSheet(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // One verdict, not two figures the reader has to combine.
                _VerdictCard(
                  dayRows:    dayRows,
                  today:      today,
                  startBalance: state.startingBalance,
                  isDoomsday: isDoomsday,
                  negIdx:     negIdx,
                ),
                const SizedBox(height: 14),

                // Day range toggle
                Row(
                  children: [
                    (30,  '30d'),
                    (60,  '60d'),
                    (90,  '90 days'),
                    (_CashflowBody._ddSentinel, 'Until I run out'),
                  ].map(((int, String) opt) {
                    final (value, label) = opt;
                    final selected  = days == value;
                    final isDdChip  = value == _CashflowBody._ddSentinel;
                    final chipColor = cs.primary;
                    return Expanded(
                      flex: isDdChip ? 3 : 2,
                      child: GestureDetector(
                        onTap: () => onDaysChanged(value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? cs.primaryContainer
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
                                  ? cs.onPrimaryContainer
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

              ],
            ),
          ),
          SliverToBoxAdapter(
            child: _BalanceChart(
              dayRows: dayRows,
              startBalance: state.startingBalance,
            ),
          ),
          // Directly under the projection it undermines.
          SliverToBoxAdapter(
            child: _UnplannedBillsCard(
              lowestBalance: dayRows.isEmpty
                  ? state.startingBalance
                  : dayRows
                      .map((d) => d.endBalance)
                      .reduce((a, b) => a < b ? a : b),
            ),
          ),

          // Only days where something happens. An empty Tuesday told the
          // reader nothing and pushed the next real event off screen.
          SliverToBoxAdapter(
            child: Builder(builder: (context) {
              final eventDays = dayRows.where((d) => d.hasEvents).toList();
              if (eventDays.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                  child: Text('Nothing scheduled in this range',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                );
              }
              var lowIdx = 0;
              for (var i = 1; i < dayRows.length; i++) {
                if (dayRows[i].endBalance < dayRows[lowIdx].endBalance) {
                  lowIdx = i;
                }
              }
              final lowDate = dayRows[lowIdx].date;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: eventDays.length,
                itemBuilder: (context, i) {
                  final day  = eventDays[i];
                  final prev = i == 0 ? null : eventDays[i - 1].date;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_needsWeekHeader(prev, day.date, today))
                        _WeekHeader(
                          date: day.date,
                          today: today,
                          gapFrom: prev,
                        ),
                      _EventDayRow(
                        day: day,
                        ref: ref,
                        maxBalance: maxBalance,
                        isLowPoint: day.date == lowDate,
                      ),
                    ],
                  );
                },
              );
            }),
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
      final toAccount = st.isTransfer && st.transferToAccountId != null
          ? accounts.where((a) => a.id == st.transferToAccountId).firstOrNull
          : null;
      final toAccountName = toAccount?.displayName;

      // A card payment costs whatever is owed, not whatever was scheduled.
      // Every bill charged to the card since the schedule was written — the
      // ones that never touch cash directly — lands in this one payment, so a
      // fixed figure here is optimistic by exactly the amount most easily
      // forgotten.
      //
      // Only the next payment can use the live balance: what a card will owe
      // three months out is not knowable, so later occurrences keep the
      // scheduled figure rather than repeating today's balance.
      final owed = (toAccount != null &&
              (toAccount.type == AccountType.creditCard ||
                  toAccount.type == AccountType.lineOfCredit) &&
              toAccount.balance < 0)
          ? toAccount.balance.abs()
          : null;
      var usedLiveBalance = false;

      for (final date in st.occurrencesUntil(today, cutoff)) {
        var amount = st.amount;
        var liveHere = false;
        if (owed != null && !usedLiveBalance && owed > st.amount.abs()) {
          amount   = -owed;      // outflow from the paying account
          liveHere = true;
          usedLiveBalance = true;
        } else if (owed != null && !usedLiveBalance) {
          // Owe less than scheduled — the first payment still clears it.
          usedLiveBalance = true;
        }

        entries.add(_ProjectedEntry(
          scheduledTx: st,
          date:        date,
          payee:       st.isTransfer
              ? (st.payeeName?.isNotEmpty == true
                  ? st.payeeName!
                  : 'Transfer')
              : (st.payeeName ?? st.memo ?? 'Scheduled'),
          accountName: st.accountName,
          amount:      amount,
          isIncome:    !st.isTransfer && st.amount > 0,
          usesLiveBalance: liveHere,
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

/// True when [date] opens a different week from [prev].
bool _needsWeekHeader(DateTime? prev, DateTime date, DateTime today) {
  if (prev == null) return true;
  DateTime weekStart(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
  return weekStart(prev) != weekStart(date);
}

/// Week divider, naming the gap it skipped so an empty stretch is stated
/// rather than silently missing.
class _WeekHeader extends StatelessWidget {
  final DateTime date;
  final DateTime today;
  final DateTime? gapFrom;
  const _WeekHeader({required this.date, required this.today, this.gapFrom});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    DateTime weekStart(DateTime d) =>
        DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));
    final diff = weekStart(date).difference(weekStart(today)).inDays ~/ 7;
    final label = diff <= 0
        ? 'THIS WEEK'
        : diff == 1
            ? 'NEXT WEEK'
            : 'WEEK OF ${DateFormat('MMM d').format(weekStart(date)).toUpperCase()}';

    String? gap;
    if (gapFrom != null) {
      final from = gapFrom!.add(const Duration(days: 1));
      final to   = date.subtract(const Duration(days: 1));
      if (!to.isBefore(from)) {
        gap = from == to
            ? 'nothing ${DateFormat('MMM d').format(from)}'
            : 'nothing ${DateFormat('MMM d').format(from)}–${DateFormat('d').format(to)}';
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Row(
        children: [
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: cs.onSurfaceVariant,
              )),
          if (gap != null) ...[
            const Spacer(),
            Text(gap,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
          ],
        ],
      ),
    );
  }
}

/// Balance over the projection as a step line.
///
/// Replaces a column of per-day bars scaled to the period peak, where a
/// $4,183 -> $1,868 fall read as a slightly shorter bar. Balance is a step
/// function — it changes only when something lands — so the line is not
/// smoothed.
class _BalanceChart extends StatelessWidget {
  final List<_DayData> dayRows;
  final double startBalance;
  final ValueChanged<DateTime>? onTapDate;

  const _BalanceChart({
    required this.dayRows,
    required this.startBalance,
    this.onTapDate,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final money = context.money;
    final f0    = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    if (dayRows.length < 2) return const SizedBox.shrink();

    var lowIdx = 0;
    for (var i = 1; i < dayRows.length; i++) {
      if (dayRows[i].endBalance < dayRows[lowIdx].endBalance) lowIdx = i;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (ctx, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                if (onTapDate == null || box.maxWidth <= 0) return;
                final i = ((d.localPosition.dx / box.maxWidth) *
                        (dayRows.length - 1))
                    .round()
                    .clamp(0, dayRows.length - 1);
                onTapDate!(dayRows[i].date);
              },
              child: CustomPaint(
                size: Size(box.maxWidth, 128),
                painter: _BalanceChartPainter(
                  rows:      dayRows,
                  start:     startBalance,
                  lowIdx:    lowIdx,
                  positive:  money.positive,
                  negative:  money.negative,
                  warning:   money.warning,
                  primary:   cs.primary,
                  gridColor: cs.outlineVariant.withValues(alpha: 0.5),
                  labelColor: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('Today · ${f0.format(startBalance)}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, color: cs.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(DateFormat('MMM d').format(dayRows[lowIdx].date),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: dayRows[lowIdx].endBalance < 0
                            ? money.negative
                            : money.warning)),
              ),
              Expanded(
                child: Text(
                    '${DateFormat('MMM d').format(dayRows.last.date)} · '
                    '${f0.format(dayRows.last.endBalance)}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceChartPainter extends CustomPainter {
  final List<_DayData> rows;
  final double start;
  final int lowIdx;
  final Color positive, negative, warning, primary, gridColor, labelColor;

  const _BalanceChartPainter({
    required this.rows,
    required this.start,
    required this.lowIdx,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.primary,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final top = 16.0, bottom = size.height - 4;
    var maxV = start, minV = start;
    for (final r in rows) {
      if (r.endBalance > maxV) maxV = r.endBalance;
      if (r.endBalance < minV) minV = r.endBalance;
    }
    if (minV > 0) minV = 0;               // always show the zero line
    if (maxV <= minV) maxV = minV + 1;

    double y(double v) =>
        bottom - ((v - minV) / (maxV - minV)) * (bottom - top);
    double x(int i) => rows.length < 2 ? 0 : size.width * i / (rows.length - 1);

    // Zero line
    final zeroY = y(0);
    final dash = Paint()..color = gridColor..strokeWidth = 1;
    for (double dx = 0; dx < size.width; dx += 6) {
      canvas.drawLine(Offset(dx, zeroY), Offset(dx + 3, zeroY), dash);
    }

    // Step path: the balance holds until something lands.
    final path = Path()..moveTo(0, y(start));
    for (var i = 0; i < rows.length; i++) {
      path.lineTo(x(i), y(i == 0 ? start : rows[i - 1].endBalance));
      path.lineTo(x(i), y(rows[i].endBalance));
    }

    final fill = Path.from(path)
      ..lineTo(size.width, zeroY)
      ..lineTo(0, zeroY)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [positive.withValues(alpha: 0.28), positive.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, top, size.width, bottom - top)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = rows.any((r) => r.endBalance < 0) ? negative : positive
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    // Low point.
    final lowY = y(rows[lowIdx].endBalance);
    final lowX = x(lowIdx);
    final ringColor = rows[lowIdx].endBalance < 0 ? negative : warning;
    canvas.drawCircle(Offset(lowX, lowY), 5,
        Paint()..color = ringColor..style = PaintingStyle.stroke..strokeWidth = 2);

    final tp = TextPainter(
      text: TextSpan(
        text: NumberFormat.currency(symbol: '\$', decimalDigits: 0)
            .format(rows[lowIdx].endBalance),
        style: GoogleFonts.plusJakartaSans(
            fontSize: 11, fontWeight: FontWeight.w700, color: ringColor),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas,
        Offset((lowX - tp.width / 2).clamp(0, size.width - tp.width), lowY - 20));

    // Today.
    canvas.drawCircle(Offset(0, y(start)), 4, Paint()..color = primary);
  }

  @override
  bool shouldRepaint(_BalanceChartPainter old) =>
      old.rows.length != rows.length || old.lowIdx != lowIdx;
}

/// Recurring money the projection cannot see, and what it would do to the
/// tightest moment.
///
/// Deliberately not an indicator on Accounts: a bill charged to a credit card
/// is a line inside a card balance, not an account, so nothing account-shaped
/// could represent it. Asking "is my plan complete?" instead of "does this
/// account have a payment?" makes rent-from-checking and gym-on-the-Amex the
/// same question, answered once, next to the number they affect.
class _UnplannedBillsCard extends ConsumerStatefulWidget {
  final double lowestBalance;
  const _UnplannedBillsCard({required this.lowestBalance});

  @override
  ConsumerState<_UnplannedBillsCard> createState() =>
      _UnplannedBillsCardState();
}

class _UnplannedBillsCardState extends ConsumerState<_UnplannedBillsCard> {
  /// Four is enough to make the point without burying the consequence line
  /// underneath a list. The rest are one tap away rather than unreachable.
  static const _collapsedCount = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final money = context.money;
    final f0    = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final bills   = ref.watch(unplannedBillsProvider).valueOrNull ?? const [];
    final ignored = ref.watch(ignoredBillPayeesProvider);

    // The card goes away when everything is either scheduled or dismissed,
    // but the dismissals stay reachable — see the footer below.
    if (bills.isEmpty) {
      return ignored.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _RestoreIgnoredButton(count: ignored.length),
              ),
            );
    }

    final shown = _expanded ? bills : bills.take(_collapsedCount).toList();
    final hidden = bills.length - shown.length;
    final impact = bills.fold(0.0, (s, b) => s + b.monthlyCost);
    final after  = widget.lowestBalance - impact;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: money.warning.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: money.warning.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 15, color: money.warning),
              const SizedBox(width: 7),
              Text('NOT IN YOUR PLAN',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: money.warning,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${bills.length} ${bills.length == 1 ? 'payee looks' : 'payees look'} '
            'regular but ${bills.length == 1 ? 'is' : 'are'} not scheduled, so '
            'the projection above does not include them.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, height: 1.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          ...shown.map((b) => _UnplannedBillRow(bill: b, f0: f0)),
          if (hidden > 0 || _expanded)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? 'Show fewer' : 'Show all ${bills.length}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary),
                    ),
                    const SizedBox(width: 2),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16, color: cs.primary),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Divider(height: 1, color: money.warning.withValues(alpha: 0.25)),
          const SizedBox(height: 8),
          // The consequence, which is the reason to care.
          Text(
            'Adding these would put your tightest moment near '
            '${f0.format(after)}.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
              color: after < 0 ? money.negative : cs.onSurface,
            ),
          ),
          if (ignored.isNotEmpty) ...[
            const SizedBox(height: 8),
            _RestoreIgnoredButton(count: ignored.length),
          ],
        ],
      ),
    );
  }
}

/// One detected payee: what it looks like, and the two things you can do about
/// it. "Not a bill" matters as much as "Schedule" — a card that can only be
/// agreed with keeps nagging about the payee you already decided is irregular,
/// and an alert nobody can dismiss stops being read at all.
class _UnplannedBillRow extends ConsumerWidget {
  final UnplannedBill bill;
  final NumberFormat f0;
  const _UnplannedBillRow({required this.bill, required this.f0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${bill.payeeName} · ${bill.frequency.shortLabel} · '
              '~${f0.format(bill.avgAmount)}',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5, color: cs.onSurface),
            ),
          ),
          const SizedBox(width: 8),
          // Straight into the existing sheet, prefilled by name.
          InkWell(
            onTap: () => showAddScheduledSheet(context, ref,
                prefill: null, presetPayee: bill.payeeName),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: cs.primary.withValues(alpha: 0.35)),
              ),
              child: Text('Schedule',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.primary)),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Not a bill',
            child: InkWell(
              onTap: () {
                final messenger = ScaffoldMessenger.of(context);
                final notifier  = ref.read(ignoredBillPayeesProvider.notifier);
                notifier.ignore(bill.payeeName);
                messenger.clearSnackBars();
                messenger.showSnackBar(SnackBar(
                  content: Text('${bill.payeeName} won\'t be flagged again'),
                  behavior: SnackBarBehavior.floating,
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () => notifier.restore(bill.payeeName),
                  ),
                ));
              },
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 30,
                width: 30,
                child: Icon(Icons.close_rounded,
                    size: 16, color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dismissing has to be reversible, and visibly so — otherwise it is a trap
/// door, and a payee wrongly marked irregular is invisible forever.
class _RestoreIgnoredButton extends ConsumerWidget {
  final int count;
  const _RestoreIgnoredButton({required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => ref.read(ignoredBillPayeesProvider.notifier).restoreAll(),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          '$count marked not a bill · Show again',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11.5,
              color: cs.onSurfaceVariant,
              decoration: TextDecoration.underline,
              decorationColor: cs.onSurfaceVariant.withValues(alpha: 0.4)),
        ),
      ),
    );
  }
}

/// The cashflow verdict: the tightest moment, when it lands, what causes it,
/// and how it resolves — in that order.
///
/// Replaces two figures ("Today", "Lowest in 30d") that stated the inputs and
/// left the reader to work out whether they were in trouble.
class _VerdictCard extends StatelessWidget {
  final List<_DayData> dayRows;
  final DateTime today;
  final double startBalance;
  final bool isDoomsday;
  final int negIdx;

  const _VerdictCard({
    required this.dayRows,
    required this.today,
    required this.startBalance,
    required this.isDoomsday,
    required this.negIdx,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final money = context.money;
    final f0    = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    if (dayRows.isEmpty) return const SizedBox.shrink();

    // The low point, and the day it happens.
    var lowIdx = 0;
    for (var i = 1; i < dayRows.length; i++) {
      if (dayRows[i].endBalance < dayRows[lowIdx].endBalance) lowIdx = i;
    }
    final low     = dayRows[lowIdx];
    final goesNeg = dayRows.any((d) => d.endBalance < 0);

    // Average daily outflow, to judge whether a positive minimum is actually
    // comfortable or merely above zero.
    final totalOut = dayRows
        .expand((d) => d.events)
        .where((e) => !e.isIncome)
        .fold(0.0, (s, e) => s + e.amount.abs());
    final monthOut = dayRows.isEmpty ? 0.0 : totalOut / dayRows.length * 30;
    final comfortable = !goesNeg && low.endBalance > monthOut;

    final tint = goesNeg
        ? money.negative
        : comfortable
            ? money.positive
            : money.warning;

    // Headline.
    final String headline;
    if (isDoomsday) {
      headline = negIdx >= 0
          ? '${f0.format(0)} on ${DateFormat('MMM d').format(dayRows[negIdx].date)}'
              ' — $negIdx days of runway'
          : '365+ days safe';
    } else {
      headline =
          '${f0.format(low.endBalance)} on ${DateFormat('EEE, MMM d').format(low.date)}';
    }

    // Cause: the one or two largest expenses at or before the low point.
    final causes = dayRows
        .take(lowIdx + 1)
        .expand((d) => d.events)
        .where((e) => !e.isIncome)
        .toList()
      ..sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));
    final causeNames = causes.take(2).map((e) => e.payee).toList();

    // Resolution: the next income after the low point.
    _ProjectedEntry? nextIn;
    double? afterIn;
    for (var i = lowIdx; i < dayRows.length; i++) {
      final inc = dayRows[i].events.where((e) => e.isIncome);
      if (inc.isNotEmpty) {
        nextIn  = inc.first;
        afterIn = dayRows[i].endBalance;
        break;
      }
    }

    final daysAway = low.date.difference(
        DateTime(today.year, today.month, today.day)).inDays;

    final buf = StringBuffer();
    if (!isDoomsday) {
      buf.write(daysAway <= 0 ? 'Today' : '$daysAway days away');
      if (causeNames.isNotEmpty) {
        buf.write(', right after ${causeNames.join(' and ')} land');
      }
      buf.write('. ');
    }
    buf.write(goesNeg
        ? 'You go negative on ${DateFormat('MMM d').format(dayRows.firstWhere((d) => d.endBalance < 0).date)}'
        : 'You stay above zero all month');
    if (nextIn != null && afterIn != null) {
      buf.write(' — ${nextIn.payee} on '
          '${DateFormat('MMM d').format(nextIn.date)} puts you back to '
          '${f0.format(afterIn)}');
    }
    buf.write('.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isDoomsday ? 'RUNWAY' : 'TIGHTEST MOMENT',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: tint,
              )),
          const SizedBox(height: 6),
          Text(headline,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              )),
          const SizedBox(height: 8),
          Text(buf.toString(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12.5,
                height: 1.55,
                color: cs.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}

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
    final amountColor  = entry.isIncome ? context.money.positive : cs.onSurface;
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
                          : entry.isIncome ? context.money.positive : cs.primary)
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
                      : entry.isIncome ? context.money.positive : cs.primary,
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
                    // Say why the figure is not the scheduled one, otherwise
                    // it just looks like the schedule is being ignored.
                    if (entry.usesLiveBalance)
                      Text(
                        'current balance, not the scheduled '
                        '${NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(entry.scheduledTx.amount.abs())}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: context.money.warning,
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

class _EventDayRow extends StatelessWidget {
  /// The single tinted card in the list, matching the chart's marker.
  final bool isLowPoint;
  final _DayData day;
  final WidgetRef ref;
  final double maxBalance;
  const _EventDayRow({
    required this.day,
    required this.ref,
    required this.maxBalance,
    this.isLowPoint = false,
  });

  @override
  Widget build(BuildContext context) {
    return _buildFull(context);
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

    final money = context.money;
    // The low point is the only tinted day, so the chart's marker and this
    // list are pointing at the same thing.
    return Container(
      margin: isLowPoint
          ? const EdgeInsets.symmetric(vertical: 4)
          : EdgeInsets.zero,
      padding: isLowPoint
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 2)
          : EdgeInsets.zero,
      decoration: isLowPoint
          ? BoxDecoration(
              color: money.warning.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: money.warning.withValues(alpha: 0.25)),
            )
          : null,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isLowPoint
                  ? money.warning
                  : isToday
                      ? cs.primary
                      : cs.onSurfaceVariant,
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
                'leaves',
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
                  color: isLowPoint
                      ? money.warning
                      : day.endBalance < 0
                          ? money.negative
                          : cs.onSurface,
                ),
              ),
            ],
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

  Color _fillColor(MoneyColors money) {
    if (balance <= 0) return money.negative;
    if (maxBalance <= 0) return money.positive;
    // Amber when below 25 % of the peak balance in the period
    if (balance / maxBalance < 0.25) return money.warning;
    return money.positive;
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
                color: _fillColor(context.money),
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
  /// True when the amount came from the card's actual balance rather than the
  /// scheduled figure, so the row can say so instead of appearing to disagree
  /// with the schedule.
  final bool usesLiveBalance;
  double runningBalance = 0;

  _ProjectedEntry({
    required this.scheduledTx,
    required this.date,
    required this.payee,
    required this.accountName,
    required this.amount,
    required this.isIncome,
    this.usesLiveBalance = false,
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
            leading: Icon(Icons.check_circle_outline, color: context.money.positive),
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

/// Every schedule, grouped by the account labels already used to group
/// accounts in the sidebar.
///
/// The cashflow list shows *occurrences* — the same rent appears four times
/// across a 90-day window. This shows the schedules themselves, which until
/// now could only be managed from Settings.
void _showScheduledSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ScheduledListSheet(),
  );
}

class _ScheduledListSheet extends ConsumerWidget {
  const _ScheduledListSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs       = Theme.of(context).colorScheme;
    final money    = context.money;
    final fmt      = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final state    = ref.watch(cashflowProvider).valueOrNull;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final labels   = ref.watch(accountLabelsProvider);
    final all      = state?.scheduled ?? const <ScheduledTransaction>[];

    // Reuse the account labels rather than inventing a second tagging system:
    // a schedule belongs to whichever label claims its account.
    Account? accountOf(ScheduledTransaction st) => st.accountId == null
        ? null
        : accounts.where((a) => a.id == st.accountId).firstOrNull;

    final groups = <String, List<ScheduledTransaction>>{};
    for (final st in all) {
      final acc = accountOf(st);
      final label = acc == null
          ? null
          : labels.where((l) => l.matches(acc)).firstOrNull;
      groups.putIfAbsent(label?.name ?? 'Everything else', () => []).add(st);
    }
    final orderedKeys = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'Everything else') return 1;
        if (b == 'Everything else') return -1;
        return a.compareTo(b);
      });

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text('Scheduled transactions',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  showAddScheduledSheet(context, ref, prefill: null);
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New'),
              ),
            ],
          ),
          if (labels.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Text(
                'Grouped by account label — add labels in Accounts to group '
                'these too.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 8),
          Flexible(
            child: all.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Text('Nothing scheduled yet.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: cs.onSurfaceVariant)),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final key in orderedKeys) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                          child: Text(key.toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: cs.onSurfaceVariant,
                              )),
                        ),
                        for (final st in groups[key]!)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              st.isActive
                                  ? Icons.event_repeat
                                  : Icons.pause_circle_outline,
                              size: 20,
                              color: st.isActive
                                  ? cs.onSurfaceVariant
                                  : cs.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                            title: Text(
                                st.payeeName?.isNotEmpty == true
                                    ? st.payeeName!
                                    : (st.memo ?? 'Scheduled'),
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface)),
                            subtitle: Text(
                                '${st.frequency.label} · next '
                                '${DateFormat('MMM d').format(st.nextDate)}'
                                '${st.endDate != null ? ' · until ${DateFormat('MMM yyyy').format(st.endDate!)}' : ''}',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant)),
                            trailing: Text(
                                fmt.format(st.amount.abs()),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: st.amount >= 0
                                      ? money.positive
                                      : cs.onSurface,
                                )),
                            onTap: () {
                              Navigator.pop(context);
                              showAddScheduledSheet(context, ref, prefill: st);
                            },
                          ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

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
  /// Seeds the payee field when creating from a detected pattern, so the
  /// name does not have to be retyped exactly to match.
  String? presetPayee,
}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _AddScheduledSheet(
        prefill: prefill, presetPayee: presetPayee, widgetRef: ref),
  );
}

class _AddScheduledSheet extends ConsumerStatefulWidget {
  final ScheduledTransaction? prefill;
  final String? presetPayee;
  final WidgetRef widgetRef;
  const _AddScheduledSheet(
      {this.prefill, this.presetPayee, required this.widgetRef});

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
    // Creating from a detected pattern: seed the name so it matches the payee
    // the detector found, rather than relying on it being retyped identically.
    if (widget.presetPayee != null) {
      _payeeCtrl.text = widget.presetPayee!;
    }
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
    // A schedule runs forward, so retired categories are excluded as of
    // today. Only the transaction sheet needs a per-date view.
    final groups = categoriesOn(
        ref.read(categoriesProvider).valueOrNull ?? [], DateTime.now());

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
                  size: 20, color: context.money.positive),
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
