import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../shared/models/account.dart';
import '../../shared/models/category.dart';
import '../../shared/models/scheduled_transaction.dart';
import '../../shared/models/transaction.dart';
import '../../shared/providers/categories_provider.dart';
import '../../shared/providers/payees_provider.dart';
import '../accounts/accounts_provider.dart';
import '../cashflow/cashflow_provider.dart';
import 'transactions_provider.dart';
import '../../core/sms/sms_parser.dart';
import '../budget/category_icons.dart';
import '../../core/sms/sms_service.dart';
import 'templates_provider.dart';

// ---------------------------------------------------------------------------

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

enum _SearchFilter { all, payee, category, account }

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  _SearchFilter _searchFilter = _SearchFilter.all;

  @override
  void initState() {
    super.initState();
    pendingSmsNotifier.addListener(_onPendingSms);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Handle SMS parsed before this screen mounted (notification tap race)
      final notified = pendingSmsNotifier.value;
      if (notified != null && mounted) {
        pendingSmsNotifier.value = null;
        showEditTransactionSheet(context, ref, smsData: notified);
        return;
      }
      // Handle cold-start pending SMS from SharedPreferences
      final pending = await SmsService.takePending();
      if (pending.isNotEmpty && mounted) {
        showEditTransactionSheet(context, ref, smsData: pending.first);
      }
    });
  }

  @override
  void dispose() {
    pendingSmsNotifier.removeListener(_onPendingSms);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onPendingSms() {
    final parsed = pendingSmsNotifier.value;
    if (parsed != null && mounted) {
      pendingSmsNotifier.value = null;
      showEditTransactionSheet(context, ref, smsData: parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final txAsync      = ref.watch(transactionsProvider);
    // Pre-warm categories so the add-transaction sheet never sees a loading state
    ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search transactions...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() {
                            _search = '';
                            _searchCtrl.clear();
                            _searchFilter = _SearchFilter.all;
                          }),
                        )
                      : null,
                ),
              ),
            ),
            if (_search.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _SearchFilter.values.map((f) {
                      final selected = _searchFilter == f;
                      final label = switch (f) {
                        _SearchFilter.all      => 'All',
                        _SearchFilter.payee    => 'Payee',
                        _SearchFilter.category => 'Category',
                        _SearchFilter.account  => 'Account',
                      };
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(label),
                          selected: selected,
                          onSelected: (_) => setState(() => _searchFilter = f),
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            Builder(
              builder: (context) {
                final accountIdFilter =
                    GoRouterState.of(context).uri.queryParameters['account'];
                if (accountIdFilter == null) return const SizedBox.shrink();
                final accountName = ref
                    .watch(accountsProvider)
                    .valueOrNull
                    ?.where((a) => a.id == accountIdFilter)
                    .firstOrNull
                    ?.displayName;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Row(
                    children: [
                      Icon(Icons.filter_alt, size: 14,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        accountName ?? 'Account',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => context.go('/transactions'),
                        child: Text(
                          'Show all',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Expanded(
              child: txAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: cs.error),
                      const SizedBox(height: 12),
                      Text('Could not load transactions',
                          style: GoogleFonts.plusJakartaSans(color: cs.onSurfaceVariant)),
                      TextButton(
                        onPressed: () => ref.invalidate(transactionsProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (all) => _TransactionsList(
                  all:             all,
                  search:          _search,
                  searchFilter:    _searchFilter,
                  fixedAccountId:  GoRouterState.of(context).uri.queryParameters['account'],
                  ref:             ref,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: MediaQuery.sizeOf(context).width >= 800 ? null : Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'transfer',
            onPressed: () => showTransferSheet(context, ref),
            backgroundColor: cs.secondaryContainer,
            foregroundColor: cs.onSecondaryContainer,
            child: const Icon(Icons.swap_horiz),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onLongPress: () => showQuickAddSheet(context, ref),
            child: FloatingActionButton(
              heroTag: 'add',
              onPressed: () => showEditTransactionSheet(context, ref),
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction list body
// ---------------------------------------------------------------------------

class _TransactionsList extends StatelessWidget {
  final List<Transaction> all;
  final String search;
  final _SearchFilter searchFilter;
  final String? fixedAccountId;
  final WidgetRef ref;

  const _TransactionsList({
    required this.all,
    required this.search,
    required this.searchFilter,
    this.fixedAccountId,
    required this.ref,
  });

  List<Transaction> get _pending {
    final base = all.where((t) => t.isPendingReview);
    if (fixedAccountId != null) {
      return base.where((t) => t.accountId == fixedAccountId).toList();
    }
    return base.toList();
  }

  List<Transaction> get _confirmed {
    Iterable<Transaction> base = all.where((t) => !t.isPendingReview);
    if (fixedAccountId != null) {
      base = base.where((t) => t.accountId == fixedAccountId);
    }
    if (search.isEmpty) return base.toList();
    final q    = search.toLowerCase();
    final byId = {for (final t in all) t.id: t};
    String partnerAccount(Transaction t) => t.transferId != null
        ? (byId[t.transferId]?.account?.displayName ?? '').toLowerCase()
        : '';
    return base.where((t) {
      if (t.isPendingReview) return false;
      return switch (searchFilter) {
        _SearchFilter.all      => t.displayPayee.toLowerCase().contains(q) ||
                                  (t.categoryName ?? '').toLowerCase().contains(q) ||
                                  (t.account?.displayName ?? '').toLowerCase().contains(q) ||
                                  partnerAccount(t).contains(q),
        _SearchFilter.payee    => t.displayPayee.toLowerCase().contains(q),
        _SearchFilter.category => (t.categoryName ?? '').toLowerCase().contains(q),
        _SearchFilter.account  => (t.account?.displayName ?? '').toLowerCase().contains(q) ||
                                  partnerAccount(t).contains(q),
      };
    }).toList();
  }

  Map<String, List<Transaction>> get _grouped {
    final map = <String, List<Transaction>>{};
    for (final tx in _confirmed) {
      (map[_dateLabel(tx.date)] ??= []).add(tx);
    }
    return map;
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
      return 'Yesterday';
    }
    return DateFormat('EEEE, MMM d').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final grouped = _grouped;

    if (pending.isEmpty && grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(search.isNotEmpty ? 'No results for "$search"' : 'No transactions yet',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final confirmed = _confirmed;
    final searchTotal = search.isNotEmpty
        ? confirmed.fold<double>(0, (sum, t) => sum + t.amount)
        : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: [
        if (search.isNotEmpty && confirmed.isNotEmpty) ...[
          _SearchSummaryBar(count: confirmed.length, total: searchTotal),
          const SizedBox(height: 8),
        ],
        if (pending.isNotEmpty) ...[
          _PendingReviewSection(transactions: pending, ref: ref),
          const SizedBox(height: 16),
        ],
        for (final entry in grouped.entries) ...[
          _DateHeader(label: entry.key, transactions: entry.value),
          const SizedBox(height: 6),
          _TransactionGroup(transactions: entry.value, ref: ref),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Search summary bar

class _SearchSummaryBar extends StatelessWidget {
  final int count;
  final double total;
  const _SearchSummaryBar({required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final isPositive = total >= 0;
    final totalColor = isPositive ? cs.tertiary : cs.error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            '$count ${count == 1 ? 'transaction' : 'transactions'}',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            fmt.format(total.abs()),
            style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: totalColor),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending review section
// ---------------------------------------------------------------------------

class _PendingReviewSection extends StatelessWidget {
  final List<Transaction> transactions;
  final WidgetRef ref;

  const _PendingReviewSection({required this.transactions, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.tertiary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(Icons.sms_outlined, size: 16, color: cs.tertiary),
                const SizedBox(width: 8),
                Text('SMS Inbox',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w700, color: cs.tertiary)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.tertiary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${transactions.length}',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, fontWeight: FontWeight.w700, color: cs.onTertiary)),
                ),
                const Spacer(),
                Text('Review all',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: cs.tertiary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Divider(height: 1, color: cs.tertiary.withValues(alpha: 0.2)),
          ...transactions.map((tx) => _PendingTile(tx: tx, ref: ref)),
        ],
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  final Transaction tx;
  final WidgetRef ref;

  const _PendingTile({required this.tx, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return InkWell(
      onTap: () => showEditTransactionSheet(context, ref, prefill: tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _PayeeAvatar(payee: tx.displayPayee, color: cs.tertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tx.displayPayee.isNotEmpty ? tx.displayPayee : 'Unknown',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  Text(tx.account?.displayName ?? '',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fmt.format(tx.amount),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: tx.amount < 0 ? cs.onSurface : cs.tertiary)),
                const SizedBox(height: 4),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.read(transactionsProvider.notifier).confirmTransaction(tx.id),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(70, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction long-press actions
// ---------------------------------------------------------------------------

void _showTransactionActions(BuildContext context, WidgetRef ref, Transaction tx) {
  final cs = Theme.of(context).colorScheme;
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
            leading: Icon(Icons.swap_horiz_rounded, color: cs.primary),
            title: Text(
              'Move to account',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              'Reassign this transaction to a different account',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _showMoveToAccountSheet(context, ref, tx);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void _showMoveToAccountSheet(BuildContext context, WidgetRef ref, Transaction tx) {
  final cs       = Theme.of(context).colorScheme;
  final accounts = ref.read(accountsProvider).valueOrNull ?? [];
  final others   = accounts.where((a) => a.id != tx.accountId).toList();

  showModalBottomSheet<void>(
    context:     context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand:          false,
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
                  Text(
                    'Move to account',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17, fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Currently in: ${tx.account?.displayName ?? 'Unknown'}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12, color: cs.onSurfaceVariant,
                    ),
                  ),
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
                    title: Text(
                      a.displayName,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600,
                      ),
                    ),
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

// ---------------------------------------------------------------------------
// Date header
// ---------------------------------------------------------------------------

class _DateHeader extends StatelessWidget {
  final String label;
  final List<Transaction> transactions;

  const _DateHeader({required this.label, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final dayTotal = transactions.fold(0.0, (s, t) => s + t.amount);

    return Row(
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
    );
  }
}

// ---------------------------------------------------------------------------
// Transaction group + tile
// ---------------------------------------------------------------------------

// Sealed display-item types for a single day's transaction list.
sealed class _DayItem {}
class _SingleTx  extends _DayItem { final Transaction tx;           _SingleTx(this.tx); }
class _SplitGroup extends _DayItem { final List<Transaction> parts; _SplitGroup(this.parts); }

List<_DayItem> _toDayItems(List<Transaction> txs) {
  final result          = <_DayItem>[];
  final seenSplitGroups = <String>{};
  final splitMap        = <String, List<Transaction>>{};

  for (final tx in txs) {
    if (tx.splitGroupId != null) {
      (splitMap[tx.splitGroupId!] ??= []).add(tx);
    }
  }

  for (final tx in txs) {
    if (tx.splitGroupId != null) {
      if (seenSplitGroups.add(tx.splitGroupId!)) {
        result.add(_SplitGroup(splitMap[tx.splitGroupId!]!));
      }
    } else {
      result.add(_SingleTx(tx));
    }
  }
  return result;
}

class _TransactionGroup extends StatelessWidget {
  final List<Transaction> transactions;
  final WidgetRef ref;

  const _TransactionGroup({required this.transactions, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final items = _toDayItems(transactions);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final isLast = e.key == items.length - 1;
          return switch (e.value) {
            _SingleTx(:final tx)      => _TransactionTile(tx: tx, isLast: isLast, ref: ref),
            _SplitGroup(:final parts) => _SplitGroupTile(parts: parts, isLast: isLast, ref: ref),
          };
        }).toList(),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction tx;
  final bool isLast;
  final WidgetRef ref;

  const _TransactionTile({required this.tx, required this.isLast, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final fmt = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    return InkWell(
      onTap: () => showEditTransactionSheet(context, ref, prefill: tx),
      onLongPress: tx.isTransfer ? null : () async {
        if (tx.isReconciled) {
          final ok = await _showReconciledGate(context, tx);
          if (!ok || !context.mounted) return;
        }
        _showTransactionActions(context, ref, tx);
      },
      onSecondaryTap: tx.isTransfer ? null : () async {
        if (tx.isReconciled) {
          final ok = await _showReconciledGate(context, tx);
          if (!ok || !context.mounted) return;
        }
        _showTransactionActions(context, ref, tx);
      },
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(16))
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            _PayeeAvatar(
              payee:         tx.isTransfer ? 'Transfer' : tx.displayPayee,
              color:         cs.primary,
              iconCodePoint: tx.isTransfer ? null : tx.categoryIconCodePoint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.isTransfer ? 'Transfer' : (tx.displayPayee.isNotEmpty ? tx.displayPayee : 'Unknown'),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                  if (tx.categoryName != null)
                    Text(
                      tx.categoryName!,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (tx.account != null)
                    Text(
                      tx.account!.displayName,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(fmt.format(tx.amount),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: tx.isIncome ? cs.tertiary : cs.onSurface)),
                if (tx.isReconciled) ...[
                  const SizedBox(height: 2),
                  Icon(
                    Icons.lock_outline,
                    size: 11,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payee avatar
// ---------------------------------------------------------------------------

class _PayeeAvatar extends StatelessWidget {
  final String payee;
  final Color color;
  final int? iconCodePoint;
  const _PayeeAvatar({required this.payee, required this.color, this.iconCodePoint});

  @override
  Widget build(BuildContext context) {
    final iconData = iconCodePoint != null
        ? iconDataFromCodePoint(iconCodePoint!)
        : null;

    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: iconData != null
          ? Icon(iconData, size: 20, color: color)
          : Text(
              payee.isNotEmpty ? payee[0].toUpperCase() : '?',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick-fill data — used when launching the sheet from a template/suggestion
// ---------------------------------------------------------------------------

class _QuickFill {
  final String  payeeName;
  final double? amount;
  final String? categoryId;
  final String? categoryName;
  final int?    categoryIconCodePoint;
  final String? accountId;
  final bool    isIncome;

  const _QuickFill({
    required this.payeeName,
    this.amount,
    this.categoryId,
    this.categoryName,
    this.categoryIconCodePoint,
    this.accountId,
    this.isIncome = false,
  });
}

// ---------------------------------------------------------------------------
// Reconciled-transaction gate
// ---------------------------------------------------------------------------

/// Shows a warning before the user edits or deletes a reconciled transaction.
/// Returns true if the user chose to proceed anyway, false if they cancelled.
Future<bool> _showReconciledGate(
  BuildContext context,
  Transaction tx, {
  bool forDelete = false,
}) async {
  final cs = Theme.of(context).colorScheme;
  final dateStr = tx.reconciledAt != null
      ? DateFormat('MMM d, yyyy').format(tx.reconciledAt!)
      : 'a previous session';

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(
        forDelete ? Icons.lock : Icons.lock_outline,
        color: forDelete ? cs.error : const Color(0xFFFFB300),
        size: 30,
      ),
      title: Text(
        forDelete
            ? 'Delete reconciled transaction?'
            : 'Edit reconciled transaction?',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        textAlign: TextAlign.center,
      ),
      content: Text(
        'This transaction was reconciled on $dateStr.\n\n'
        '${forDelete
            ? 'Deleting it will permanently remove it and may unbalance your reconciliation.'
            : 'Editing it may affect your reconciliation balance.'}',
        style: GoogleFonts.plusJakartaSans(fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          style: forDelete
              ? TextButton.styleFrom(foregroundColor: cs.error)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(forDelete ? 'Delete anyway' : 'Edit anyway'),
        ),
      ],
    ),
  );
  return ok == true;
}

// ---------------------------------------------------------------------------
// Add / Edit Transaction sheet
// ---------------------------------------------------------------------------

/// Public so the account detail view can open the same edit sheet.
/// Shows a reconciliation warning first when [prefill] is a reconciled transaction.
Future<void> showEditTransactionSheet(
  BuildContext context,
  WidgetRef ref, {
  Transaction? prefill,
  ParsedSms?   smsData,
  _QuickFill?  quickFill,
}) async {
  // Gate: warn before letting the user edit a reconciled transaction.
  if (prefill?.isReconciled == true) {
    final proceed = await _showReconciledGate(context, prefill!);
    if (!proceed || !context.mounted) return;
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddTransactionSheet(
      prefill:   prefill,
      smsData:   smsData,
      quickFill: quickFill,
      widgetRef: ref,
    ),
  );
}

class _AddTransactionSheet extends ConsumerStatefulWidget {
  final Transaction? prefill;
  final ParsedSms?   smsData;
  final _QuickFill?  quickFill;
  final WidgetRef    widgetRef;
  const _AddTransactionSheet({this.prefill, this.smsData, this.quickFill, required this.widgetRef});

  @override
  ConsumerState<_AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<_AddTransactionSheet> {
  final _payeeCtrl    = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _memoCtrl     = TextEditingController();
  late final FocusNode _numpadFocus;

  // ── Calculator state ──────────────────────────────────────────────────────
  // Right-hand side of the current expression, typed in cents-shift mode
  // (each digit shifts existing value left, e.g. 2→3→4 = $0.23→$2.34).
  int _rightCents = 0;
  // For × and ÷ the right operand is a plain count (e.g. ×3 means ×3 items),
  // entered as a regular integer, not cent-shifted.
  int _rightCount = 0;
  // Accumulated left-hand value (in dollars) after the first operator press.
  double _leftDollars = 0;
  // Pending operator: '+', '−', '×', '÷', or null.
  String? _pendingOp;

  // True when the right-hand side is money (+ / −); false for count (× / ÷).
  bool get _isCentsMode =>
      _pendingOp == null || _pendingOp == '+' || _pendingOp == '−';

  // Evaluate the current expression to a dollar amount.
  double get _effectiveDollars {
    if (_pendingOp == null) return _rightCents / 100.0;
    return _applyOp(_leftDollars,
        _isCentsMode ? _rightCents / 100.0 : _rightCount.toDouble(),
        _pendingOp!);
  }

  double _applyOp(double left, double right, String op) {
    switch (op) {
      case '+': return left + right;
      case '−': return (left - right).clamp(0, double.infinity);
      case '×': return left * right;
      case '÷': return right > 0 ? left / right : left;
      default:  return left;
    }
  }

  // Expression string for the secondary display line, e.g. "$10.00 + $5.00".
  String get _expressionString {
    if (_pendingOp == null) return '';
    final mf = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final leftStr = mf.format(_leftDollars);
    if (_isCentsMode) {
      if (_rightCents == 0) return '$leftStr ${_pendingOp!}';
      return '$leftStr ${_pendingOp!} ${mf.format(_rightCents / 100.0)}';
    } else {
      if (_rightCount == 0) return '$leftStr ${_pendingOp!}';
      return '$leftStr ${_pendingOp!} $_rightCount';
    }
  }
  String? _selectedCategoryId;
  String? _selectedCategoryName;
  Account? _selectedAccount;
  DateTime _date = DateTime.now();
  bool _isIncome = false;
  bool _incomeNextMonth = false;
  bool _makeRecurring = false;
  ScheduledFrequency _recurFrequency = ScheduledFrequency.monthly;
  bool _showSuggestions = false;
  bool _showCategorySuggestions = false;
  bool _saving = false;

  // ── Split state ───────────────────────────────────────────────────────────
  bool _isSplit = false;
  final List<_SplitEntry> _splits = [];

  @override
  void initState() {
    super.initState();
    _numpadFocus = FocusNode();
    // Auto-focus the numpad so keyboard digits work immediately on desktop,
    // and no software keyboard pops up on mobile.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _numpadFocus.requestFocus();
    });

    final p   = widget.prefill;
    final sms = widget.smsData;
    final qf  = widget.quickFill;

    if (p != null) {
      _rightCents           = (p.amount.abs() * 100).round();
      _payeeCtrl.text       = p.displayPayee;
      _memoCtrl.text        = p.memo ?? '';
      _categoryCtrl.text    = p.categoryName ?? '';
      _selectedCategoryId   = p.categoryId;
      _selectedCategoryName = p.categoryName;
      _selectedAccount      = p.account;
      _date                 = p.date;
      _isIncome             = p.isIncome;
    } else {
      // Default to first budget account
      final accounts       = widget.widgetRef.read(accountsProvider).valueOrNull ?? [];
      final budgetAccounts = accounts.where((a) => !a.isTracking && !a.isCreditCard);
      _selectedAccount     = budgetAccounts.isNotEmpty
          ? budgetAccounts.first
          : accounts.isNotEmpty ? accounts.first : null;

      if (sms != null) {
        // Override with SMS-parsed values
        _rightCents = (sms.amount.abs() * 100).round();
        if (sms.payee?.isNotEmpty == true) _payeeCtrl.text = sms.payee!;
        _isIncome = !sms.isDebit;
        if (sms.accountLastFour != null) {
          final matched = accounts
              .where((a) => a.lastFour == sms.accountLastFour)
              .firstOrNull;
          if (matched != null) _selectedAccount = matched;
        }
      } else if (qf != null) {
        // Pre-fill from template / quick-add suggestion
        if (qf.amount != null) _rightCents = (qf.amount! * 100).round();
        _payeeCtrl.text       = qf.payeeName;
        _categoryCtrl.text    = qf.categoryName ?? '';
        _selectedCategoryId   = qf.categoryId;
        _selectedCategoryName = qf.categoryName;
        _isIncome             = qf.isIncome;
        if (qf.accountId != null) {
          final matched = accounts.where((a) => a.id == qf.accountId).firstOrNull;
          if (matched != null) _selectedAccount = matched;
        }
      }
    }
  }

  @override
  void dispose() {
    _numpadFocus.dispose();
    _payeeCtrl.dispose();
    _categoryCtrl.dispose();
    _memoCtrl.dispose();
    for (final s in _splits) s.dispose();
    super.dispose();
  }

  void _onNumpad(String key) {
    setState(() {
      if (_isCentsMode) {
        if (key == '⌫') {
          _rightCents = _rightCents ~/ 10;
        } else if (key == '00') {
          final next = _rightCents * 100;
          if (next <= 999999999) _rightCents = next;
        } else {
          final next = _rightCents * 10 + int.parse(key);
          if (next <= 999999999) _rightCents = next; // cap at $9,999,999.99
        }
      } else {
        // ×/÷ mode: right side is a plain integer count
        if (key == '⌫') {
          _rightCount = _rightCount ~/ 10;
        } else if (key == '00') {
          final next = _rightCount * 100;
          if (next <= 99999) _rightCount = next;
        } else {
          final next = _rightCount * 10 + int.parse(key);
          if (next <= 99999) _rightCount = next;
        }
      }
    });
  }

  void _onOperator(String op) {
    setState(() {
      if (_pendingOp == null) {
        // First operator: capture current value as left side.
        _leftDollars = _rightCents / 100.0;
      } else {
        // Chained operator: evaluate what we have so far.
        _leftDollars = _applyOp(
          _leftDollars,
          _isCentsMode ? _rightCents / 100.0 : _rightCount.toDouble(),
          _pendingOp!,
        );
      }
      _rightCents = 0;
      _rightCount = 0;
      _pendingOp  = op;
    });
  }

  List<_PayeeSuggestion> _suggestions(List payees) {
    final q = _payeeCtrl.text.toLowerCase();
    if (q.isEmpty) return [];
    return payees
        .where((p) => p.name.toLowerCase().contains(q))
        .take(5)
        .map((p) => _PayeeSuggestion(name: p.name,
            categoryId: p.defaultCategoryId,
            categoryName: p.defaultCategoryName))
        .toList();
  }

  List<Category> _categoryMatches(List<CategoryGroup> groups) {
    final q = _categoryCtrl.text.toLowerCase().trim();
    if (q.isEmpty) return [];
    return groups
        .expand((g) => g.categories)
        .where((c) => c.name.toLowerCase().contains(q))
        .take(6)
        .toList();
  }

  bool get _canSave {
    if (_selectedAccount == null || _saving || _effectiveDollars <= 0) return false;
    if (_isSplit) {
      if (_splits.length < 2) return false;
      final splitTotal = _splits.fold(0.0, (s, e) => s + e.amount);
      return (_splitRemaining).abs() < 0.01 && splitTotal > 0;
    }
    return true;
  }

  double get _splitRemaining =>
      _effectiveDollars - _splits.fold(0.0, (s, e) => s + e.amount);

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      final amt    = _effectiveDollars;
      final signed = _isIncome ? amt : -amt;

      // "Next month" income: shift date to 1st of next month so
      // v_to_be_budgeted places this income in the correct budget month.
      // Dart's DateTime normalises month 13 → January of next year automatically.
      final saveDate = (_isIncome && _incomeNextMonth)
          ? DateTime(_date.year, _date.month + 1, 1)
          : _date;

      final p = widget.prefill;
      if (p != null && p.isPendingReview) {
        await ref.read(transactionsProvider.notifier).confirmTransaction(
          p.id,
          categoryId: _selectedCategoryId,
          memo: _memoCtrl.text.trim(),
        );
      } else if (p != null) {
        await ref.read(transactionsProvider.notifier).updateTransaction(
          p.id,
          accountId:  _selectedAccount!.id,
          amount:     signed,
          date:       saveDate,
          payeeName:  _payeeCtrl.text.trim(),
          categoryId: _selectedCategoryId,
          memo:       _memoCtrl.text.trim(),
        );
      } else if (_isSplit) {
        await ref.read(transactionsProvider.notifier).addSplitTransactions(
          accountId: _selectedAccount!.id,
          date:      saveDate,
          payeeName: _payeeCtrl.text.trim(),
          memo:      _memoCtrl.text.trim(),
          splits:    _splits
              .map((s) => (categoryId: s.categoryId, amount: s.amount))
              .toList(),
        );
      } else {
        await ref.read(transactionsProvider.notifier).addTransaction(
          accountId:  _selectedAccount!.id,
          amount:     signed,
          date:       saveDate,
          payeeName:  _payeeCtrl.text.trim(),
          categoryId: _selectedCategoryId,
          memo:       _memoCtrl.text.trim(),
        );
        // If "Make recurring" is on, also create a scheduled transaction for
        // future occurrences. The first occurrence starts after saveDate.
        if (_makeRecurring) {
          final nextDate = _recurFrequency.advance(saveDate) ?? saveDate;
          await ref.read(cashflowProvider.notifier).addScheduled(
            accountId:  _selectedAccount!.id,
            amount:     signed,
            frequency:  _recurFrequency,
            nextDate:   nextDate,
            payeeName:  _payeeCtrl.text.trim(),
            categoryId: _selectedCategoryId,
            memo:       _memoCtrl.text.trim().isEmpty
                ? null
                : _memoCtrl.text.trim(),
          );
        }
      }
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

  Future<void> _confirmDelete() async {
    final cs        = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Reconciled transactions get a stronger warning (second gate — first was
    // on sheet open, this one is the final confirmation for the destructive act).
    bool confirmed;
    if (widget.prefill?.isReconciled == true) {
      // ignore: use_build_context_synchronously
      confirmed = await _showReconciledGate(context, widget.prefill!, forDelete: true);
    } else {
      // ignore: use_build_context_synchronously
      confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Delete transaction?',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
              content: Text('This will permanently remove the transaction.',
                  style: GoogleFonts.plusJakartaSans()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Delete',
                      style: TextStyle(
                          color: cs.error, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ) == true;
    }

    if (confirmed && mounted) {
      setState(() => _saving = true);
      try {
        await ref
            .read(transactionsProvider.notifier)
            .deleteTransaction(widget.prefill!.id);
        navigator.pop();
      } catch (e) {
        messenger.showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: cs.error,
          behavior: SnackBarBehavior.floating,
        ));
        if (mounted) setState(() => _saving = false);
      }
    }
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
      return 'Yesterday';
    }
    return DateFormat('MMM d').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final fmt      = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final payees          = ref.watch(payeesProvider).valueOrNull ?? [];
    final categoryGroups  = ref.watch(categoriesProvider).valueOrNull ?? [];
    final suggestions     = _suggestions(payees);
    final categoryMatches = _categoryMatches(categoryGroups);

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 1.0,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        widget.prefill == null
                            ? 'New Transaction'
                            : widget.prefill!.isPendingReview
                                ? 'Review Transaction'
                                : 'Edit Transaction',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface),
                      ),
                      const Spacer(),
                      // Split toggle — only available for new transactions
                      if (widget.prefill == null) ...[
                        GestureDetector(
                          onTap: () {
                            if (_isSplit) {
                              setState(() {
                                _isSplit = false;
                                for (final s in _splits) s.dispose();
                                _splits.clear();
                              });
                            } else {
                              final total = _effectiveDollars;
                              setState(() {
                                _isSplit = true;
                                _splits
                                  ..clear()
                                  ..add(_SplitEntry(
                                    categoryId:   _selectedCategoryId,
                                    categoryName: _selectedCategoryName,
                                    amount:       total,
                                  ))
                                  ..add(_SplitEntry());
                              });
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _isSplit
                                  ? cs.primaryContainer
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: _isSplit
                                  ? Border.all(
                                      color: cs.primary.withValues(alpha: 0.4))
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.call_split_rounded,
                                    size: 13,
                                    color: _isSplit
                                        ? cs.primary
                                        : cs.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text('Split',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _isSplit
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                    )),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_outlined,
                                  size: 13, color: cs.onSurfaceVariant),
                              const SizedBox(width: 5),
                              Text(_dateLabel(_date),
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12, fontWeight: FontWeight.w600,
                                      color: cs.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                children: [
                  // Amount display — expression line + evaluated result
                  Center(
                    child: Column(
                      children: [
                        // Secondary: expression string (e.g. "$10.00 + $5.00")
                        if (_pendingOp != null)
                          Text(
                            _expressionString,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 22, fontWeight: FontWeight.w500,
                                color: cs.onSurfaceVariant),
                          ),
                        // Primary: evaluated total
                        Text(
                          '${_isIncome ? '+' : '−'}${fmt.format(_effectiveDollars)}',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: _pendingOp != null ? 38 : 48,
                              fontWeight: FontWeight.w800,
                              color: _effectiveDollars == 0
                                  ? cs.onSurfaceVariant
                                  : _isIncome ? cs.tertiary : cs.onSurface),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Income / expense toggle
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isIncome = !_isIncome;
                        if (!_isIncome) _incomeNextMonth = false;
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: _isIncome
                              ? cs.tertiaryContainer
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: _isIncome
                              ? Border.all(color: cs.tertiary.withValues(alpha: 0.4))
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                              size: 13,
                              color: _isIncome ? cs.tertiary : cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isIncome ? 'Income' : 'Expense',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12, fontWeight: FontWeight.w700,
                                color: _isIncome ? cs.tertiary : cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Income availability — only shown when income is toggled on
                  if (_isIncome) ...[
                    const SizedBox(height: 10),
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
                        onSelectionChanged: (s) =>
                            setState(() => _incomeNextMonth = s.first),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  Focus(
                    focusNode: _numpadFocus,
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent &&
                          event is! KeyRepeatEvent) {
                        return KeyEventResult.ignored;
                      }
                      final char = event.character;
                      if (char != null && char.length == 1) {
                        final code = char.codeUnitAt(0);
                        // Digit keys '0'–'9'
                        if (code >= 0x30 && code <= 0x39) {
                          _onNumpad(char);
                          return KeyEventResult.handled;
                        }
                        // Operator keys
                        if (char == '+') { _onOperator('+'); return KeyEventResult.handled; }
                        if (char == '-') { _onOperator('−'); return KeyEventResult.handled; }
                        if (char == '*') { _onOperator('×'); return KeyEventResult.handled; }
                        if (char == '/') { _onOperator('÷'); return KeyEventResult.handled; }
                      }
                      // Backspace / Delete
                      final key = event.logicalKey;
                      if (key == LogicalKeyboardKey.backspace ||
                          key == LogicalKeyboardKey.delete) {
                        _onNumpad('⌫');
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: _Numpad(onKey: _onNumpad, onOperator: _onOperator),
                  ),
                  const SizedBox(height: 24),

                  // Payee
                  TextField(
                    controller: _payeeCtrl,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (v) => setState(() => _showSuggestions = v.isNotEmpty),
                    decoration: const InputDecoration(
                      labelText: 'Payee',
                      prefixIcon: Icon(Icons.storefront_outlined, size: 18),
                    ),
                  ),

                  // Payee autocomplete
                  if (_showSuggestions && suggestions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: suggestions.map((s) => InkWell(
                          onTap: () {
                            _payeeCtrl.text    = s.name;
                            _categoryCtrl.text = s.categoryName ?? '';
                            setState(() {
                              _showSuggestions         = false;
                              _showCategorySuggestions = false;
                              _selectedCategoryId      = s.categoryId;
                              _selectedCategoryName    = s.categoryName;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Icon(Icons.history, size: 14,
                                    color: cs.onSurfaceVariant),
                                const SizedBox(width: 10),
                                Text(s.name,
                                    style: GoogleFonts.plusJakartaSans(
                                        fontSize: 14, color: cs.onSurface)),
                                const Spacer(),
                                if (s.categoryName != null)
                                  Text(s.categoryName!,
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        )).toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // ── Category OR split lines ──────────────────────────────
                  if (_isSplit) ...[
                    // Split header: remaining indicator
                    Row(
                      children: [
                        Icon(Icons.call_split_rounded,
                            size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Text('Split lines',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: cs.primary,
                            )),
                        const Spacer(),
                        Text(
                          _splitRemaining.abs() < 0.005
                              ? 'Balanced ✓'
                              : _splitRemaining > 0
                                  ? '${NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(_splitRemaining)} remaining'
                                  : '${NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(-_splitRemaining)} over',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, fontWeight: FontWeight.w600,
                            color: _splitRemaining.abs() < 0.005
                                ? cs.tertiary
                                : cs.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._splits.asMap().entries.map((e) {
                      final i     = e.key;
                      final split = e.value;
                      return _SplitLineRow(
                        key:          ValueKey(split.id),
                        split:        split,
                        canDelete:    _splits.length > 2,
                        onPickCategory: () async {
                          final picked = await _pickCategoryFromSheet(context, ref);
                          if (picked != null) {
                            setState(() {
                              _splits[i].categoryId   = picked.id;
                              _splits[i].categoryName = picked.name;
                            });
                          }
                        },
                        onDelete: () => setState(() {
                          _splits[i].dispose();
                          _splits.removeAt(i);
                        }),
                        onAmountChanged: () => setState(() {}),
                      );
                    }),
                    TextButton.icon(
                      onPressed: () => setState(() => _splits.add(_SplitEntry())),
                      icon:  const Icon(Icons.add, size: 15),
                      label: Text('Add line',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                  ] else ...[
                    // Normal single-category field
                    TextField(
                      controller: _categoryCtrl,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (v) => setState(() {
                        _showCategorySuggestions = v.isNotEmpty;
                        if (v != _selectedCategoryName) {
                          _selectedCategoryId   = null;
                          _selectedCategoryName = null;
                        }
                      }),
                      decoration: InputDecoration(
                        labelText: 'Category',
                        prefixIcon: const Icon(Icons.label_outline, size: 18),
                        suffixIcon: _categoryCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => setState(() {
                                  _categoryCtrl.clear();
                                  _selectedCategoryId      = null;
                                  _selectedCategoryName    = null;
                                  _showCategorySuggestions = false;
                                }),
                              )
                            : null,
                      ),
                    ),

                    if (_showCategorySuggestions && categoryMatches.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: categoryMatches.map((c) => InkWell(
                            onTap: () {
                              _categoryCtrl.text = c.name;
                              setState(() {
                                _selectedCategoryId      = c.id;
                                _selectedCategoryName    = c.name;
                                _showCategorySuggestions = false;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(Icons.label_outline,
                                      size: 14, color: cs.onSurfaceVariant),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(c.name,
                                        style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14, color: cs.onSurface)),
                                  ),
                                  Text(c.groupName,
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          )).toList(),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 12),

                  // Account picker
                  _PickerChip(
                    icon: _selectedAccount?.isCreditCard == true
                        ? Icons.credit_card
                        : Icons.account_balance_outlined,
                    label:   _selectedAccount?.displayName ?? 'Account',
                    isEmpty: _selectedAccount == null,
                    onTap:   () => _pickAccount(context),
                  ),
                  const SizedBox(height: 12),

                  const SizedBox(height: 12),

                  // Make recurring — only for new transactions (not edits/confirms)
                  if (widget.prefill == null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: _makeRecurring
                            ? Border.all(
                                color: cs.primary.withValues(alpha: 0.35))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.repeat,
                              size: 16,
                              color: _makeRecurring
                                  ? cs.primary
                                  : cs.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Make recurring',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: _makeRecurring
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: _makeRecurring
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: _makeRecurring,
                            onChanged: (v) =>
                                setState(() => _makeRecurring = v),
                          ),
                        ],
                      ),
                    ),
                    if (_makeRecurring) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<ScheduledFrequency>(
                        initialValue: _recurFrequency,
                        decoration: const InputDecoration(
                          labelText: 'Repeat',
                          prefixIcon:
                              Icon(Icons.schedule_outlined, size: 18),
                        ),
                        items: const [
                          ScheduledFrequency.weekly,
                          ScheduledFrequency.biweekly,
                          ScheduledFrequency.monthly,
                          ScheduledFrequency.yearly,
                        ]
                            .map((f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(f.label,
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14)),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _recurFrequency = v);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],

                  // Memo
                  TextField(
                    controller: _memoCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Memo (optional)',
                      prefixIcon: Icon(Icons.notes_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 24),

                  FilledButton(
                    onPressed: _canSave ? _save : null,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: _saving
                        ? SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cs.onPrimary))
                        : Text(
                            widget.prefill?.isPendingReview == true
                                ? 'Confirm Transaction'
                                : widget.prefill != null
                                    ? 'Save Changes'
                                    : 'Save Transaction',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700)),
                  ),

                  // Delete — only visible when editing a confirmed transaction
                  if (widget.prefill != null &&
                      !widget.prefill!.isPendingReview) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _saving ? null : _confirmDelete,
                      icon: Icon(Icons.delete_outline,
                          size: 18, color: cs.error),
                      label: Text('Delete transaction',
                          style: GoogleFonts.plusJakartaSans(
                              color: cs.error, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickAccount(BuildContext context) {
    final accounts = ref.read(accountsProvider).valueOrNull ?? [];
    final budget   = accounts.where((a) => !a.isTracking).toList();

    showModalBottomSheet(
      context:            context,
      useSafeArea:        true,
      isScrollControlled: true,
      builder: (_) => _AccountPickerSheet(
        accounts:        budget,
        selectedAccount: _selectedAccount,
        onSelect: (a) {
          setState(() => _selectedAccount = a);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account picker sheet (with live search)
// ---------------------------------------------------------------------------

class _AccountPickerSheet extends StatefulWidget {
  final List<Account> accounts;
  final Account? selectedAccount;
  final ValueChanged<Account> onSelect;

  const _AccountPickerSheet({
    required this.accounts,
    required this.selectedAccount,
    required this.onSelect,
  });

  @override
  State<_AccountPickerSheet> createState() => _AccountPickerSheetState();
}

class _AccountPickerSheetState extends State<_AccountPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Account> get _filtered {
    if (_query.isEmpty) return widget.accounts;
    final q = _query.toLowerCase();
    return widget.accounts
        .where((a) => a.displayName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs       = Theme.of(context).colorScheme;
    final filtered = _filtered;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize:     0.3,
      maxChildSize:     0.85,
      expand:           false,
      builder: (ctx, scrollController) => Container(
        color: cs.surfaceContainerHigh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Drag handle ────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // ── Title ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
              child: Text('Account',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: cs.onSurface)),
            ),
            // ── Search field ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search accounts…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() {
                            _query = '';
                            _searchCtrl.clear();
                          }),
                        )
                      : null,
                ),
              ),
            ),
            const Divider(height: 1),
            // ── Filtered account list ──────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('No accounts match "$_query"',
                          style: GoogleFonts.plusJakartaSans(
                              color: cs.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final a          = filtered[i];
                        final isSelected = a == widget.selectedAccount;
                        return InkWell(
                          onTap: () => widget.onSelect(a),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 13, horizontal: 4),
                            child: Row(
                              children: [
                                Icon(a.type.icon, size: 18,
                                    color: isSelected
                                        ? cs.primary
                                        : cs.onSurfaceVariant),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(a.displayName,
                                      style: GoogleFonts.plusJakartaSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? cs.primary
                                              : cs.onSurface)),
                                ),
                                if (isSelected)
                                  Icon(Icons.check_circle,
                                      size: 18, color: cs.primary),
                              ],
                            ),
                          ),
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

// ---------------------------------------------------------------------------
// Numpad
// ---------------------------------------------------------------------------

class _Numpad extends StatelessWidget {
  final ValueChanged<String> onKey;
  final ValueChanged<String> onOperator;
  const _Numpad({required this.onKey, required this.onOperator});

  // 4-column layout: digits left, operators right.
  // Operators use display symbols; '−'/'×'/'÷' map to dart strings used in state.
  static const _layout = [
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '−'],
    ['00', '0', '⌫', '+'],
  ];
  static const _ops = {'+', '−', '×', '÷'};

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: _layout.map((row) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: row.map((key) {
            final isOp  = _ops.contains(key);
            final isBsp = key == '⌫';
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextButton(
                  onPressed: () => isOp ? onOperator(key) : onKey(key),
                  style: TextButton.styleFrom(
                    backgroundColor: isOp
                        ? cs.primaryContainer.withValues(alpha: 0.75)
                        : isBsp
                            ? cs.errorContainer.withValues(alpha: 0.4)
                            : cs.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isBsp
                      ? Icon(Icons.backspace_outlined, size: 20, color: cs.error)
                      : Text(
                          key,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: isOp
                                  ? cs.onPrimaryContainer
                                  : cs.onSurface),
                        ),
                ),
              ),
            );
          }).toList(),
        ),
      )).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Picker chip
// ---------------------------------------------------------------------------

class _PickerChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isEmpty;
  final VoidCallback onTap;

  const _PickerChip({
    required this.icon,
    required this.label,
    required this.isEmpty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: isEmpty ? null : Border.all(color: cs.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16,
                color: isEmpty ? cs.onSurfaceVariant : cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: isEmpty ? FontWeight.w400 : FontWeight.w600,
                      color: isEmpty ? cs.onSurfaceVariant : cs.onSurface)),
            ),
            Icon(Icons.expand_more, size: 16, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal helper
// ---------------------------------------------------------------------------

class _PayeeSuggestion {
  final String name;
  final String? categoryId;
  final String? categoryName;
  const _PayeeSuggestion({required this.name, this.categoryId, this.categoryName});
}

// ---------------------------------------------------------------------------
// Split entry model (mutable, holds per-line data in the edit sheet)
// ---------------------------------------------------------------------------

class _SplitEntry {
  final String id;
  String? categoryId;
  String? categoryName;
  final TextEditingController amountCtrl;

  _SplitEntry({this.categoryId, this.categoryName, double? amount})
      : id = _makeId(),
        amountCtrl = TextEditingController(
          text: (amount != null && amount > 0)
              ? amount.toStringAsFixed(2)
              : '',
        );

  static String _makeId() {
    final uuid = Uuid();
    return uuid.v4();
  }

  double get amount => double.tryParse(amountCtrl.text.trim()) ?? 0.0;

  void dispose() => amountCtrl.dispose();
}

// ---------------------------------------------------------------------------
// Split line row — one editable line inside the split section
// ---------------------------------------------------------------------------

class _SplitLineRow extends StatelessWidget {
  final _SplitEntry split;
  final bool canDelete;
  final VoidCallback onPickCategory;
  final VoidCallback onDelete;
  final VoidCallback onAmountChanged;

  const _SplitLineRow({
    super.key,
    required this.split,
    required this.canDelete,
    required this.onPickCategory,
    required this.onDelete,
    required this.onAmountChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          // Category chip
          Expanded(
            flex: 5,
            child: GestureDetector(
              onTap: onPickCategory,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: split.categoryId != null
                      ? Border.all(color: cs.primary.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(Icons.label_outline,
                        size: 14,
                        color: split.categoryId != null
                            ? cs.primary
                            : cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        split.categoryName ?? 'Category',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: split.categoryName != null
                              ? cs.onSurface
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Amount field
          Expanded(
            flex: 3,
            child: TextField(
              controller: split.amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => onAmountChanged(),
              decoration: const InputDecoration(
                prefixText: '\$',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                isDense: true,
              ),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          // Delete button (hidden but space-reserved when canDelete = false)
          if (canDelete)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              color: cs.error,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            )
          else
            const SizedBox(width: 32),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Split group tile — renders a split group in the confirmed-transactions list
// ---------------------------------------------------------------------------

class _SplitGroupTile extends StatelessWidget {
  final List<Transaction> parts;
  final bool isLast;
  final WidgetRef ref;

  const _SplitGroupTile({
    required this.parts,
    required this.isLast,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final fmt   = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    final first = parts.first;
    final total = parts.fold(0.0, (s, t) => s + t.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        InkWell(
          onTap: () => showEditTransactionSheet(context, ref, prefill: first),
          borderRadius: BorderRadius.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _PayeeAvatar(payee: first.displayPayee, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              first.displayPayee.isNotEmpty
                                  ? first.displayPayee
                                  : 'Unknown',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Split',
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onPrimaryContainer)),
                          ),
                        ],
                      ),
                      if (first.account != null)
                        Text(
                          first.account!.displayName,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Text(fmt.format(total),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: total >= 0 ? cs.tertiary : cs.onSurface)),
              ],
            ),
          ),
        ),
        // Sub-rows: each split line
        ...parts.asMap().entries.map((e) {
          final i          = e.key;
          final part       = e.value;
          final isPartLast = isLast && i == parts.length - 1;
          return InkWell(
            onTap: () => showEditTransactionSheet(context, ref, prefill: part),
            borderRadius: isPartLast
                ? const BorderRadius.vertical(bottom: Radius.circular(16))
                : BorderRadius.zero,
            child: Padding(
              padding: const EdgeInsets.only(
                  left: 68, right: 16, top: 4, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      part.categoryName ?? 'Uncategorized',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(fmt.format(part.amount),
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          );
        }),
        if (!isLast)
          Divider(
              height: 1,
              color: cs.outlineVariant.withValues(alpha: 0.5)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category picker sheet — used inside split-line rows
// ---------------------------------------------------------------------------

Future<({String id, String name})?> _pickCategoryFromSheet(
  BuildContext context,
  WidgetRef ref,
) {
  final groups = ref.read(categoriesProvider).valueOrNull ?? [];
  return showModalBottomSheet<({String id, String name})?>(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    builder:            (ctx) => _CategoryPickerSheet(groups: groups),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  final List<CategoryGroup> groups;
  const _CategoryPickerSheet({required this.groups});

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Category> get _matches {
    final all = widget.groups.expand((g) => g.categories).toList();
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((c) => c.name.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final matches = _matches;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize:     0.4,
      maxChildSize:     0.9,
      expand:           false,
      builder: (ctx, scrollController) => Container(
        color: cs.surfaceContainerHigh,
        child: Column(
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text('Category',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus:  true,
                onChanged:  (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search categories…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () => setState(() {
                            _query = '';
                            _searchCtrl.clear();
                          }),
                        )
                      : null,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text('No categories match "$_query"',
                          style: GoogleFonts.plusJakartaSans(
                              color: cs.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount:  matches.length,
                      itemBuilder: (_, i) {
                        final c = matches[i];
                        return ListTile(
                          leading: Icon(Icons.label_outline,
                              size: 18, color: cs.onSurfaceVariant),
                          title: Text(c.name,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          subtitle: Text(c.groupName,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant)),
                          onTap: () =>
                              Navigator.pop(ctx, (id: c.id, name: c.name)),
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

// ---------------------------------------------------------------------------
// Quick-add sheet — opened by long-pressing the main FAB
// ---------------------------------------------------------------------------

void showQuickAddSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    builder:            (_) => _QuickAddSheet(widgetRef: ref),
  );
}

class _QuickAddSheet extends ConsumerWidget {
  final WidgetRef widgetRef;
  const _QuickAddSheet({required this.widgetRef});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs          = Theme.of(context).colorScheme;
    final pinned      = ref.watch(quickTemplatesProvider);
    final suggestions = ref.watch(quickSuggestionsProvider);
    final fmt         = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

    void useTemplate(QuickTemplate t) {
      Navigator.pop(context);
      showEditTransactionSheet(
        context,
        widgetRef,
        quickFill: _QuickFill(
          payeeName:             t.payeeName,
          amount:                t.amount,
          categoryId:            t.categoryId,
          categoryName:          t.categoryName,
          categoryIconCodePoint: t.categoryIconCodePoint,
          accountId:             t.accountId,
          isIncome:              t.isIncome,
        ),
      );
    }

    void useSuggestion(AutoSuggestion s) {
      Navigator.pop(context);
      showEditTransactionSheet(
        context,
        widgetRef,
        quickFill: _QuickFill(
          payeeName:             s.payeeName,
          amount:                s.medianAmount,
          categoryId:            s.categoryId,
          categoryName:          s.categoryName,
          categoryIconCodePoint: s.categoryIconCodePoint,
        ),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize:     0.35,
      maxChildSize:     0.85,
      expand:           false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text('Quick Add',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          showEditTransactionSheet(context, widgetRef);
                        },
                        child: const Text('Add custom'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // ── Layer 2: Pinned templates ─────────────────────────────
                  if (pinned.isNotEmpty) ...[
                    _QuickSectionHeader(
                        label: 'Pinned',
                        icon:  Icons.push_pin_outlined),
                    const SizedBox(height: 8),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics:    const NeverScrollableScrollPhysics(),
                      onReorder:  (oldIdx, newIdx) => ref
                          .read(quickTemplatesProvider.notifier)
                          .reorder(oldIdx, newIdx),
                      children: pinned
                          .map((t) => _PinnedTemplateTile(
                                key:      ValueKey(t.id),
                                template: t,
                                fmt:      fmt,
                                onTap:    () => useTemplate(t),
                                onDelete: () => ref
                                    .read(quickTemplatesProvider.notifier)
                                    .remove(t.id),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Layer 1: Auto-suggestions ─────────────────────────────
                  if (suggestions.isNotEmpty) ...[
                    _QuickSectionHeader(
                      label:    'Recent',
                      icon:     Icons.bolt_outlined,
                      subtitle: 'Based on last 60 days',
                    ),
                    const SizedBox(height: 8),
                    ...suggestions.map((s) => _SuggestionTile(
                          suggestion: s,
                          fmt:        fmt,
                          onTap:      () => useSuggestion(s),
                          onPin: () {
                            ref
                                .read(quickTemplatesProvider.notifier)
                                .add(templateFromSuggestion(s));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Pinned "${s.payeeName}"'),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        )),
                  ],

                  // Empty state
                  if (pinned.isEmpty && suggestions.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Icon(Icons.bolt_outlined,
                                size: 40, color: cs.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text('No recent transactions yet',
                                style: GoogleFonts.plusJakartaSans(
                                    color: cs.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            Text(
                              'Add some transactions to see quick\nsuggestions here',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
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

// Section header for the quick-add sheet
class _QuickSectionHeader extends StatelessWidget {
  final String  label;
  final IconData icon;
  final String? subtitle;
  const _QuickSectionHeader({
    required this.label,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5)),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Text(subtitle!,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ],
    );
  }
}

// Pinned template tile (drag-reorderable)
class _PinnedTemplateTile extends StatelessWidget {
  final QuickTemplate template;
  final VoidCallback  onTap;
  final VoidCallback  onDelete;
  final NumberFormat  fmt;

  const _PinnedTemplateTile({
    super.key,
    required this.template,
    required this.onTap,
    required this.onDelete,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.push_pin, size: 14, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(template.name,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  if (template.categoryName != null)
                    Text(template.categoryName!,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            if (template.amount != null) ...[
              Text(fmt.format(template.amount!),
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: template.isIncome ? cs.tertiary : cs.onSurface)),
              const SizedBox(width: 4),
            ],
            IconButton(
              onPressed:   onDelete,
              icon:        Icon(Icons.close, size: 16, color: cs.onSurfaceVariant),
              padding:     EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            // Drag handle icon — ReorderableListView's default handles
            // (buildDefaultDragHandles: true) activate drag on long-press.
            Icon(Icons.drag_handle, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// Auto-suggestion tile
class _SuggestionTile extends StatelessWidget {
  final AutoSuggestion suggestion;
  final VoidCallback   onTap;
  final VoidCallback   onPin;
  final NumberFormat   fmt;

  const _SuggestionTile({
    required this.suggestion,
    required this.onTap,
    required this.onPin,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:        cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _PayeeAvatar(
              payee:         suggestion.payeeName,
              color:         cs.primary,
              iconCodePoint: suggestion.categoryIconCodePoint,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(suggestion.payeeName,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  if (suggestion.categoryName != null)
                    Text(suggestion.categoryName!,
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(fmt.format(suggestion.medianAmount),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                Text('${suggestion.frequency}×',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed:   onPin,
              icon: Icon(Icons.push_pin_outlined,
                  size: 16, color: cs.onSurfaceVariant),
              tooltip:     'Pin as template',
              padding:     EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transfer sheet
// ---------------------------------------------------------------------------

void showTransferSheet(BuildContext context, WidgetRef ref) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TransferSheet(widgetRef: ref),
  );
}

class _TransferSheet extends StatefulWidget {
  final WidgetRef widgetRef;
  const _TransferSheet({required this.widgetRef});

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  final _amountCtrl = TextEditingController();
  final _memoCtrl   = TextEditingController();
  Account? _fromAccount;
  Account? _toAccount;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  bool get _canSave {
    final amt = double.tryParse(_amountCtrl.text.trim());
    return amt != null && amt > 0 &&
        _fromAccount != null &&
        _toAccount != null &&
        _fromAccount!.id != _toAccount!.id &&
        !_saving;
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    try {
      await widget.widgetRef.read(transactionsProvider.notifier).transferTransaction(
        fromAccountId: _fromAccount!.id,
        toAccountId:   _toAccount!.id,
        amount:        double.parse(_amountCtrl.text.trim()),
        date:          _date,
        memo:          _memoCtrl.text.trim(),
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
    final cs       = Theme.of(context).colorScheme;
    final accounts = widget.widgetRef.read(accountsProvider).valueOrNull ?? [];
    final budgetAccounts = accounts.where((a) => !a.isTracking && a.isActive).toList();

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
              children: [
                Icon(Icons.swap_horiz, size: 22, color: cs.secondary),
                const SizedBox(width: 8),
                Text('Transfer',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
              ],
            ),
            const SizedBox(height: 24),

            // From account
            DropdownButtonFormField<Account>(
              initialValue: _fromAccount,
              decoration: const InputDecoration(
                labelText: 'From account',
                prefixIcon: Icon(Icons.arrow_upward, size: 18),
              ),
              items: budgetAccounts.map((a) => DropdownMenuItem(
                value: a,
                child: Text(a.displayName,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14)),
              )).toList(),
              onChanged: (v) => setState(() => _fromAccount = v),
            ),
            const SizedBox(height: 16),

            // To account
            DropdownButtonFormField<Account>(
              initialValue: _toAccount,
              decoration: const InputDecoration(
                labelText: 'To account',
                prefixIcon: Icon(Icons.arrow_downward, size: 18),
              ),
              items: budgetAccounts.map((a) => DropdownMenuItem(
                value: a,
                child: Text(a.displayName,
                    style: GoogleFonts.plusJakartaSans(fontSize: 14)),
              )).toList(),
              onChanged: (v) => setState(() => _toAccount = v),
            ),
            const SizedBox(height: 16),

            // Amount
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 16),

            // Date
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                );
                if (picked != null) setState(() => _date = picked);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(DateFormat('MMM d, yyyy').format(_date),
                        style: GoogleFonts.plusJakartaSans(fontSize: 14, color: cs.onSurface)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Memo (optional)
            TextField(
              controller: _memoCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Memo (optional)',
                prefixIcon: Icon(Icons.notes_outlined, size: 18),
              ),
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _canSave ? _save : null,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Transfer',
                      style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
