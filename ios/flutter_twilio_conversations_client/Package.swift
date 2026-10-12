// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_twilio_conversations_client",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "flutter-twilio-conversations-client", targets: ["flutter_twilio_conversations_client"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/twilio/conversations-ios", exact: "4.0.9")
    ],
    targets: [
        .target(
            name: "flutter_twilio_conversations_client",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "TwilioConversationsClient", package: "conversations-ios")
            ],
            resources: [
                // Declares no data collection or tracking; the plugin uses no required-reason APIs.
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
