// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PDFtoExcel",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(
            name: "PDFtoExcel",
            targets: ["PDFtoExcel"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/weichsel/ZIPFoundation.git",
            .upToNextMajor(from: "0.9.0")
        )
    ],
    targets: [
        .executableTarget(
            name: "PDFtoExcel",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"], .when(configuration: .release))
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Vision"),
                .linkedFramework("Combine"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
