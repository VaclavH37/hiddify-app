import 'dart:io' show ZLibDecoder;

/// The newest rule-set format this build's core reads: `RuleSetVersionCurrent`
/// in `hiddify-core/hiddify-sing-box/constant/rule.go`. A file in a newer
/// format fails the core's next start (`unsupported version: N`), so a
/// download in one is refused, and this build keeps the set it has. Update it
/// with the core.
const kMaxSrsVersion = 5;

/// The most a rule-set body may inflate to. Today's largest file inflates to
/// well under 2 MiB; the cap exists so a crafted body cannot exhaust memory,
/// which on iOS would take the tunnel extension down with it.
const srsInflatedCap = 16 << 20;

const _magic = [0x53, 0x52, 0x53]; // "SRS"

/// Why [bytes] would not load as a rule-set in this build's core, or null when
/// it would as far as can be told without a full parser.
///
/// It checks the header (the `SRS` magic and a format version from 1 to
/// [maxVersion]), that the zlib body inflates within [srsInflatedCap] and
/// matches the Adler-32 checksum zlib stores in its last four bytes, and that
/// it declares at least one rule. The checksum is computed here because
/// `dart:io`'s decoder does not verify it: it inflates half a file without
/// complaint. The mirror's pipeline has already loaded every file with the
/// real core; this is the second line, for whatever a CDN, a cache or a bug
/// between the two could do to the bytes, and for a format newer than this
/// build's core.
String? srsProblem(List<int> bytes, {int maxVersion = kMaxSrsVersion}) {
  if (bytes.length < 5) return 'too short to be a rule-set';
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) return 'not a rule-set file';
  }
  final version = bytes[3];
  if (version < 1 || version > maxVersion) return 'format version $version; this build reads 1 to $maxVersion';

  final body = _CappedSink(srsInflatedCap);
  try {
    ZLibDecoder().startChunkedConversion(body)
      ..addSlice(bytes, 4, bytes.length, false)
      ..close();
  } on _TooLarge {
    return 'body inflates past $srsInflatedCap bytes';
  } on FormatException catch (e) {
    return 'body does not inflate (${e.message})';
  }

  final n = bytes.length;
  final stored = (bytes[n - 4] << 24) | (bytes[n - 3] << 16) | (bytes[n - 2] << 8) | bytes[n - 1];
  if (body.adler32 != stored) return 'body is incomplete or damaged (checksum mismatch)';

  final ruleCount = _readUvarint(body.head);
  if (ruleCount == null) return 'body ends before its rule count';
  if (ruleCount == 0) return 'body declares no rules';
  return null;
}

class _TooLarge implements Exception {}

/// Counts what the decoder produces, keeps the first bytes, runs zlib's
/// Adler-32 over all of it, and stops at [cap].
class _CappedSink implements Sink<List<int>> {
  _CappedSink(this.cap);

  static const _adlerMod = 65521;

  final int cap;
  final head = <int>[];
  int length = 0;
  var _a = 1;
  var _b = 0;

  int get adler32 => (_b << 16) | _a;

  @override
  void add(List<int> chunk) {
    length += chunk.length;
    if (length > cap) throw _TooLarge();
    if (head.length < 10) head.addAll(chunk.take(10 - head.length));
    var a = _a;
    var b = _b;
    for (final byte in chunk) {
      a = (a + byte) % _adlerMod;
      b = (b + a) % _adlerMod;
    }
    _a = a;
    _b = b;
  }

  @override
  void close() {}
}

/// A protobuf-style unsigned varint, as Go's `binary.ReadUvarint` reads the
/// rule count. Null when [bytes] end mid-number or it runs past 10 bytes.
int? _readUvarint(List<int> bytes) {
  var value = 0;
  var shift = 0;
  for (final byte in bytes) {
    value |= (byte & 0x7f) << shift;
    if (byte < 0x80) return value;
    shift += 7;
    if (shift > 63) return null;
  }
  return null;
}
