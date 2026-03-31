import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/core/providers/push_notification_providers.dart';
import 'package:flutter_app/core/router/app_router.dart';
import 'package:flutter_app/shared/theme/swapp_theme.dart';
import 'package:flutter_app/shared/theme/theme_provider.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Activate push notification lifecycle (OneSignal login/logout + handlers)
    ref.watch(pushNotificationLifecycleProvider);

    return MaterialApp.router(
      title: 'Sticker Swapp',
      theme: SwappTheme.light,
      darkTheme: SwappTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
