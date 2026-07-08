// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FocusLensMacMVP",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FocusLensMacMVP",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ScreenCaptureKit")
            ]
        )
    ]
)
