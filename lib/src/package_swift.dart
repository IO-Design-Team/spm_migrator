/// Template Package.swift file
String packageSwiftContent({
  required String pluginName,
  String? iOSTarget,
  String? macOSTarget,
  
  bool hasPrivacyManifest = false,
}) {
  final platforms = [
    if (iOSTarget != null) '.iOS("$iOSTarget")',
    if (macOSTarget != null) '.macOS("$macOSTarget")',
  ].join(',\n${' ' * 6}');

  final libraryName = pluginName.replaceAll('_', '-');
  final privacyManifestLine = hasPrivacyManifest
      ? '\n${' ' * 16}.process("PrivacyInfo.xcprivacy"),\n'
      : '';

  return '''
// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "$pluginName",
    platforms: [
      $platforms
    ],
    products: [
        .library(name: "$libraryName", targets: ["$pluginName"])
    ],
    targets: [
        .target(
            name: "$pluginName",
            dependencies: [],
            resources: [$privacyManifestLine
                // TODO: If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
''';
}
