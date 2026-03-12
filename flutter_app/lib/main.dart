import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/core/services/push_notification_service.dart';
import 'package:flutter_app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ... existing Supabase init, etc.

  final pushService = PushNotificationService(
    appId: const String.fromEnvironment('ONESIGNAL_APP_ID'),
  );
  await pushService.initialize();

  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
