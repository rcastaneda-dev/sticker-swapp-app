import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_app/core/services/attestation_service.dart';
import 'package:flutter_app/core/services/attested_http_client.dart';

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

class _FakeAttestationService extends AttestationService {
  String? tokenToReturn;
  String? platformToReturn;
  int getTokenCount = 0;

  _FakeAttestationService({this.tokenToReturn, this.platformToReturn})
      : super(googleCloudProjectNumber: null);

  @override
  Future<String?> getAttestationToken() async {
    getTokenCount++;
    return tokenToReturn;
  }

  @override
  String? get platform => platformToReturn;
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('AttestedHttpClient', () {
    late _FakeHttpClient innerClient;
    late _FakeAttestationService attestation;
    late AttestedHttpClient client;

    setUp(() {
      innerClient = _FakeHttpClient();
    });

    test('attaches attestation headers for Android', () async {
      attestation = _FakeAttestationService(
        tokenToReturn: 'android-integrity-token',
        platformToReturn: 'android',
      );
      client = AttestedHttpClient(innerClient, attestation);

      final request = http.Request(
        'POST',
        Uri.parse('https://api.stickerstadium.app/api/v1/ably/auth'),
      );

      await client.send(request);

      expect(innerClient.sendCount, 1);
      expect(
        innerClient.lastRequest?.headers['X-Attestation-Token'],
        'android-integrity-token',
      );
      expect(
        innerClient.lastRequest?.headers['X-Attestation-Platform'],
        'android',
      );
    });

    test('attaches attestation headers for iOS', () async {
      attestation = _FakeAttestationService(
        tokenToReturn: 'ios-attest-assertion',
        platformToReturn: 'ios',
      );
      client = AttestedHttpClient(innerClient, attestation);

      final request = http.Request(
        'POST',
        Uri.parse('https://api.stickerstadium.app/api/v1/ably/auth'),
      );

      await client.send(request);

      expect(innerClient.sendCount, 1);
      expect(
        innerClient.lastRequest?.headers['X-Attestation-Token'],
        'ios-attest-assertion',
      );
      expect(
        innerClient.lastRequest?.headers['X-Attestation-Platform'],
        'ios',
      );
    });

    test('sends request without headers when token is null', () async {
      attestation = _FakeAttestationService(
        tokenToReturn: null,
        platformToReturn: null,
      );
      client = AttestedHttpClient(innerClient, attestation);

      final request = http.Request(
        'POST',
        Uri.parse('https://api.stickerstadium.app/api/v1/ably/auth'),
      );

      await client.send(request);

      expect(innerClient.sendCount, 1);
      expect(
        innerClient.lastRequest?.headers.containsKey('X-Attestation-Token'),
        isFalse,
      );
      expect(
        innerClient.lastRequest?.headers.containsKey('X-Attestation-Platform'),
        isFalse,
      );
    });

    test('sends request without headers when platform is null but token exists',
        () async {
      attestation = _FakeAttestationService(
        tokenToReturn: 'some-token',
        platformToReturn: null,
      );
      client = AttestedHttpClient(innerClient, attestation);

      final request = http.Request(
        'GET',
        Uri.parse('https://api.stickerstadium.app/healthz'),
      );

      await client.send(request);

      expect(innerClient.sendCount, 1);
      expect(
        innerClient.lastRequest?.headers.containsKey('X-Attestation-Token'),
        isFalse,
      );
    });

    test('preserves response from inner client', () async {
      attestation = _FakeAttestationService(
        tokenToReturn: 'token',
        platformToReturn: 'android',
      );
      client = AttestedHttpClient(innerClient, attestation);

      final expectedBody = utf8.encode('{"tokenRequest":{}}');
      innerClient.responseToReturn = http.StreamedResponse(
        Stream.value(expectedBody),
        200,
        headers: {'content-type': 'application/json'},
      );

      final request = http.Request(
        'POST',
        Uri.parse('https://api.stickerstadium.app/api/v1/ably/auth'),
      );

      final response = await client.send(request);

      expect(response.statusCode, 200);
      final body = await response.stream.bytesToString();
      expect(body, '{"tokenRequest":{}}');
    });

    test('calls getAttestationToken on every request', () async {
      attestation = _FakeAttestationService(
        tokenToReturn: 'token',
        platformToReturn: 'android',
      );
      client = AttestedHttpClient(innerClient, attestation);

      for (var i = 0; i < 3; i++) {
        final request = http.Request(
          'POST',
          Uri.parse('https://api.stickerstadium.app/api/v1/ably/auth'),
        );
        await client.send(request);
      }

      expect(attestation.getTokenCount, 3);
      expect(innerClient.sendCount, 3);
    });
  });
}
