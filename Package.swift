// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "KaidoRoutes",
  products: [
    .library(name: "KaidoDomain", targets: ["KaidoDomain"]),
    .library(name: "KaidoRouting", targets: ["KaidoRouting"]),
    .library(name: "KaidoNavigation", targets: ["KaidoNavigation"]),
    .library(name: "KaidoSurfaceRouting", targets: ["KaidoSurfaceRouting"]),
    .library(name: "KaidoAppleAdapters", targets: ["KaidoAppleAdapters"]),
    .library(name: "KaidoScenarioRunner", targets: ["KaidoScenarioRunner"]),
    .executable(name: "kaido-scenarios", targets: ["KaidoScenariosCLI"]),
    .executable(name: "kaido-surface-probe", targets: ["KaidoSurfaceProbeCLI"]),
    .executable(name: "kaido-surface-evidence", targets: ["KaidoSurfaceEvidenceCLI"]),
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
    .target(name: "KaidoSurfaceRouting"),
    .target(
      name: "KaidoAppleAdapters",
      dependencies: ["KaidoSurfaceRouting"]
    ),
    .target(
      name: "KaidoScenarioRunner",
      dependencies: ["KaidoDomain", "KaidoRouting", "KaidoNavigation"]
    ),
    .executableTarget(
      name: "KaidoScenariosCLI",
      dependencies: ["KaidoScenarioRunner"]
    ),
    .executableTarget(
      name: "KaidoSurfaceProbeCLI",
      dependencies: ["KaidoSurfaceRouting", "KaidoAppleAdapters"]
    ),
    .executableTarget(
      name: "KaidoSurfaceEvidenceCLI",
      dependencies: ["KaidoSurfaceRouting"]
    ),
    .testTarget(
      name: "KaidoScenarioTests",
      dependencies: [
        "KaidoDomain",
        "KaidoRouting",
        "KaidoNavigation",
        "KaidoSurfaceRouting",
        "KaidoAppleAdapters",
        "KaidoScenarioRunner",
      ]
    ),
  ]
)
