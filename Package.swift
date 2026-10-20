// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tile",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Tile", targets: ["Tile"])],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.0")
    ],
    targets: [
        .executableTarget(name: "Tile", dependencies: ["SwiftTerm"])
    ]
)
