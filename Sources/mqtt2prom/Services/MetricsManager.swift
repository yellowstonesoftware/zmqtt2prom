import Foundation
import Logging
import Metrics
import Prometheus

actor MetricsManager {
  private let logger = Logger(label: "zmqtt2prom.metrics")

  public let registry = PrometheusCollectorRegistry()

  init() {
    logger.info("Initialized metrics manager")
  }

  func processPayload(
    _ payload: [String: Any],
    for deviceInfo: DeviceInfo
  ) {
    logger.trace("Processing payload [\(payload)] for device \(deviceInfo.device.friendlyName)")

    for expose in deviceInfo.exposes {
      guard let value = payload[expose.property] else {
        logger.warning("No value for property \(expose.property) for device \(deviceInfo.device.friendlyName)")
        continue
      }
      // TODO externalize this Set to configuration
      guard !Set(["power_on_behavior"]).contains(expose.property) else {
        logger.trace("Skipping \(expose.property) \(deviceInfo.device.friendlyName)")
        continue
      }
      let device = deviceInfo.device
      let labels = [
        ("friendly_name", device.friendlyName),
        ("manufacturer", device.manufacturer ?? "none"),
        ("ieee_address", device.ieeeAddress),
        ("network_address", String(device.networkAddress)),
        ("model_id", device.modelId ?? "none"),
        ("type", device.type),
        ("property", expose.property),
        ("unit", expose.unit ?? "none"),
      ]

      // PrometheusCollectorRegistry maintains a cache of previously created metrics
      let gauge = registry.makeGauge(name: "mqtt2prom_gauge", labels: labels)
      switch expose.type {
      case .numeric:
        guard let numericValue = asDouble(value) else {
          logger.warning("Failed to extract numeric value from \(value) for property \(expose.property)")
          return
        }
        gauge.set(numericValue)

      case .binary:
        let binaryValue: Double
        if let valueOn = expose.valueOn {
          switch valueOn {
          case .bool(let boolValueOn):
            if let boolValue = value as? Bool {
              binaryValue = boolValue == boolValueOn ? 1.0 : 0.0
            } else if let numberValue = value as? NSNumber {
              binaryValue = numberValue.boolValue == boolValueOn ? 1.0 : 0.0
            } else {
              binaryValue = (String(describing: value).lowercased() == "true") ? 1.0 : 0.0
            }
          case .string(let stringValue):
            binaryValue = stringValue.caseInsensitiveCompare(String(describing: value)) == .orderedSame ? 1.0 : 0.0
          }
        } else {
          if let boolValue = value as? Bool {
            binaryValue = boolValue ? 1.0 : 0.0
          } else if let numberValue = value as? NSNumber {
            binaryValue = numberValue.boolValue ? 1.0 : 0.0
          } else {
            binaryValue = (String(describing: value).lowercased() == "true") ? 1.0 : 0.0
          }
        }
        gauge.set(binaryValue)
        logger.trace(
          "device \(device.friendlyName) property [\(expose.property)] value: \(value) valueOn: \(String(describing: expose.valueOn)) valueOff: \(String(describing: expose.valueOff)) binaryValue: \(binaryValue)"
        )

      case .`enum`:
        logger.warning("Enum metrics are not supported: \(expose.property) \(device.friendlyName)")

      case .text:
        logger.warning("Text metrics are not supported \(expose.property) \(device.friendlyName)")

      default:
        logger.warning("Skipping unsupported expose type: \(expose.type)")
      }
    }
  }

  private func asDouble(_ value: Any) -> Double? {
    return switch value {
    case let double as Double: double
    case let float as Float: Double(float)
    case let int as Int: Double(int)
    case let string as String: Double(string)
    default: nil
    }
  }
}

