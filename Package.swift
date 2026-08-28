// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeleteWhenUnzipMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "DeleteWhenUnzipCore",
            targets: ["DeleteWhenUnzipCore"]
        ),
        .executable(
            name: "dwum",
            targets: ["DeleteWhenUnzipCLI"]
        ),
        .executable(
            name: "DeleteWhenUnzipMac",
            targets: ["DeleteWhenUnzipApp"]
        )
    ],
    dependencies: [],
    targets: [
        .systemLibrary(
            name: "Clibarchive",
            pkgConfig: "libarchive",
            providers: [
                .brew(["libarchive"])
            ]
        ),
        .target(
            name: "DeleteWhenUnzipCore",
            dependencies: ["Clibarchive"],
            swiftSettings: [
                .unsafeFlags([
                    "-I/opt/homebrew/opt/libarchive/include",
                    "-I/usr/local/opt/libarchive/include"
                ])
            ],
            linkerSettings: [
                .linkedLibrary("archive"),
                .unsafeFlags([
                    "-L/opt/homebrew/opt/libarchive/lib",
                    "-L/usr/local/opt/libarchive/lib"
                ])
            ]
        ),
        .executableTarget(
            name: "DeleteWhenUnzipCLI",
            dependencies: ["DeleteWhenUnzipCore"]
        ),
        .executableTarget(
            name: "DeleteWhenUnzipApp",
            dependencies: ["DeleteWhenUnzipCore"]
        ),
        .testTarget(
            name: "DeleteWhenUnzipCoreTests",
            dependencies: ["DeleteWhenUnzipCore"]
        )
    ]
)
