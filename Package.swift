// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "RouteBar",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "RouteBarCore", targets: ["RouteBarCore"]),
    .executable(name: "routebar", targets: ["RouteBarCLI"]),
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
    .testTarget(
      name: "RouteBarCoreTests",
      dependencies: ["RouteBarCore"]
    ),
  ]
)
