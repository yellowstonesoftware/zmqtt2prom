import Foundation

struct Device: Codable, Sendable {
  let disabled: Bool
  let friendlyName: String
  let ieeeAddress: String
  let interviewCompleted: Bool
  let manufacturer: String?
  let modelId: String?
  let networkAddress: UInt16
  let supported: Bool
  let type: String
  let definition: DeviceDefinition?

  private enum CodingKeys: String, CodingKey {
    case disabled
    case friendlyName = "friendly_name"
    case ieeeAddress = "ieee_address"
    case interviewCompleted = "interview_completed"
    case manufacturer
    case modelId = "model_id"
    case networkAddress = "network_address"
    case supported
    case type
    case definition
  }

  /// Check if device is eligible for monitoring
  var isEligible: Bool {
    return supported && !disabled && interviewCompleted
  }

  var mqttTopic: String {
    return "zigbee2mqtt/\(friendlyName)"
  }
}

struct DeviceDefinition: Codable, Sendable {
  let description: String?
  let model: String?
  let vendor: String?
  let exposes: [Expose]

  private enum CodingKeys: String, CodingKey {
    case description, model, vendor, exposes
  }
}
