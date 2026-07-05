import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../shared/models/account.dart';
import '../../shared/models/transaction.dart';
import '../accounts/accounts_provider.dart';
import '../budget/budget_provider.dart';
import '../reports/reports_provider.dart';
import '../transactions/transactions_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs       = Theme.of(context).colorScheme;
    final budget   = ref.watch(budgetProvider).valueOrNull;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? [];
    final txns     = ref.watch(transactionsProvider).valueOrNull ?? [];
    final report1  = ref.watch(reportsProvider(1)).valueOrNull;
    final report3  = ref.watch(reportsProvider(3)).valueOrNull;

    final tbb          = budget?.tbb ?? 0.0;
    final lifetimeRate = ref.watch(lifetimeSavingsRateProvider).valueOrNull;

    double assets = 0, liabilities = 0;
    for (final a in accounts.where((a) => a.isActive)) {
      switch (a.type) {
        case AccountType.checking:
        case AccountType.savings:
        case AccountType.cash:
        case AccountType.investment:
        case AccountType.asset:
          assets += a.balance.clamp(0, double.infinity);
        case AccountType.creditCard:
        case AccountType.lineOfCredit:
        case AccountType.loan:
        case AccountType.mortgage:
          if (a.balance < 0) liabilities += a.balance.abs();
      }
    }
    final netWorth    = assets - liabilities;
    final savingsRate = report1?.savingsRate ?? 0.0;
    final recentTxns  = txns.where((t) => !t.isPendingReview).take(7).toList();
    final topCats     = report1?.byCategory.take(6).toList() ?? [];

    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Text('Overview',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 28, fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
              Text(DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: cs.onSurfaceVariant)),
              const SizedBox(height: 28),

              // ── Stat cards ────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(child: _StatCard(
                    label: 'To Be Budgeted',
                    value: fmt.format(tbb),
                    icon: Icons.account_balance_wallet_outlined,
                    color: tbb < 0 ? cs.error : cs.primary,
                    sub: tbb < 0 ? 'Over-assigned' : 'Ready to assign',
                  )),
                  const SizedBox(width: 16),
                  Expanded(child: _StatCard(
                    label: 'Net Worth',
                    value: fmt.format(netWorth),
                    icon: Icons.trending_up_outlined,
                    color: cs.tertiary,
                    sub: '${fmt.format(assets)} assets',
                  )),
                  const SizedBox(width: 16),
                  Expanded(child: _SavingsRateCard(
                    monthly:  savingsRate,
                    lifetime: lifetimeRate,
                  )),
                ],
              ),
              const SizedBox(height: 20),

              // ── Middle row ────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _DashCard(
                      title: 'RECENT TRANSACTIONS',
                      child: recentTxns.isEmpty
                          ? _emptyHint(cs, 'No transactions yet')
                          : Column(
                              children: recentTxns.map((tx) =>
                                  _RecentTxRow(tx: tx)).toList(),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _DashCard(
                      title: 'SPENDING THIS MONTH',
                      child: topCats.isEmpty
                          ? _emptyHint(cs, 'No spending data yet')
                          : Column(
                              children: topCats.asMap().entries.map((e) {
                                final cat   = e.value;
                                final total = report1?.totalExpenses ?? 1;
                                final pct   = total > 0 ? cat.amount / total : 0.0;
                                return _SpendingCatRow(
                                  name:    cat.name,
                                  amount:  cat.amount,
                                  pct:     pct,
                                  color:   chartPalette[e.key % chartPalette.length],
                                  fmt:     fmt,
                                );
                              }).toList(),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Cashflow chart ────────────────────────────────────────────
              if (report3 != null && report3.byMonth.isNotEmpty)
                _DashCard(
                  title: 'CASHFLOW — LAST 3 MONTHS',
                  child: SizedBox(
                    height: 180,
                    child: _CashflowChart(byMonth: report3.byMonth),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyHint(ColorScheme cs, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(text,
          style: GoogleFonts.plusJakartaSans(color: cs.onSurfaceVariant)),
    ),
  );
}

// ---------------------------------------------------------------------------
// Stat card (TBB / Net Worth / Savings Rate)
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  final String    label;
  final String    value;
  final IconData  icon;
  final Color     color;
  final String    sub;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Text(value,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface)),
          Text(sub,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Savings Rate card — monthly + lifetime side by side, centered
// ---------------------------------------------------------------------------

class _SavingsRateCard extends StatelessWidget {
  final double  monthly;
  final double? lifetime;

  const _SavingsRateCard({required this.monthly, this.lifetime});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final color = monthly < 0 ? cs.error : cs.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Icon row ──────────────────────────────────────────────────
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.savings_outlined, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          // ── Label ─────────────────────────────────────────────────────
          Text('Savings Rate',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          const SizedBox(height: 8),
          // ── Two-rate row ───────────────────────────────────────────────
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(child: _RateColumn(
                  rate:  monthly,
                  label: 'This month',
                  color: color,
                )),
                if (lifetime != null) ...[
                  VerticalDivider(
                    width: 24,
                    thickness: 0.5,
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                  Expanded(child: _RateColumn(
                    rate:  lifetime!,
                    label: 'Lifetime',
                    color: lifetime! < 0 ? cs.error : cs.secondary,
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RateColumn extends StatelessWidget {
  final double rate;
  final String label;
  final Color  color;

  const _RateColumn({
    required this.rate,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '${(rate * 100).toStringAsFixed(0)}%',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 22, fontWeight: FontWeight.w800, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 10, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Generic dashboard card wrapper
// ---------------------------------------------------------------------------

class _DashCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _DashCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant, letterSpacing: 0.8)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recent transaction row
// ---------------------------------------------------------------------------

class _RecentTxRow extends StatelessWidget {
  final Transaction tx;
  const _RecentTxRow({required this.tx});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final fmt    = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final isExp  = tx.amount < 0;
    final payee  = tx.displayPayee.isNotEmpty
        ? tx.displayPayee
        : tx.account?.displayName ?? '—';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: (isExp ? cs.errorContainer : cs.tertiaryContainer)
                  .withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isExp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 14,
              color: isExp ? cs.error : cs.tertiary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payee,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w500,
                        color: cs.onSurface),
                    overflow: TextOverflow.ellipsis),
                Text(DateFormat('MMM d').format(tx.date),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            '${isExp ? '-' : '+'}${fmt.format((tx.amount as double).abs())}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: isExp ? cs.onSurface : cs.tertiary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Spending category row with progress bar
// ---------------------------------------------------------------------------

class _SpendingCatRow extends StatelessWidget {
  final String name;
  final double amount;
  final double pct;
  final Color  color;
  final NumberFormat fmt;

  const _SpendingCatRow({
    required this.name,
    required this.amount,
    required this.pct,
    required this.color,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(name,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w500,
                        color: cs.onSurface),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(fmt.format(amount),

                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cashflow bar chart (income vs expenses, 3 months)
// ---------------------------------------------------------------------------

class _CashflowChart extends StatelessWidget {
  final List<MonthData> byMonth;
  const _CashflowChart({required this.byMonth});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final months = byMonth.length > 3 ? byMonth.sublist(byMonth.length - 3) : byMonth;
    final maxY   = months.fold(0.0, (m, d) =>
        [m, d.income, d.expenses].reduce((a, b) => a > b ? a : b));

    return BarChart(
      BarChartData(
        maxY: maxY * 1.2,
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= months.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('MMM').format(months[idx].month),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: List.generate(months.length, (i) {
          final m = months[i];
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: m.income,
                color: cs.tertiary,
                width: 22,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              BarChartRodData(
                toY: m.expenses,
                color: cs.error.withValues(alpha: 0.7),
                width: 22,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
            barsSpace: 6,
          );
        }),
        barTouchData: BarTouchData(enabled: false),
      ),
    );
  }
}
