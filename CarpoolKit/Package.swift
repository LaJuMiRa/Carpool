// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CarpoolKit",
    defaultLocalization: "de",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "CarpoolKit", targets: ["CarpoolKit"]),
        .library(name: "CarpoolUI", targets: ["CarpoolUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "CarpoolKit",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ]
        ),
        .target(
            name: "CarpoolUI",
            dependencies: ["CarpoolKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CarpoolKitTests",
            dependencies: ["CarpoolKit"]
        ),
        .testTarget(
            name: "CarpoolUITests",
            dependencies: ["CarpoolUI"]
        )
    ]
)
