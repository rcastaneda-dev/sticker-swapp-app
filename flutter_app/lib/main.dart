import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_app/core/services/attestation_service.dart';
import 'package:flutter_app/core/services/attested_http_client.dart';
import 'package:flutter_app/core/services/certificate_pinner.dart';
import 'package:flutter_app/core/services/device_integrity_http_client.dart';
import 'package:flutter_app/core/services/device_integrity_service.dart';
import 'package:flutter_app/core/services/pinned_http_client.dart';
import 'package:flutter_app/core/services/push_notification_service.dart';
import 'package:flutter_app/core/services/replay_guard_http_client.dart';
import 'package:flutter_app/core/providers/push_notification_providers.dart';
import 'package:flutter_app/features/stickers/data/services/guest_storage_service.dart';
import 'package:flutter_app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Security client chain — dart:io only, skip on web.
  // AttestedHttpClient → ReplayGuardHttpClient → DeviceIntegrityHttpClient → PinnedHttpClient → http.Client()
  http.Client? httpClient;
  if (!kIsWeb) {
    const gcpProjectNumber = int.fromEnvironment(
      'GOOGLE_CLOUD_PROJECT_NUMBER',
    );
    final attestation = AttestationService(
      googleCloudProjectNumber:
          gcpProjectNumber != 0 ? gcpProjectNumber : null,
    );
    final pinnedClient = PinnedHttpClient(http.Client(), CertificatePinner());

    // Root/jailbreak detection — check once at launch, cache for session.
    final deviceIntegrity = DeviceIntegrityService();
    await deviceIntegrity.isDeviceCompromised();
    final integrityClient = DeviceIntegrityHttpClient(
      pinnedClient,
      deviceIntegrity,
    );

    // Replay attack prevention — nonce + timestamp + HMAC-SHA256.
    const replayHmacSecret = String.fromEnvironment('REPLAY_HMAC_SECRET');
    final replayGuardClient = ReplayGuardHttpClient(
      integrityClient,
      replayHmacSecret,
    );

    httpClient = AttestedHttpClient(replayGuardClient, attestation);
  }

  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
    httpClient: httpClient,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Clear stale Keychain data on first launch after reinstall,
  // then mark this install as initialized.
  await GuestStorageService().init();

  // OneSignal uses dart:io Platform — skip on web.
  PushNotificationService? pushService;
  if (!kIsWeb) {
    pushService = PushNotificationService(
      appId: const String.fromEnvironment('ONESIGNAL_APP_ID'),
    );
    await pushService.initialize();
  }

  runApp(
    ProviderScope(
      overrides: [
        if (pushService != null)
          pushNotificationServiceProvider.overrideWithValue(pushService),
      ],
      child: const App(),
    ),
  );
}
