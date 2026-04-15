import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// An [http.BaseClient] that attaches replay prevention headers to
/// every outgoing request.
///
/// Works in the layered client chain:
/// ```
/// AttestedHttpClient → ReplayGuardHttpClient → DeviceIntegrityHttpClient → PinnedHttpClient → http.Client()
/// ```
///
/// Adds three headers:
/// - `X-Nonce`: 32-char hex string (16 random bytes)
/// - `X-Timestamp`: Unix epoch seconds
/// - `X-Signature`: HMAC-SHA256 hex digest of `"METHOD:PATH:TIMESTAMP:NONCE"`
class ReplayGuardHttpClient extends http.BaseClient {
  final http.Client _inner;
  final String _hmacSecret;
  final Random _random = Random.secure();

  ReplayGuardHttpClient(this._inner, this._hmacSecret);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final nonce = _generateNonce();
    final timestamp =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final signingString =
        '${request.method}:${request.url.path}:$timestamp:$nonce';

    final hmacSha256 = Hmac(sha256, utf8.encode(_hmacSecret));
    final digest = hmacSha256.convert(utf8.encode(signingString));

    request.headers['X-Nonce'] = nonce;
    request.headers['X-Timestamp'] = timestamp;
    request.headers['X-Signature'] = digest.toString();

    return _inner.send(request);
  }

  String _generateNonce() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
