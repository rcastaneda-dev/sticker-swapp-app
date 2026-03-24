import 'package:http/http.dart' as http;

import 'device_integrity_service.dart';

/// An [http.BaseClient] that attaches the device integrity header to
/// every outgoing request.
///
/// Works alongside [AttestedHttpClient] and [PinnedHttpClient] in a
/// layered client chain:
/// ```
/// AttestedHttpClient → DeviceIntegrityHttpClient → PinnedHttpClient → http.Client()
/// ```
///
/// Adds one header when integrity status is known:
/// - `X-Device-Integrity`: `"compromised"` or `"clean"`
///
/// When status is unknown (web, detection failure), the header is omitted.
/// The Go backend defaults to "not compromised" when the header is absent.
class DeviceIntegrityHttpClient extends http.BaseClient {
  final http.Client _inner;
  final DeviceIntegrityService _integrityService;

  DeviceIntegrityHttpClient(this._inner, this._integrityService);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final value = await _integrityService.integrityHeaderValue;
    if (value != null) {
      request.headers['X-Device-Integrity'] = value;
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
