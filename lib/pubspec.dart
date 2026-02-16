/// Read the platforms this plugin supports from the pubspec.yaml
Set<String> readSupportedPlatforms(Map<String, dynamic>? flutter) {
  if (flutter == null) return {};

  final plugin = (flutter['plugin'] as Map?)?.cast<String, dynamic>();
  if (plugin == null) return {};

  final platforms = (plugin['platforms'] as Map?)?.cast<String, dynamic>();
  if (platforms == null) return {};

  return platforms.keys.toSet();
}
