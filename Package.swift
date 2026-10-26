// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "EchoVela",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EchoVelaCore", targets: ["EchoVelaCore"]),
        .executable(name: "EchoVelaApp", targets: ["EchoVelaApp"])
    ],
    dependencies: [
        // Automatic updates. Pinned exactly; the packaged app embeds this framework.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "EchoVelaCore"),
        .executableTarget(
            name: "EchoVelaApp",
            dependencies: [
                "EchoVelaCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            linkerSettings: [
                // The packaged app keeps Sparkle.framework in Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(name: "EchoVelaTests", dependencies: ["EchoVelaCore"])
    ]
)
