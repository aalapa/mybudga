import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'reports_provider.dart';

// ---------------------------------------------------------------------------

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int _months     = 1;
  int _touchedIdx = -1; // for donut chart

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final async = ref.watch(reportsProvider(_months));

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:   (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: cs.error),
                const SizedBox(height: 12),
                Text('Could not load reports',
                    style: GoogleFonts.plusJakartaSans(color: cs.onSurfaceVariant)),
                TextButton(
                  onPressed: () => ref.invalidate(reportsProvider(_months)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (data) => _ReportsBody(
            data:       data,
            months:     _months,
            touchedIdx: _touchedIdx,
            onMonthsChanged:     (m) => setState(() { _months = m; _touchedIdx = -1; }),
            onTouchedIdxChanged: (i) => setState(() => _touchedIdx = i),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — single scrollable page
// ---------------------------------------------------------------------------

class _ReportsBody extends StatelessWidget {
  final ReportsState data;
  final int months;
  final int touchedIdx;
  final ValueChanged<int> onMonthsChanged;
  final ValueChanged<int> onTouchedIdxChanged;

  const _ReportsBody({
    required this.data,
    required this.months,
    required this.touchedIdx,
    required this.onMonthsChanged,
    required this.onTouchedIdxChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CustomScrollView(
      slivers: [
        // ── Header + period selector ────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reports',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 24, fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                const SizedBox(height: 14),
                _PeriodSelector(months: months, onChanged: onMonthsChanged),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // ── Net Worth ───────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _NetWorthSection(data: data),
        ),

        // ── Summary (income / expenses / saved / rate) ─────────────────────
        SliverToBoxAdapter(
          child: _SummarySection(data: data, months: months),
        ),

        // ── Spending by category ────────────────────────────────────────────
        SliverToBoxAdapter(
          child: data.byCategory.isEmpty
              ? _EmptySection(
                  label: 'SPENDING BY CATEGORY',
                  message: 'No expense transactions in this period',
                )
              : _SpendingSection(
                  data:       data,
                  touchedIdx: touchedIdx,
                  onTouch:    onTouchedIdxChanged,
                ),
        ),

        // ── Monthly trend ───────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: _TrendSection(data: data, months: months),
        ),

        // ── Top payees ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: data.topPayees.isEmpty
              ? const SizedBox.shrink()
              : _PayeesSection(data: data),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Period selector
// ---------------------------------------------------------------------------

class _PeriodSelector extends StatelessWidget {
  final int months;
  final ValueChanged<int> onChanged;

  const _PeriodSelector({required this.months, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [1, 3, 6, 12].map((m) {
        final selected = months == m;
        final label    = m == 1 ? '1M' : m == 12 ? '12M' : '${m}M';
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected ? cs.primaryContainer : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
                border: selected
                    ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                    : null,
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  )),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Net worth section
// ---------------------------------------------------------------------------

class _NetWorthSection extends StatelessWidget {
  final ReportsState data;
  const _NetWorthSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final nw  = data.netWorth;
    final nwColor = nw >= 0 ? cs.tertiary : cs.error;

    return _Section(
      label: 'NET WORTH',
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              nwColor.withValues(alpha: 0.08),
              nwColor.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: nwColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              nw >= 0 ? fmt.format(nw) : '-${fmt.format(nw.abs())}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 32, fontWeight: FontWeight.w800, color: nwColor,
              ),
            ),
            const SizedBox(height: 4),
            Text('Net worth',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            // Assets vs liabilities bar
            _NetWorthBar(
              assets:      data.totalAssets,
              liabilities: data.totalLiabilities,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _NwLegend(
                    color: cs.tertiary, label: 'Assets',
                    value: fmt.format(data.totalAssets)),
                const SizedBox(width: 24),
                _NwLegend(
                    color: cs.error, label: 'Liabilities',
                    value: fmt.format(data.totalLiabilities)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NetWorthBar extends StatelessWidget {
  final double assets;
  final double liabilities;
  const _NetWorthBar({required this.assets, required this.liabilities});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final total = assets + liabilities;
    final ratio = total > 0 ? (assets / total).clamp(0.0, 1.0) : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 10,
          width: constraints.maxWidth,
          child: Stack(
            children: [
              Container(color: cs.error.withValues(alpha: 0.25)),
              FractionallySizedBox(
                widthFactor: ratio,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [cs.tertiary, cs.tertiary.withValues(alpha: 0.8)],
                    ),
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

class _NwLegend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _NwLegend({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary section — 4 metric cards
// ---------------------------------------------------------------------------

class _SummarySection extends StatelessWidget {
  final ReportsState data;
  final int months;
  const _SummarySection({required this.data, required this.months});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final pct = NumberFormat.percentPattern()..maximumFractionDigits = 0;
    final saved = data.netSavings;

    return _Section(
      label: months == 1 ? 'THIS MONTH' : 'LAST $months MONTHS',
      child: Row(
        children: [
          _MetricCard(
            label: 'Income',
            value: fmt.format(data.totalIncome),
            icon:  Icons.arrow_downward_rounded,
            color: cs.tertiary,
          ),
          const SizedBox(width: 8),
          _MetricCard(
            label: 'Spent',
            value: fmt.format(data.totalExpenses),
            icon:  Icons.arrow_upward_rounded,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          _MetricCard(
            label: saved >= 0 ? 'Saved' : 'Deficit',
            value: saved >= 0
                ? fmt.format(saved)
                : '-${fmt.format(saved.abs())}',
            icon:  saved >= 0
                ? Icons.savings_outlined
                : Icons.warning_amber_rounded,
            color: saved >= 0 ? cs.tertiary : cs.error,
          ),
          const SizedBox(width: 8),
          _MetricCard(
            label: 'Rate',
            value: pct.format(data.savingsRate),
            icon:  Icons.percent,
            color: data.savingsRate >= 0.2
                ? cs.tertiary
                : data.savingsRate >= 0
                    ? cs.onSurface
                    : cs.error,
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 8),
            Text(value,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, fontWeight: FontWeight.w800, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spending by category — donut chart
// ---------------------------------------------------------------------------

class _SpendingSection extends StatelessWidget {
  final ReportsState data;
  final int touchedIdx;
  final ValueChanged<int> onTouch;

  const _SpendingSection({
    required this.data,
    required this.touchedIdx,
    required this.onTouch,
  });

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    // Limit to top 9 + "Other"
    final cats  = data.byCategory;
    final shown = cats.take(9).toList();
    final other = cats.length > 9
        ? cats.skip(9).fold(0.0, (s, c) => s + c.amount)
        : 0.0;
    final allSlices = [
      ...shown,
      if (other > 0) CategorySpend(name: 'Other', amount: other),
    ];

    final sections = allSlices.asMap().entries.map((e) {
      final i      = e.key;
      final cat    = e.value;
      final pct    = data.totalExpenses > 0
          ? cat.amount / data.totalExpenses * 100
          : 0.0;
      final color  = chartPalette[i % chartPalette.length];
      final isSel  = touchedIdx == i;

      return PieChartSectionData(
        color:  color,
        value:  cat.amount,
        radius: isSel ? 72.0 : 60.0,
        title:  pct >= 6 ? '${pct.toStringAsFixed(0)}%' : '',
        titleStyle: GoogleFonts.plusJakartaSans(
          fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
        ),
        badgeWidget: null,
      );
    }).toList();

    final selCat = (touchedIdx >= 0 && touchedIdx < allSlices.length)
        ? allSlices[touchedIdx]
        : null;

    return _Section(
      label: 'SPENDING BY CATEGORY',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Donut + centre label
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 56,
                    sectionsSpace: 2,
                    pieTouchData: PieTouchData(
                      enabled: true,
                      touchCallback: (FlTouchEvent event,
                          PieTouchResponse? response) {
                        if (!event.isInterestedForInteractions ||
                            response?.touchedSection == null) {
                          onTouch(-1);
                        } else {
                          onTouch(response!
                              .touchedSection!.touchedSectionIndex);
                        }
                      },
                    ),
                  ),
                  swapAnimationDuration:
                      const Duration(milliseconds: 200),
                ),
                // Centre text
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selCat != null
                          ? selCat.name
                          : 'Total spent',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selCat != null
                          ? fmt.format(selCat.amount)
                          : fmt.format(data.totalExpenses),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface),
                    ),
                    if (selCat != null)
                      Text(
                        '${(selCat.amount / data.totalExpenses * 100).toStringAsFixed(1)}%',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Legend
          ...allSlices.asMap().entries.map((e) {
            final i   = e.key;
            final cat = e.value;
            final pct = data.totalExpenses > 0
                ? cat.amount / data.totalExpenses * 100
                : 0.0;
            final barFrac = data.totalExpenses > 0
                ? cat.amount / data.totalExpenses
                : 0.0;
            final color   = chartPalette[i % chartPalette.length];
            final isSel   = touchedIdx == i;

            return GestureDetector(
              onTap: () => onTouch(isSel ? -1 : i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSel
                      ? color.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10, height: 10,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(cat.name,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: isSel
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: cs.onSurface)),
                    ),
                    const SizedBox(width: 8),
                    // Mini bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        width: 80, height: 4,
                        child: LinearProgressIndicator(
                          value: barFrac,
                          backgroundColor:
                              cs.surfaceContainerHighest,
                          valueColor:
                              AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${pct.toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: cs.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 64,
                      child: Text(
                        fmt.format(cat.amount),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Monthly income vs expenses — grouped bar chart
// ---------------------------------------------------------------------------

class _TrendSection extends StatelessWidget {
  final ReportsState data;
  final int months;
  const _TrendSection({required this.data, required this.months});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final fmt   = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final byMonth = data.byMonth;
    if (byMonth.isEmpty) return const SizedBox.shrink();

    final maxY = byMonth
        .expand((m) => [m.income, m.expenses])
        .reduce((a, b) => a > b ? a : b);
    final yMax  = maxY <= 0 ? 100.0 : _ceilNice(maxY * 1.15);
    final yStep = yMax / 4;

    final groups = byMonth.asMap().entries.map((e) {
      final i = e.key;
      final m = e.value;
      return BarChartGroupData(
        x:         i,
        barsSpace: 3,
        barRods: [
          BarChartRodData(
            toY:    m.income,
            width:  10,
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [cs.tertiary.withValues(alpha: 0.5), cs.tertiary],
              begin: Alignment.bottomCenter,
              end:   Alignment.topCenter,
            ),
          ),
          BarChartRodData(
            toY:    m.expenses,
            width:  10,
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(
              colors: [cs.primary.withValues(alpha: 0.5), cs.primary],
              begin: Alignment.bottomCenter,
              end:   Alignment.topCenter,
            ),
          ),
        ],
      );
    }).toList();

    // Fixed width per group so it scrolls on narrow screens
    final chartW = (months * 56.0).clamp(
        MediaQuery.sizeOf(context).width - 32, double.infinity);

    return _Section(
      label: 'INCOME VS EXPENSES',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend
          Row(
            children: [
              _BarLegend(color: cs.tertiary, label: 'Income'),
              const SizedBox(width: 16),
              _BarLegend(color: cs.primary, label: 'Expenses'),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width:  chartW,
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment:  BarChartAlignment.spaceAround,
                  maxY:       yMax,
                  barGroups:  groups,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show:             true,
                    drawVerticalLine: false,
                    horizontalInterval: yStep,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color:       cs.outlineVariant.withValues(alpha: 0.4),
                      strokeWidth: 1,
                      dashArray:   [4, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles:   AxisTitles(
                        sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 48,
                      interval: yStep,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        final label = value >= 1000
                            ? '\$${(value / 1000).toStringAsFixed(0)}k'
                            : '\$${value.toStringAsFixed(0)}';
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(label,
                              textAlign: TextAlign.right,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: cs.onSurfaceVariant)),
                        );
                      },
                    )),
                    rightTitles: AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles:   AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles:   true,
                        reservedSize: 28,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= byMonth.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              DateFormat(months <= 3 ? 'MMM' : 'MMM')
                                  .format(byMonth[idx].month),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => cs.surfaceContainerHigh,
                      getTooltipItem: (group, groupIdx, rod, rodIdx) {
                        final label = rodIdx == 0 ? 'Income' : 'Expenses';
                        return BarTooltipItem(
                          '$label\n${fmt.format(rod.toY)}',
                          GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static double _ceilNice(double v) {
    if (v <= 0) return 100;
    final mag = (v / 4).ceil();
    // Round up to nearest 50 or 500
    final step = v < 1000 ? 50.0 : 500.0;
    return ((mag / step).ceil() * step * 4).toDouble();
  }
}

class _BarLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _BarLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Top payees — animated horizontal bars
// ---------------------------------------------------------------------------

class _PayeesSection extends StatelessWidget {
  final ReportsState data;
  const _PayeesSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final fmt    = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final maxAmt = data.topPayees.first.amount;

    return _Section(
      label: 'TOP PAYEES',
      child: Column(
        children: data.topPayees.asMap().entries.map((e) {
          final i     = e.key;
          final p     = e.value;
          final ratio = maxAmt > 0 ? p.amount / maxAmt : 0.0;
          final color = chartPalette[i % chartPalette.length];

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(p.name,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(fmt.format(p.amount),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface)),
                  ],
                ),
                const SizedBox(height: 4),
                LayoutBuilder(
                  builder: (context, constraints) => ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 6,
                      width: constraints.maxWidth,
                      child: Stack(
                        children: [
                          Container(
                              color: cs.surfaceContainerHighest),
                          FractionallySizedBox(
                            widthFactor: ratio,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    color.withValues(alpha: 0.7),
                                    color,
                                  ],
                                ),
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
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty section placeholder
// ---------------------------------------------------------------------------

class _EmptySection extends StatelessWidget {
  final String label;
  final String message;
  const _EmptySection({required this.label, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Section(
      label: label,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(message,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: cs.onSurfaceVariant)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared section container
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                  letterSpacing: 0.8)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
