// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QuakeKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "QuakeKit", targets: ["QuakeKit"]),
    ],
    targets: [
        .target(name: "QuakeKit"),
        .testTarget(
            name: "QuakeKitTests",
            dependencies: ["QuakeKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
