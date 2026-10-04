import 'package:freezed_annotation/freezed_annotation.dart';

part 'ruleset_manifest.freezed.dart';
part 'ruleset_manifest.g.dart';

/// The set of rule-set files this build's core expects: the ten `Path:`
/// literals in `hiddify-core/v2/config/builder.go`. Bump it whenever a set is
/// added, removed or renamed. A downloaded set is only ever installed when its
/// manifest carries this schema, and the mirror publishes each schema under its
/// own path, so a build never receives file names its core does not know.
const kRulesetSchema = 1;

@freezed
class RulesetManifest with _$RulesetManifest {
  const RulesetManifest._();

  /// [schema] is absent from every MANIFEST written before the mirror existed;
  /// those all describe the schema-1 file set, hence the default.
  ///
  /// [version] orders manifests: the newer one wins. It is a UTC timestamp
  /// (`2026-09-20T13:54:30Z`): the fetch time for the bundle, the publish time
  /// for the mirror. MANIFESTs written before that change carry a bare date
  /// (`2026-09-20`), read as midnight UTC. See [versionTime].
  ///
  /// [fetchedAt] is when the files were fetched from upstream. It is for
  /// people (logs, the About text, the release staleness warning), never for
  /// ordering: a mirror rollback re-publishes older files under a newer
  /// [version].
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory RulesetManifest({
    @Default(1) int schema,
    required String version,
    String? fetchedAt,
    required List<RulesetManifestFile> files,
  }) = _RulesetManifest;

  factory RulesetManifest.fromJson(Map<String, dynamic> json) => _$RulesetManifestFromJson(json);

  /// [version] as a UTC instant, or null when it is neither form above.
  DateTime? get versionTime => parseRulesetVersion(version);

  /// The file names this manifest lists.
  Set<String> get fileNames => {for (final file in files) file.name};
}

@freezed
class RulesetManifestFile with _$RulesetManifestFile {
  const RulesetManifestFile._();

  /// [sha256] is the lowercase hex digest of the file's bytes, and it is
  /// **required**: it is what makes re-extraction self-healing, so a MANIFEST
  /// that omits it must fail loudly at parse time rather than silently
  /// downgrade the check to "the file exists".
  ///
  /// [size] is the byte count. It lets a download be capped before the bytes
  /// arrive; the digest is still what decides whether they are right.
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory RulesetManifestFile({required String name, required String sha256, int? size}) = _RulesetManifestFile;

  factory RulesetManifestFile.fromJson(Map<String, dynamic> json) => _$RulesetManifestFileFromJson(json);
}

final _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final _utcTimestamp = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$');

/// Reads a manifest version: a bare date (midnight UTC) or a UTC timestamp
/// ending in `Z`. Anything else is null, including a timestamp without a zone,
/// which `DateTime.parse` would read in the device's local time and so order
/// differently from one device to the next.
DateTime? parseRulesetVersion(String version) {
  final date = _dateOnly.firstMatch(version);
  if (date != null) {
    final parsed = DateTime.utc(int.parse(date[1]!), int.parse(date[2]!), int.parse(date[3]!));
    // DateTime.utc rolls 2026-02-30 over into March; refuse it instead.
    final valid = parsed.month == int.parse(date[2]!) && parsed.day == int.parse(date[3]!);
    return valid ? parsed : null;
  }
  if (_utcTimestamp.hasMatch(version)) return DateTime.tryParse(version)?.toUtc();
  return null;
}
