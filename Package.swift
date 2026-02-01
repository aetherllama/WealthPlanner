// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WealthPlanner",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "WealthPlanner",
            targets: ["WealthPlanner"]
        )
    ],
    dependencies: [
        // Plaid Link SDK for bank connections
        // Note: In a real project, add: .package(url: "https://github.com/plaid/plaid-link-ios", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "WealthPlanner",
            dependencies: [],
            path: "WealthPlanner"
        )
    ]
)
