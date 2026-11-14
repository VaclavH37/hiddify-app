import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/hiddifycore/core_interface/core_certificate_pin.dart';

/// The pin both cores' channels rest on: mobile since the authenticated mode,
/// Windows since upstream 092b5ee7's desktop half. The core hands its fresh
/// certificate over in-process, and the channel must accept those exact bytes
/// and nothing else.
void main() {
  final der = List<int>.generate(64, (i) => i);
  final pem = _pemOf(der);

  test('reads a PEM certificate', () {
    expect(CoreCertificatePin.fromPem(pem), isNotNull);
    expect(CoreCertificatePin.fromPem(pem)!.pem, pem);
  });

  test('refuses what is not one', () {
    expect(CoreCertificatePin.fromPem(Uint8List(0)), isNull);
    expect(CoreCertificatePin.fromPem(_bytes('-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n')), isNull);
    expect(CoreCertificatePin.fromPem(_bytes('not a certificate at all!')), isNull);
  });

  test('matches the pinned bytes and nothing else', () {
    final pin = CoreCertificatePin.fromPem(pem)!;
    expect(pin.matches(_Certificate(der)), isTrue);
    expect(pin.matches(_Certificate([...der.take(63), 0xFF])), isFalse, reason: 'one byte differs');
    expect(pin.matches(_Certificate(der.take(63).toList())), isFalse, reason: 'a different length');
    expect(pin.matches(_Certificate([])), isFalse);
  });

  test('the credentials pin the certificate both ways', () {
    // Both halves matter: certificates for the trust store, and onBadCertificate
    // because on iOS the trust store refuses the core's certificate outright.
    final credentials = CoreCertificatePin.fromPem(pem)!.credentials();
    expect(credentials.isSecure, isTrue);
    expect(credentials.onBadCertificate, isNotNull);
    expect(credentials.onBadCertificate!(_Certificate(der), '127.0.0.1'), isTrue);
    expect(credentials.onBadCertificate!(_Certificate(List<int>.filled(64, 7)), '127.0.0.1'), isFalse);
  });
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _pemOf(List<int> der) =>
    _bytes('-----BEGIN CERTIFICATE-----\n${base64.encode(der)}\n-----END CERTIFICATE-----\n');

class _Certificate implements X509Certificate {
  _Certificate(List<int> der) : der = Uint8List.fromList(der);

  @override
  final Uint8List der;

  @override
  String get pem => throw UnimplementedError();

  @override
  Uint8List get sha1 => throw UnimplementedError();

  @override
  String get subject => throw UnimplementedError();

  @override
  String get issuer => throw UnimplementedError();

  @override
  DateTime get startValidity => throw UnimplementedError();

  @override
  DateTime get endValidity => throw UnimplementedError();
}
