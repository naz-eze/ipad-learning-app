// swift-tools-version: 5.9

// WARNING:
// This is a Swift Playgrounds app package. It opens in Swift Playgrounds on
// iPad/Mac and in Xcode. Swift Playgrounds may regenerate this file.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "PianoFall",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "PianoFall",
            targets: ["AppModule"],
            bundleIdentifier: "com.nazeze.PianoFall",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .heart),
            accentColor: .presetColor(.green),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft
            ],
            appCategory: .music
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
