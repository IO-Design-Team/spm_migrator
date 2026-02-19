import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as path;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:recase/recase.dart';
import 'package:spm_migrator/pens.dart';
import 'package:spm_migrator/podspec.dart';
import 'package:spm_migrator/package_swift.dart';
import 'package:spm_migrator/pubspec.dart';

void main(List<String> args) async {
  final runner =
      CommandRunner<void>(
          'spm_migrator',
          'Easily migrate a Flutter plugin to support Swift Package Manager',
        )
        ..addCommand(MigrateCommand())
        ..addCommand(ValidateCommand());

  await runner.run(args);
}

class MigrateCommand extends Command<void> {
  @override
  String get name => 'migrate';

  @override
  String get description =>
      'Migrate a Flutter plugin to support Swift Package Manager';

  @override
  Future<void> run() async {
    final pubspec = parsePubspec();
    final pluginName = pubspec.name;

    for (final platform in ['ios', 'macos', 'darwin']) {
      migratePlatform(platform: platform, pluginName: pluginName);
    }

    migratePigeon(pluginName: pluginName);
    migrateGitignore();
    await validate(pubspec: pubspec);

    print(green('Migration complete. See the documentation for help:'));
    print(
      'https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors',
    );
  }
}

class ValidateCommand extends Command<void> {
  @override
  String get name => 'validate';

  @override
  String get description =>
      'Validate CocoaPods and SwiftPM builds for all supported platforms';

  @override
  Future<void> run() async {
    final pubspec = parsePubspec();
    await validate(pubspec: pubspec, requestConfirmation: false);
  }
}

Pubspec parsePubspec() {
  final pubspecFile = File('pubspec.yaml');
  final pubspecContent = pubspecFile.readAsStringSync();
  return Pubspec.parse(pubspecContent);
}

bool confirm(String message) {
  stdout.write('$message (y/n): ');
  final answer = stdin.readLineSync();
  return answer == 'y';
}

void needsManualMigration(String item) {
  print(yellow('$item detected. This will need manual migration.'));
}

void migratePlatform({required String platform, required String pluginName}) {
  if (!Directory(platform).existsSync()) return;

  print('Migrating $platform...');

  final classesDirectory = Directory(path.join(platform, 'Classes'));
  final swiftFiles = classesDirectory
      .listSync(recursive: true)
      .whereType<File>()
      .where((e) => path.extension(e.path) == '.swift');
  final objectiveCFiles = classesDirectory
      .listSync(recursive: true)
      .whereType<File>()
      .where((e) => {'.m', '.h'}.contains(path.extension(e.path)));

  if (swiftFiles.isNotEmpty && objectiveCFiles.isNotEmpty) {
    print(
      yellow(
        'The $platform directory contains both Swift and Objective-C files.'
        ' SwiftPM does not support mixed language targets.'
        ' If you did not write any Objective-C, the plugin can be automatically migrated.'
        ' If this plugin does contain Objective-C code, it will need to be manually migrated to a split-target plugin.'
        ' See the in_app_purchase plugin for an example.',
      ),
    );
    if (!confirm('Migrate plugin to Swift only?')) {
      print(red('Migration aborted for $platform'));
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
    privacyManifest.copySync(
      path.join(sourcesDirectory.path, 'PrivacyInfo.xcprivacy'),
    );
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

  if (podspec.dependencies.keys.any((e) => e != 'Flutter')) {
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
    '--include=*.swift',
    r'Bundle(for: Self\.self)',
    platform,
  ]);

  if (bundleGrepResult.stdout.isNotEmpty) {
    needsManualMigration('Resource loading');
  }

  print(green('Migration complete for $platform\n'));
}

void migratePigeon({required String pluginName}) {
  final dartFiles = Directory.current
      .listSync(recursive: true)
      .whereType<File>()
      .where((e) => e.path.endsWith('.dart'));

  for (final file in dartFiles) {
    final content = file.readAsStringSync();
    if (!content.contains('@ConfigurePigeon')) continue;

    final newContent = content.replaceAllMapped(
      RegExp(r"((?:swiftOut|objcHeaderOut|objcSourceOut): '.+?)\/Classes\/"),
      (m) => '${m[1]}/$pluginName/Sources/$pluginName/',
    );
    file.writeAsStringSync(newContent);
  }
}

void migrateGitignore() {
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
}

Future<void> validate({
  required Pubspec pubspec,
  bool requestConfirmation = true,
}) async {
  if (!File(path.join('example', 'pubspec.yaml')).existsSync()) {
    print(yellow('No example project found. Manual validation is required.'));
    return;
  }

  if (requestConfirmation &&
      !confirm(
        'Do you want to validate the builds for all supported platforms?'
        ' If manual migrations are required, the build will likely fail.',
      )) {
    return;
  }

  final flutterConfigResult = Process.runSync('flutter', ['config', '--list']);
  final wasSpmEnabled = flutterConfigResult.stdout.contains(
    'enable-swift-package-manager: true',
  );

  final supportedPlatforms = readSupportedPlatforms(pubspec.flutter);
  final supportedDarwinPlatforms = supportedPlatforms.intersection({
    'ios',
    'macos',
  });

  var exitCode = 0;
  for (final platform in supportedDarwinPlatforms) {
    exitCode |= await validatePlatform(platform: platform);
    if (exitCode != 0) break;
  }

  if (exitCode == 0) {
    print(green('Validation complete'));
  } else {
    print(red('Validation failed'));
    print('Fix any issues and run `spm_migrator validate` to try again');
  }
}

Future<int> buildForPlatform({
  required String platform,
  required String packageManager,
}) async {
  print('Validating $packageManager build for $platform...');

  final configFlag = packageManager == 'CocoaPods'
      ? '--no-enable-swift-package-manager'
      : '--enable-swift-package-manager';
  Process.runSync('flutter', ['config', configFlag]);
  Process.runSync('flutter', ['clean'], workingDirectory: 'example');
  Process.runSync('flutter', ['pub', 'get'], workingDirectory: 'example');
  final process = await Process.start(
    'flutter',
    ['build', platform],
    workingDirectory: 'example',
    mode: ProcessStartMode.inheritStdio,
  );

  final exitCode = await process.exitCode;
  if (exitCode == 0) {
    print(green('$packageManager build successful for $platform\n'));
  } else {
    print(red('$packageManager build failed for $platform'));
  }

  return exitCode;
}

Future<int> validatePlatform({required String platform}) async {
  final cocoaPodsExitCode = await buildForPlatform(
    platform: platform,
    packageManager: 'CocoaPods',
  );
  if (cocoaPodsExitCode != 0) return cocoaPodsExitCode;

  final swiftPMExitCode = await buildForPlatform(
    platform: platform,
    packageManager: 'SwiftPM',
  );
  if (swiftPMExitCode != 0) return swiftPMExitCode;

  return 0;
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
