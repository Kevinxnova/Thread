// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Thread", platforms: [.macOS(.v13)], products: [.executable(name: "Thread", targets: ["ThreadApp"])], targets: [.target(name: "ThreadCore"), .executableTarget(name: "ThreadApp", dependencies: ["ThreadCore"]), .testTarget(name: "ThreadCoreTests", dependencies: ["ThreadCore"]), .testTarget(name: "ThreadAppTests", dependencies: ["ThreadApp"])])
