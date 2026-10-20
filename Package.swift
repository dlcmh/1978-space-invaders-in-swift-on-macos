// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpaceInvadersArcade",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SpaceInvadersArcade", targets: ["SpaceInvadersArcade"])
    ],
    targets: [
        .target(
            name: "SpaceInvadersCore"
        ),
        .executableTarget(
            name: "SpaceInvadersArcade",
            dependencies: ["SpaceInvadersCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "SpaceInvadersChecks",
            dependencies: ["SpaceInvadersCore"],
            path: "Checks"
        )
    ]
)
