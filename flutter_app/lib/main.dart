import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_app/core/services/push_notification_service.dart';
import 'package:flutter_app/features/stickers/data/services/guest_storage_service.dart';
import 'package:flutter_app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Clear stale Keychain data on first launch after reinstall,
  // then mark this install as initialized.
  await GuestStorageService().init();

  // OneSignal uses dart:io Platform — skip on web.
  if (!kIsWeb) {
    final pushService = PushNotificationService(
      appId: const String.fromEnvironment('ONESIGNAL_APP_ID'),
    );
    await pushService.initialize();
  }

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
