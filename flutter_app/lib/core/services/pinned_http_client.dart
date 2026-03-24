import 'package:http/http.dart' as http;

import 'certificate_pinner.dart';

/// An [http.BaseClient] that validates SPKI SHA-256 certificate pins
/// before forwarding requests to the inner client.
///
/// Pinned domains (defined in [CertificatePins]) are validated on every
/// request (with TTL-based caching in [CertificatePinner]). Non-pinned
/// domains pass through unchanged with standard TLS validation.
///
/// Usage:
/// ```dart
/// final client = PinnedHttpClient(http.Client(), CertificatePinner());
/// // Pass to Supabase.initialize(httpClient: client)
/// ```
class PinnedHttpClient extends http.BaseClient {
  final http.Client _inner;
  final CertificatePinner _pinner;

  PinnedHttpClient(this._inner, this._pinner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final host = request.url.host;
    if (CertificatePins.isPinned(host)) {
      await _pinner.validate(host);
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
