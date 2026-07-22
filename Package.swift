// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "KaidoRoutes",
  products: [
    .library(name: "KaidoDomain", targets: ["KaidoDomain"]),
    .library(name: "KaidoRouting", targets: ["KaidoRouting"]),
    .library(name: "KaidoNavigation", targets: ["KaidoNavigation"]),
    .library(name: "KaidoScenarioRunner", targets: ["KaidoScenarioRunner"]),
    .executable(name: "kaido-scenarios", targets: ["KaidoScenariosCLI"]),
  ],
  targets: [
    .target(name: "KaidoDomain"),
    .target(
      name: "KaidoRouting",
      dependencies: ["KaidoDomain"]
    ),
    .target(
      name: "KaidoNavigation",
      dependencies: ["KaidoDomain", "KaidoRouting"]
    ),
    .target(
      name: "KaidoScenarioRunner",
      dependencies: ["KaidoDomain", "KaidoRouting", "KaidoNavigation"]
    ),
    .executableTarget(
      name: "KaidoScenariosCLI",
      dependencies: ["KaidoScenarioRunner"]
    ),
    .testTarget(
      name: "KaidoScenarioTests",
      dependencies: [
        "KaidoDomain",
        "KaidoRouting",
        "KaidoNavigation",
        "KaidoScenarioRunner",
      ]
    ),
  ]
)
