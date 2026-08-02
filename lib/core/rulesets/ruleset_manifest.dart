import 'package:freezed_annotation/freezed_annotation.dart';

part 'ruleset_manifest.freezed.dart';
part 'ruleset_manifest.g.dart';

@freezed
class RulesetManifest with _$RulesetManifest {
  const RulesetManifest._();

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory RulesetManifest({required String version, required List<RulesetManifestFile> files}) = _RulesetManifest;

  factory RulesetManifest.fromJson(Map<String, dynamic> json) => _$RulesetManifestFromJson(json);
}

@freezed
class RulesetManifestFile with _$RulesetManifestFile {
  const RulesetManifestFile._();

  /// [sha256] is the lowercase hex digest of the file's bytes, and it is
  /// **required**: it is what makes re-extraction self-healing, so a MANIFEST
  /// that omits it must fail loudly at parse time rather than silently
  /// downgrade the check to "the file exists". `size` is present in the JSON
  /// but deliberately not modelled — the digest subsumes it.
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory RulesetManifestFile({required String name, required String sha256}) = _RulesetManifestFile;

  factory RulesetManifestFile.fromJson(Map<String, dynamic> json) => _$RulesetManifestFileFromJson(json);
}
