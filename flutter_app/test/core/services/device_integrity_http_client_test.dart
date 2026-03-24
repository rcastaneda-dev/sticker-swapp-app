import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_app/core/services/device_integrity_service.dart';
import 'package:flutter_app/core/services/device_integrity_http_client.dart';

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

class _FakeDeviceIntegrityService extends DeviceIntegrityService {
  String? headerValueToReturn;
  int headerValueCount = 0;

  _FakeDeviceIntegrityService({this.headerValueToReturn}) : super();

  @override
  Future<String?> get integrityHeaderValue async {
    headerValueCount++;
    return headerValueToReturn;
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────

void main() {
  group('DeviceIntegrityHttpClient', () {
    late _FakeHttpClient innerClient;
    late _FakeDeviceIntegrityService integrityService;
    late DeviceIntegrityHttpClient client;

    setUp(() {
      innerClient = _FakeHttpClient();
    });

    test('attaches X-Device-Integrity header when compromised', () async {
      integrityService = _FakeDeviceIntegrityService(
        headerValueToReturn: 'compromised',
      );
      client = DeviceIntegrityHttpClient(innerClient, integrityService);

      final request = http.Request(
        'POST',
        Uri.parse('https://api.stickerstadium.app/api/v1/ably/auth'),
      );

      await client.send(request);

      expect(innerClient.sendCount, 1);
      expect(
        innerClient.lastRequest?.headers['X-Device-Integrity'],
        'compromised',
      );
    });

    test('attaches X-Device-Integrity header when clean', () async {
      integrityService = _FakeDeviceIntegrityService(
        headerValueToReturn: 'clean',
      );
      client = DeviceIntegrityHttpClient(innerClient, integrityService);

      final request = http.Request(
        'POST',
        Uri.parse('https://api.stickerstadium.app/api/v1/ably/auth'),
      );

      await client.send(request);

      expect(innerClient.sendCount, 1);
      expect(
        innerClient.lastRequest?.headers['X-Device-Integrity'],
        'clean',
      );
    });

    test('sends request without header when value is null', () async {
      integrityService = _FakeDeviceIntegrityService(
        headerValueToReturn: null,
      );
      client = DeviceIntegrityHttpClient(innerClient, integrityService);

      final request = http.Request(
        'POST',
        Uri.parse('https://api.stickerstadium.app/api/v1/ably/auth'),
      );

      await client.send(request);

      expect(innerClient.sendCount, 1);
      expect(
        innerClient.lastRequest?.headers.containsKey('X-Device-Integrity'),
        isFalse,
      );
    });

    test('preserves response from inner client', () async {
      integrityService = _FakeDeviceIntegrityService(
        headerValueToReturn: 'clean',
      );
      client = DeviceIntegrityHttpClient(innerClient, integrityService);

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

    test('calls integrityHeaderValue on every request', () async {
      integrityService = _FakeDeviceIntegrityService(
        headerValueToReturn: 'compromised',
      );
      client = DeviceIntegrityHttpClient(innerClient, integrityService);

      for (var i = 0; i < 3; i++) {
        final request = http.Request(
          'POST',
          Uri.parse('https://api.stickerstadium.app/api/v1/ably/auth'),
        );
        await client.send(request);
      }

      expect(integrityService.headerValueCount, 3);
      expect(innerClient.sendCount, 3);
    });
  });
}
