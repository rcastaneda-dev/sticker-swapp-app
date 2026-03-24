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
import 'package:flutter_app/features/stickers/data/services/guest_storage_service.dart';
import 'package:flutter_app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Security client chain — dart:io only, skip on web.
  // AttestedHttpClient → DeviceIntegrityHttpClient → PinnedHttpClient → http.Client()
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

    httpClient = AttestedHttpClient(integrityClient, attestation);
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
