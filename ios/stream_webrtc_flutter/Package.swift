// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "stream_webrtc_flutter",
    platforms: [
        .iOS("13.0")  // update as needed
    ],
    products: [
        .library(name: "stream-webrtc-flutter", targets: ["stream_webrtc_flutter"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/GetStream/stream-video-swift-webrtc.git", exact: "125.6422.070"
        )

    ],
    targets: [
        .target(
            name: "stream_webrtc_flutter",
            dependencies: [
                .product(name: "StreamWebRTC", package: "stream-video-swift-webrtc")
            ],
            resources: [
                // If you have PrivacyInfo.xcprivacy or other resources:
                // .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
