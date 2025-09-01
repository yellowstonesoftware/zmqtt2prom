import Foundation

enum ExposeType: String, Codable, Sendable {
  case binary
  case numeric
  case `enum` = "enum"
  case text
  case composite
  case `switch`
  case light
  case climate
  case cover
  case fan
  case lock
}

struct Expose: Codable, Sendable {
  let type: ExposeType
  let property: String?
  let name: String?
  let unit: String?
  let access: Int?
  let category: String?
  let description: String?
  let features: [Expose]?

  // Binary-specific properties
  let valueOn: TypeBinaryValue?
  let valueOff: TypeBinaryValue?

  // Enum-specific properties
  let values: [String]?

  // Numeric-specific properties
  let valueMin: Double?
  let valueMax: Double?
  let valueStep: Double?
  // let presets: [ExposePreset]?

  private enum CodingKeys: String, CodingKey {
    case type, property, name, unit, access, category, description, features, values
    case valueOn = "value_on"
    case valueOff = "value_off"
    case valueMin = "value_min"
    case valueMax = "value_max"
    case valueStep = "value_step"
  }

  /// Check if this expose type should be monitored
  var shouldMonitor: Bool {
    switch type {
    case .binary, .numeric, .`enum`, .text:
      return true
    case .composite, .`switch`, .light, .climate, .cover, .fan, .lock:
      return false
    }
  }
}

enum TypeBinaryValue: Codable, Sendable {
  case bool(Bool)
  case string(String)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let stringValue = try? container.decode(String.self) {
      self = .string(stringValue)
    } else if let boolValue = try? container.decode(Bool.self) {
      self = .bool(boolValue)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "value_on must be a Bool or String"
      )
    }
  }
}
