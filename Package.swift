// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlackBoxCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "BlackBoxCore", targets: ["BlackBoxCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "BlackBoxCore", dependencies: ["CSQLite"]),
        .testTarget(name: "BlackBoxCoreTests", dependencies: ["BlackBoxCore"])
    ]
)
