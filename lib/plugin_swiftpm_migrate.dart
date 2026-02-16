import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:spm_migrator/src/model/podspec.dart';

void main() {
  final pubspecFile = File('pubspec.yaml');
  final pubspecContent = pubspecFile.readAsStringSync();
  final pubspec = Pubspec.parse(pubspecContent);

  final pluginName = pubspec.name;

  for (final platform in ['ios', 'macos', 'darwin']) {
    migratePlatform(platform: platform, pluginName: pluginName);
  }

  final pigeonsFile = File(path.join('pigeons', 'messages.dart'));
  if (pigeonsFile.existsSync()) {
    final content = pigeonsFile.readAsStringSync();
    content.replaceFirstMapped(
      RegExp(r"swiftOut: '(.+?)\/Classes\/messages.g.swift',"),
      (m) =>
          "swiftOut: '${m[1]}/$pluginName/Sources/$pluginName/messages.g.swift',",
    );
  }
}

/// Migrate a plugin platform to Swift Package Manager
void migratePlatform({required String platform, required String pluginName}) {
  final podspecJson = Process.runSync('pod', [
    'ipc',
    'spec',
  ], workingDirectory: platform);

  final podspec = Podspec.fromJson(jsonDecode(podspecJson.stdout));

  final sourcesDirectory = Directory(
    path.join(platform, pluginName, 'Sources', pluginName),
  );

  sourcesDirectory.createSync(recursive: true);

  final privacyManifest = File(
    path.join(platform, 'Resources', 'PrivacyInfo.xcprivacy'),
  );

  if (privacyManifest.existsSync()) {
    privacyManifest.copySync(sourcesDirectory.path);
    Directory(path.join(platform, 'Resources')).deleteSync(recursive: true);
  }

  final assetsDirectory = Directory(path.join(platform, 'Assets'));
  if (assetsDirectory.existsSync()) {
    assetsDirectory.copySync(path.join(sourcesDirectory.path, 'Assets'));
    assetsDirectory.deleteSync(recursive: true);
  }

  final classesDirectory = Directory(path.join(platform, 'Classes'));
  classesDirectory.copySync(sourcesDirectory.path);
  classesDirectory.deleteSync(recursive: true);
}

/// Extension methods on [Directory]
extension DirectoryExtension on Directory {
  /// Copies this directory and all of its contents to [newPath]
  void copySync(String newPath) {
    for (final file in listSync(recursive: true).whereType<File>()) {
      final relativePath = path.relative(file.path, from: this.path);
      final targetPath = path.join(newPath, relativePath);

      Directory(path.dirname(targetPath)).createSync(recursive: true);
      file.copySync(targetPath);
    }
  }
}
