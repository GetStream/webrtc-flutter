// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "stream_webrtc_flutter",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "stream-webrtc-flutter", targets: ["stream_webrtc_flutter"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/GetStream/stream-video-swift-webrtc.git", exact: "137.0.54"
        )

    ],
    targets: [
        .target(
            name: "stream_webrtc_flutter",
            dependencies: [
                .product(name: "StreamWebRTC", package: "stream-video-swift-webrtc")
            ],
            path: "ios/stream_webrtc_flutter/Sources/stream_webrtc_flutter",
            resources: []
        )
    ]
)
