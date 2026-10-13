// swift-tools-version: 6.0
import Foundation
import PackageDescription

let kit: Package.Dependency = ProcessInfo.processInfo.environment["VIALETKIT_PATH"]
    .map { .package(path: $0) } ?? .package(url: "https://github.com/avialet/vialetkit.git", .upToNextMinor(from: "0.2.5"))

let package = Package(
    name: "RangeCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RangeCore", targets: ["RangeCore"]),
    ],
    dependencies: [
        kit,
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(
            name: "RangeCore",
            dependencies: [
                .product(name: "VialetKit", package: "vialetkit"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        // Harnais de tests : XCTest et Swift Testing ne sont pas livres avec
        // les Command Line Tools (voir docs/tests.md).
        .executableTarget(
            name: "rangecore-check",
            dependencies: ["RangeCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        // Essai en ligne de commande sur un dossier jetable (clone de Telechargements) :
        // apercu, rangement et annulation complete, sans l'app.
        .executableTarget(
            name: "range-essai",
            dependencies: ["RangeCore"]
        ),
    ]
)
