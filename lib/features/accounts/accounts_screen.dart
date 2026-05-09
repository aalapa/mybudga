import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/account.dart';
import '../../shared/models/transaction.dart';
import 'account_labels_provider.dart';
import 'accounts_provider.dart';
import '../transactions/transactions_provider.dart';

// ---------------------------------------------------------------------------
// Due-day helpers
// ---------------------------------------------------------------------------

int _daysUntilDue(int? dueDay) {
  if (dueDay == null) return 999;
  final today = DateTime.now().day;
  if (dueDay >= today) return dueDay - today;
  final now = DateTime.now();
  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  return (daysInMonth - today) + dueDay;
}

String _ordinal(int n) {
  if (n >= 11 && n <= 13) return '${n}th';
  return switch (n % 10) {
    1 => '${n}st',
    2 => '${n}nd',
    3 => '${n}rd',
    _ => '${n}th',
  };
}

List<Account> _sortByDueDay(List<Account> accounts) {
  final sorted = [...accounts];
  sorted.sort((a, b) => _daysUntilDue(a.dueDay).compareTo(_daysUntilDue(b.dueDay)));
  return sorted;
}

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(accountsProvider);
    final labels        = ref.watch(accountLabelsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: cs.error),
              const SizedBox(height: 12),
              Text('Could not load accounts',
                  style: GoogleFonts.plusJakartaSans(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(accountsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (accounts) {
          final ccIdsKey = (accounts
                  .where((a) => a.isCreditCard)
                  .map((a) => a.id)
                  .toList()
                ..sort())
              .join(',');
          return _AccountsBody(
            accounts:       accounts,
            labels:         labels,
            onManageLabels: () => _showManageLabelsSheet(context, ref),
            onCcDebtTap:    ccIdsKey.isEmpty
                ? null
                : () => _showCcDebtHistorySheet(context, ccIdsKey),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAccountSheet(context, ref),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — built only when data is loaded
// ---------------------------------------------------------------------------

class _AccountsBody extends StatelessWidget {
  final List<Account> accounts;
  final List<AccountLabel> labels;
  final VoidCallback onManageLabels;
  final VoidCallback? onCcDebtTap;

  const _AccountsBody({
    required this.accounts,
    required this.labels,
    required this.onManageLabels,
    this.onCcDebtTap,
  });

  List<Account> get _budgetAccounts => accounts.where((a) => !a.isTracking).toList();
  List<Account> get _tracking        => accounts.where((a) => a.isTracking).toList();

  double get _netWorth   => accounts.fold(0.0, (s, a) => s + a.balance);
  double get _liquidCash => accounts
      .where((a) => !a.isTracking && !a.isCreditCard)
      .fold(0.0, (s, a) => s + a.balance);
  double get _ccDebt     => accounts
      .where((a) => a.isCreditCard)
      .fold(0.0, (s, a) => s + a.balance);

  @override
  Widget build(BuildContext context) {
    final budget = _budgetAccounts;

    // Build labeled sections when labels are defined.
    // Each label claims accounts in order; a claimed account is not shown again.
    final claimed = <String>{};
    final labeledSections = <({AccountLabel label, List<Account> accounts})>[];
    for (final label in labels) {
      final matched = budget.where((a) => !claimed.contains(a.id) && label.matches(a)).toList();
      if (matched.isNotEmpty) {
        for (final a in matched) claimed.add(a.id);
        labeledSections.add((label: label, accounts: matched));
      }
    }
    final unclaimed = budget.where((a) => !claimed.contains(a.id)).toList();

    // Apply the same labels to tracking accounts independently.
    final trackingClaimed = <String>{};
    final trackingLabeledSections = <({AccountLabel label, List<Account> accounts})>[];
    for (final label in labels) {
      final matched = _tracking.where((a) => !trackingClaimed.contains(a.id) && label.matches(a)).toList();
      if (matched.isNotEmpty) {
        for (final a in matched) trackingClaimed.add(a.id);
        trackingLabeledSections.add((label: label, accounts: matched));
      }
    }
    final unclaimedTracking = _tracking.where((a) => !trackingClaimed.contains(a.id)).toList();

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _NetWorthHeader(
              netWorth:       _netWorth,
              liquidCash:     _liquidCash,
              ccDebt:         _ccDebt,
              onManageLabels: onManageLabels,
              onCcDebtTap:    onCcDebtTap,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Labeled sections ──────────────────────────────────────
                for (final sec in labeledSections) ...[
                  _SectionHeader(
                    label: sec.label.name.toUpperCase(),
                    total: sec.accounts.fold(0.0, (s, a) => s + a.balance),
                    isDebt: sec.accounts.every((a) => a.isCreditCard),
                  ),
                  const SizedBox(height: 8),
                  _AccountGroup(accounts: _sortByDueDay(sec.accounts)),
                  const SizedBox(height: 20),
                ],

                // ── Unclaimed budget accounts ("Other") ───────────────────
                if (unclaimed.isNotEmpty) ...[
                  _SectionHeader(
                    label: labels.isEmpty ? 'BUDGET ACCOUNTS' : 'OTHER',
                    total: unclaimed.fold(0.0, (s, a) => s + a.balance),
                    isDebt: unclaimed.every((a) => a.isCreditCard),
                  ),
                  const SizedBox(height: 8),
                  _AccountGroup(accounts: _sortByDueDay(unclaimed)),
                  const SizedBox(height: 20),
                ],

                // ── Tracking accounts ─────────────────────────────────────
                if (_tracking.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'TRACKING ACCOUNTS',
                    total: _tracking.fold(0.0, (s, a) => s + a.balance),
                  ),
                  const SizedBox(height: 8),
                  for (final sec in trackingLabeledSections) ...[
                    _SectionHeader(
                      label: sec.label.name.toUpperCase(),
                      total: sec.accounts.fold(0.0, (s, a) => s + a.balance),
                    ),
                    const SizedBox(height: 6),
                    _AccountGroup(accounts: _sortByDueDay(sec.accounts)),
                    const SizedBox(height: 16),
                  ],
                  if (unclaimedTracking.isNotEmpty) ...[
                    if (trackingLabeledSections.isNotEmpty) ...[
                      _SectionHeader(
                        label: 'OTHER',
                        total: unclaimedTracking.fold(0.0, (s, a) => s + a.balance),
                      ),
                      const SizedBox(height: 6),
                    ],
                    _AccountGroup(accounts: _sortByDueDay(unclaimedTracking)),
                  ],
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Net worth header
// ---------------------------------------------------------------------------

class _NetWorthHeader extends StatelessWidget {
  final double netWorth;
  final double liquidCash;
  final double ccDebt;
  final VoidCallback onManageLabels;
  final VoidCallback? onCcDebtTap;

  const _NetWorthHeader({
    required this.netWorth,
    required this.liquidCash,
    required this.ccDebt,
    required this.onManageLabels,
    this.onCcDebtTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.15),
            cs.primaryContainer.withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('NET WORTH',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: cs.primary, letterSpacing: 1)),
              const Spacer(),
              InkWell(
                onTap: onManageLabels,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.label_outline, size: 13, color: cs.primary),
                      const SizedBox(width: 5),
                      Text('Groups',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: cs.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(fmt.format(netWorth),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 36, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 16),
          Row(
            children: [
              _NetWorthStat(
                label: 'Liquid Cash',
                value: fmt.format(liquidCash),
                color: cs.tertiary,
                icon:  Icons.account_balance_outlined,
              ),
              const SizedBox(width: 12),
              _NetWorthStat(
                label: 'CC Debt',
                value: fmt.format(ccDebt.abs()),
                color: cs.error,
                icon:  Icons.credit_card_outlined,
                isNegative: true,
                onTap: onCcDebtTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NetWorthStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool isNegative;
  final VoidCallback? onTap;

  const _NetWorthStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isNegative = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isNegative ? '-$value' : value,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w700, color: color),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(label,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.bar_chart_rounded, size: 14, color: color.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String label;
  final double total;
  final bool isDebt;

  const _SectionHeader({required this.label, required this.total, this.isDebt = false});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final color = isDebt ? cs.error : cs.onSurfaceVariant;

    return Row(
      children: [
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant, letterSpacing: 0.8)),
        const Spacer(),
        Text(
          isDebt ? '-${fmt.format(total.abs())}' : fmt.format(total),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Account group card
// ---------------------------------------------------------------------------

class _AccountGroup extends StatelessWidget {
  final List<Account> accounts;
  const _AccountGroup({required this.accounts});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: accounts.asMap().entries.map((e) {
          return _AccountTile(
            account: e.value,
            isLast:  e.key == accounts.length - 1,
          );
        }).toList(),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Account tile
// ---------------------------------------------------------------------------

class _AccountTile extends ConsumerWidget {
  final Account account;
  final bool isLast;

  const _AccountTile({required this.account, required this.isLast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs       = Theme.of(context).colorScheme;
    final fmt      = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final isNeg    = account.balance < 0;
    final balColor = isNeg ? cs.error : cs.onSurface;
    final iconColor = _iconColor(cs);

    return InkWell(
      onTap: () => _showAccountDetail(context, ref, account),
      onLongPress: () => _showReconcileSheet(context, account, ref),
      onSecondaryTap: () => _showAccountContextMenu(context, ref, account),
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(16))
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(account.type.icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.displayName,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  Text(
                    account.dueDay != null
                        ? '${account.type.typeName} · Due ${_ordinal(account.dueDay!)}'
                        : account.type.typeName,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Text(fmt.format(account.balance),
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15, fontWeight: FontWeight.w700, color: balColor)),
          ],
        ),
      ),
    );
  }

  Color _iconColor(ColorScheme cs) => switch (account.type) {
    AccountType.checking     => cs.primary,
    AccountType.savings      => cs.tertiary,
    AccountType.creditCard   => cs.error,
    AccountType.lineOfCredit => cs.error,
    AccountType.cash         => cs.tertiary,
    AccountType.investment   => const Color(0xFF4CAF50),
    AccountType.mortgage     => cs.onSurfaceVariant,
    AccountType.loan         => cs.onSurfaceVariant,
    AccountType.asset        => cs.onSurfaceVariant,
  };
}

// ---------------------------------------------------------------------------
// CC debt history sheet
// ---------------------------------------------------------------------------

void _showCcDebtHistorySheet(BuildContext context, String ccIdsKey) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _CcDebtHistorySheet(ccIdsKey: ccIdsKey),
  );
}

class _CcDebtHistorySheet extends ConsumerWidget {
  final String ccIdsKey;
  const _CcDebtHistorySheet({required this.ccIdsKey});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs   = Theme.of(context).colorScheme;
    final hist = ref.watch(ccDebtHistoryProvider(ccIdsKey));

    return Container(
      decoration: BoxDecoration(
        color:        cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
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
          Text('CC Debt History',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 18, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text('End-of-month balance — lower is better',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 24),
          SizedBox(
            height: 220,
            child: hist.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error:   (e, s) => Center(
                  child: Text('Could not load history',
                      style: GoogleFonts.plusJakartaSans(color: cs.onSurfaceVariant))),
              data: (data) {
                final nonZero = data.where((d) => d.debt > 0).toList();
                if (nonZero.isEmpty) {
                  return Center(
                    child: Text('No CC debt found',
                        style: GoogleFonts.plusJakartaSans(color: cs.onSurfaceVariant)),
                  );
                }
                return _CcDebtChart(data: data);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CcDebtChart extends StatelessWidget {
  final List<({DateTime month, double debt})> data;
  const _CcDebtChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final fmt    = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
    final maxVal = data.map((d) => d.debt).fold(0.0, math.max);

    return BarChart(
      BarChartData(
        maxY: maxVal * 1.25,
        barGroups: data.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY:          e.value.debt,
                color:        cs.error.withValues(alpha: 0.75),
                width:        18,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
              ),
            ],
          );
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles:   true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    DateFormat('MMM').format(data[i].month),
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
          leftTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData:   FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gi, rod, ri) {
              final d = data[group.x];
              return BarTooltipItem(
                '${DateFormat('MMM yy').format(d.month)}\n${fmt.format(d.debt)}',
                GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Manage account labels sheet
// ---------------------------------------------------------------------------

void _showManageLabelsSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    builder: (_) => _ManageLabelsSheet(widgetRef: ref),
  );
}

class _ManageLabelsSheet extends ConsumerStatefulWidget {
  final WidgetRef widgetRef;
  const _ManageLabelsSheet({required this.widgetRef});

  @override
  ConsumerState<_ManageLabelsSheet> createState() => _ManageLabelsSheetState();
}

class _ManageLabelsSheetState extends ConsumerState<_ManageLabelsSheet> {
  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final labels = ref.watch(accountLabelsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize:     0.4,
      maxChildSize:     0.92,
      expand:           false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
              child: Row(
                children: [
                  Text('Account Groups',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18, fontWeight: FontWeight.w800,
                          color: cs.onSurface)),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => _showEditLabelDialog(
                        context, ref, null),
                    icon:  const Icon(Icons.add, size: 16),
                    label: Text('New',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Accounts matching earlier groups won\'t appear in later ones.',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            Expanded(
              child: labels.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.label_outline,
                              size: 48, color: cs.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('No groups yet',
                              style: GoogleFonts.plusJakartaSans(
                                  color: cs.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          Text('Tap New to create your first group.',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      scrollController: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: labels.length,
                      onReorder: (old, neo) =>
                          ref.read(accountLabelsProvider.notifier)
                              .reorder(old, neo),
                      itemBuilder: (_, i) {
                        final label = labels[i];
                        return _LabelTile(
                          key:     ValueKey(label.id),
                          label:   label,
                          onEdit:  () => _showEditLabelDialog(
                              context, ref, label),
                          onDelete: () => ref
                              .read(accountLabelsProvider.notifier)
                              .deleteLabel(label.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelTile extends StatelessWidget {
  final AccountLabel label;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LabelTile({
    super.key,
    required this.label,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
        leading: Icon(Icons.label_outline, size: 18, color: cs.primary),
        title: Text(label.name,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14, fontWeight: FontWeight.w600,
                color: cs.onSurface)),
        subtitle: Text(
          '${label.matchType == LabelMatchType.startsWith ? 'Starts with' : 'Contains'}  "${label.keyword}"',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 12, color: cs.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: cs.onSurfaceVariant),
              onPressed: onEdit,
              tooltip: 'Edit',
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
              onPressed: onDelete,
              tooltip: 'Delete',
            ),
            Icon(Icons.drag_handle,
                size: 18,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

void _showEditLabelDialog(
    BuildContext context, WidgetRef ref, AccountLabel? existing) {
  final nameCtrl    = TextEditingController(text: existing?.name ?? '');
  final keywordCtrl = TextEditingController(text: existing?.keyword ?? '');
  var matchType     = existing?.matchType ?? LabelMatchType.contains;

  showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      final cs = Theme.of(dialogCtx).colorScheme;
      return StatefulBuilder(builder: (dialogCtx, setDlgState) {
        return AlertDialog(
          title: Text(existing == null ? 'New Group' : 'Edit Group',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller:         nameCtrl,
                autofocus:          true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Group name'),
              ),
              const SizedBox(height: 14),
              // Match type toggle
              Text('Match type',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              SegmentedButton<LabelMatchType>(
                style: SegmentedButton.styleFrom(
                  textStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w600),
                  visualDensity: VisualDensity.compact,
                ),
                segments: const [
                  ButtonSegment(
                    value: LabelMatchType.contains,
                    label: Text('Contains'),
                  ),
                  ButtonSegment(
                    value: LabelMatchType.startsWith,
                    label: Text('Starts with'),
                  ),
                ],
                selected: {matchType},
                onSelectionChanged: (s) =>
                    setDlgState(() => matchType = s.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller:  keywordCtrl,
                decoration:  const InputDecoration(
                  labelText: 'Keyword',
                  hintText:  'e.g. HDFC, Axis',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name    = nameCtrl.text.trim();
                final keyword = keywordCtrl.text.trim();
                if (name.isEmpty || keyword.isEmpty) return;
                final notifier =
                    ref.read(accountLabelsProvider.notifier);
                if (existing == null) {
                  notifier.addLabel(
                      name: name, matchType: matchType, keyword: keyword);
                } else {
                  notifier.updateLabel(existing.copyWith(
                      name: name,
                      matchType: matchType,
                      keyword: keyword));
                }
                Navigator.pop(dialogCtx);
              },
              child: Text(existing == null ? 'Create' : 'Save',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700)),
            ),
          ],
        );
      });
    },
  );
}

// ---------------------------------------------------------------------------
// Account detail sheet
// ---------------------------------------------------------------------------

enum _TxFilter { all, uncleared, cleared }

void _showAccountDetail(BuildContext context, WidgetRef ref, Account account) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AccountDetailSheet(account: account, widgetRef: ref),
  );
}

void _showAccountContextMenu(BuildContext context, WidgetRef ref, Account account) {
  final box  = context.findRenderObject()! as RenderBox;
  final pos  = box.localToGlobal(Offset(box.size.width, box.size.height / 2));
  final size = MediaQuery.sizeOf(context);
  showMenu<String>(
    context:  context,
    position: RelativeRect.fromLTRB(
        pos.dx - 180, pos.dy, size.width - pos.dx, size.height - pos.dy),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: [
      PopupMenuItem(
        value: 'edit',
        child: Row(children: [
          const Icon(Icons.edit_outlined, size: 16),
          const SizedBox(width: 10),
          const Text('Edit account'),
        ]),
      ),
      PopupMenuItem(
        value: 'reconcile',
        child: Row(children: [
          const Icon(Icons.check_circle_outline, size: 16),
          const SizedBox(width: 10),
          const Text('Reconcile'),
        ]),
      ),
    ],
  ).then((value) {
    if (!context.mounted) return;
    if (value == 'edit')      _showEditAccountSheet(context, account, ref);
    if (value == 'reconcile') _showReconcileSheet(context, account, ref);
  });
}

class _AccountDetailSheet extends ConsumerStatefulWidget {
  final Account  account;
  final WidgetRef widgetRef;
  const _AccountDetailSheet({required this.account, required this.widgetRef});

  @override
  ConsumerState<_AccountDetailSheet> createState() => _AccountDetailSheetState();
}

class _AccountDetailSheetState extends ConsumerState<_AccountDetailSheet> {
  int _days = 14;
  _TxFilter _filter = _TxFilter.all;

  static const _periods = [
    (label: '14d',  days: 14),
    (label: '30d',  days: 30),
    (label: '90d',  days: 90),
  ];

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final fmt     = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final account = widget.account;
    final isNeg   = account.balance < 0;
    final balColor = isNeg ? cs.error : cs.tertiary;

    final txAsync = ref.watch(accountTransactionsProvider(
      (accountId: account.id, days: _days),
    ));

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     1.0,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: CustomScrollView(
          controller: scrollController,
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Column(
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
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(account.name,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 20, fontWeight: FontWeight.w800,
                                      color: cs.onSurface)),
                              if (account.lastFour != null)
                                Text('···· ${account.lastFour}',
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13, color: cs.onSurfaceVariant)),
                              Text(account.type.typeName,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13, color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(fmt.format(account.balance),
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 28, fontWeight: FontWeight.w800,
                                    color: balColor)),
                            Text(isNeg ? 'balance owed' : 'available',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () =>
                                _showEditAccountSheet(context, account, widget.widgetRef),
                            child: Text('Edit',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () =>
                                _showReconcileSheet(context, account, widget.widgetRef),
                            child: Text('Reconcile',
                                style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Close / delete
                        IconButton(
                          tooltip: 'More options',
                          icon: const Icon(Icons.more_horiz),
                          onPressed: () => _showAccountActionsSheet(
                              context, ref, account),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // ── Period filter ──────────────────────────────────────
                    Row(
                      children: [
                        Text('TRANSACTIONS',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 11, fontWeight: FontWeight.w700,
                                color: cs.onSurfaceVariant, letterSpacing: 0.8)),
                        const Spacer(),
                        ...(_periods.map((p) => Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: GestureDetector(
                            onTap: () => setState(() => _days = p.days),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 5),
                              decoration: BoxDecoration(
                                color: _days == p.days
                                    ? cs.primary
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(p.label,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12, fontWeight: FontWeight.w700,
                                      color: _days == p.days
                                          ? cs.onPrimary
                                          : cs.onSurfaceVariant)),
                            ),
                          ),
                        ))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // ── Cleared filter ─────────────────────────────────────
                    Row(
                      children: _TxFilter.values.map((f) {
                        final active = _filter == f;
                        final label  = switch (f) {
                          _TxFilter.all       => 'All',
                          _TxFilter.uncleared => 'Uncleared',
                          _TxFilter.cleared   => 'Cleared',
                        };
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _filter = f),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: active
                                    ? cs.secondaryContainer
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(label,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: active
                                          ? cs.onSecondaryContainer
                                          : cs.onSurfaceVariant)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),

            // ── Transaction list ─────────────────────────────────────────
            txAsync.when(
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Could not load transactions',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                          color: cs.onSurfaceVariant)),
                ),
              ),
              data: (allTxs) {
                final txs = switch (_filter) {
                  _TxFilter.all       => allTxs,
                  _TxFilter.uncleared => allTxs.where((t) => !t.cleared).toList(),
                  _TxFilter.cleared   => allTxs.where((t) => t.cleared).toList(),
                };

                if (txs.isEmpty) {
                  final msg = switch (_filter) {
                    _TxFilter.uncleared => 'No uncleared transactions',
                    _TxFilter.cleared   => 'No cleared transactions',
                    _TxFilter.all       => 'No transactions in the last $_days days',
                  };
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 48, color: cs.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(msg,
                              style: GoogleFonts.plusJakartaSans(
                                  color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  );
                }

                // Group by date label
                final groups = <String, List<Transaction>>{};
                for (final tx in txs) {
                  (groups[_dateLabel(tx.date)] ??= []).add(tx);
                }

                final entries = groups.entries.toList();
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final entry = entries[i];
                        return _TxGroup(
                          dateLabel:    entry.key,
                          transactions: entry.value,
                          fmt:          fmt,
                          ref:          ref,
                          onClearToggle: (txId, nowCleared) async {
                            await Supabase.instance.client
                                .from('transactions')
                                .update({'cleared': nowCleared})
                                .eq('id', txId);
                            ref.invalidate(accountTransactionsProvider(
                              (accountId: account.id, days: _days),
                            ));
                          },
                        );
                      },
                      childCount: entries.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month &&
        d.day == yesterday.day) {
      return 'Yesterday';
    }
    return DateFormat('EEEE, MMM d').format(d);
  }
}

class _TxGroup extends StatelessWidget {
  final String label;
  final List<Transaction> transactions;
  final NumberFormat fmt;
  final WidgetRef ref;
  final Future<void> Function(String txId, bool nowCleared)? onClearToggle;

  const _TxGroup({
    required String dateLabel,
    required this.transactions,
    required this.fmt,
    required this.ref,
    this.onClearToggle,
  }) : label = dateLabel;

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final dayTotal = transactions.fold(0.0, (s, t) => s + t.amount);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant, letterSpacing: 0.5)),
              const Spacer(),
              Text(fmt.format(dayTotal),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: dayTotal >= 0 ? cs.tertiary : cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: transactions.asMap().entries.map((e) {
                final tx     = e.value;
                final isLast = e.key == transactions.length - 1;
                return InkWell(
                  borderRadius: isLast
                      ? const BorderRadius.vertical(bottom: Radius.circular(14))
                      : BorderRadius.zero,
                  onTap: () {},
                  onLongPress:    tx.isTransfer ? null : () => _showMoveToAccountSheet(context, ref, tx),
                  onSecondaryTap: tx.isTransfer ? null : () => _showMoveToAccountSheet(context, ref, tx),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        // Cleared indicator — tap to toggle
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onClearToggle != null
                              ? () => onClearToggle!(tx.id, !tx.cleared)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Icon(
                              tx.cleared
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              size: 18,
                              color: tx.cleared
                                  ? const Color(0xFF4CAF50)
                                  : cs.onSurfaceVariant
                                        .withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            tx.displayPayee.isNotEmpty
                                ? tx.displayPayee[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14, fontWeight: FontWeight.w800,
                                color: cs.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tx.isTransfer
                                    ? 'Transfer'
                                    : tx.displayPayee.isNotEmpty
                                        ? tx.displayPayee
                                        : 'Unknown',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 14, fontWeight: FontWeight.w600,
                                    color: cs.onSurface),
                              ),
                              if (tx.categoryName != null)
                                Text(tx.categoryName!,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Text(fmt.format(tx.amount),
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14, fontWeight: FontWeight.w700,
                                color: tx.isIncome
                                    ? cs.tertiary
                                    : cs.onSurface)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reconcile sheet
// ---------------------------------------------------------------------------
// Account actions sheet (close / delete)
// ---------------------------------------------------------------------------

void _showAccountActionsSheet(
    BuildContext context, WidgetRef ref, Account account) {
  showModalBottomSheet<void>(
    context:     context,
    useSafeArea: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
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
            const SizedBox(height: 8),
            // ── Close ─────────────────────────────────────────────────────
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text('Close account',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              subtitle: Text('Hides the account but keeps all history.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.onSurfaceVariant)),
              onTap: () {
                Navigator.pop(ctx);
                _showCloseAccountDialog(context, ref, account);
              },
            ),
            // ── Delete ────────────────────────────────────────────────────
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: cs.error),
              title: Text('Delete account',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, color: cs.error)),
              subtitle: Text('Permanently removes this account and all its transactions.',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.onSurfaceVariant)),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteAccountDialog(context, ref, account);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

void _showCloseAccountDialog(
    BuildContext context, WidgetRef ref, Account account) {
  showDialog<void>(
    context: context,
    builder: (ctx) {
      bool saving = false;
      return StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: Text('Close account?',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
          content: Text(
            '${account.displayName} will be hidden from your accounts list. '
            'All transactions and budget history are kept — you can still see them in reports.',
            style: GoogleFonts.plusJakartaSans(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      setState(() => saving = true);
                      try {
                        await ref
                            .read(accountsProvider.notifier)
                            .closeAccount(account.id);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);           // dialog
                          Navigator.pop(context);       // detail sheet
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setState(() => saving = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('Could not close account: $e'),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Close account'),
            ),
          ],
        );
      });
    },
  );
}

void _showDeleteAccountDialog(
    BuildContext context, WidgetRef ref, Account account) {
  final confirmCtrl = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      bool saving  = false;
      bool canDelete = false;

      return StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: Text('Delete account?',
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, color: cs.error)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This permanently deletes ${account.displayName} and every '
                'transaction on it. Your budget history will change. '
                'This cannot be undone.',
                style: GoogleFonts.plusJakartaSans(fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text('Type DELETE to confirm:',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller:  confirmCtrl,
                autofocus:   true,
                onChanged:   (v) => setState(() => canDelete = v == 'DELETE'),
                decoration: InputDecoration(
                  hintText:       'DELETE',
                  errorText:      confirmCtrl.text.isNotEmpty && !canDelete
                      ? 'Type DELETE in capitals'
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: cs.error, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              onPressed: (canDelete && !saving)
                  ? () async {
                      setState(() => saving = true);
                      try {
                        await ref
                            .read(accountsProvider.notifier)
                            .deleteAccount(account.id);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);           // dialog
                          Navigator.pop(context);       // detail sheet
                        }
                      } catch (e) {
                        if (ctx.mounted) {
                          setState(() => saving = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('Could not delete account: $e'),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    }
                  : null,
              child: saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Delete permanently'),
            ),
          ],
        );
      });
    },
  );
}

// ---------------------------------------------------------------------------
// Rename account dialog
// ---------------------------------------------------------------------------

void _showEditAccountSheet(BuildContext context, Account account, WidgetRef ref) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _EditAccountSheet(account: account, widgetRef: ref),
  );
}

class _EditAccountSheet extends StatefulWidget {
  final Account account;
  final WidgetRef widgetRef;
  const _EditAccountSheet({required this.account, required this.widgetRef});

  @override
  State<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends State<_EditAccountSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _lastFourCtrl;
  late final TextEditingController _balanceCtrl;
  final _balanceFocus = FocusNode();
  int?  _dueDay;
  bool _saving = false;

  bool get _isLiability =>
      widget.account.type == AccountType.creditCard ||
      widget.account.type == AccountType.lineOfCredit ||
      widget.account.type == AccountType.mortgage ||
      widget.account.type == AccountType.loan;

  bool get _showLastFour =>
      widget.account.type == AccountType.creditCard ||
      widget.account.type == AccountType.lineOfCredit;

  @override
  void initState() {
    super.initState();
    _nameCtrl     = TextEditingController(text: widget.account.name);
    _nicknameCtrl = TextEditingController(text: widget.account.nickname ?? '');
    _lastFourCtrl = TextEditingController(text: widget.account.lastFour ?? '');
    _balanceCtrl  = TextEditingController(
        text: widget.account.balance.abs().toStringAsFixed(2));
    _dueDay = widget.account.dueDay;
    _balanceFocus.addListener(() {
      if (!_balanceFocus.hasFocus && _balanceCtrl.text.isNotEmpty) {
        final v = double.tryParse(_balanceCtrl.text.replaceAll(',', '')) ?? 0.0;
        _balanceCtrl.text = v.toStringAsFixed(2);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _nicknameCtrl.dispose();
    _lastFourCtrl.dispose(); _balanceCtrl.dispose();
    _balanceFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final raw     = double.tryParse(_balanceCtrl.text.replaceAll(',', '')) ?? 0.0;
      final balance = _isLiability ? -raw.abs() : raw.abs();
      await widget.widgetRef.read(accountsProvider.notifier).updateAccount(
        widget.account.id,
        name:     _nameCtrl.text.trim(),
        nickname: _nicknameCtrl.text.trim(),
        lastFour: _showLastFour ? _lastFourCtrl.text.trim() : null,
        balance:  balance,
        dueDay:   _isLiability ? _dueDay : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 20),
              Text('Edit Account',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Account name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nicknameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nickname (optional)',
                  hintText:  'e.g. Primary, Sapphire',
                ),
              ),
              if (_showLastFour) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _lastFourCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Last 4 digits',
                    counterText: '',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller:      _balanceCtrl,
                focusNode:       _balanceFocus,
                keyboardType:    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted:     (_) => _save(),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  _TwoDecimalInputFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: _isLiability ? 'Current balance owed' : 'Current balance',
                  prefixText: '\$ ',
                  hintText:   '0.00',
                ),
              ),
              if (_isLiability) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _dueDay,
                  decoration: InputDecoration(
                    labelText: 'Payment due day (optional)',
                    prefixIcon: const Icon(Icons.event_outlined, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4))),
                  ),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text('No due date',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    ),
                    ...List.generate(
                      31,
                      (i) => DropdownMenuItem<int?>(
                        value: i + 1,
                        child: Text(_ordinal(i + 1),
                            style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _dueDay = v),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Save', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------------------

void _showReconcileSheet(BuildContext context, Account account, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReconcileSheet(account: account, widgetRef: ref),
  );
}

class _ReconcileSheet extends ConsumerStatefulWidget {
  final Account account;
  final WidgetRef widgetRef;
  const _ReconcileSheet({required this.account, required this.widgetRef});

  @override
  ConsumerState<_ReconcileSheet> createState() => _ReconcileSheetState();
}

class _ReconcileSheetState extends ConsumerState<_ReconcileSheet> {
  late final TextEditingController _ctrl;
  bool   _saving       = false;
  double? _clearedTotal;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.account.balance.abs().toStringAsFixed(2),
    );
    _loadClearedTotal();
  }

  Future<void> _loadClearedTotal() async {
    try {
      final rows = await Supabase.instance.client
          .from('transactions')
          .select('amount')
          .eq('account_id', widget.account.id)
          .eq('cleared', true)
          .isFilter('deleted_at', null);
      final total = (rows as List)
          .fold(0.0, (s, r) => s + (r['amount'] as num).toDouble());
      if (mounted) setState(() => _clearedTotal = total);
    } catch (_) {}
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final val = double.tryParse(_ctrl.text.replaceAll(',', ''));
    if (val == null) return;
    setState(() => _saving = true);
    final isLiability = widget.account.isCreditCard ||
        widget.account.type == AccountType.loan ||
        widget.account.type == AccountType.mortgage;
    final newBalance   = isLiability ? -val.abs() : val;
    try {
      await widget.widgetRef.read(accountsProvider.notifier).updateBalance(
        widget.account.id, newBalance,
      );
      if (mounted) Navigator.pop(context);
      if (mounted) Navigator.pop(context); // close detail sheet too
    } catch (e) {
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
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: 20),
            Text('Reconcile Account',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
            const SizedBox(height: 6),
            Text('Enter the balance from your bank statement. '
                'Mark transactions as cleared to track what matches.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 28, fontWeight: FontWeight.w800, color: cs.onSurface),
              decoration: InputDecoration(
                labelText: 'Bank statement balance',
                prefixText: '\$ ',
                prefixStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 28, fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            // Cleared balance summary
            if (_clearedTotal != null) ...[
              Builder(builder: (context) {
                final fmt           = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
                final statement     = double.tryParse(
                    _ctrl.text.replaceAll(',', '')) ?? 0.0;
                final clearedAbs    = widget.account.isCreditCard
                    ? -_clearedTotal!.abs()
                    : _clearedTotal!;
                final diff          = statement - clearedAbs.abs();
                final isMatch       = diff.abs() < 0.005;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMatch
                        ? const Color(0xFF4CAF50).withValues(alpha: 0.12)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isMatch
                            ? Icons.check_circle_rounded
                            : Icons.info_outline,
                        size: 16,
                        color: isMatch
                            ? const Color(0xFF4CAF50)
                            : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isMatch
                              ? 'Cleared balance matches statement!'
                              : 'Cleared balance: ${fmt.format(_clearedTotal!.abs())}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: isMatch
                                  ? const Color(0xFF4CAF50)
                                  : cs.onSurfaceVariant),
                        ),
                      ),
                      if (!isMatch)
                        Text(
                          'Diff: ${fmt.format(diff.abs())}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? SizedBox(height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                  : Text('Save Balance',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Account sheet
// ---------------------------------------------------------------------------

void _showAddAccountSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddAccountSheet(widgetRef: ref),
  );
}

class _AddAccountSheet extends StatefulWidget {
  final WidgetRef widgetRef;
  const _AddAccountSheet({required this.widgetRef});

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  final _nameCtrl     = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _lastFourCtrl = TextEditingController();
  final _balanceCtrl  = TextEditingController();
  final _balanceFocus = FocusNode();

  AccountType _type       = AccountType.checking;
  bool        _isTracking = false;
  DateTime?   _startDate;
  int?        _dueDay;
  bool        _saving     = false;

  @override
  void initState() {
    super.initState();
    // Auto-format to 2 decimal places when the balance field loses focus.
    _balanceFocus.addListener(() {
      if (!_balanceFocus.hasFocus && _balanceCtrl.text.isNotEmpty) {
        final val = double.tryParse(
                _balanceCtrl.text.replaceAll(',', '')) ??
            0.0;
        _balanceCtrl.text = val.toStringAsFixed(2);
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _nicknameCtrl.dispose();
    _lastFourCtrl.dispose(); _balanceCtrl.dispose();
    _balanceFocus.dispose();
    super.dispose();
  }

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty && !_saving;

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      // Round to exactly 2 decimal places to avoid floating-point drift.
      final balance = ((double.tryParse(
                  _balanceCtrl.text.replaceAll(',', '')) ??
              0.0) *
          100).round() /
          100.0;
      final isCc        = _type == AccountType.creditCard ||
                         _type == AccountType.lineOfCredit;
      final isLiability = isCc || _type == AccountType.loan || _type == AccountType.mortgage;

      await widget.widgetRef.read(accountsProvider.notifier).addAccount(
        name:            _nameCtrl.text.trim(),
        nickname:        _nicknameCtrl.text.trim(),
        type:            _type,
        isTracking:      _isTracking,
        lastFour:        isCc ? _lastFourCtrl.text.trim() : null,
        startingBalance: isLiability ? -balance.abs() : balance,
        startDate:       _startDate,
        dueDay:          isLiability ? _dueDay : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save account: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final fmt  = DateFormat('MMM d, yyyy');
    final isCc        = _type == AccountType.creditCard ||
                       _type == AccountType.lineOfCredit;
    final isLiability = isCc || _type == AccountType.loan || _type == AccountType.mortgage;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 20),
              Text('New Account',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 22, fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
              const SizedBox(height: 24),

              // Type dropdown
              DropdownButtonFormField<AccountType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: 'Account type',
                  prefixIcon: Icon(_type.icon, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                          color: cs.outline.withValues(alpha: 0.4))),
                ),
                items: AccountType.values.map((t) => DropdownMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Icon(t.icon, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Text(t.label,
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    ],
                  ),
                )).toList(),
                onChanged: (t) {
                  if (t == null) return;
                  setState(() {
                    _type       = t;
                    _isTracking = t.defaultTracking;
                  });
                },
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Account name'),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _nicknameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nickname (optional)',
                  hintText: 'e.g. Sapphire, Gold',
                ),
              ),
              const SizedBox(height: 12),

              if (isCc) ...[
                TextField(
                  controller: _lastFourCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Last 4 digits',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
              ],

              TextField(
                controller:      _balanceCtrl,
                focusNode:       _balanceFocus,
                keyboardType:    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted:     (_) => _save(),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  _TwoDecimalInputFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: isLiability ? 'Current balance owed' : 'Starting balance',
                  prefixText: '\$ ',
                  hintText: '0.00',
                ),
              ),
              const SizedBox(height: 12),

              // Start date picker
              InkWell(
                onTap: _pickStartDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: _startDate != null
                        ? Border.all(
                            color: cs.primary.withValues(alpha: 0.4))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 16,
                          color: _startDate != null
                              ? cs.primary
                              : cs.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Text(
                        _startDate != null
                            ? 'Tracking from ${fmt.format(_startDate!)}'
                            : 'Start date (optional)',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: _startDate != null
                                ? cs.onSurface
                                : cs.onSurfaceVariant),
                      ),
                      if (_startDate != null) ...[
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _startDate = null),
                          child: Icon(Icons.clear,
                              size: 16, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (isLiability) ...[
                DropdownButtonFormField<int?>(
                  initialValue: _dueDay,
                  decoration: InputDecoration(
                    labelText: 'Payment due day (optional)',
                    prefixIcon: const Icon(Icons.event_outlined, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: cs.outline.withValues(alpha: 0.4))),
                  ),
                  items: [
                    DropdownMenuItem<int?>(
                      value: null,
                      child: Text('No due date',
                          style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    ),
                    ...List.generate(
                      31,
                      (i) => DropdownMenuItem<int?>(
                        value: i + 1,
                        child: Text(_ordinal(i + 1),
                            style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _dueDay = v),
                ),
                const SizedBox(height: 16),
              ],

              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  title: Text('Tracking account (off-budget)',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  subtitle: Text(
                    _isTracking
                        ? "Transactions won't affect your envelopes"
                        : 'Transactions will affect your envelopes',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  value: _isTracking,
                  onChanged: (v) => setState(() => _isTracking = v),
                  activeThumbColor: cs.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 28),

              FilledButton(
                onPressed: _canSave ? _save : null,
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.onPrimary))
                    : Text('Add Account',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input formatter — allows digits + at most one decimal point with ≤2 places.
// ---------------------------------------------------------------------------

class _TwoDecimalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    // Reject anything that isn't: optional digits, optional dot, up to 2 digits
    if (RegExp(r'^\d*\.?\d{0,2}$').hasMatch(text)) return newValue;
    return oldValue; // revert to previous valid value
  }
}

// ---------------------------------------------------------------------------
// Move transaction to a different account (long-press / right-click)
// ---------------------------------------------------------------------------

void _showMoveToAccountSheet(BuildContext context, WidgetRef ref, Transaction tx) {
  final cs      = Theme.of(context).colorScheme;
  final accounts = ref.read(accountsProvider).valueOrNull ?? [];
  final others   = accounts.where((a) => a.id != tx.accountId).toList();

  showModalBottomSheet<void>(
    context:            context,
    useSafeArea:        true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand:           false,
      initialChildSize: 0.5,
      minChildSize:     0.35,
      maxChildSize:     0.85,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Move to account',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('Currently in: ${tx.account?.displayName ?? 'Unknown'}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount:  others.length,
                itemBuilder: (_, i) {
                  final a = others[i];
                  return ListTile(
                    leading: Icon(a.type.icon, color: cs.onSurfaceVariant, size: 20),
                    title: Text(a.displayName,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await ref.read(transactionsProvider.notifier).updateTransaction(
                        tx.id,
                        accountId:  a.id,
                        amount:     tx.amount,
                        date:       tx.date,
                        payeeName:  tx.payeeName ?? '',
                        categoryId: tx.categoryId,
                        memo:       tx.memo,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
