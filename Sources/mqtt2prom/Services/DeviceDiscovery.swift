import Foundation
import Logging

struct DeviceDiscovery {
  private static let logger = Logger(label: "zmqtt2prom.device-discovery")

  private init() {}

  static func parseDevices(from jsonData: Data) throws -> [Device] {
    logger.info("Parsing devices from bridge/devices message")

    let decoder = JSONDecoder()
    let devices = try decoder.decode([Device].self, from: jsonData)

    logger.info("Parsed \(devices.count) total devices")
    return devices
  }

  static func buildDeviceRegistry(_ devices: [Device]) -> [String: DeviceInfo] {
    // `uniqueKeysWithValues` traps on a duplicate key. Zigbee2MQTT does not guarantee
    // friendly_name uniqueness in every state - a hand-edited configuration.yaml or a
    // rename in flight can briefly produce two - and trapping here would crash-loop the
    // exporter over a recoverable condition. Keep the first and say so.
    return Dictionary(
      devices.compactMap { device in
        guard let definition = device.definition else {
          logger.warning("Device \(device.friendlyName) has no definition, skipping")
          return nil
        }

        let flattenedExposes = ExposeFlattener.flatten(definition.exposes)
        guard !flattenedExposes.isEmpty else {
          logger.warning("Device \(device.friendlyName) has no monitorable exposes, skipping")
          return nil
        }

        logger.info("Registered device \(device.friendlyName) with \(flattenedExposes.count) exposes")

        return (
          device.friendlyName,
          DeviceInfo(device: device, exposes: flattenedExposes)
        )
      },
      uniquingKeysWith: { first, _ in
        logger.warning("Duplicate friendly_name in bridge/devices, keeping the first entry")
        return first
      }
    )
  }
}

struct DeviceInfo: Sendable {
  let device: Device
  let exposes: [FlattenedExpose]
}
