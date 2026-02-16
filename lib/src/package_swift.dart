/// Template Package.swift file
String packageSwiftContent({
  required String pluginName,
  String? iOSTarget,
  String? macOSTarget,
  
}) {
  final platforms = [
    if (iOSTarget != null) '.iOS($iOSTarget)',
    if (macOSTarget != null) '.macOS($macOSTarget)',
  ].join(', ');

  final libraryName = pluginName.replaceAll('_', '-');

  return '''
// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "$pluginName",
    platforms: [ $platforms ],
    products: [
        .library(name: "$libraryName", targets: ["$pluginName"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "$pluginName",
            dependencies: [],
            resources: [
                // TODO: If your plugin requires a privacy manifest
                // (e.g. if it uses any required reason APIs), update the PrivacyInfo.xcprivacy file
                // to describe your plugin's privacy impact, and then uncomment this line.
                // For more information, see:
                // https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
                // .process("PrivacyInfo.xcprivacy"),

                // TODO: If you have other resources that need to be bundled with your plugin, refer to
                // the following instructions to add them:
                // https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package
            ]
        )
    ]
)
''';
}
