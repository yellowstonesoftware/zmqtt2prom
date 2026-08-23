import Foundation

struct PayloadFlattener {
  /// Flattens a nested dictionary into a single-level dictionary with underscore-separated keys.
  /// Example: {"overload_protection": {"min_current": 0.5}} becomes {"overload_protection_min_current": 0.5}
  static func flatten(_ payload: [String: Any], prefix: String = "") -> [String: Any] {
    var result: [String: Any] = [:]

    for (key, value) in payload {
      let newKey = prefix.isEmpty ? key : "\(prefix)_\(key)"

      if let nested = value as? [String: Any] {
        let flattened = flatten(nested, prefix: newKey)
        for (flatKey, flatValue) in flattened {
          result[flatKey] = flatValue
        }
      } else {
        result[newKey] = value
      }
    }

    return result
  }
}
