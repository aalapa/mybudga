import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    _TabItem(path: '/budget',       label: 'Budget',       icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet),
    _TabItem(path: '/transactions', label: 'Transactions', icon: Icons.receipt_long_outlined,           activeIcon: Icons.receipt_long),
    _TabItem(path: '/cashflow',     label: 'Cashflow',     icon: Icons.waterfall_chart_outlined,        activeIcon: Icons.waterfall_chart),
    _TabItem(path: '/accounts',     label: 'Accounts',     icon: Icons.credit_card_outlined,            activeIcon: Icons.credit_card),
    _TabItem(path: '/reports',      label: 'Reports',      icon: Icons.bar_chart_outlined,              activeIcon: Icons.bar_chart),
  ];

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final idx = _tabs.indexWhere((t) => location.startsWith(t.path));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final selectedIndex = _selectedIndex(context);
    final statusBarH   = MediaQuery.of(context).viewPadding.top;
    final isWide       = MediaQuery.sizeOf(context).width >= 600;

    Widget profileButton = IconButton(
      icon: Icon(Icons.account_circle_outlined, size: 26, color: cs.onSurfaceVariant),
      onPressed: () => context.push('/settings'),
      tooltip: 'Settings',
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => context.go(_tabs[i].path),
              trailing: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: profileButton,
              ),
              destinations: _tabs.map((t) => NavigationRailDestination(
                icon: Icon(t.icon),
                selectedIcon: Icon(t.activeIcon),
                label: Text(t.label),
              )).toList(),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          child,
          // Floating profile icon — top-right, just below status bar
          Positioned(
            top: statusBarH + 2,
            right: 4,
            child: profileButton,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: _tabs.map((t) => NavigationDestination(
          icon: Icon(t.icon),
          selectedIcon: Icon(t.activeIcon),
          label: t.label,
        )).toList(),
      ),
    );
  }
}

class _TabItem {
  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _TabItem({required this.path, required this.label, required this.icon, required this.activeIcon});
}
