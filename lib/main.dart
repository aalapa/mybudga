import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/sms/sms_service.dart';
import 'features/insights/notification_service.dart';
import 'features/auth/app_lock_provider.dart';
import 'features/auth/app_lock_screen.dart';

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnon,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Load persisted theme prefs before the first frame so there's no flash.
  final prefs = await SharedPreferences.getInstance();

  FlutterNativeSplash.remove();
  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
    child: const MyBudgaApp(),
  ));

  // MethodChannel calls require a running platform loop — init after first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await NotificationService.instance.initialize();
    await SmsService.init();
    // Cold-start from notification tap: navigate to transactions now that the
    // router is running and the platform channel has responded.
    if (smsInitialLocation == '/transactions') {
      smsInitialLocation = null;
      appRouter?.go('/transactions');
    }
  });
}


class MyBudgaApp extends ConsumerWidget {
  const MyBudgaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router    = ref.watch(routerProvider);
    final themePref = ref.watch(themeProvider);
    return MaterialApp.router(
      title:        'MyBudga',
      theme:        AppTheme.light(seedColor: themePref.seedColor, cardStyle: themePref.cardStyle, cardRadius: themePref.cardRadius),
      darkTheme:    AppTheme.dark(seedColor: themePref.seedColor,  cardStyle: themePref.cardStyle, cardRadius: themePref.cardRadius),
      themeMode:    themePref.mode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Text scaling is applied here rather than at 600-odd call sites: a
      // TextScaler multiplies every font size at paint time, so the whole app
      // follows one preference without a single widget knowing about it.
      //
      // Composed with the platform's own factor rather than replacing it, so
      // an OS accessibility setting still counts — the app previously ignored
      // it entirely. Clamped because the budget's fixed-width numeric columns
      // start clipping beyond roughly 1.3.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final platformFactor = mq.textScaler.scale(100) / 100;
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(
                (platformFactor * themePref.textScale).clamp(0.85, 1.3)),
          ),
          child: AppLockOverlay(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// App lock overlay + background-timer observer
// ---------------------------------------------------------------------------

class AppLockOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockOverlay({required this.child, super.key});

  @override
  ConsumerState<AppLockOverlay> createState() => _AppLockOverlayState();
}

class _AppLockOverlayState extends ConsumerState<AppLockOverlay>
    with WidgetsBindingObserver {
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(appLockProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final bg = _backgroundedAt;
        _backgroundedAt = null;
        if (bg != null &&
            DateTime.now().difference(bg).inSeconds >= 60) {
          notifier.lock();
        }
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    if (lock.isLocked) return const AppLockScreen();
    return widget.child;
  }
}
