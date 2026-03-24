import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_app/core/services/certificate_pinner.dart';
import 'package:flutter_app/core/services/pinned_http_client.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────

class _FakeHttpClient extends http.BaseClient {
  http.BaseRequest? lastRequest;
  int sendCount = 0;
  http.StreamedResponse? responseToReturn;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    sendCount++;
    return responseToReturn ??
        http.StreamedResponse(
          Stream.value(utf8.encode('ok')),
          200,
        );
  }
}

class _FakeCertificatePinner extends CertificatePinner {
  int validateCount = 0;
  String? lastValidatedHost;
  CertificatePinningException? errorToThrow;

  _FakeCertificatePinner()
      : super(
          connect: (host, port) => throw UnimplementedError(
            'Fake pinner should not open sockets',
          ),
        );

  @override
  Future<void> validate(String host) async {
    if (!CertificatePins.isPinned(host)) return;
    validateCount++;
    lastValidatedHost = host;
    if (errorToThrow != null) throw errorToThrow!;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('PinnedHttpClient', () {
    late _FakeHttpClient innerClient;
    late _FakeCertificatePinner pinner;
    late PinnedHttpClient client;

    setUp(() {
      innerClient = _FakeHttpClient();
      pinner = _FakeCertificatePinner();
      client = PinnedHttpClient(innerClient, pinner);
    });

    test('validates pin before forwarding request to pinned domain', () async {
      final request = http.Request(
        'GET',
        Uri.parse('https://hieuxypdjrdweznedjsm.supabase.co/rest/v1/stickers'),
      );

      await client.send(request);

      expect(pinner.validateCount, 1);
      expect(
        pinner.lastValidatedHost,
        'hieuxypdjrdweznedjsm.supabase.co',
      );
      expect(innerClient.sendCount, 1);
      expect(innerClient.lastRequest, request);
    });

    test('passes through non-pinned domains without validation', () async {
      final request = http.Request(
        'GET',
        Uri.parse('https://www.googleapis.com/auth/userinfo'),
      );

      await client.send(request);

      expect(pinner.validateCount, 0);
      expect(innerClient.sendCount, 1);
    });

    test('throws and does NOT forward when pin validation fails', () async {
      pinner.errorToThrow = CertificatePinningException(
        'hieuxypdjrdweznedjsm.supabase.co',
        actualHash: 'bad-hash',
      );

      final request = http.Request(
        'GET',
        Uri.parse('https://hieuxypdjrdweznedjsm.supabase.co/rest/v1/stickers'),
      );

      expect(
        () => client.send(request),
        throwsA(isA<CertificatePinningException>()),
      );

      // The inner client should NOT have been called
      expect(innerClient.sendCount, 0);
    });

    test('preserves response from inner client', () async {
      final expectedBody = utf8.encode('{"data": []}');
      innerClient.responseToReturn = http.StreamedResponse(
        Stream.value(expectedBody),
        200,
        headers: {'content-type': 'application/json'},
      );

      final request = http.Request(
        'GET',
        Uri.parse('https://unpinned.example.com/api'),
      );

      final response = await client.send(request);

      expect(response.statusCode, 200);
      final body = await response.stream.bytesToString();
      expect(body, '{"data": []}');
    });
  });
}
