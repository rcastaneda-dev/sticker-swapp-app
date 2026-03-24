import 'package:http/http.dart' as http;

import 'attestation_service.dart';

/// An [http.BaseClient] that attaches device attestation headers to
/// every outgoing request.
///
/// Works alongside [PinnedHttpClient] in a layered client chain:
/// ```
/// AttestedHttpClient → PinnedHttpClient → http.Client()
/// ```
///
/// Adds two headers when an attestation token is available:
/// - `X-Attestation-Token`: the platform-specific attestation token
/// - `X-Attestation-Platform`: `"android"` or `"ios"`
///
/// When attestation is unavailable (web, emulator, platform exception),
/// the request is sent without attestation headers. The Go backend's
/// `ATTESTATION_DISABLED=true` env var handles this for local development.
class AttestedHttpClient extends http.BaseClient {
  final http.Client _inner;
  final AttestationService _attestation;

  AttestedHttpClient(this._inner, this._attestation);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _attestation.getAttestationToken();
    final platform = _attestation.platform;

    if (token != null && platform != null) {
      request.headers['X-Attestation-Token'] = token;
      request.headers['X-Attestation-Platform'] = platform;
    }

    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
