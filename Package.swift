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
            // Neither file is a build input. Info.plist is embedded by the
            // linker below, and entitlements are applied at signing time by
            // Scripts/make-app.sh, so SwiftPM should leave both alone.
            exclude: [
                "PDFtoExcel/Info.plist",
                "PDFtoExcel/PDFtoExcel.entitlements"
            ],
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"], .when(configuration: .release))
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Vision"),
                .linkedFramework("Combine"),
                .linkedFramework("SwiftUI"),
                // Carry Info.plist inside the executable. A SwiftPM product is
                // a bare Mach-O, not an .app, so without this the bundle
                // identifier, document types and display settings the app
                // declares never reach the running process.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PDFtoExcel/Info.plist"
                ])
            ]
        )
    ]
)
