import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/insights/insights_provider.dart';
import '../../features/insights/notification_service.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = [
    _TabItem(path: '/budget',       label: 'Budget',   icon: Icons.account_balance_wallet_outlined, activeIcon: Icons.account_balance_wallet),
    _TabItem(path: '/accounts',     label: 'Accounts', icon: Icons.credit_card_outlined,            activeIcon: Icons.credit_card),
    _TabItem(path: '/transactions', label: 'Txns',     icon: Icons.receipt_long_outlined,           activeIcon: Icons.receipt_long),
    _TabItem(path: '/cashflow',     label: 'Cashflow', icon: Icons.waterfall_chart_outlined,        activeIcon: Icons.waterfall_chart),
    _TabItem(path: '/reports',      label: 'Reports',  icon: Icons.bar_chart_outlined,              activeIcon: Icons.bar_chart),
  ];

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final idx = _tabs.indexWhere((t) => location.startsWith(t.path));
    return idx < 0 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs            = Theme.of(context).colorScheme;
    final selectedIndex = _selectedIndex(context);
    final isWide        = MediaQuery.sizeOf(context).width >= 600;

    // Path B — schedule notifications whenever established patterns update
    ref.listen(notificationPatternsProvider, (_, next) {
      next.whenData((patterns) =>
          NotificationService.instance.schedulePatternNotifications(patterns));
    });

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: (i) => context.go(_tabs[i].path),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IconButton(
                      icon: Icon(Icons.account_circle_outlined, size: 26, color: cs.onSurfaceVariant),
                      onPressed: () => context.push('/settings'),
                      tooltip: 'Settings',
                    ),
                  ),
                ),
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

    // ── Mobile: no AppBar — every pixel goes to content ─────────────────────
    return Scaffold(
      // SafeArea here consumes top insets once, so child screens don't double-pad
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: _BottomBar(
        tabs: _tabs,
        selectedIndex: selectedIndex,
        onTabSelected: (i) => context.go(_tabs[i].path),
        onSettingsTap: () => context.push('/settings'),
      ),
    );
  }
}

// ── Custom bottom bar ─────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final List<_TabItem> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final VoidCallback onSettingsTap;

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
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, -3),
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
                // ── 5 nav tabs ─────────────────────────────────────────────
                ...List.generate(tabs.length, (i) => Expanded(
                  child: i == tabs.length ~/ 2
                      ? _CenterNavItem(
                          item: tabs[i],
                          isSelected: i == selectedIndex,
                          onTap: () => onTabSelected(i),
                        )
                      : _NavItem(
                          item: tabs[i],
                          isSelected: i == selectedIndex,
                          onTap: () => onTabSelected(i),
                        ),
                )),
                // ── hairline separator ─────────────────────────────────────
                VerticalDivider(
                  width: 1,
                  thickness: 0.5,
                  indent: 10,
                  endIndent: 10,
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),
                // ── settings icon ──────────────────────────────────────────
                SizedBox(
                  width: 52,
                  child: InkWell(
                    onTap: onSettingsTap,
                    splashColor: cs.primary.withValues(alpha: 0.08),
                    highlightColor: cs.primary.withValues(alpha: 0.04),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.account_circle_outlined,
                          size: 22,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Me',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurfaceVariant,
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
  final _TabItem item;
  final bool isSelected;
  final VoidCallback onTap;
  const _CenterNavItem({required this.item, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = isSelected ? cs.primary : cs.primaryContainer;
    final fg = isSelected ? cs.onPrimary : cs.onPrimaryContainer;

    return InkWell(
      onTap: onTap,
      splashColor: cs.primary.withValues(alpha: 0.08),
      highlightColor: cs.primary.withValues(alpha: 0.04),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 34,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withValues(alpha: 0.18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                isSelected ? item.activeIcon : item.icon,
                size: 20,
                color: fg,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final _TabItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({required this.item, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      splashColor: cs.primary.withValues(alpha: 0.08),
      highlightColor: cs.primary.withValues(alpha: 0.04),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated pill indicator — expands on selection (MD3 style)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: isSelected ? 56 : 32,
            height: 32,
            decoration: BoxDecoration(
              color: isSelected ? cs.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Icon(
                isSelected ? item.activeIcon : item.icon,
                size: 20,
                color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
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
  final String path;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _TabItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });
}
