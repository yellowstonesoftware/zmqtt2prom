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
    return Dictionary(
      uniqueKeysWithValues: devices.compactMap { device in
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
      }
    )
  }
}

struct DeviceInfo: Sendable {
  let device: Device
  let exposes: [FlattenedExpose]
}
