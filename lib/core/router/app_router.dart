import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/widgets/app_shell.dart';
import '../../features/auth/auth_screen.dart';
import '../../features/auth/household_setup_screen.dart';
import '../../features/budget/budget_screen.dart';
import '../../features/transactions/transactions_screen.dart';
import '../../features/cashflow/cashflow_screen.dart';
import '../../features/accounts/accounts_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/settings/settings_screen.dart';

/// Global router reference — set once by [routerProvider].
/// Used by SmsService to navigate when a notification is tapped.
GoRouter? appRouter;

// ---------------------------------------------------------------------------
// Auth state model
// ---------------------------------------------------------------------------

enum _AppAuthState { loading, unauthenticated, noHousehold, ready }

class _AppAuthNotifier extends ChangeNotifier {
  _AppAuthState _state = _AppAuthState.loading;
  _AppAuthState get state => _state;

  _AppAuthNotifier() {
    _init();
  }

  Future<void> _init() async {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      // Only re-resolve on meaningful auth transitions, not token refreshes
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.signedOut:
        case AuthChangeEvent.initialSession:
          await _resolve();
        default:
          break;
      }
    });
    await _resolve();
  }

  Future<void> _resolve() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      _update(_AppAuthState.unauthenticated);
      return;
    }

    // Retry once on failure — handles transient token-refresh races.
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await Supabase.instance.client
            .from('household_members')
            .select('id')
            .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
            .limit(1);
        final hasHousehold = (res as List).isNotEmpty;
        _update(hasHousehold ? _AppAuthState.ready : _AppAuthState.noHousehold);
        return;
      } catch (_) {
        if (attempt == 0) await Future.delayed(const Duration(seconds: 1));
      }
    }
    // Both attempts failed — fall back so app is never stuck on loading.
    _update(_AppAuthState.noHousehold);
  }

  void _update(_AppAuthState s) {
    if (_state != s) {
      _state = s;
      notifyListeners();
    }
  }

  // Called by household setup screen after creating the household
  void householdCreated() => _update(_AppAuthState.ready);
}

final appAuthNotifier = _AppAuthNotifier();

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    refreshListenable: appAuthNotifier,
    initialLocation: '/budget',
    redirect: (context, state) {
      final authState = appAuthNotifier.state;
      final loc = state.matchedLocation;

      switch (authState) {
        case _AppAuthState.loading:
          return loc == '/loading' ? null : '/loading';
        case _AppAuthState.unauthenticated:
          return loc == '/login' || loc == '/forgot-password' ? null : '/login';
        case _AppAuthState.noHousehold:
          return loc == '/setup' ? null : '/setup';
        case _AppAuthState.ready:
          if (loc == '/login' || loc == '/setup' || loc == '/loading') {
            return '/budget';
          }
          return null; // '/settings' and all shell routes are allowed
      }
    },
    routes: [
      GoRoute(
        path: '/loading',
        builder: (context, state) => const _LoadingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) => HouseholdSetupScreen(
          onCreated: () => appAuthNotifier.householdCreated(),
        ),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const _ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/budget',
            builder: (context, state) => const BudgetScreen(),
          ),
          GoRoute(
            path: '/transactions',
            builder: (context, state) => const TransactionsScreen(),
          ),
          GoRoute(
            path: '/cashflow',
            builder: (context, state) => const CashflowScreen(),
          ),
          GoRoute(
            path: '/accounts',
            builder: (context, state) => const AccountsScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
        ],
      ),
    ],
  );
  appRouter = router;
  return router;
});

// ---------------------------------------------------------------------------
// Loading screen
// ---------------------------------------------------------------------------

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) =>
      Scaffold(backgroundColor: Theme.of(context).colorScheme.surface);
}

// ---------------------------------------------------------------------------
// Forgot password screen
// ---------------------------------------------------------------------------

class _ForgotPasswordScreen extends StatefulWidget {
  const _ForgotPasswordScreen();

  @override
  State<_ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<_ForgotPasswordScreen> {
  final _ctrl   = TextEditingController();
  bool _loading = false;
  bool _sent    = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _send() async {
    final email = _ctrl.text.trim();
    if (email.isEmpty || !email.contains('@')) return;
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
    } catch (_) {
      // Always show success to avoid email enumeration
    } finally {
      if (mounted) setState(() { _loading = false; _sent = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: cs.onSurface),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _sent
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mark_email_read_outlined, size: 56, color: cs.primary),
                    const SizedBox(height: 20),
                    Text('Check your email',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
                    const SizedBox(height: 8),
                    Text('A reset link has been sent if that account exists.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Reset password',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: cs.onSurface)),
                    const SizedBox(height: 8),
                    Text("We'll send a reset link to your email.",
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _ctrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _send,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      child: _loading
                          ? SizedBox(height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary))
                          : const Text('Send reset link'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
