import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/sms/sms_service.dart';
import 'features/insights/notification_service.dart';

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

  FlutterNativeSplash.remove();
  runApp(const ProviderScope(child: MyBudgaApp()));

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
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'MyBudga',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
