// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'podspec.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Podspec _$PodspecFromJson(Map<String, dynamic> json) => Podspec(
  dependencies:
      (json['dependencies'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, (e as List<dynamic>).map((e) => e as String).toList()),
      ) ??
      const {},
  platforms:
      (json['platforms'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  subspecs: json['subspecs'] as List<dynamic>? ?? const [],
);
