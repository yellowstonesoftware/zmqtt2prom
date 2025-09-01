// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "zmqtt2prom",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "zmqtt2prom",
      targets: ["zmqtt2prom"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-metrics.git", from: "2.5.0"),
    .package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0"),
    .package(url: "https://github.com/swift-server-community/mqtt-nio.git", from: "2.10.0"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
    .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.30.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.1"),
    .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "zmqtt2prom",
      dependencies: [
        .product(name: "Metrics", package: "swift-metrics"),
        .product(name: "Prometheus", package: "swift-prometheus"),
        .product(name: "MQTTNIO", package: "mqtt-nio"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOSSL", package: "swift-nio-ssl"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "Logging", package: "swift-log"),
        .product(name: "Hummingbird", package: "hummingbird"),
      ]
    ),
    .testTarget(
      name: "zmqtt2promTests",
      dependencies: ["zmqtt2prom"]
    ),
  ]
)
