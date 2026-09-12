// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TransferWatcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TransferWatcher")
    ]
)
