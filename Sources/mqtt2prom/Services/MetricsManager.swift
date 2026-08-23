import Foundation
import Logging
import Metrics
import Prometheus

actor MetricsManager {
  private let logger = Logger(label: "zmqtt2prom.metrics")

  public let registry = PrometheusCollectorRegistry()

  /// Gauges emitted on behalf of a single device, so they can be unregistered when
  /// Zigbee2MQTT renames it.
  ///
  /// `friendly_name` is a metric label, so a rename produces a brand new label set. The
  /// collector registry caches a gauge per label set and emits every one it holds, so
  /// without unregistering the old set it keeps being scraped forever with whatever value
  /// it last held - a series that looks fresh but never changes again.
  private struct TrackedDevice {
    var friendlyName: String
    /// Keyed by an internal metric key (see `MetricKey`), not by label set. The labels
    /// are kept alongside so a change in any of them - not just `friendly_name` - can
    /// replace the series rather than adding a second one.
    var gauges: [String: (labels: [(String, String)], gauge: Prometheus.Gauge)] = [:]
  }

  private enum MetricKey {
    static let deviceInfo = "device_info"
    static let lastMessage = "last_message"
    static func property(_ property: String) -> String { "property:\(property)" }
  }

  /// Both call sites must describe the connection gauge identically; the registry caches
  /// by name, so a mismatch would publish two series instead of updating one.
  private let mqttConnected = MetricNameDescriptor(
    metricName: "mqtt2prom_mqtt_connected",
    unitName: "",
    helpText: ""
  )

  /// Keyed by `ieee_address`, which is the only device identifier Zigbee2MQTT never changes.
  private var tracked: [String: TrackedDevice] = [:]

  init() {
    logger.info("Initialized metrics manager")
    // Publish the series immediately so a scrape before the first connect attempt
    // reports "not connected" rather than nothing at all.
    registry.makeGauge(descriptor: mqttConnected, labels: []).set(0.0)
  }

  /// Whether the MQTT session is currently up.
  ///
  /// Without this the exporter has no honest health signal: the HTTP server keeps
  /// serving every cached gauge at its last value even after the broker connection has
  /// gone, so a scrape succeeds and `up` stays 1 while nothing is being collected at
  /// all. For an exporter feeding a water leak alert, that is the difference between
  /// "no leak" and "not looking".
  func setMQTTConnected(_ connected: Bool) {
    registry.makeGauge(descriptor: mqttConnected, labels: []).set(connected ? 1.0 : 0.0)
  }

  /// Publishes one `mqtt2prom_device_info` series per known device and retires the series
  /// of devices that were renamed or have left the network.
  ///
  /// Called on every `bridge/devices` message. Devices that only report on state change
  /// (IAS Zone water leak, contact and motion sensors) produce no `mqtt2prom_gauge` series
  /// until something physically triggers them, so this is the only evidence that such a
  /// device exists at all before its first event.
  func syncDeviceInfo(_ devices: [DeviceInfo]) {
    let known = Set(devices.map { $0.device.ieeeAddress })

    for (ieeeAddress, device) in tracked where !known.contains(ieeeAddress) {
      unregisterAll(for: ieeeAddress)
      logger.info("Device \(device.friendlyName) (\(ieeeAddress)) is gone, unregistered its metrics")
    }

    for deviceInfo in devices {
      let device = deviceInfo.device
      forgetStaleLabelSets(for: device)

      let gauge = gauge(
        MetricKey.deviceInfo,
        name: "mqtt2prom_device_info",
        labels: [
          ("friendly_name", device.friendlyName),
          ("manufacturer", device.manufacturer ?? "none"),
          ("ieee_address", device.ieeeAddress),
          ("model_id", device.modelId ?? "none"),
          ("type", device.type),
        ],
        for: device
      )
      gauge.set(1.0)
    }
  }

  func processPayload(
    _ payload: [String: Any],
    for deviceInfo: DeviceInfo
  ) {
    logger.trace("Processing payload [\(payload)] for device \(deviceInfo.device.friendlyName)")

    let device = deviceInfo.device
    // Backstop for a rename that arrives on the device topic before bridge/devices.
    forgetStaleLabelSets(for: device)
    recordLastMessage(for: device)

    for expose in deviceInfo.exposes {
      guard let value = payload[expose.property] else {
        logger.warning("No value for property \(expose.property) for device \(device.friendlyName)")
        continue
      }
      // TODO externalize this Set to configuration
      guard !Set(["power_on_behavior"]).contains(expose.property) else {
        logger.trace("Skipping \(expose.property) \(device.friendlyName)")
        continue
      }
      let labels = [
        ("friendly_name", device.friendlyName),
        ("manufacturer", device.manufacturer ?? "none"),
        ("ieee_address", device.ieeeAddress),
        ("model_id", device.modelId ?? "none"),
        ("type", device.type),
        ("property", expose.property),
        ("unit", expose.unit ?? "none"),
      ]

      let gauge = gauge(
        MetricKey.property(expose.property),
        name: "mqtt2prom_gauge",
        labels: labels,
        for: device
      )
      switch expose.type {
      case .numeric:
        guard let numericValue = asDouble(value) else {
          logger.warning("Failed to extract numeric value from \(value) for property \(expose.property)")
          continue
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

  /// Records when this device was last heard from.
  ///
  /// Uses the time the message was received rather than Zigbee2MQTT's own `last_seen`
  /// field, which is off by default and is not part of the expose schema. Because every
  /// other series holds its last value indefinitely, this is the only metric that can
  /// distinguish a sensor that is quiet from one that is dead - which for a water leak
  /// sensor is the difference between "dry" and "not watching".
  private func recordLastMessage(for device: Device) {
    let gauge = gauge(
      MetricKey.lastMessage,
      name: "mqtt2prom_device_last_message_timestamp_seconds",
      labels: [
        ("friendly_name", device.friendlyName),
        ("ieee_address", device.ieeeAddress),
      ],
      for: device
    )
    gauge.set(Date().timeIntervalSince1970)
  }

  /// Retires every series still carrying a previous `friendly_name` for this device.
  private func forgetStaleLabelSets(for device: Device) {
    guard let previous = tracked[device.ieeeAddress],
      previous.friendlyName != device.friendlyName
    else { return }

    let count = previous.gauges.count
    unregisterAll(for: device.ieeeAddress)
    logger.info(
      "Device \(device.ieeeAddress) renamed \(previous.friendlyName) -> \(device.friendlyName), unregistered \(count) stale metrics"
    )
  }

  private func unregisterAll(for ieeeAddress: String) {
    guard let device = tracked[ieeeAddress] else { return }
    for entry in device.gauges.values {
      registry.unregisterGauge(entry.gauge)
    }
    tracked[ieeeAddress] = nil
  }

  /// Creates or returns the gauge for `key`, remembering it so it can be unregistered later.
  ///
  /// The registry caches by label set, so `makeGauge` is already idempotent; the extra
  /// bookkeeping here exists only so we hold a reference to pass to `unregisterGauge`.
  private func gauge(
    _ key: String,
    name: String,
    labels: [(String, String)],
    for device: Device
  ) -> Prometheus.Gauge {
    if let existing = tracked[device.ieeeAddress]?.gauges[key] {
      if Self.labelsEqual(existing.labels, labels) {
        return existing.gauge
      }
      // A label other than friendly_name changed - a re-interview reporting a new
      // model_id, say. Retire the old set so it does not linger frozen.
      registry.unregisterGauge(existing.gauge)
    }

    let gauge = registry.makeGauge(
      descriptor: MetricNameDescriptor(metricName: name, unitName: "", helpText: ""),
      labels: labels
    )
    var entry = tracked[device.ieeeAddress] ?? TrackedDevice(friendlyName: device.friendlyName)
    entry.friendlyName = device.friendlyName
    entry.gauges[key] = (labels, gauge)
    tracked[device.ieeeAddress] = entry
    return gauge
  }

  private static func labelsEqual(_ a: [(String, String)], _ b: [(String, String)]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
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
