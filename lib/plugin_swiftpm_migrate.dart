import 'dart:convert';
import 'dart:io';

import 'package:ansicolor/ansicolor.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:spm_migrator/src/model/podspec.dart';
import 'package:spm_migrator/src/package_swift.dart';

/// Yellow pen
final yellow = AnsiPen()..yellow();

/// Green pen
final green = AnsiPen()..green();

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

  green('Migration complete. See the documentation for help.');
  print(
    'https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors',
  );
}

/// Migrate a plugin platform to Swift Package Manager
void migratePlatform({required String platform, required String pluginName}) {
  if (!Directory(platform).existsSync()) return;

  print('Migrating $platform...');

  final sourcesDirectory = Directory(
    path.join(platform, pluginName, 'Sources', pluginName),
  );

  sourcesDirectory.createSync(recursive: true);

  final privacyManifest = File(
    path.join(platform, 'Resources', 'PrivacyInfo.xcprivacy'),
  );

  final hasPrivacyManifest = privacyManifest.existsSync();

  if (hasPrivacyManifest) {
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

  final podspecJson = Process.runSync('pod', [
    'ipc',
    'spec',
    '$pluginName.podspec',
  ], workingDirectory: platform);

  final podspec = Podspec.fromJson(jsonDecode(podspecJson.stdout));

  if (podspec.subspecs.isNotEmpty) {
    yellow('Subspecs detected. This will need manual migration.');
  }

  final packageSwift = packageSwiftContent(
    pluginName: pluginName,
    iOSTarget: podspec.platforms['ios'],
    macOSTarget: podspec.platforms['macos'],
    hasPrivacyManifest: hasPrivacyManifest,
  );
  File(
    path.join(platform, pluginName, 'Package.swift'),
  ).writeAsStringSync(packageSwift);

  final podspecFile = File(path.join(platform, '$pluginName.podspec'));
  final podspecContent = podspecFile.readAsStringSync();
  final newPodspecContent = podspecContent
      .replaceFirst(
        "s.source_files = 'Classes/**/*.swift'",
        "s.source_files = '$pluginName/Sources/$pluginName/**/*.swift'",
      )
      .replaceFirst(
        "s.resource_bundles = {'${pluginName}_privacy' => ['Resources/PrivacyInfo.xcprivacy']}",
        "s.resource_bundles = {'${pluginName}_privacy' => ['$pluginName/Sources/$pluginName/PrivacyInfo.xcprivacy']}",
      );

  podspecFile.writeAsStringSync(newPodspecContent);

  /// grep -r --include="*.swift" "Bundle(for: Self\.self)" .
  final bundleGrepResult = Process.runSync('grep', [
    '-r',
    '--include="*.swift"',
    r'Bundle(for: Self\.self)',
    '.',
  ]);

  if (bundleGrepResult.stdout.isNotEmpty) {
    yellow('Resource loading detected. This will need manual migration.');
  }

  green('Migration complete for $platform\n');
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
