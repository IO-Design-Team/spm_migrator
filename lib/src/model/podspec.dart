import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

part 'podspec.g.dart';

/// The fields from the podspec that we need for the SPM migration
@JsonSerializable()
@immutable
class Podspec {
  /// The dependencies of the plugin
  final Map<String, List<String>> dependencies;

  /// The platforms that the plugin supports
  final Map<String, String> platforms;

  /// Constructor
  const Podspec({required this.dependencies, required this.platforms});

  /// From json
  factory Podspec.fromJson(Map<String, dynamic> json) => _$PodspecFromJson(json);

  /// To json
  Map<String, dynamic> toJson() => _$PodspecToJson(this);
}
