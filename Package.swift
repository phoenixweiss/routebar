// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "RouteBar",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "RouteBarCore", targets: ["RouteBarCore"]),
    .library(name: "RouteBarDaemonIPC", targets: ["RouteBarDaemonIPC"]),
    .executable(name: "routebar", targets: ["RouteBarCLI"]),
    .executable(name: "routebar-app", targets: ["RouteBarApp"]),
    .executable(name: "routebar-daemon", targets: ["RouteBarDaemon"]),
  ],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2")
  ],
  targets: [
    .target(
      name: "RouteBarCore",
      dependencies: [
        .product(name: "Yams", package: "Yams")
      ],
      linkerSettings: [
        .linkedFramework("CoreWLAN")
      ]
    ),
    .executableTarget(
      name: "RouteBarCLI",
      dependencies: ["RouteBarCore"]
    ),
    .executableTarget(
      name: "RouteBarApp",
      dependencies: ["RouteBarCore", "RouteBarDaemonIPC"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ServiceManagement"),
        .linkedFramework("SwiftUI"),
      ]
    ),
    .target(
      name: "RouteBarDaemonIPC",
      linkerSettings: [
        .linkedFramework("Security")
      ]
    ),
    .executableTarget(
      name: "RouteBarDaemon",
      dependencies: ["RouteBarDaemonIPC"]
    ),
    .testTarget(
      name: "RouteBarCoreTests",
      dependencies: ["RouteBarCore"]
    ),
    .testTarget(
      name: "RouteBarDaemonIPCTests",
      dependencies: ["RouteBarDaemonIPC"]
    ),
    .testTarget(
      name: "RouteBarAppTests",
      dependencies: ["RouteBarApp", "RouteBarDaemonIPC"]
    ),
  ]
)
