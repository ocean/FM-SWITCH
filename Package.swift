// swift-tools-version: 6.1
import PackageDescription

// fm1-catalogue builds the merged firmware list that fm-1.drewr.dev publishes as firmwares.json,
// with the app's own list code: App/Catalogue is the FM1Catalogue library here, and is also
// compiled straight into the app by the Xcode project.
//
// FM1Kit comes from its tagged release, matching project.yml. Set FM1KIT=local to use a checkout
// at ../FM1Kit instead.
let fm1Kit: Package.Dependency =
    Context.environment["FM1KIT"] == "local"
    ? .package(path: "../FM1Kit")
    : .package(url: "https://github.com/ocean/FM1Kit.git", .upToNextMinor(from: "0.4.3"))

let package = Package(
    name: "FM1Catalogue",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "fm1-catalogue", targets: ["fm1-catalogue"])
    ],
    dependencies: [fm1Kit],
    targets: [
        .target(name: "FM1Catalogue", dependencies: ["FM1Kit"], path: "App/Catalogue"),
        .executableTarget(name: "fm1-catalogue", dependencies: ["FM1Catalogue"], path: "Tools/fm1-catalogue"),
    ],
    swiftLanguageModes: [.v6]
)
