import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';

void main() {
  final pubspecFile = File('pubspec.yaml');
  final pubspecContent = pubspecFile.readAsStringSync();
  final pubspec = Pubspec.parse(pubspecContent);

  for (final platform in ['ios', 'macos', 'darwin']) {
    migratePlatform(platform: platform, pluginName: pubspec.name);
  }
}

void migratePlatform({required String platform, required String pluginName}) {
  final podspecJson = Process.runSync('pod', [
    'ipc',
    'spec',
  ], workingDirectory: platform);

  Directory(
    path.join(platform, pluginName, 'Sources', pluginName),
  ).createSync(recursive: true);
}
