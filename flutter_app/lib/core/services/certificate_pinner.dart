import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';

/// SHA-256 SPKI pin configuration for certificate pinning.
///
/// Each domain maps to a set of base64-encoded SHA-256 hashes of the
/// SubjectPublicKeyInfo (SPKI) field from trusted certificates.
/// Include both the leaf and an intermediate/backup pin so that
/// routine certificate rotation does not break the app.
///
/// To extract a pin from a live server:
/// ```bash
/// openssl s_client -connect DOMAIN:443 -servername DOMAIN </dev/null 2>/dev/null \
///   | openssl x509 -pubkey -noout \
///   | openssl pkey -pubin -outform der \
///   | openssl dgst -sha256 -binary \
///   | base64
/// ```
class CertificatePins {
  CertificatePins._();

  static const Map<String, Set<String>> pins = {
    // Supabase project — leaf + intermediate (Google Trust Services WE1)
    'hieuxypdjrdweznedjsm.supabase.co': {
      'GU2W4j1P24T3sqlI+o6YTnidzz0PI8fB/Gvd2ITfSZE=', // leaf
      'kIdp6NNEd8wsugYyyIYFsi1ylMCED3hZbSR8ZFsa/A4=', // intermediate CA
    },
    // Go trading engine — add hashes when deployed.
    // 'api.stickerstadium.app': {
    //   '<leaf-spki-sha256-base64>',
    //   '<backup-spki-sha256-base64>',
    // },
  };

  static bool isPinned(String host) => pins.containsKey(host);
}

/// Thrown when a server's SPKI hash does not match any pinned value.
class CertificatePinningException implements Exception {
  final String host;
  final String? actualHash;

  CertificatePinningException(this.host, {this.actualHash});

  @override
  String toString() =>
      'CertificatePinningException: pin mismatch for $host'
      '${actualHash != null ? ' (got $actualHash)' : ''}';
}

/// Callback type for creating a [SecureSocket] connection.
/// Injectable for testing — production default is [SecureSocket.connect].
typedef SecureSocketConnector = Future<SecureSocket> Function(
  dynamic host,
  int port,
);

/// Validates server certificates against pinned SPKI SHA-256 hashes.
///
/// Usage:
/// ```dart
/// final pinner = CertificatePinner();
/// await pinner.validate('hieuxypdjrdweznedjsm.supabase.co');
/// ```
class CertificatePinner {
  final SecureSocketConnector _connect;
  final Duration cacheTtl;

  /// Cached validation results: host → expiry time.
  final Map<String, DateTime> _cache = {};

  CertificatePinner({
    SecureSocketConnector? connect,
    this.cacheTtl = const Duration(minutes: 5),
  }) : _connect = connect ?? SecureSocket.connect;

  /// Validates the certificate for [host] against its pinned SPKI hashes.
  ///
  /// Does nothing if [host] is not in [CertificatePins.pins].
  /// Throws [CertificatePinningException] if the server's SPKI hash
  /// does not match any pinned value.
  Future<void> validate(String host) async {
    if (!CertificatePins.isPinned(host)) return;

    final now = DateTime.now();
    final expiry = _cache[host];
    if (expiry != null && now.isBefore(expiry)) return;

    final socket = await _connect(host, 443);
    try {
      final cert = socket.peerCertificate;
      if (cert == null) {
        throw CertificatePinningException(host);
      }

      final hash = computeSpkiSha256(Uint8List.fromList(cert.der));
      final pins = CertificatePins.pins[host]!;

      if (!pins.contains(hash)) {
        throw CertificatePinningException(host, actualHash: hash);
      }

      _cache[host] = now.add(cacheTtl);
    } finally {
      await socket.close();
    }
  }

  /// Clears the validation cache, forcing re-validation on next request.
  void clearCache() => _cache.clear();

  /// Computes the base64-encoded SHA-256 hash of the SubjectPublicKeyInfo
  /// field extracted from a DER-encoded X.509 certificate.
  static String computeSpkiSha256(Uint8List derCert) {
    final spkiBytes = extractSpki(derCert);
    final digest = sha256.convert(spkiBytes);
    return base64.encode(digest.bytes);
  }

  /// Extracts the SubjectPublicKeyInfo (SPKI) DER bytes from a
  /// DER-encoded X.509 certificate.
  ///
  /// X.509 TBSCertificate layout (v3):
  ///   [0] version, serialNumber, signature, issuer, validity,
  ///   subject, subjectPublicKeyInfo, ...
  ///
  /// The version field is tagged [0] and optional (absent in v1).
  /// SPKI is at index 6 when version is present, index 5 otherwise.
  static Uint8List extractSpki(Uint8List derCert) {
    final parser = ASN1Parser(derCert);
    final cert = parser.nextObject() as ASN1Sequence;
    final tbsCert = cert.elements[0] as ASN1Sequence;

    // Check whether the optional version tag [0] is present.
    final firstElement = tbsCert.elements[0];
    final hasVersion = firstElement.tag == 0xA0;
    final spkiIndex = hasVersion ? 6 : 5;

    final spki = tbsCert.elements[spkiIndex];
    return Uint8List.fromList(spki.encodedBytes);
  }
}
