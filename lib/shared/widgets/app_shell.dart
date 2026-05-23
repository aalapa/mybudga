import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/accounts/accounts_provider.dart'
    show accountsProvider, recentCreditDatesProvider,
         futureTxSumsProvider, todayBalanceProvider;
import '../../features/insights/insights_provider.dart';
import '../../features/insights/notification_service.dart';
import '../../shared/models/account.dart';
import '../../features/transactions/transactions_screen.dart'
    show showEditTransactionSheet, showTransferSheet, showQuickAddSheet;
import '../../features/cashflow/cashflow_screen.dart'
    show showAddScheduledSheet;
import '../../features/accounts/accounts_screen.dart'
    show showAddAccountSheet;

// ---------------------------------------------------------------------------
// Due-date helpers (mirrors accounts_screen.dart logic)
// ---------------------------------------------------------------------------

enum _SidebarPayStatus { unpaid, partial, paid }

DateTime _sidebarLastDue(int dueDay) {
  final now = DateTime.now();
  return dueDay <= now.day
      ? DateTime(now.year, now.month, dueDay)
      : DateTime(now.year, now.month - 1, dueDay);
}

_SidebarPayStatus _sidebarPayStatus(Account a, Map<String, DateTime> creditDates) {
  if (a.dueDay == null) return _SidebarPayStatus.unpaid;
  if (a.balance >= 0)   return _SidebarPayStatus.paid;
  final lastCredit = creditDates[a.id];
  if (lastCredit != null && !lastCredit.isBefore(_sidebarLastDue(a.dueDay!))) {
    return _SidebarPayStatus.partial;
  }
  return _SidebarPayStatus.unpaid;
}

// Sidebar balance formatter: always two decimals; compact only for ≥ 1M
String _compactBalance(double balance) {
  final abs  = balance.abs();
  final sign = balance < 0 ? '-' : '';
  if (abs >= 1000000) {
    final m = abs / 1000000;
    return '$sign\$${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
  }
  return '$sign\$${NumberFormat('#,##0.00').format(abs)}';
}

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  // Mobile bottom nav — 5 tabs, no dashboard
  static const _mobileTabs = [
    _TabItem(path: '/budget',       label: 'Budget',   icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet),
    _TabItem(path: '/accounts',     label: 'Accounts', icon: Icons.credit_card_outlined,            activeIcon: Icons.credit_card),
    _TabItem(path: '/transactions', label: 'Txns',     icon: Icons.receipt_long_outlined,           activeIcon: Icons.receipt_long),
    _TabItem(path: '/cashflow',     label: 'Cashflow', icon: Icons.waterfall_chart_outlined,        activeIcon: Icons.waterfall_chart),
    _TabItem(path: '/reports',      label: 'Reports',  icon: Icons.bar_chart_outlined,              activeIcon: Icons.bar_chart),
  ];

  // Desktop sidebar nav — Accounts moved into sidebar, not a top-level tab
  static const _desktopTabs = [
    _TabItem(path: '/dashboard',    label: 'Home',         icon: Icons.home_outlined,                   activeIcon: Icons.home),
    _TabItem(path: '/budget',       label: 'Budget',       icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet),
    _TabItem(path: '/transactions', label: 'Transactions', icon: Icons.receipt_long_outlined,           activeIcon: Icons.receipt_long),
    _TabItem(path: '/cashflow',     label: 'Cashflow',     icon: Icons.waterfall_chart_outlined,        activeIcon: Icons.waterfall_chart),
    _TabItem(path: '/reports',      label: 'Reports',      icon: Icons.bar_chart_outlined,              activeIcon: Icons.bar_chart),
  ];

  int _selectedIndex(BuildContext context, bool isWide) {
    final location = GoRouterState.of(context).uri.path;
    final tabs = isWide ? _desktopTabs : _mobileTabs;
    final idx = tabs.indexWhere((t) => location.startsWith(t.path));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide        = MediaQuery.sizeOf(context).width >= 800;
    final selectedIndex = _selectedIndex(context, isWide);

    ref.listen(notificationPatternsProvider, (_, next) {
      next.whenData((patterns) =>
          NotificationService.instance.schedulePatternNotifications(patterns));
    });

    if (isWide) {
      return Scaffold(
        body: Stack(
          children: [
            Row(
              children: [
                _DesktopSidebar(
                  tabs:          _desktopTabs,
                  selectedIndex: selectedIndex,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 72),
                    child: child,
                  ),
                ),
              ],
            ),
            const Positioned(
              right: 8,
              bottom: 24,
              child: _DesktopFabLayer(),
            ),
          ],
        ),
      );
    }

    // ── Mobile ───────────────────────────────────────────────────────────────
    return Scaffold(
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: _BottomBar(
        tabs:          _mobileTabs,
        selectedIndex: selectedIndex,
        onTabSelected: (i) => context.go(_mobileTabs[i].path),
        onSettingsTap: () => context.push('/settings'),
      ),
    );
  }
}

// ── Desktop sidebar ───────────────────────────────────────────────────────────

class _DesktopSidebar extends ConsumerStatefulWidget {
  final List<_TabItem> tabs;
  final int selectedIndex;
  const _DesktopSidebar({required this.tabs, required this.selectedIndex});

  @override
  ConsumerState<_DesktopSidebar> createState() => _DesktopSidebarState();
}

class _DesktopSidebarState extends ConsumerState<_DesktopSidebar> {
  bool _collapsed = false;

  static const _prefKeyCollapsed = 'sidebar_collapsed';
  static const _expandedWidth    = 300.0;
  static const _collapsedWidth   = 60.0;

  @override
  void initState() {
    super.initState();
    _loadPref();
  }

  Future<void> _loadPref() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_prefKeyCollapsed) ?? false;
    if (mounted && v != _collapsed) setState(() => _collapsed = v);
  }

  Future<void> _toggle() async {
    final next = !_collapsed;
    setState(() => _collapsed = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyCollapsed, next);
  }

  @override
  Widget build(BuildContext context) {
    final cs               = Theme.of(context).colorScheme;
    final accounts         = ref.watch(accountsProvider).valueOrNull ?? [];
    final creditDates      = ref.watch(recentCreditDatesProvider).valueOrNull ?? {};
    final todayOn    = ref.watch(todayBalanceProvider);
    final futureSums = todayOn
        ? (ref.watch(futureTxSumsProvider).valueOrNull ?? <String, double>{})
        : <String, double>{};
    final currentAccountId = GoRouterState.of(context).uri.queryParameters['account'];

    final budgetCash = accounts.where((a) =>
        !a.isTracking &&
        a.type != AccountType.creditCard &&
        a.type != AccountType.lineOfCredit).toList();
    final creditCards = accounts.where((a) =>
        !a.isTracking &&
        (a.type == AccountType.creditCard ||
         a.type == AccountType.lineOfCredit)).toList();
    final trackingList = accounts.where((a) => a.isTracking).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve:    Curves.easeInOut,
      width:    _collapsed ? _collapsedWidth : _expandedWidth,
      decoration: BoxDecoration(
        color:  cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.35),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRect(
        child: SafeArea(
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header / collapse toggle ──────────────────────────
              _buildHeader(cs),
              const SizedBox(height: 4),
              // ── Nav items ─────────────────────────────────────────
              for (int i = 0; i < widget.tabs.length; i++)
                _SidebarNavRow(
                  tab:       widget.tabs[i],
                  selected:  i == widget.selectedIndex,
                  collapsed: _collapsed,
                  onTap:     () => context.go(widget.tabs[i].path),
                ),
              const SizedBox(height: 6),
              Divider(
                height: 1,
                indent:    _collapsed ? 8 : 12,
                endIndent: 12,
                color: cs.outlineVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 6),
              // ── Account groups ────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // "As of today" toggle — only when sidebar is expanded
                      if (!_collapsed)
                        _SidebarTodayToggle(
                          value:     todayOn,
                          onChanged: (v) =>
                              ref.read(todayBalanceProvider.notifier).set(v),
                        ),
                      if (budgetCash.isNotEmpty)
                        _SidebarAccountGroup(
                          label:             'CASH & SAVINGS',
                          accounts:          budgetCash,
                          collapsed:         _collapsed,
                          selectedAccountId: currentAccountId,
                          creditDates:       creditDates,
                          futureSums:        futureSums,
                          onAccountTap: (a) =>
                              context.go('/transactions?account=${a.id}'),
                        ),
                      if (creditCards.isNotEmpty)
                        _SidebarAccountGroup(
                          label:             'CREDIT CARDS',
                          accounts:          creditCards,
                          collapsed:         _collapsed,
                          selectedAccountId: currentAccountId,
                          creditDates:       creditDates,
                          futureSums:        futureSums,
                          onAccountTap: (a) =>
                              context.go('/transactions?account=${a.id}'),
                        ),
                      if (trackingList.isNotEmpty)
                        _SidebarAccountGroup(
                          label:             'TRACKING',
                          accounts:          trackingList,
                          collapsed:         _collapsed,
                          selectedAccountId: currentAccountId,
                          creditDates:       creditDates,
                          futureSums:        futureSums,
                          onAccountTap: (a) =>
                              context.go('/transactions?account=${a.id}'),
                        ),
                      if (!_collapsed)
                        _SidebarManageRow(
                          onTap: () => context.go('/accounts'),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              // ── Settings ──────────────────────────────────────────
              Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
              _SidebarSettingsRow(
                collapsed: _collapsed,
                onTap:     () => context.push('/settings'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (!_collapsed) ...[
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'MyBudga',
                overflow: TextOverflow.fade,
                softWrap: false,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
          if (_collapsed) const Spacer(),
          IconButton(
            icon: Icon(
              _collapsed ? Icons.chevron_right : Icons.chevron_left,
              size: 20,
              color: cs.onSurfaceVariant,
            ),
            onPressed: _toggle,
            tooltip:   _collapsed ? 'Expand sidebar' : 'Collapse sidebar',
            padding:   const EdgeInsets.all(8),
          ),
        ],
      ),
    );
  }
}

// ── Sidebar nav row ───────────────────────────────────────────────────────────

class _SidebarNavRow extends StatelessWidget {
  final _TabItem    tab;
  final bool        selected;
  final bool        collapsed;
  final VoidCallback onTap;
  const _SidebarNavRow({
    required this.tab,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final row = InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration:  const Duration(milliseconds: 180),
        height:    40,
        padding:   EdgeInsets.symmetric(horizontal: collapsed ? 0 : 12),
        decoration: BoxDecoration(
          color:        selected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: collapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Icon(
              selected ? tab.activeIcon : tab.icon,
              size:  20,
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            if (!collapsed) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize:   13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color:      selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (collapsed) {
      return Tooltip(
        message:     tab.label,
        preferBelow: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: SizedBox(width: double.infinity, child: row),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child:   row,
    );
  }
}

// ── "As of today" toggle row ──────────────────────────────────────────────────

class _SidebarTodayToggle extends StatelessWidget {
  final bool                value;
  final ValueChanged<bool>  onChanged;
  const _SidebarTodayToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 10, 2),
      child: Row(
        children: [
          Icon(
            Icons.today_outlined,
            size:  13,
            color: cs.onSurfaceVariant.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'As of today',
              style: GoogleFonts.plusJakartaSans(
                fontSize:      10,
                fontWeight:    FontWeight.w600,
                color:         cs.onSurfaceVariant.withValues(alpha: 0.65),
                letterSpacing: 0.4,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.65,
            alignment: Alignment.centerRight,
            child: Switch(
              value:     value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Account group ─────────────────────────────────────────────────────────────

class _SidebarAccountGroup extends StatefulWidget {
  final String                    label;
  final List<Account>             accounts;
  final bool                      collapsed;       // sidebar collapsed (icon-only mode)
  final String?                   selectedAccountId;
  final Map<String, DateTime>     creditDates;
  final Map<String, double>       futureSums;      // accountId → sum of future txns
  final ValueChanged<Account>     onAccountTap;

  const _SidebarAccountGroup({
    required this.label,
    required this.accounts,
    required this.collapsed,
    required this.selectedAccountId,
    required this.creditDates,
    required this.futureSums,
    required this.onAccountTap,
  });

  @override
  State<_SidebarAccountGroup> createState() => _SidebarAccountGroupState();
}

class _SidebarAccountGroupState extends State<_SidebarAccountGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final account in widget.accounts)
          _SidebarAccountRow(
            account:          account,
            effectiveBalance: account.balance - (widget.futureSums[account.id] ?? 0.0),
            selected:         account.id == widget.selectedAccountId,
            collapsed:        widget.collapsed,
            creditDates:      widget.creditDates,
            onTap:            () => widget.onAccountTap(account),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header — only when sidebar is expanded
        if (!widget.collapsed)
          _buildHeader(cs)
        else
          const SizedBox(height: 6),
        // Animated expand/collapse of account rows
        ClipRect(
          child: AnimatedAlign(
            duration:     const Duration(milliseconds: 200),
            curve:        Curves.easeInOut,
            alignment:    Alignment.topCenter,
            heightFactor: _expanded ? 1.0 : 0.0,
            child: rows,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return InkWell(
      onTap:        () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize:      10,
                  fontWeight:    FontWeight.w700,
                  color:         cs.onSurfaceVariant.withValues(alpha: 0.65),
                  letterSpacing: 0.8,
                ),
              ),
            ),
            AnimatedRotation(
              turns:    _expanded ? 0.0 : -0.25,   // ▾ when expanded, ► when collapsed
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.expand_more,
                size:  14,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Account row ───────────────────────────────────────────────────────────────

class _SidebarAccountRow extends StatelessWidget {
  final Account               account;
  final double                effectiveBalance; // may differ from account.balance when "As of today" is on
  final bool                  selected;
  final bool                  collapsed;
  final Map<String, DateTime> creditDates;
  final VoidCallback          onTap;

  const _SidebarAccountRow({
    required this.account,
    required this.effectiveBalance,
    required this.selected,
    required this.collapsed,
    required this.creditDates,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isNeg  = effectiveBalance < 0;
    final balStr = _compactBalance(effectiveBalance);

    final isCC   = account.type == AccountType.creditCard ||
                   account.type == AccountType.lineOfCredit;
    final hasDue = isCC && account.dueDay != null;
    // Use effective balance for pay-status so the CC badge stays accurate
    final statusAccount = account.balance == effectiveBalance
        ? account
        : account.copyWith(balance: effectiveBalance);
    final status = hasDue ? _sidebarPayStatus(statusAccount, creditDates) : null;

    // Leading widget: due-date badge for CCs (expanded), or type icon
    Widget leading;
    if (!collapsed && hasDue && status != null) {
      leading = _SidebarDueBadge(dueDay: account.dueDay!, status: status);
    } else {
      leading = Icon(
        account.type.icon,
        size:  16,
        color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
      );
    }

    final row = InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration:  const Duration(milliseconds: 180),
        height:    38,
        padding:   EdgeInsets.symmetric(horizontal: collapsed ? 0 : 8),
        decoration: BoxDecoration(
          color:        selected ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: collapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            leading,
            if (!collapsed) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  account.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize:   12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color:      selected ? cs.onSecondaryContainer : cs.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                balStr,
                style: GoogleFonts.plusJakartaSans(
                  fontSize:   11,
                  fontWeight: FontWeight.w600,
                  color: isNeg
                      ? cs.error
                      : (selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ],
        ),
      ),
    );

    // Tooltip content: include payment status for CCs
    String tooltip = account.displayName;
    if (hasDue) {
      final statusLabel = switch (status!) {
        _SidebarPayStatus.paid    => 'Paid',
        _SidebarPayStatus.partial => 'Payment received',
        _SidebarPayStatus.unpaid  => 'Due ${account.dueDay}',
      };
      tooltip = '${account.displayName} · $statusLabel\n$balStr';
    } else {
      tooltip = '${account.displayName}\n$balStr';
    }

    if (collapsed) {
      return Tooltip(
        message:     tooltip,
        preferBelow: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: SizedBox(width: double.infinity, child: row),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child:   row,
    );
  }
}

// ── Due-date badge (compact, for sidebar CC rows) ─────────────────────────────

class _SidebarDueBadge extends StatelessWidget {
  final int               dueDay;
  final _SidebarPayStatus status;
  const _SidebarDueBadge({required this.dueDay, required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (status != _SidebarPayStatus.unpaid) {
      final isPaid = status == _SidebarPayStatus.paid;
      final color  = isPaid
          ? const Color(0xFF4CAF50)   // green
          : const Color(0xFFFFB300);  // amber
      return Container(
        width: 28, height: 32,
        decoration: BoxDecoration(
          color:        color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Icon(Icons.check_circle_rounded, size: 18, color: color),
        ),
      );
    }

    // Unpaid — mini calendar
    final now     = DateTime.now();
    final dueDate = dueDay >= now.day
        ? DateTime(now.year, now.month, dueDay)
        : DateTime(now.year, now.month + 1, dueDay);
    final month   = DateFormat('MMM').format(dueDate).toUpperCase();

    return Container(
      width: 28, height: 32,
      decoration: BoxDecoration(
        color:        cs.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            month,
            style: GoogleFonts.plusJakartaSans(
              fontSize:     7,
              fontWeight:   FontWeight.w800,
              color:        cs.error.withValues(alpha: 0.75),
              letterSpacing: 0.4,
            ),
          ),
          Text(
            '$dueDay',
            style: GoogleFonts.plusJakartaSans(
              fontSize:   15,
              fontWeight: FontWeight.w800,
              color:      cs.error,
              height:     1.0,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Manage accounts row ───────────────────────────────────────────────────────

class _SidebarManageRow extends StatelessWidget {
  final VoidCallback onTap;
  const _SidebarManageRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 34,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Icon(Icons.add, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Manage accounts',
                style: GoogleFonts.plusJakartaSans(
                  fontSize:   12,
                  fontWeight: FontWeight.w500,
                  color:      cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Settings row ──────────────────────────────────────────────────────────────

class _SidebarSettingsRow extends StatelessWidget {
  final bool         collapsed;
  final VoidCallback onTap;
  const _SidebarSettingsRow({required this.collapsed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inner = InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisAlignment: collapsed
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            if (!collapsed) const SizedBox(width: 14),
            Icon(Icons.account_circle_outlined, size: 22,
                color: cs.onSurfaceVariant),
            if (!collapsed) ...[
              const SizedBox(width: 10),
              Text(
                'Settings',
                style: GoogleFonts.plusJakartaSans(
                  fontSize:   13,
                  fontWeight: FontWeight.w500,
                  color:      cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (collapsed) {
      return Tooltip(
        message:     'Settings',
        preferBelow: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(width: double.infinity, child: inner),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child:   inner,
    );
  }
}

// ── Desktop FAB layer (positioned in right padding area) ──────────────────────

class _DesktopFabLayer extends ConsumerWidget {
  const _DesktopFabLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs   = Theme.of(context).colorScheme;
    final path = GoRouterState.of(context).uri.path;

    switch (path) {
      case '/transactions':
        return Column(
          mainAxisSize:      MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FloatingActionButton.small(
              heroTag:         'desk_transfer',
              onPressed:       () => showTransferSheet(context, ref),
              backgroundColor: cs.secondaryContainer,
              foregroundColor: cs.onSecondaryContainer,
              child: const Icon(Icons.swap_horiz),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onLongPress: () => showQuickAddSheet(context, ref),
              child: FloatingActionButton(
                heroTag:         'desk_add_tx',
                onPressed:       () => showEditTransactionSheet(context, ref),
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );

      case '/cashflow':
        return FloatingActionButton(
          heroTag:         'desk_add_sched',
          onPressed:       () => showAddScheduledSheet(context, ref, prefill: null),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          child: const Icon(Icons.add),
        );

      case '/accounts':
        return FloatingActionButton(
          heroTag:         'desk_add_acct',
          onPressed:       () => showAddAccountSheet(context, ref),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          child: const Icon(Icons.add),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Custom bottom bar (mobile — unchanged) ────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final List<_TabItem>     tabs;
  final int                selectedIndex;
  final ValueChanged<int>  onTabSelected;
  final VoidCallback       onSettingsTap;

  const _BottomBar({
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.35),
              width: 0.5,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset:     const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...List.generate(tabs.length, (i) => Expanded(
                  child: i == tabs.length ~/ 2
                      ? _CenterNavItem(
                          item:       tabs[i],
                          isSelected: i == selectedIndex,
                          onTap:      () => onTabSelected(i),
                        )
                      : _NavItem(
                          item:       tabs[i],
                          isSelected: i == selectedIndex,
                          onTap:      () => onTabSelected(i),
                        ),
                )),
                VerticalDivider(
                  width: 1, thickness: 1, indent: 8, endIndent: 8,
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
                SizedBox(
                  width: 52,
                  child: InkWell(
                    onTap:           onSettingsTap,
                    splashColor:     cs.primary.withValues(alpha: 0.08),
                    highlightColor:  cs.primary.withValues(alpha: 0.04),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_circle_outlined, size: 22,
                            color: cs.onSurfaceVariant),
                        const SizedBox(height: 3),
                        Text(
                          'Me',
                          style: TextStyle(
                            fontSize:   10,
                            fontWeight: FontWeight.w500,
                            color:      cs.onSurfaceVariant,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterNavItem extends StatelessWidget {
  final _TabItem     item;
  final bool         isSelected;
  final VoidCallback onTap;
  const _CenterNavItem({required this.item, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap:           onTap,
      splashColor:     cs.primary.withValues(alpha: 0.08),
      highlightColor:  cs.primary.withValues(alpha: 0.04),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration:  const Duration(milliseconds: 250),
            curve:     Curves.easeInOut,
            width:     isSelected ? 56 : 32,
            height:    32,
            decoration: BoxDecoration(
              color: isSelected ? cs.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              boxShadow: isSelected
                  ? [BoxShadow(
                      color:      cs.shadow.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset:     const Offset(0, 2),
                    )]
                  : null,
            ),
            child: Center(
              child: Icon(
                isSelected ? item.activeIcon : item.icon,
                size:  20,
                color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize:   10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color:      isSelected ? cs.primary : cs.onSurfaceVariant,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _TabItem     item;
  final bool         isSelected;
  final VoidCallback onTap;
  const _NavItem({required this.item, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap:           onTap,
      splashColor:     cs.primary.withValues(alpha: 0.08),
      highlightColor:  cs.primary.withValues(alpha: 0.04),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration:  const Duration(milliseconds: 250),
            curve:     Curves.easeInOut,
            width:     isSelected ? 56 : 32,
            height:    32,
            decoration: BoxDecoration(
              color:        isSelected ? cs.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Icon(
                isSelected ? item.activeIcon : item.icon,
                size:  20,
                color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize:   10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color:      isSelected ? cs.primary : cs.onSurfaceVariant,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class _TabItem {
  final String   path;
  final String   label;
  final IconData icon;
  final IconData activeIcon;
  const _TabItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}
