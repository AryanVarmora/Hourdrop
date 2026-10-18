// swift-tools-version: 6.0
// Lets `swift test` check Hourdrop's logic. Run the tests with:  bash test.sh
// The app itself is still built by build.sh, from every file in Sources/.
import PackageDescription

let package = Package(
    name: "Hourdrop",
    platforms: [.macOS(.v14)],
    targets: [
        // All of Hourdrop's code except HourdropApp.swift, the file that starts the app,
        // so the tests can use it.
        .target(
            name: "HourdropCore",
            path: "Sources",
            exclude: ["HourdropApp.swift"]
        ),
        .testTarget(
            name: "HourdropTests",
            dependencies: ["HourdropCore"],
            path: "Tests/HourdropTests"
        ),
    ],
    // Same Swift language mode as build.sh uses for the app.
    swiftLanguageModes: [.v5]
)
