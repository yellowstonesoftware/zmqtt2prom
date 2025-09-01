import Foundation

/// A flattened representation of an expose for easier metric generation
struct FlattenedExpose: Sendable {
  let type: ExposeType
  let property: String
  let unit: String?
  let valueOn: TypeBinaryValue?
  let valueOff: TypeBinaryValue?
  let values: [String]?

  init(expose: Expose, propertyPath: String = "") {
    self.type = expose.type

    let basePath = propertyPath.isEmpty ? "" : propertyPath + "_"
    if let property = expose.property {
      self.property = basePath + property
    } else if let name = expose.name {
      self.property = basePath + name
    } else {
      self.property = basePath + "unknown"
    }

    self.unit = expose.unit
    self.valueOn = expose.valueOn
    self.valueOff = expose.valueOff
    self.values = expose.values
  }
}

struct ExposeFlattener {
  static func flatten(_ exposes: [Expose], propertyPath: String = "") -> [FlattenedExpose] {
    var result: [FlattenedExpose] = []

    for expose in exposes {
      if expose.shouldMonitor {
        result.append(FlattenedExpose(expose: expose, propertyPath: propertyPath))
      }

      // Process nested features for composite types
      if let features = expose.features {
        let nestedPath =
          if let property = expose.property {
            propertyPath.isEmpty ? property : "\(propertyPath)_\(property)"
          } else {
            propertyPath
          }
        result.append(contentsOf: flatten(features, propertyPath: nestedPath))
      }
    }

    return result
  }
}
