import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:recase/recase.dart';
import 'package:spm_migrator/pens.dart';
import 'package:spm_migrator/podspec.dart';
import 'package:spm_migrator/package_swift.dart';

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

  final gitignoreFile = File('.gitignore');
  if (gitignoreFile.existsSync()) {
    final lines = gitignoreFile.readAsLinesSync();
    if (!lines.contains('.build/')) lines.add('.build/');
    if (!lines.contains('.swiftpm/')) lines.add('.swiftpm/');
    gitignoreFile.writeAsStringSync(lines.join('\n'));
  } else {
    print(
      yellow('''
No .gitignore file found in this directory. Make sure to ignore the following:
.build/
.swiftpm/
'''),
    );
  }

  print(green('Migration complete. See the documentation for help:'));
  print(
    'https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors',
  );
}

void needsManualMigration(String item) {
  print(yellow('$item detected. This will need manual migration.'));
}

void migratePlatform({required String platform, required String pluginName}) {
  if (!Directory(platform).existsSync()) return;

  print('Migrating $platform...');

  final classesDirectory = Directory(path.join(platform, 'Classes'));
  final swiftFiles = classesDirectory.listSync().whereType<File>().where(
    (e) => path.extension(e.path) == '.swift',
  );
  final objectiveCFiles = classesDirectory.listSync().whereType<File>().where(
    (e) => {'.m', '.h'}.contains(path.extension(e.path)),
  );

  if (swiftFiles.isNotEmpty && objectiveCFiles.isNotEmpty) {
    print(
      yellow(
        'The $platform directory contains both Swift and Objective-C files.'
        ' SwiftPM does not support mixed language targets.'
        ' If you did not write any Objective-C, the plugin can be automatically migrated.',
      ),
    );
    stdout.write(yellow('Migrate plugin to Swift only? (y/n): '));
    final answer = stdin.readLineSync();
    if (answer != 'y') {
      print(red('Migration aborted'));
      return;
    }
    for (final file in objectiveCFiles) {
      file.deleteSync();
    }

    final pluginClass = '${pluginName.pascalCase}Plugin';

    final swiftPluginFileName = 'Swift$pluginClass.swift';
    final swiftPluginFile = File(
      path.join(platform, 'Classes', swiftPluginFileName),
    );
    if (swiftPluginFile.existsSync()) {
      final pluginSwiftContent = swiftPluginFile.readAsStringSync();
      final newPluginSwiftContent = pluginSwiftContent.replaceAll(
        'Swift$pluginClass',
        pluginClass,
      );
      swiftPluginFile.writeAsStringSync(newPluginSwiftContent);

      swiftPluginFile.renameSync(
        path.join(platform, 'Classes', '$pluginClass.swift'),
      );
    } else {
      print(
        yellow(
          '$swiftPluginFileName not found. Manual migration may be required.',
        ),
      );
    }
  }

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
    final contents = assetsDirectory.listSync();

    // The plugin template created an Assets directory with a .gitkeep file
    // Do not copy it if it is the only file in the directory
    final onlyGitkeep =
        contents.length == 1 &&
        path.basename(contents.first.path) == '.gitkeep';
    if (contents.isNotEmpty && !onlyGitkeep) {
      assetsDirectory.copySync(path.join(sourcesDirectory.path, 'Assets'));
    }

    assetsDirectory.deleteSync(recursive: true);
  }

  classesDirectory.copySync(sourcesDirectory.path);
  classesDirectory.deleteSync(recursive: true);

  final podspecJson = Process.runSync('pod', [
    'ipc',
    'spec',
    '$pluginName.podspec',
  ], workingDirectory: platform);

  final podspec = Podspec.fromJson(jsonDecode(podspecJson.stdout));

  if (podspec.subspecs.isNotEmpty) {
    needsManualMigration('Subspecs');
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

  if (podspec.dependencies.keys.where((e) => e != 'Flutter').isNotEmpty) {
    needsManualMigration('Podspec dependencies');
  }

  final podspecFile = File(path.join(platform, '$pluginName.podspec'));
  final podspecContent = podspecFile.readAsStringSync();
  final newPodspecContent = podspecContent
      .replaceFirst(
        "s.source_files = 'Classes/**/*'",
        "s.source_files = '$pluginName/Sources/$pluginName/**/*'",
      )
      .replaceFirst(
        "s.resource_bundles = {'${pluginName}_privacy' => ['Resources/PrivacyInfo.xcprivacy']}",
        "s.resource_bundles = {'${pluginName}_privacy' => ['$pluginName/Sources/$pluginName/PrivacyInfo.xcprivacy']}",
      );

  podspecFile.writeAsStringSync(newPodspecContent);

  final bundleGrepResult = Process.runSync('grep', [
    '-r',
    '--include="*.swift"',
    r'Bundle(for: Self\.self)',
    '.',
  ]);

  if (bundleGrepResult.stdout.isNotEmpty) {
    needsManualMigration('Resource loading');
  }

  print(green('Migration complete for $platform\n'));
}

extension DirectoryExtension on Directory {
  void copySync(String newPath) {
    for (final file in listSync(recursive: true).whereType<File>()) {
      final relativePath = path.relative(file.path, from: this.path);
      final targetPath = path.join(newPath, relativePath);

      Directory(path.dirname(targetPath)).createSync(recursive: true);
      file.copySync(targetPath);
    }
  }
}
