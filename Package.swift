// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DuplicateFinder",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
    ],
    products: [
        .library(name: "DuplicateFinderCore", targets: ["DuplicateFinderCore"]),
        .executable(name: "dupefind", targets: ["dupefind"]),
        .executable(name: "DuplicateFinderMac", targets: ["DuplicateFinderMac"]),
    ],
    targets: [
        .target(
            name: "DuplicateFinderCore",
            path: "Sources/DuplicateFinderCore"
        ),
        .executableTarget(
            name: "dupefind",
            dependencies: ["DuplicateFinderCore"],
            path: "Sources/dupefind"
        ),
        .executableTarget(
            name: "DuplicateFinderMac",
            dependencies: ["DuplicateFinderCore"],
            path: "Sources/DuplicateFinderMac"
        ),
        .testTarget(
            name: "DuplicateFinderCoreTests",
            dependencies: ["DuplicateFinderCore"],
            path: "Tests/DuplicateFinderCoreTests"
        ),
    ]
)
