import 'package:freezed_annotation/freezed_annotation.dart';

part 'ruleset_manifest.freezed.dart';
part 'ruleset_manifest.g.dart';

@freezed
class RulesetManifest with _$RulesetManifest {
  const RulesetManifest._();

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory RulesetManifest({
    required String version,
    required List<RulesetManifestFile> files,
  }) = _RulesetManifest;

  factory RulesetManifest.fromJson(Map<String, dynamic> json) => _$RulesetManifestFromJson(json);
}

@freezed
class RulesetManifestFile with _$RulesetManifestFile {
  const RulesetManifestFile._();

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory RulesetManifestFile({
    required String name,
  }) = _RulesetManifestFile;

  factory RulesetManifestFile.fromJson(Map<String, dynamic> json) => _$RulesetManifestFileFromJson(json);
}
