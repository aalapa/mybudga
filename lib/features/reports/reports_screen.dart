import 'dart:ui' as ui;
import 'dart:math' show max, min;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Drag-to-reorder over the section list. A separate sheet rather than drag
/// handles inline, matching how group reordering already works elsewhere and
/// avoiding a drag gesture competing with the accordion taps.
class _ReorderSectionsSheet extends StatefulWidget {
  final List<_RSection> order;
  final ValueChanged<List<_RSection>> onDone;
  const _ReorderSectionsSheet({required this.order, required this.onDone});

  @override
  State<_ReorderSectionsSheet> createState() => _ReorderSectionsSheetState();
}

class _ReorderSectionsSheetState extends State<_ReorderSectionsSheet> {
  late final List<_RSection> _list = List.of(widget.order);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
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
          Text('Reorder sections',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface)),
          const SizedBox(height: 4),
          Text('Drag to change the order reports appear in.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          Flexible(
            child: ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              onReorder: (oldIdx, newIdx) => setState(() {
                if (newIdx > oldIdx) newIdx -= 1;
                _list.insert(newIdx, _list.removeAt(oldIdx));
              }),
              children: [
                for (int i = 0; i < _list.length; i++)
                  ReorderableDragStartListener(
                    key: ValueKey(_list[i].name),
                    index: i,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.drag_handle,
                          size: 20,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                      title: Text(_list[i].title,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: cs.onSurface)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              widget.onDone(_list);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Accordion shell
// ---------------------------------------------------------------------------

/// The report sections, in their default order. Stored by name so a saved
/// order survives adding or removing sections.
enum _RSection {
  netWorth('Net worth'),
  summary('Summary'),
  spending('Spending by category'),
  budgetVsActual('Budget vs actual'),
  trend('Income vs expenses'),
  savingsRate('Savings rate'),
  budgetHealth('Budget health'),
  tiers('Committed vs free'),
  payees('Top payees');

  const _RSection(this.title);
  final String title;
}

/// Marks that a section is being rendered inside an accordion, so [_Section]
/// drops its own heading and rule — the slot draws those.
class _InAccordion extends InheritedWidget {
  const _InAccordion({required super.child});
  static bool of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_InAccordion>() != null;
  @override
  bool updateShouldNotify(_InAccordion _) => false;
}

/// One collapsible section. Only one is open at a time: with nine sections
/// the page was a long scroll of charts, and opening one thing meant
/// scrolling past everything above it.
class _AccordionSlot extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  const _AccordionSlot({
    required this.title,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(
            height: 1, color: cs.outlineVariant.withValues(alpha: 0.55)),
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: expanded ? FontWeight.w700 : FontWeight.w600,
                      color: expanded ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more,
                      size: 20, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? _InAccordion(child: child)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Report window. Kept as intent rather than a bare month count because YTD
/// resolves to whatever month it currently is — in March that is 3, in June 6
/// — which would collide with the fixed windows and light two chips at once.
enum _Period {
  mtd,
  m3,
  m6,
  m12,
  ytd;

  /// Months back from the start of the current month, which is how the
  /// provider windows its query.
  int get months => switch (this) {
        _Period.mtd => 1,
        _Period.m3  => 3,
        _Period.m6  => 6,
        _Period.m12 => 12,
        // January YTD is one month, December YTD is twelve.
        _Period.ytd => DateTime.now().month,
      };

  String get label => switch (this) {
        _Period.mtd => 'MTD',
        _Period.m3  => '3M',
        _Period.m6  => '6M',
        _Period.m12 => '12M',
        _Period.ytd => 'YTD',
      };
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  // Year to date by default: the window people actually reason about, and
  // wide enough for the multi-month sections to have something to say.
  _Period     _period       = _Period.ytd;

  // Order and open-state are device-local, like the sidebar and account
  // groups — a layout preference, not household data.
  static const _kOrderKey = 'reports_section_order';
  List<_RSection> _order = List.of(_RSection.values);
  _RSection? _open = _RSection.values.first;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kOrderKey);
    if (saved == null || !mounted) return;
    // Rebuilt against the enum so a saved order survives sections being
    // added or removed: unknown names drop out, new ones append.
    final byName = {for (final s in _RSection.values) s.name: s};
    final restored = <_RSection>[
      for (final n in saved)
        if (byName[n] != null) byName[n]!,
    ];
    for (final s in _RSection.values) {
      if (!restored.contains(s)) restored.add(s);
    }
    setState(() => _order = restored);
  }

  Future<void> _persistOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kOrderKey, [for (final s in _order) s.name]);
  }

  void _toggleSection(_RSection sec) =>
      setState(() => _open = _open == sec ? null : sec);

  Future<void> _showReorderSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReorderSectionsSheet(
        order: List.of(_order),
        onDone: (next) {
          setState(() => _order = next);
          _persistOrder();
        },
      ),
    );
  }
  int         _touchedIdx   = -1;
  Set<String> _excludedCats = {};

  void _showDeepDive(
      BuildContext context, ReportsState data, CategorySpend cat, Color color) {
    final daily = data.categoryDailySpend[cat.categoryId] ?? {};
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryDeepDiveSheet(
        category:   cat,
        dailySpend: daily,
        color:      color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final async = ref.watch(reportsProvider(_period.months));

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // Show what actually failed. A bare "could not load" gives no way to
          // tell a missing column from a dropped connection.
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: cs.error),
                  const SizedBox(height: 12),
                  Text('Could not load reports',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const SizedBox(height: 8),
                  SelectableText(
                    e.toString(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(reportsProvider(_period.months)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (data) => _ReportsBody(
            data:       data,
            period:     _period,
            months:     _period.months,
            order:           _order,
            openSection:     _open,
            onToggleSection: _toggleSection,
            onReorder:       _showReorderSheet,
            touchedIdx: _touchedIdx,
            onPeriodChanged:     (p) => setState(() {
              _period = p; _touchedIdx = -1; _excludedCats = {};
            }),
            onTouchedIdxChanged: (i) => setState(() => _touchedIdx = i),
            onDrillDown:         (cat, color) => _showDeepDive(context, data, cat, color),
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
  final _Period period;
  final ValueChanged<_Period> onPeriodChanged;
  final List<_RSection> order;
  final _RSection? openSection;
  final ValueChanged<_RSection> onToggleSection;
  final VoidCallback onReorder;
  final ValueChanged<int> onTouchedIdxChanged;
  final void Function(CategorySpend, Color) onDrillDown;
  final void Function(String) onExclude;

  const _ReportsBody({
    required this.data,
    required this.months,
    required this.touchedIdx,
    required this.excludedCats,
    required this.period,
    required this.onPeriodChanged,
    required this.order,
    required this.openSection,
    required this.onToggleSection,
    required this.onReorder,
    required this.onTouchedIdxChanged,
    required this.onDrillDown,
    required this.onExclude,
  });

  /// Null when a section has nothing worth showing for this period.
  Widget? _bodyFor(_RSection sec) => switch (sec) {
        _RSection.netWorth => _NetWorthSection(data: data),
        _RSection.summary  => _SummarySection(data: data, months: months),
        _RSection.spending => data.byCategory.isEmpty
            ? const _EmptySection(
                label:   'SPENDING BY CATEGORY',
                message: 'No expense transactions in this period',
              )
            : _SpendingSection(
                data:         data,
                touchedIdx:   touchedIdx,
                excludedCats: excludedCats,
                onTouch:      onTouchedIdxChanged,
                onDrillDown:  onDrillDown,
                onExclude:    onExclude,
              ),
        _RSection.budgetVsActual =>
          data.budgetVsActual.isEmpty ? null : _BudgetVsActualSection(data: data),
        _RSection.trend       => _TrendSection(data: data, months: months),
        _RSection.savingsRate =>
          months > 1 ? _SavingsRateTrendSection(data: data) : null,
        _RSection.budgetHealth => _BudgetHealthSection(data: data),
        _RSection.tiers        => _SpendingTierSection(data: data),
        _RSection.payees =>
          data.topPayees.isEmpty ? null : _PayeesSection(data: data),
      };

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
                _PeriodSelector(period: period, onChanged: onPeriodChanged),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onReorder,
                    icon: const Icon(Icons.swap_vert, size: 16),
                    label: Text('Reorder',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),

        // ── Sections, in the user's order, one open at a time ───────────────
        ...order.map((sec) {
          final body = _bodyFor(sec);
          // Sections with nothing to show are skipped entirely rather than
          // offering a header that opens onto blank space.
          if (body == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
          return SliverToBoxAdapter(
            child: _AccordionSlot(
              title:    sec.title,
              expanded: openSection == sec,
              onToggle: () => onToggleSection(sec),
              child:    body,
            ),
          );
        }),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Period selector
// ---------------------------------------------------------------------------

class _PeriodSelector extends StatelessWidget {
  final _Period period;
  final ValueChanged<_Period> onChanged;

  const _PeriodSelector({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: _Period.values.map((p) {
        final selected = period == p;
        final label    = p.label;
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 2),
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
      // First section on the page — the header above it is separation enough.
      showDivider: false,
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
            if (data.netWorthByMonth.length > 1) ...[
              const SizedBox(height: 16),
              _NetWorthTrend(points: data.netWorthByMonth),
            ],
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

/// Reconstructed net worth over time, with the movement split into money
/// saved and debt paid down — very different things that a single line hides.
class _NetWorthTrend extends StatelessWidget {
  final List<NetWorthPoint> points;
  const _NetWorthTrend({required this.points});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.compactCurrency(symbol: '\$', decimalDigits: 0);
    final full = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final vals = points.map((p) => p.netWorth).toList();
    final lo   = vals.reduce(min);
    final hi   = vals.reduce(max);
    final pad  = ((hi - lo).abs() * 0.15).clamp(1.0, double.infinity);
    final yMin = lo - pad;
    final yMax = hi + pad;

    final first  = points.first;
    final last   = points.last;
    final change = last.netWorth - first.netWorth;
    final saved  = last.assets - first.assets;
    final paid   = first.liabilities - last.liabilities;
    final up     = change >= 0;
    final line   = up ? cs.tertiary : cs.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(up ? Icons.trending_up : Icons.trending_down,
                size: 16, color: line),
            const SizedBox(width: 6),
            Text('${up ? '+' : '−'}${full.format(change.abs())}',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w800, color: line)),
            const SizedBox(width: 6),
            Text('over ${points.length} months',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${saved >= 0 ? 'Saved' : 'Drew down'} '
          '${full.format(saved.abs())} · '
          '${paid >= 0 ? 'paid down' : 'took on'} '
          '${full.format(paid.abs())} of debt',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11, color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 150,
          child: LineChart(
            LineChartData(
              minY: yMin,
              maxY: yMax,
              clipData: FlClipData.all(),
              lineBarsData: [
                LineChartBarData(
                  spots: vals
                      .asMap()
                      .entries
                      .map((e) => FlSpot(e.key.toDouble(), e.value))
                      .toList(),
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: line,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: points.length <= 13,
                    getDotPainter: (sp, pct, bar, idx) => FlDotCirclePainter(
                      radius: 3.5,
                      color: line,
                      strokeWidth: 2,
                      strokeColor: cs.surface,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        line.withValues(alpha: 0.20),
                        line.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: (yMax - yMin) / 3,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    interval: (yMax - yMin) / 3,
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(fmt.format(v),
                          textAlign: TextAlign.right,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10, color: cs.onSurfaceVariant)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length) {
                        return const SizedBox.shrink();
                      }
                      // Thin the labels so a 12-month window stays readable.
                      final step = (points.length / 6).ceil();
                      if (i % step != 0 && i != points.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return Text(DateFormat('MMM').format(points[i].month),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 10, color: cs.onSurfaceVariant));
                    },
                  ),
                ),
              ),
              lineTouchData: const LineTouchData(enabled: false),
            ),
          ),
        ),
        const SizedBox(height: 18),
      ],
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
// Spending by category — donut chart, tapping a row opens bottom-sheet drill
// ---------------------------------------------------------------------------

class _SpendingSection extends StatelessWidget {
  final ReportsState data;
  final int touchedIdx;
  final Set<String> excludedCats;
  final ValueChanged<int> onTouch;
  final void Function(CategorySpend, Color) onDrillDown;
  final void Function(String) onExclude;

  const _SpendingSection({
    required this.data,
    required this.touchedIdx,
    required this.excludedCats,
    required this.onTouch,
    required this.onDrillDown,
    required this.onExclude,
  });

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final cats  = data.byCategory;
    final shown = cats.take(9).toList();
    final other = cats.length > 9
        ? cats.skip(9).fold(0.0, (s, c) => s + c.amount)
        : 0.0;
    final allSlices = [
      ...shown,
      if (other > 0) CategorySpend(name: 'Other', amount: other),
    ];

    final visibleSlices = allSlices
        .where((c) => !excludedCats.contains(c.name))
        .toList();
    final visibleTotal = visibleSlices.fold(0.0, (s, c) => s + c.amount);

    final visibleOriginalIndices = allSlices.asMap().entries
        .where((e) => !excludedCats.contains(e.value.name))
        .map((e) => e.key)
        .toList();

    final sections = visibleSlices.asMap().entries.map((e) {
      final vi    = e.key;
      final cat   = e.value;
      final origI = visibleOriginalIndices[vi];
      final pct   = visibleTotal > 0 ? cat.amount / visibleTotal * 100 : 0.0;
      final color = chartPalette[origI % chartPalette.length];
      final isSel = touchedIdx == origI;

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
                      touchCallback: (FlTouchEvent event, PieTouchResponse? response) {
                        if (!event.isInterestedForInteractions ||
                            response?.touchedSection == null) {
                          onTouch(-1);
                        } else {
                          onTouch(response!.touchedSection!.touchedSectionIndex);
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

          // Legend rows — tap to open bottom-sheet drill, swipe left to exclude
          if (excludedCats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.visibility_off_outlined,
                      size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('${excludedCats.length} hidden · tap grayed row to restore',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ...allSlices.asMap().entries.map((e) {
            final i          = e.key;
            final cat        = e.value;
            final isExcluded = excludedCats.contains(cat.name);
            final color      = chartPalette[i % chartPalette.length];
            final isSel      = touchedIdx == i;
            final canDrill   = cat.categoryId != null;

            final pct     = visibleTotal > 0 && !isExcluded
                ? cat.amount / visibleTotal * 100
                : 0.0;
            final barFrac = visibleTotal > 0 && !isExcluded
                ? cat.amount / visibleTotal
                : 0.0;

            return GestureDetector(
              onTap: () {
                if (isExcluded) {
                  onExclude(cat.name);
                } else if (canDrill) {
                  onDrillDown(cat, color);
                }
              },
              onHorizontalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -250) {
                  onExclude(cat.name);
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
                    color: isSel && !isExcluded
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
                      if (canDrill && !isExcluded)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.show_chart_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
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
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category deep-dive bottom sheet  — weekly → daily → close on tap
// ---------------------------------------------------------------------------

class _CategoryDeepDiveSheet extends StatefulWidget {
  final CategorySpend       category;
  final Map<String, double> dailySpend; // 'yyyy-MM-dd' → amount
  final Color               color;

  const _CategoryDeepDiveSheet({
    required this.category,
    required this.dailySpend,
    required this.color,
  });

  @override
  State<_CategoryDeepDiveSheet> createState() => _CategoryDeepDiveSheetState();
}

class _CategoryDeepDiveSheetState extends State<_CategoryDeepDiveSheet> {
  _DrillMode _mode = _DrillMode.weekly;

  void _onModeTap() {
    if (_mode == _DrillMode.weekly) {
      setState(() => _mode = _DrillMode.daily);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header — category name + total
          Row(
            children: [
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                    color: widget.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.category.name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 18, fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
              ),
              Text(fmt.format(widget.category.amount),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 10),

          // Mode chip — tap to cycle: weekly → daily → close
          GestureDetector(
            onTap: _onModeTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: widget.color.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _mode == _DrillMode.weekly
                        ? Icons.bar_chart_rounded
                        : Icons.view_day_rounded,
                    size: 14, color: widget.color,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _mode == _DrillMode.weekly
                        ? 'Weekly  ·  tap for daily view'
                        : 'Daily  ·  tap to close',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: widget.color),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Chart — reuses _DrillChart (no inline header)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _DrillChart(
              key:        ValueKey(_mode),
              dailySpend: widget.dailySpend,
              drillMode:  _mode,
              color:      widget.color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared weekly / daily bar chart used inside the bottom sheet
// ---------------------------------------------------------------------------

class _DrillChart extends StatelessWidget {
  /// 'yyyy-MM-dd' → spending amount for the selected category.
  final Map<String, double> dailySpend;
  final _DrillMode drillMode;
  final Color      color;

  const _DrillChart({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // ── Bar chart ─────────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: chartW,
              height: 200,
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

// ---------------------------------------------------------------------------
// Budget health — is the budget itself working, not just what was spent
// ---------------------------------------------------------------------------

class _BudgetHealthSection extends StatefulWidget {
  final ReportsState data;
  const _BudgetHealthSection({required this.data});

  @override
  State<_BudgetHealthSection> createState() => _BudgetHealthSectionState();
}

class _BudgetHealthSectionState extends State<_BudgetHealthSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final withSignal =
        widget.data.categoryHealth.where((h) => h.hasSignal).toList();

    if (withSignal.isEmpty) {
      return const _EmptySection(
        label: 'Budget health',
        message:
            'Needs at least three months of budgeting in a category before a '
            'pattern can be told from noise.',
      );
    }

    final offTarget = withSignal.where((h) => !h.isOnTarget).length;
    final shown     = _showAll ? withSignal : withSignal.take(5).toList();
    final remaining = withSignal.length - shown.length;

    return _Section(
      label: 'Budget health',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            offTarget == 0
                ? 'Every budgeted category lands within 10% of its number.'
                : '$offTarget of ${withSignal.length} categories consistently '
                    'miss their number. Sorted by how much attention they want.',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          ...shown.map((h) => _HealthRow(health: h)),
          if (remaining > 0)
            TextButton(
              onPressed: () => setState(() => _showAll = true),
              child: Text('Show $remaining more',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  final CategoryHealth health;
  const _HealthRow({required this.health});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    final biasPct = (health.medianBias * 100).round().abs();
    final Color biasColor;
    final String biasText;
    if (health.isOnTarget) {
      biasColor = cs.tertiary;
      biasText  = 'on target';
    } else if (health.budgetsLow) {
      biasColor = cs.error;
      biasText  = '$biasPct% low';
    } else {
      biasColor = cs.onSurfaceVariant;
      biasText  = '$biasPct% high';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(health.name,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: biasColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(biasText,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: biasColor)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 2,
            children: [
              if (health.overspendMonths > 0)
                _HealthFact(
                  'over ${health.overspendMonths} of ${health.monthsBudgeted} months'
                  '${health.avgOverspend > 0 ? ' · avg ${fmt.format(health.avgOverspend)}' : ''}',
                  cs.error,
                ),
              _HealthFact(
                  '${health.predictability.label} · ${health.predictability.advice}',
                  cs.onSurfaceVariant),
              if (!health.isOnTarget && health.suggestedBudget > 0)
                _HealthFact(
                    'try ${fmt.format(health.suggestedBudget)}', cs.primary),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthFact extends StatelessWidget {
  final String text;
  final Color color;
  const _HealthFact(this.text, this.color);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: color),
      );
}

// ---------------------------------------------------------------------------
// Committed vs free — outflow split by how much choice you have over it
// ---------------------------------------------------------------------------

/// Whole percents that sum to exactly 100.
///
/// Rounding each share on its own lands on 99 or 101 whenever the fractions
/// straddle a half — three thirds round to 33 each and visibly lose a point.
/// Largest remainder instead: floor everything, then hand the leftover points
/// to the largest fractional parts. Zero stays zero.
List<int> _wholePercents(List<double> parts) {
  final total = parts.fold(0.0, (s, v) => s + v);
  if (total <= 0) return List.filled(parts.length, 0);

  final exact  = [for (final v in parts) v / total * 100];
  final result = [for (final v in exact) v.floor()];
  var leftover = 100 - result.fold(0, (s, v) => s + v);

  final order = [for (var i = 0; i < exact.length; i++) i]
    ..sort((a, b) =>
        (exact[b] - result[b]).compareTo(exact[a] - result[a]));

  for (var i = 0; leftover > 0 && i < order.length; i++, leftover--) {
    result[order[i]]++;
  }
  return result;
}

const _tierColors = <SpendingTier, Color>{
  SpendingTier.fixed:         Color(0xFF6C63FF),
  SpendingTier.essential:     Color(0xFF42A5F5),
  SpendingTier.discretionary: Color(0xFF00BFA5),
};

class _SpendingTierSection extends ConsumerStatefulWidget {
  final ReportsState data;
  const _SpendingTierSection({required this.data});

  @override
  ConsumerState<_SpendingTierSection> createState() =>
      _SpendingTierSectionState();
}

class _SpendingTierSectionState extends ConsumerState<_SpendingTierSection> {
  late bool _editing;

  @override
  void initState() {
    super.initState();
    // Nothing classified yet means the split is a guess, so lead with the
    // editor rather than making the reader hunt for it.
    _editing = widget.data.groupTiers.every((g) => g.isDefault);
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final data = widget.data;
    final fmt  = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    if (data.byTierMonth.isEmpty || data.classifiedOutflow <= 0) {
      return const _EmptySection(
        label: 'Committed vs free',
        message: 'No categorised spending in this period yet.',
      );
    }

    final unconfirmed = data.groupTiers.where((g) => g.isDefault).length;
    // Same apportionment as the month rows, so the headline reaches 100 too
    // and agrees with the sentence beneath it.
    final periodPcts = _wholePercents(
        [for (final t in SpendingTier.values) data.tierTotal(t)]);
    // Every group still on its default guess means the split carries no
    // information — showing "100% essential" as though it were a finding is
    // worse than admitting nothing has been classified.
    final allGuessed = data.groupTiers.isNotEmpty &&
        unconfirmed == data.groupTiers.length;

    return _Section(
      label: 'Committed vs free',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (allGuessed) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune, size: 15, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Not classified yet',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your group names did not match anything recognisable, so '
                    'all ${data.groupTiers.length} landed on the same default. '
                    'A split built on that would say nothing, so it is hidden '
                    'until you set them below — once, and it holds.',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // ── Period headline ──────────────────────────────────────────────
          if (!allGuessed)
          Row(
            children: [
              for (final t in SpendingTier.values) ...[
                Expanded(
                  // Inset every column the same, so the first does not sit
                  // flush against the section edge while the last trails
                  // slack and the row reads shifted left.
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, right: 10),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: _tierColors[t],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(t.label,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${periodPcts[t.index]}%',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface)),
                      Text(fmt.format(data.tierTotal(t)),
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (!allGuessed) const SizedBox(height: 6),
          if (!allGuessed)
            Text(
              'Of every dollar that left, '
              '${periodPcts[SpendingTier.discretionary.index]}c '
              'was genuinely yours to choose.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: cs.onSurfaceVariant),
            ),
          if (!allGuessed) const SizedBox(height: 18),

          // ── Month-by-month share ─────────────────────────────────────────
          if (!allGuessed) Text('SHARE BY MONTH',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: cs.onSurfaceVariant)),
          if (!allGuessed) const SizedBox(height: 10),
          if (!allGuessed) _TierMonthChart(months: data.byTierMonth),

          const SizedBox(height: 14),
          // ── Classification ───────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _editing = !_editing),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(_editing ? Icons.expand_less : Icons.tune,
                      size: 15, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      unconfirmed > 0
                          ? 'How groups are classified · $unconfirmed guessed'
                          : 'How groups are classified',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_editing) ...[
            const SizedBox(height: 4),
            Text(
              'Recurring is not the same as obligatory, so this is not '
              'inferred. Groups start from a guess based on their name — '
              'correct any that are wrong.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            ...data.groupTiers.map((g) => _GroupTierRow(group: g)),
          ],
        ],
      ),
    );
  }
}

/// Share by month as three bars per month with a trend line per tier.
///
/// Drawn directly rather than with fl_chart: overlaying a line series on a bar
/// chart there means two widgets with independently computed x-positions, and
/// bar groups do not land on the line's x coordinates. One painter keeps the
/// lines registered to the bars they connect.
class _TierMonthChart extends StatefulWidget {
  final List<TierMonth> months;
  const _TierMonthChart({required this.months});

  @override
  State<_TierMonthChart> createState() => _TierMonthChartState();
}

class _TierMonthChartState extends State<_TierMonthChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final fmt  = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final live = widget.months.where((m) => m.total > 0).toList();
    if (live.isEmpty) return const SizedBox.shrink();

    final pcts = [
      for (final m in live)
        _wholePercents([for (final t in SpendingTier.values) m.amountOf(t)]),
    ];

    // Headroom above the tallest bar so the trend line is not clipped.
    var top = 0;
    for (final p in pcts) {
      for (final v in p) {
        if (v > top) top = v;
      }
    }
    final maxY = ((top / 10).ceil() * 10).clamp(30, 100).toDouble();

    final idx = (_selected ?? live.length - 1).clamp(0, live.length - 1);
    final sel = live[idx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Figures for the highlighted month, since bars cannot carry labels
        // at this density.
        Text(DateFormat('MMMM yyyy').format(sel.month),
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 14,
          runSpacing: 2,
          children: [
            for (final t in SpendingTier.values)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _tierColors[t],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${t.label} ${pcts[idx][t.index]}%  '
                    '${fmt.format(sel.amountOf(t))}',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (ctx, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              const gutter = 30.0;
              final plotW = box.maxWidth - gutter;
              if (plotW <= 0) return;
              final i = ((d.localPosition.dx - gutter) / (plotW / live.length))
                  .floor();
              if (i >= 0 && i < live.length) setState(() => _selected = i);
            },
            child: CustomPaint(
              size: Size(box.maxWidth, 180),
              painter: _TierChartPainter(
                months:    live,
                pcts:      pcts,
                maxY:      maxY,
                selected:  idx,
                grid:      cs.outlineVariant.withValues(alpha: 0.35),
                axisText:  cs.onSurfaceVariant,
                highlight: cs.onSurface.withValues(alpha: 0.06),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TierChartPainter extends CustomPainter {
  final List<TierMonth> months;
  final List<List<int>> pcts;
  final double maxY;
  final int selected;
  final Color grid;
  final Color axisText;
  final Color highlight;

  const _TierChartPainter({
    required this.months,
    required this.pcts,
    required this.maxY,
    required this.selected,
    required this.grid,
    required this.axisText,
    required this.highlight,
  });

  static const _gutter = 30.0; // y labels
  static const _footer = 18.0; // month labels

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTWH(
        _gutter, 0, size.width - _gutter, size.height - _footer);
    if (plot.width <= 0 || plot.height <= 0) return;

    double yOf(num v) => plot.bottom - (v / maxY) * plot.height;

    // Gridlines and their labels.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var v = 0.0; v <= maxY; v += maxY / 4) {
      final y = yOf(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(canvas, '${v.round()}%', Offset(_gutter - 6, y),
          axisText, 10, alignRight: true, centreY: true);
    }

    final slot = plot.width / months.length;
    // Three bars per slot, sharing 62% of it so months stay visually apart.
    final barW = (slot * 0.62) / SpendingTier.values.length;

    // Highlight behind the selected month.
    canvas.drawRect(
      Rect.fromLTWH(plot.left + slot * selected, plot.top, slot, plot.height),
      Paint()..color = highlight,
    );

    for (var i = 0; i < months.length; i++) {
      final centre = plot.left + slot * i + slot / 2;
      final groupW = barW * SpendingTier.values.length;
      for (final t in SpendingTier.values) {
        final v = pcts[i][t.index].toDouble();
        final x = centre - groupW / 2 + barW * t.index;
        final r = RRect.fromRectAndCorners(
          Rect.fromLTRB(x + 0.5, yOf(v), x + barW - 0.5, plot.bottom),
          topLeft: const Radius.circular(2),
          topRight: const Radius.circular(2),
        );
        canvas.drawRRect(r, Paint()..color = _tierColors[t]!);
      }

      // Month label, thinned so a full year stays legible.
      final step = (months.length / 6).ceil();
      if (i % step == 0 || i == months.length - 1) {
        _text(canvas, DateFormat('MMM').format(months[i].month),
            Offset(centre, size.height - _footer + 4), axisText, 10,
            centreX: true);
      }
    }

    // One trend line per tier, through the top of each of its bars.
    for (final t in SpendingTier.values) {
      final path = Path();
      for (var i = 0; i < months.length; i++) {
        final centre = plot.left + slot * i + slot / 2;
        final groupW = barW * SpendingTier.values.length;
        final x = centre - groupW / 2 + barW * t.index + barW / 2;
        final y = yOf(pcts[i][t.index].toDouble());
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = _tierColors[t]!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (var i = 0; i < months.length; i++) {
        final centre = plot.left + slot * i + slot / 2;
        final groupW = barW * SpendingTier.values.length;
        final x = centre - groupW / 2 + barW * t.index + barW / 2;
        canvas.drawCircle(Offset(x, yOf(pcts[i][t.index].toDouble())), 2.0,
            Paint()..color = _tierColors[t]!);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset at, Color color, double size,
      {bool alignRight = false, bool centreX = false, bool centreY = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: GoogleFonts.plusJakartaSans(fontSize: size, color: color)),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(
        alignRight ? at.dx - tp.width : centreX ? at.dx - tp.width / 2 : at.dx,
        centreY ? at.dy - tp.height / 2 : at.dy,
      ),
    );
  }

  @override
  bool shouldRepaint(_TierChartPainter old) =>
      old.selected != selected ||
      old.maxY != maxY ||
      old.months.length != months.length;
}

class _GroupTierRow extends ConsumerWidget {
  final GroupTier group;
  const _GroupTierRow({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(group.name,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: cs.onSurface)),
                ),
                if (group.isDefault) ...[
                  const SizedBox(width: 6),
                  Text('guessed',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7))),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          for (final t in SpendingTier.values)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Tooltip(
                message: t.blurb,
                child: InkWell(
                  onTap: () => setGroupSpendingTier(ref, group.id, t),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: group.tier == t
                          ? _tierColors[t]!.withValues(alpha: 0.18)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: group.tier == t
                            ? _tierColors[t]!
                            : cs.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      t.label.substring(0, 1),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: group.tier == t
                            ? _tierColors[t]
                            : cs.onSurfaceVariant,
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
}

class _EmptySection extends StatelessWidget {
  final String label;
  final String message;
  final bool showDivider;
  const _EmptySection({
    required this.label,
    required this.message,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Section(
      label: label,
      showDivider: showDivider,
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

  /// Hairline above the label marking a new section. The page runs to ten of
  /// these and several end in a chart, where the next section's small label
  /// alone was not enough of a break. Off for the first one, which already
  /// sits below the page header.
  final bool showDivider;

  const _Section({
    required this.label,
    required this.child,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Inside an accordion the slot already drew the heading and the rule.
    if (_InAccordion.of(context)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: child,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showDivider) ...[
            Divider(
                height: 1, color: cs.outlineVariant.withValues(alpha: 0.55)),
            const SizedBox(height: 18),
          ],
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
