import 'dart:math' show max, min;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'reports_provider.dart';

// ---------------------------------------------------------------------------
// Drill-down mode for inline per-category chart
// ---------------------------------------------------------------------------

enum _DrillMode { weekly, daily }

// ---------------------------------------------------------------------------

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  int         _months       = 1;
  int         _touchedIdx   = -1;
  Set<String> _excludedCats = {};

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
            onMonthsChanged:     (m) => setState(() {
              _months = m; _touchedIdx = -1; _excludedCats = {};
            }),
            onTouchedIdxChanged: (i) => setState(() => _touchedIdx = i),
            excludedCats:        _excludedCats,
            onExclude:           (name) => setState(() {
              if (_excludedCats.contains(name)) {
                _excludedCats = {..._excludedCats}..remove(name);
              } else {
                _excludedCats = {..._excludedCats, name};
              }
            }),
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
  final Set<String> excludedCats;
  final ValueChanged<int> onMonthsChanged;
  final ValueChanged<int> onTouchedIdxChanged;
  final void Function(String) onExclude;

  const _ReportsBody({
    required this.data,
    required this.months,
    required this.touchedIdx,
    required this.excludedCats,
    required this.onMonthsChanged,
    required this.onTouchedIdxChanged,
    required this.onExclude,
  });

  @override
  Widget build(BuildContext context) {
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
                        color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 14),
                _PeriodSelector(months: months, onChanged: onMonthsChanged),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // ── Net Worth ───────────────────────────────────────────────────────
        SliverToBoxAdapter(child: _NetWorthSection(data: data)),

        // ── Summary (income / expenses / saved / rate) ─────────────────────
        SliverToBoxAdapter(child: _SummarySection(data: data, months: months)),

        // ── Spending by category (donut + inline drill) ────────────────────
        SliverToBoxAdapter(
          child: data.byCategory.isEmpty
              ? _EmptySection(
                  label:   'SPENDING BY CATEGORY',
                  message: 'No expense transactions in this period',
                )
              : _SpendingSection(
                  data:         data,
                  touchedIdx:   touchedIdx,
                  excludedCats: excludedCats,
                  onTouch:      onTouchedIdxChanged,
                  onExclude:    onExclude,
                ),
        ),

        // ── Budget vs Actual ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: data.budgetVsActual.isEmpty
              ? const SizedBox.shrink()
              : _BudgetVsActualSection(data: data),
        ),

        // ── Monthly income vs expenses trend ────────────────────────────────
        SliverToBoxAdapter(child: _TrendSection(data: data, months: months)),

        // ── Savings rate trend ──────────────────────────────────────────────
        SliverToBoxAdapter(
          child: months > 1
              ? _SavingsRateTrendSection(data: data)
              : const SizedBox.shrink(),
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
// Budget vs Actual
// ---------------------------------------------------------------------------

class _BudgetVsActualSection extends StatefulWidget {
  final ReportsState data;
  const _BudgetVsActualSection({required this.data});

  @override
  State<_BudgetVsActualSection> createState() => _BudgetVsActualSectionState();
}

class _BudgetVsActualSectionState extends State<_BudgetVsActualSection> {
  static const _pageSize = 10;
  bool _showAll = false;

  Color _barColor(BudgetVsActualEntry e, ColorScheme cs) {
    if (e.budgeted == 0) return cs.primary;
    final ratio = e.spent / e.budgeted;
    if (ratio > 1.0) return cs.error;
    if (ratio > 0.85) return const Color(0xFFFF9800);
    return cs.tertiary;
  }

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final fmt       = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final all       = widget.data.budgetVsActual;
    final visible   = _showAll ? all : all.take(_pageSize).toList();
    final remaining = all.length - _pageSize;

    return _Section(
      label: 'BUDGET VS ACTUAL',
      child: Column(
        children: [
          ...visible.map((e) {
          final color      = _barColor(e, cs);
          final fillRatio  = e.budgeted > 0
              ? (e.spent / e.budgeted).clamp(0.0, 1.0)
              : 0.0;
          final pctLabel   = e.budgeted > 0
              ? '${(e.spent / e.budgeted * 100).toStringAsFixed(0)}%'
              : '—';

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.name,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${fmt.format(e.spent)} / ${fmt.format(e.budgeted)}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: e.isOverBudget ? cs.error : cs.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (_, constraints) => ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      height: 8,
                      width: constraints.maxWidth,
                      child: Stack(
                        children: [
                          Container(color: cs.surfaceContainerHighest),
                          FractionallySizedBox(
                            widthFactor: fillRatio,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    color.withValues(alpha: 0.75),
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
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(pctLabel,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10, color: color)),
                    const Spacer(),
                    if (e.isOverBudget)
                      Text(
                        '+${fmt.format(e.spent - e.budgeted)} over',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: cs.error),
                      )
                    else if (e.budgeted > 0)
                      Text(
                        '${fmt.format(e.variance)} left',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
            ),
          );
          }),
          if (!_showAll && all.length > _pageSize)
            TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text('Show $remaining more',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spending by category — donut chart + inline weekly/daily drill
// ---------------------------------------------------------------------------

class _SpendingSection extends StatefulWidget {
  final ReportsState data;
  final int touchedIdx;
  final Set<String> excludedCats;
  final ValueChanged<int> onTouch;
  final void Function(String) onExclude;

  const _SpendingSection({
    required this.data,
    required this.touchedIdx,
    required this.excludedCats,
    required this.onTouch,
    required this.onExclude,
  });

  @override
  State<_SpendingSection> createState() => _SpendingSectionState();
}

class _SpendingSectionState extends State<_SpendingSection> {
  String?    _drillCatId;
  Color?     _drillColor;
  _DrillMode _drillMode = _DrillMode.weekly;

  void _onCategoryTap(CategorySpend cat, Color color) {
    if (cat.categoryId == null) return;
    setState(() {
      if (_drillCatId != cat.categoryId) {
        // New category → open in weekly mode
        _drillCatId = cat.categoryId;
        _drillColor = color;
        _drillMode  = _DrillMode.weekly;
      } else if (_drillMode == _DrillMode.weekly) {
        // Same category, weekly → switch to daily
        _drillMode = _DrillMode.daily;
      } else {
        // Same category, daily → dismiss
        _drillCatId = null;
        _drillColor = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final cats  = widget.data.byCategory;
    final shown = cats.take(9).toList();
    final other = cats.length > 9
        ? cats.skip(9).fold(0.0, (s, c) => s + c.amount)
        : 0.0;
    final allSlices = [
      ...shown,
      if (other > 0) CategorySpend(name: 'Other', amount: other),
    ];

    // Pie uses only non-excluded slices; percentages recalculate accordingly
    final visibleSlices = allSlices
        .where((c) => !widget.excludedCats.contains(c.name))
        .toList();
    final visibleTotal = visibleSlices.fold(0.0, (s, c) => s + c.amount);

    // Map visible index back to original palette index for consistent colours
    final visibleOriginalIndices = allSlices.asMap().entries
        .where((e) => !widget.excludedCats.contains(e.value.name))
        .map((e) => e.key)
        .toList();

    final sections = visibleSlices.asMap().entries.map((e) {
      final vi    = e.key;
      final cat   = e.value;
      final origI = visibleOriginalIndices[vi];
      final pct   = visibleTotal > 0 ? cat.amount / visibleTotal * 100 : 0.0;
      final color = chartPalette[origI % chartPalette.length];
      final isSel = widget.touchedIdx == origI;

      return PieChartSectionData(
        color:  color,
        value:  cat.amount,
        radius: isSel ? 72.0 : 60.0,
        title:  pct >= 6 ? '${pct.toStringAsFixed(0)}%' : '',
        titleStyle: GoogleFonts.plusJakartaSans(
          fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white,
        ),
      );
    }).toList();

    final selCat = (widget.touchedIdx >= 0 && widget.touchedIdx < allSlices.length)
        ? allSlices[widget.touchedIdx]
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
                      touchCallback: (FlTouchEvent event, PieTouchResponse? response) {
                        if (!event.isInterestedForInteractions ||
                            response?.touchedSection == null) {
                          widget.onTouch(-1);
                        } else {
                          widget.onTouch(
                              response!.touchedSection!.touchedSectionIndex);
                        }
                      },
                    ),
                  ),
                  swapAnimationDuration: const Duration(milliseconds: 200),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selCat != null ? selCat.name : 'Total spent',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selCat != null
                          ? fmt.format(selCat.amount)
                          : fmt.format(visibleTotal),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, fontWeight: FontWeight.w800,
                          color: cs.onSurface),
                    ),
                    if (selCat != null && visibleTotal > 0)
                      Text(
                        '${(selCat.amount / visibleTotal * 100).toStringAsFixed(1)}%',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Legend rows — tap to drill (weekly→daily→dismiss), swipe left to exclude
          if (widget.excludedCats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.visibility_off_outlined,
                      size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${widget.excludedCats.length} hidden · tap grayed row to restore',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ...allSlices.asMap().entries.map((e) {
            final i          = e.key;
            final cat        = e.value;
            final isExcluded = widget.excludedCats.contains(cat.name);
            final color      = chartPalette[i % chartPalette.length];
            final isSel      = widget.touchedIdx == i;
            final isDrilled  = _drillCatId == cat.categoryId && cat.categoryId != null;

            final pct     = visibleTotal > 0 && !isExcluded
                ? cat.amount / visibleTotal * 100
                : 0.0;
            final barFrac = visibleTotal > 0 && !isExcluded
                ? cat.amount / visibleTotal
                : 0.0;

            return GestureDetector(
              onTap: () {
                if (isExcluded) {
                  widget.onExclude(cat.name);
                } else {
                  _onCategoryTap(cat, color);
                }
              },
              onHorizontalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -250) {
                  widget.onExclude(cat.name);
                }
              },
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isExcluded ? 0.35 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                  decoration: BoxDecoration(
                    color: (isSel && !isExcluded) || isDrilled
                        ? color.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(
                          color: isExcluded ? cs.onSurfaceVariant : color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(cat.name,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: cs.onSurface)),
                      ),
                      const SizedBox(width: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: SizedBox(
                          width: 80, height: 4,
                          child: LinearProgressIndicator(
                            value: barFrac,
                            backgroundColor: cs.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text(
                          isExcluded ? '—' : '${pct.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 64,
                        child: Text(
                          fmt.format(cat.amount),
                          textAlign: TextAlign.right,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: cs.onSurface),
                        ),
                      ),
                      // Drill icon — shows current drill state for active row
                      if (cat.categoryId != null && !isExcluded)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            isDrilled
                                ? (_drillMode == _DrillMode.weekly
                                    ? Icons.bar_chart_rounded
                                    : Icons.view_day_rounded)
                                : Icons.show_chart_rounded,
                            size: 18,
                            color: isDrilled
                                ? color
                                : cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                        )
                      else
                        const SizedBox(width: 22),
                    ],
                  ),
                ),
              ),
            );
          }),

          // ── Inline drill-down chart (weekly or daily) ──────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _drillCatId == null
                ? const SizedBox.shrink()
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _InlineDrillChart(
                      key: ValueKey('${_drillCatId}_${_drillMode.name}'),
                      dailySpend: widget.data.categoryDailySpend[_drillCatId!] ?? {},
                      drillMode:  _drillMode,
                      color:      _drillColor ?? cs.primary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline drill-down bar chart (weekly or daily) — no bottom sheet
// ---------------------------------------------------------------------------

class _InlineDrillChart extends StatelessWidget {
  /// 'yyyy-MM-dd' → spending amount for the selected category.
  final Map<String, double> dailySpend;
  final _DrillMode drillMode;
  final Color      color;

  const _InlineDrillChart({
    super.key,
    required this.dailySpend,
    required this.drillMode,
    required this.color,
  });

  // ── Bucket builders ────────────────────────────────────────────────────────

  List<({String label, double amount})> _weeklyBuckets() {
    final Map<String, double>   weekAmt  = {};
    final Map<String, DateTime> weekDate = {};
    for (final e in dailySpend.entries) {
      final date = DateTime.parse(e.key);
      // Snap to Monday (ISO week start)
      final mon = date.subtract(Duration(days: date.weekday - 1));
      final key = '${mon.year}-${mon.month.toString().padLeft(2, '0')}'
                  '-${mon.day.toString().padLeft(2, '0')}';
      weekAmt.update(key, (v) => v + e.value, ifAbsent: () => e.value);
      weekDate.putIfAbsent(key, () => mon);
    }
    final keys = weekAmt.keys.toList()..sort();
    return keys.map((k) => (
      label:  DateFormat('MMM d').format(weekDate[k]!),
      amount: weekAmt[k]!,
    )).toList();
  }

  List<({String label, double amount})> _dailyBuckets() {
    final sorted = dailySpend.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted.map((e) => (
      label:  DateFormat('d').format(DateTime.parse(e.key)),
      amount: e.value,
    )).toList();
  }

  static double _ceilNice(double v) {
    if (v <= 0) return 100;
    final step = v < 500 ? 50.0 : v < 2000 ? 100.0 : 500.0;
    return ((v / step).ceil() * step).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final buckets = drillMode == _DrillMode.weekly
        ? _weeklyBuckets()
        : _dailyBuckets();

    if (buckets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text('No data for this period',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: cs.onSurfaceVariant)),
        ),
      );
    }

    final peak  = buckets.map((b) => b.amount).reduce(max);
    final total = buckets.map((b) => b.amount).fold(0.0, (s, b) => s + b);
    final nonZero = buckets.where((b) => b.amount > 0);
    final avg   = nonZero.isEmpty ? 0.0 : total / nonZero.length;
    final yMax  = _ceilNice(peak * 1.15);

    // Bar width & chart width — scroll when many bars
    final n = buckets.length;
    final barW = n <= 6 ? 28.0 : n <= 14 ? 20.0 : 12.0;
    final minChartW = MediaQuery.sizeOf(context).width - 32;
    final chartW = max(minChartW, n * (barW + 6) + 24.0);

    final groups = buckets.asMap().entries.map((e) => BarChartGroupData(
      x: e.key,
      barRods: [
        BarChartRodData(
          toY: e.value.amount,
          width: barW,
          borderRadius: BorderRadius.circular(5),
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.55), color],
            begin: Alignment.bottomCenter,
            end:   Alignment.topCenter,
          ),
        ),
      ],
    )).toList();

    // Skip labels when too crowded
    final labelEvery = n <= 8 ? 1 : n <= 16 ? 2 : n <= 31 ? 5 : 7;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header strip ─────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(
                  drillMode == _DrillMode.weekly
                      ? Icons.bar_chart_rounded
                      : Icons.view_day_rounded,
                  size: 14, color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  drillMode == _DrillMode.weekly ? 'Weekly spend' : 'Daily spend',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w700, color: color),
                ),
                const Spacer(),
                Text(
                  drillMode == _DrillMode.weekly
                      ? 'tap row for daily ›'
                      : 'tap row to close ×',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // ── Bar chart ─────────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartW,
              height: 140,
              child: BarChart(
                BarChartData(
                  maxY:      yMax,
                  barGroups: groups,
                  alignment: BarChartAlignment.spaceAround,
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yMax / 4,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color:       cs.outlineVariant.withValues(alpha: 0.4),
                      strokeWidth: 1,
                      dashArray:   [4, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles:   true,
                        reservedSize: 22,
                        getTitlesWidget: (value, _) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= buckets.length) {
                            return const SizedBox.shrink();
                          }
                          if (idx % labelEvery != 0) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              buckets[idx].label,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10, color: cs.onSurfaceVariant),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => cs.surfaceContainerHigh,
                      getTooltipItem: (group, gi, rod, _) => BarTooltipItem(
                        '${buckets[gi].label}\n${fmt.format(rod.toY)}',
                        GoogleFonts.plusJakartaSans(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: cs.onSurface),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Stats row ─────────────────────────────────────────────────────
          const SizedBox(height: 12),
          Row(
            children: [
              _DrillStat(
                label: drillMode == _DrillMode.weekly ? 'Wk avg' : 'Day avg',
                value: fmt.format(avg),
                color: color,
              ),
              _DrillStat(
                label: drillMode == _DrillMode.weekly ? 'Peak wk' : 'Peak day',
                value: fmt.format(peak),
                color: color,
              ),
              _DrillStat(label: 'Total', value: fmt.format(total), color: color),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _DrillStat extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _DrillStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center),
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
    final cs      = Theme.of(context).colorScheme;
    final fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
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

    final chartW = (months * 56.0).clamp(
        MediaQuery.sizeOf(context).width - 32, double.infinity);

    return _Section(
      label: 'INCOME VS EXPENSES',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles:   true,
                        reservedSize: 48,
                        interval:     yStep,
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
                                    fontSize: 10, color: cs.onSurfaceVariant)),
                          );
                        },
                      ),
                    ),
                    rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                              DateFormat('MMM').format(byMonth[idx].month),
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11, color: cs.onSurfaceVariant),
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
                              fontSize: 11, fontWeight: FontWeight.w600,
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
    final mag  = (v / 4).ceil();
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
// Savings rate trend — line chart
// ---------------------------------------------------------------------------

class _SavingsRateTrendSection extends StatelessWidget {
  final ReportsState data;
  const _SavingsRateTrendSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final byMonth = data.byMonth;
    if (byMonth.isEmpty) return const SizedBox.shrink();

    final rates = byMonth
        .map((m) => m.income > 0 ? m.savingsRate * 100 : 0.0)
        .toList();

    final minRate = rates.reduce(min);
    final maxRate = rates.reduce(max);
    final yMin    = min(minRate - 10, -5.0).clamp(-100.0, 0.0).toDouble();
    final yMax    = max(maxRate + 10, 35.0);

    final spots = rates.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

    final avgRate = rates.reduce((a, b) => a + b) / rates.length;
    final lineColor = avgRate >= 0 ? cs.tertiary : cs.error;

    return _Section(
      label: 'SAVINGS RATE TREND',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avg badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: lineColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Avg ${avgRate.toStringAsFixed(1)}%',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: lineColor),
                ),
              ),
              const SizedBox(width: 10),
              Text('20% = healthy target',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: yMin,
                maxY: yMax,
                clipData: FlClipData.all(),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: lineColor,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                        radius: 4,
                        color: lineColor,
                        strokeWidth: 2,
                        strokeColor: cs.surface,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          lineColor.withValues(alpha: 0.2),
                          lineColor.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end:   Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 20,
                      color: const Color(0xFFFFCA28).withValues(alpha: 0.8),
                      strokeWidth: 1.5,
                      dashArray: [6, 4],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.topRight,
                        labelResolver: (_) => '20%',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFFCA28),
                        ),
                      ),
                    ),
                    if (yMin < 0)
                      HorizontalLine(
                        y: 0,
                        color: cs.outlineVariant,
                        strokeWidth: 1,
                      ),
                  ],
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (yMax - yMin) / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color:       cs.outlineVariant.withValues(alpha: 0.3),
                    strokeWidth: 1,
                    dashArray:   [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles:   true,
                      reservedSize: 40,
                      interval:     (yMax - yMin) / 4,
                      getTitlesWidget: (value, _) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          '${value.toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10, color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                  rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles:   true,
                      reservedSize: 24,
                      getTitlesWidget: (value, _) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= byMonth.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('MMM').format(byMonth[idx].month),
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => cs.surfaceContainerHigh,
                    getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(1)}%',
                      GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: lineColor),
                    )).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
                              fontSize: 13, fontWeight: FontWeight.w500,
                              color: cs.onSurface),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(fmt.format(p.amount),
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w700,
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
                          Container(color: cs.surfaceContainerHighest),
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
