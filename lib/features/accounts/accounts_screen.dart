import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../shared/models/account.dart';
import '../../shared/models/transaction.dart';
import 'accounts_provider.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  bool _ccExpanded = false;

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final accountsAsync = ref.watch(accountsProvider);

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
        data: (accounts) => _AccountsBody(
          accounts:    accounts,
          ccExpanded:  _ccExpanded,
          onToggleCC:  () => setState(() => _ccExpanded = !_ccExpanded),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddAccountSheet(context, ref),
        icon: const Icon(Icons.add),
        label: Text('Add Account',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body — built only when data is loaded
// ---------------------------------------------------------------------------

class _AccountsBody extends StatelessWidget {
  final List<Account> accounts;
  final bool ccExpanded;
  final VoidCallback onToggleCC;

  const _AccountsBody({
    required this.accounts,
    required this.ccExpanded,
    required this.onToggleCC,
  });

  List<Account> get _budgetNonCC => accounts
      .where((a) => !a.isTracking && !a.isCreditCard)
      .toList();

  List<Account> get _creditCards => accounts
      .where((a) => a.isCreditCard)
      .toList();

  List<Account> get _tracking => accounts.where((a) => a.isTracking).toList();

  double get _netWorth  => accounts.fold(0.0, (s, a) => s + a.balance);
  double get _liquidCash => _budgetNonCC.fold(0.0, (s, a) => s + a.balance);
  double get _ccDebt    => _creditCards.fold(0.0, (s, a) => s + a.balance);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _NetWorthHeader(
              netWorth:  _netWorth,
              liquidCash: _liquidCash,
              ccDebt:    _ccDebt,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_budgetNonCC.isNotEmpty) ...[
                  _SectionHeader(label: 'BUDGET ACCOUNTS', total: _liquidCash),
                  const SizedBox(height: 8),
                  _AccountGroup(accounts: _budgetNonCC),
                  const SizedBox(height: 20),
                ],
                if (_creditCards.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'CREDIT CARDS (${_creditCards.length})',
                    total: _ccDebt,
                    isDebt: true,
                  ),
                  const SizedBox(height: 8),
                  _CreditCardGroup(
                    accounts:  _creditCards,
                    expanded:  ccExpanded,
                    onToggle:  onToggleCC,
                  ),
                  const SizedBox(height: 20),
                ],
                if (_tracking.isNotEmpty) ...[
                  _SectionHeader(
                    label: 'TRACKING ACCOUNTS',
                    total: _tracking.fold(0.0, (s, a) => s + a.balance),
                  ),
                  const SizedBox(height: 8),
                  _AccountGroup(accounts: _tracking),
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

  const _NetWorthHeader({
    required this.netWorth,
    required this.liquidCash,
    required this.ccDebt,
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
          Text('NET WORTH',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: cs.primary, letterSpacing: 1)),
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

  const _NetWorthStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.isNegative = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isNegative ? '-$value' : value,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700, color: color),
                ),
                Text(label,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
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
// Credit card group — collapsed by default
// ---------------------------------------------------------------------------

class _CreditCardGroup extends StatelessWidget {
  final List<Account> accounts;
  final bool expanded;
  final VoidCallback onToggle;

  const _CreditCardGroup({
    required this.accounts,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs        = Theme.of(context).colorScheme;
    final visible   = expanded ? accounts : accounts.take(3).toList();
    final remaining = accounts.length - 3;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ...visible.asMap().entries.map((e) {
            final isLast = e.key == visible.length - 1 && (expanded || remaining <= 0);
            return _AccountTile(account: e.value, isLast: isLast);
          }),
          if (accounts.length > 3)
            InkWell(
              onTap: onToggle,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      expanded ? 'Show less' : 'Show $remaining more',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary),
                    ),
                  ],
                ),
              ),
            ),
        ],
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
                  Text(account.type.typeName,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: cs.onSurfaceVariant)),
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
    AccountType.checking   => cs.primary,
    AccountType.savings    => cs.tertiary,
    AccountType.creditCard => cs.error,
    AccountType.cash       => cs.tertiary,
    AccountType.investment => const Color(0xFF4CAF50),
    AccountType.loan       => cs.onSurfaceVariant,
    AccountType.asset      => cs.onSurfaceVariant,
  };
}

// ---------------------------------------------------------------------------
// Account detail sheet
// ---------------------------------------------------------------------------

void _showAccountDetail(BuildContext context, WidgetRef ref, Account account) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AccountDetailSheet(account: account, widgetRef: ref),
  );
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
                            onPressed: () {},
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
              data: (txs) {
                if (txs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 48, color: cs.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('No transactions in the last $_days days',
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

  const _TxGroup({
    required String dateLabel,
    required this.transactions,
    required this.fmt,
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
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

void _showReconcileSheet(BuildContext context, Account account, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReconcileSheet(account: account, ref: ref),
  );
}

class _ReconcileSheet extends StatefulWidget {
  final Account account;
  final WidgetRef ref;
  const _ReconcileSheet({required this.account, required this.ref});

  @override
  State<_ReconcileSheet> createState() => _ReconcileSheetState();
}

class _ReconcileSheetState extends State<_ReconcileSheet> {
  late final TextEditingController _ctrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.account.balance.abs().toStringAsFixed(2),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final val = double.tryParse(_ctrl.text.replaceAll(',', ''));
    if (val == null) return;
    setState(() => _saving = true);
    final newBalance = widget.account.isCreditCard ? -val.abs() : val;
    try {
      await widget.ref.read(accountsProvider.notifier).updateBalance(
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
            Text('Enter the actual balance from your bank statement.',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 28, fontWeight: FontWeight.w800, color: cs.onSurface),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 28, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 24),
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

  AccountType _type       = AccountType.checking;
  bool        _isTracking = false;
  bool        _saving     = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _nicknameCtrl.dispose();
    _lastFourCtrl.dispose(); _balanceCtrl.dispose();
    super.dispose();
  }

  bool get _canSave => _nameCtrl.text.trim().isNotEmpty && !_saving;

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final balance = double.tryParse(
        _balanceCtrl.text.replaceAll(',', ''),
      ) ?? 0.0;
      final isCc = _type == AccountType.creditCard;

      await widget.widgetRef.read(accountsProvider.notifier).addAccount(
        name:            _nameCtrl.text.trim(),
        nickname:        _nicknameCtrl.text.trim(),
        type:            _type,
        isTracking:      _isTracking,
        lastFour:        isCc ? _lastFourCtrl.text.trim() : null,
        startingBalance: isCc ? -balance.abs() : balance,
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
    final cs  = Theme.of(context).colorScheme;
    final isCc = _type == AccountType.creditCard;

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
                      fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
              const SizedBox(height: 24),

              Text('TYPE',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: cs.onSurfaceVariant, letterSpacing: 0.8)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: AccountType.values.map((t) {
                  final selected = _type == t;
                  return FilterChip(
                    label: Text(t.label,
                        style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                    avatar: Icon(t.icon, size: 14),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      _type       = t;
                      _isTracking = t == AccountType.investment ||
                                    t == AccountType.loan      ||
                                    t == AccountType.asset;
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

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
                  hintText:  'e.g. Sapphire, Gold',
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
                controller: _balanceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: isCc ? 'Current balance owed' : 'Starting balance',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 16),

              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text('Tracking account (off-budget)',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 28),

              FilledButton(
                onPressed: _canSave ? _save : null,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: _saving
                    ? SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                    : Text('Add Account',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
