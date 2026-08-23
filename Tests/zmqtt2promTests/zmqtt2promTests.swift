import Foundation
import XCTest

@testable import zmqtt2prom

final class zmqtt2promTests: XCTestCase {

  // MARK: - Device Model Tests

  func testDeviceEligibility() throws {
    // Test eligible device
    let eligibleDevice = Device(
      disabled: false,
      friendlyName: "Test Device",
      ieeeAddress: "0x123456789abcdef0",
      interviewCompleted: true,
      manufacturer: "TestCorp",
      modelId: "TEST01",
      networkAddress: 12345,
      supported: true,
      type: "EndDevice",
      definition: nil
    )

    XCTAssertTrue(eligibleDevice.isEligible)
    XCTAssertEqual(eligibleDevice.mqttTopic, "zigbee2mqtt/Test Device")

    // Test ineligible device (disabled)
    let disabledDevice = Device(
      disabled: true,
      friendlyName: "Disabled Device",
      ieeeAddress: "0x123456789abcdef1",
      interviewCompleted: true,
      manufacturer: "TestCorp",
      modelId: "TEST01",
      networkAddress: 12346,
      supported: true,
      type: "EndDevice",
      definition: nil
    )

    XCTAssertFalse(disabledDevice.isEligible)

    // Test ineligible device (not supported)
    let unsupportedDevice = Device(
      disabled: false,
      friendlyName: "Unsupported Device",
      ieeeAddress: "0x123456789abcdef2",
      interviewCompleted: true,
      manufacturer: "TestCorp",
      modelId: "TEST01",
      networkAddress: 12347,
      supported: false,
      type: "EndDevice",
      definition: nil
    )

    XCTAssertFalse(unsupportedDevice.isEligible)
  }

  // MARK: - Expose Tests

  func testExposeShouldMonitor() throws {
    let numericExpose = Expose(
      type: .numeric,
      property: "temperature",
      name: "Temperature",
      unit: "°C",
      access: nil,
      category: nil,
      description: nil,
      features: nil,
      valueOn: nil,
      valueOff: nil,
      values: nil,
      valueMin: nil,
      valueMax: nil,
      valueStep: nil,
    )

    XCTAssertTrue(numericExpose.shouldMonitor)

    let compositeExpose = Expose(
      type: .composite,
      property: nil,
      name: "Light",
      unit: nil,
      access: nil,
      category: nil,
      description: nil,
      features: nil,
      valueOn: nil,
      valueOff: nil,
      values: nil,
      valueMin: nil,
      valueMax: nil,
      valueStep: nil,
    )

    XCTAssertFalse(compositeExpose.shouldMonitor)
  }

  func testExposeWriteOnlyShouldNotMonitor() throws {
    // access: 2 = write-only (not published by device)
    let writeOnlyExpose = Expose(
      type: .numeric,
      property: "inching_time",
      name: "Inching time",
      unit: "seconds",
      access: 2,
      category: nil,
      description: nil,
      features: nil,
      valueOn: nil,
      valueOff: nil,
      values: nil,
      valueMin: nil,
      valueMax: nil,
      valueStep: nil
    )

    XCTAssertFalse(writeOnlyExpose.shouldMonitor)

    // access: 1 = read (published by device)
    let readableExpose = Expose(
      type: .numeric,
      property: "temperature",
      name: "Temperature",
      unit: "°C",
      access: 1,
      category: nil,
      description: nil,
      features: nil,
      valueOn: nil,
      valueOff: nil,
      values: nil,
      valueMin: nil,
      valueMax: nil,
      valueStep: nil
    )

    XCTAssertTrue(readableExpose.shouldMonitor)

    // access: 7 = read + write + get (should still be monitored since it's readable)
    let readWriteExpose = Expose(
      type: .numeric,
      property: "brightness",
      name: "Brightness",
      unit: "%",
      access: 7,
      category: nil,
      description: nil,
      features: nil,
      valueOn: nil,
      valueOff: nil,
      values: nil,
      valueMin: nil,
      valueMax: nil,
      valueStep: nil
    )

    XCTAssertTrue(readWriteExpose.shouldMonitor)

    // access: nil should default to monitoring (backwards compatibility)
    let noAccessExpose = Expose(
      type: .numeric,
      property: "power",
      name: "Power",
      unit: "W",
      access: nil,
      category: nil,
      description: nil,
      features: nil,
      valueOn: nil,
      valueOff: nil,
      values: nil,
      valueMin: nil,
      valueMax: nil,
      valueStep: nil
    )

    XCTAssertTrue(noAccessExpose.shouldMonitor)
  }

  // MARK: - Flattened Expose Tests

  func testExposeFlattening() throws {
    let simpleExpose = Expose(
      type: .numeric,
      property: "temperature",
      name: "Temperature",
      unit: "°C",
      access: nil,
      category: nil,
      description: nil,
      features: nil,
      valueOn: nil,
      valueOff: nil,
      values: nil,
      valueMin: nil,
      valueMax: nil,
      valueStep: nil,
    )

    let flattened = ExposeFlattener.flatten([simpleExpose])

    XCTAssertEqual(flattened.count, 1)
    XCTAssertEqual(flattened[0].property, "temperature")
    XCTAssertEqual(flattened[0].unit, "°C")
    XCTAssertEqual(flattened[0].type, .numeric)
  }

  func testExposeNestedFlattening() throws {
    let nestedFeature = Expose(
      type: .numeric,
      property: "x",
      name: "X coordinate",
      unit: nil,
      access: nil,
      category: nil,
      description: nil,
      features: nil,
      valueOn: nil,
      valueOff: nil,
      values: nil,
      valueMin: nil,
      valueMax: nil,
      valueStep: nil,
    )

    let parentExpose = Expose(
      type: .composite,
      property: "color_xy",
      name: "Color XY",
      unit: nil,
      access: nil,
      category: nil,
      description: nil,
      features: [nestedFeature],
      valueOn: nil,
      valueOff: nil,
      values: nil,
      valueMin: nil,
      valueMax: nil,
      valueStep: nil,
    )

    let flattened = ExposeFlattener.flatten([parentExpose])

    XCTAssertEqual(flattened.count, 1)  // Only the nested feature should be included
    XCTAssertEqual(flattened[0].property, "color_xy_x")
    XCTAssertEqual(flattened[0].type, .numeric)
  }

  // MARK: - Device JSON Parsing Tests

  func testDeviceJSONDecoding() throws {
    let jsonString = """
      {
          "disabled": false,
          "friendly_name": "Test Sensor",
          "ieee_address": "0x12345678",
          "interview_completed": true,
          "manufacturer": "TestCorp",
          "model_id": "SENSOR01",
          "network_address": 1234,
          "supported": true,
          "type": "EndDevice",
          "definition": {
              "description": "Test sensor",
              "model": "SENSOR01",
              "vendor": "TestCorp",
              "exposes": [
                  {
                      "type": "numeric",
                      "property": "temperature",
                      "name": "Temperature",
                      "unit": "°C",
                      "access": 1
                  }
              ]
          }
      }
      """

    let jsonData = jsonString.data(using: .utf8)!
    let device = try JSONDecoder().decode(Device.self, from: jsonData)

    XCTAssertEqual(device.friendlyName, "Test Sensor")
    XCTAssertEqual(device.ieeeAddress, "0x12345678")
    XCTAssertTrue(device.isEligible)
    XCTAssertNotNil(device.definition)
    XCTAssertEqual(device.definition?.exposes.count, 1)
    XCTAssertEqual(device.definition?.exposes.first?.type, .numeric)
  }

  // MARK: - MetricsManager Tests

  func testProcessPayloadContinuesAfterNullNumericValue() async throws {
    let manager = MetricsManager()

    let device = Device(
      disabled: false,
      friendlyName: "Test Sensor",
      ieeeAddress: "0x123456789abcdef0",
      interviewCompleted: true,
      manufacturer: "TestCorp",
      modelId: "TEST01",
      networkAddress: 12345,
      supported: true,
      type: "EndDevice",
      definition: nil
    )

    let exposes = [
      FlattenedExpose(
        expose: Expose(
          type: .numeric,
          property: "countdown",
          name: "Countdown",
          unit: nil,
          access: nil,
          category: nil,
          description: nil,
          features: nil,
          valueOn: nil,
          valueOff: nil,
          values: nil,
          valueMin: nil,
          valueMax: nil,
          valueStep: nil
        )
      ),
      FlattenedExpose(
        expose: Expose(
          type: .numeric,
          property: "temperature",
          name: "Temperature",
          unit: "°C",
          access: nil,
          category: nil,
          description: nil,
          features: nil,
          valueOn: nil,
          valueOff: nil,
          values: nil,
          valueMin: nil,
          valueMax: nil,
          valueStep: nil
        )
      ),
    ]

    let deviceInfo = DeviceInfo(device: device, exposes: exposes)

    // NSNull represents a JSON null value — this is what triggers
    // "Failed to extract numeric value from <null> for property countdown"
    let payload: [String: Any] = [
      "countdown": NSNull(),
      "temperature": 22.5,
    ]

    await manager.processPayload(payload, for: deviceInfo)

    // Emit metrics and verify the temperature gauge was set despite countdown being null
    var buffer = [UInt8]()
    await manager.registry.emit(into: &buffer)
    let output = String(decoding: buffer, as: UTF8.self)

    XCTAssertTrue(
      output.contains("22.5"),
      "Temperature gauge should have been set even though countdown was null. Output: \(output)"
    )
  }

  // MARK: - Nested Payload Tests

  func testProcessPayloadWithNestedProperties() async throws {
    let manager = MetricsManager()

    let device = Device(
      disabled: false,
      friendlyName: "Test Device",
      ieeeAddress: "0x123456789abcdef0",
      interviewCompleted: true,
      manufacturer: "TestCorp",
      modelId: "TEST01",
      networkAddress: 12345,
      supported: true,
      type: "EndDevice",
      definition: nil
    )

    // Create exposes that match what ExposeFlattener would produce
    // for a composite "overload_protection" with nested "min_current"
    let exposes = [
      FlattenedExpose(
        expose: Expose(
          type: .numeric,
          property: "min_current",
          name: "Min current",
          unit: "A",
          access: nil,
          category: nil,
          description: nil,
          features: nil,
          valueOn: nil,
          valueOff: nil,
          values: nil,
          valueMin: nil,
          valueMax: nil,
          valueStep: nil
        ),
        propertyPath: "overload_protection"
      ),
      FlattenedExpose(
        expose: Expose(
          type: .numeric,
          property: "current",
          name: "Current",
          unit: "A",
          access: nil,
          category: nil,
          description: nil,
          features: nil,
          valueOn: nil,
          valueOff: nil,
          values: nil,
          valueMin: nil,
          valueMax: nil,
          valueStep: nil
        )
      ),
    ]

    let deviceInfo = DeviceInfo(device: device, exposes: exposes)

    // This is the actual payload structure from zigbee2mqtt - nested!
    let payload: [String: Any] = [
      "current": 0.47,
      "overload_protection": [
        "min_current": 0.5,
        "max_current": 17.0,
      ] as [String: Any],
    ]

    await manager.processPayload(payload, for: deviceInfo)

    var buffer = [UInt8]()
    await manager.registry.emit(into: &buffer)
    let output = String(decoding: buffer, as: UTF8.self)

    // Both the top-level current and nested overload_protection_min_current should be captured
    XCTAssertTrue(
      output.contains("0.47"),
      "Top-level current should be captured. Output: \(output)"
    )
    XCTAssertTrue(
      output.contains("0.5"),
      "Nested overload_protection_min_current should be captured. Output: \(output)"
    )
  }

  // MARK: - MQTT Config Tests

  func testMQTTConfig() throws {
    let config = MQTTConfig(
      host: "broker.example.com",
      port: 1883,
      username: "testuser",
      password: "testpass",
      useTLS: true,
      caCert: nil
    )

    XCTAssertEqual(config.host, "broker.example.com")
    XCTAssertEqual(config.port, 1883)
    XCTAssertEqual(config.username, "testuser")
    XCTAssertEqual(config.password, "testpass")
    XCTAssertTrue(config.useTLS)
  }

  // MARK: - Device Lifecycle Tests

  /// Builds a device that exposes a single numeric `temperature`.
  private func makeDevice(friendlyName: String, ieeeAddress: String) -> DeviceInfo {
    let device = Device(
      disabled: false,
      friendlyName: friendlyName,
      ieeeAddress: ieeeAddress,
      interviewCompleted: true,
      manufacturer: "TestCorp",
      modelId: "SENSOR01",
      networkAddress: 1234,
      supported: true,
      type: "EndDevice",
      definition: nil
    )

    let expose = FlattenedExpose(
      expose: Expose(
        type: .numeric,
        property: "temperature",
        name: "Temperature",
        unit: "°C",
        access: nil,
        category: nil,
        description: nil,
        features: nil,
        valueOn: nil,
        valueOff: nil,
        values: nil,
        valueMin: nil,
        valueMax: nil,
        valueStep: nil
      )
    )

    return DeviceInfo(device: device, exposes: [expose])
  }

  private func emit(_ manager: MetricsManager) async -> String {
    var buffer = [UInt8]()
    await manager.registry.emit(into: &buffer)
    return String(decoding: buffer, as: UTF8.self)
  }

  /// A rename in Zigbee2MQTT must not leave the previous `friendly_name` behind. The old
  /// label set would otherwise keep being exported with its last value forever, looking
  /// fresh at every scrape while never changing again.
  func testRenameUnregistersStaleLabelSet() async throws {
    let manager = MetricsManager()
    let ieee = "0xa4c138090b0bffff"

    await manager.processPayload(["temperature": 21.5], for: makeDevice(friendlyName: "Old Name", ieeeAddress: ieee))

    var output = await emit(manager)
    XCTAssertTrue(output.contains("Old Name"), "Expected the original name to be exported. Output: \(output)")

    await manager.processPayload(["temperature": 22.5], for: makeDevice(friendlyName: "New Name", ieeeAddress: ieee))

    output = await emit(manager)
    XCTAssertFalse(
      output.contains("Old Name"),
      "The pre-rename label set should have been unregistered. Output: \(output)"
    )
    XCTAssertTrue(output.contains("New Name"), "Expected the new name to be exported. Output: \(output)")
  }

  /// The same device seen under two names at discovery time collapses to one.
  func testDiscoveryRenameUnregistersStaleLabelSet() async throws {
    let manager = MetricsManager()
    let ieee = "0xf044d3fffe08ff21"

    await manager.syncDeviceInfo([makeDevice(friendlyName: "Old Name", ieeeAddress: ieee)])
    await manager.syncDeviceInfo([makeDevice(friendlyName: "New Name", ieeeAddress: ieee)])

    let output = await emit(manager)
    XCTAssertFalse(output.contains("Old Name"), "Discovery should retire the old label set. Output: \(output)")
    XCTAssertTrue(output.contains("New Name"), "Output: \(output)")
  }

  /// Event-driven devices (water leak, contact, motion) send nothing until physically
  /// triggered, so `mqtt2prom_device_info` is the only evidence they exist at all.
  func testDeviceInfoIsEmittedBeforeAnyPayload() async throws {
    let manager = MetricsManager()
    let deviceInfo = makeDevice(friendlyName: "Water Leak Sensor", ieeeAddress: "0x00158d0009ef7433")

    await manager.syncDeviceInfo([deviceInfo])

    let output = await emit(manager)
    XCTAssertTrue(
      output.contains("mqtt2prom_device_info"),
      "A device that has never reported should still be visible. Output: \(output)"
    )
    XCTAssertTrue(output.contains("Water Leak Sensor"), "Output: \(output)")
    XCTAssertFalse(
      output.contains("mqtt2prom_gauge"),
      "No reading has arrived, so there should be no reading series. Output: \(output)"
    )
  }

  /// A device that leaves the network stops being exported entirely.
  func testDeviceRemovedFromBridgeIsUnregistered() async throws {
    let manager = MetricsManager()
    let deviceInfo = makeDevice(friendlyName: "Departed Sensor", ieeeAddress: "0x00158d008b7eb058")

    await manager.syncDeviceInfo([deviceInfo])
    let seeded = await emit(manager)
    XCTAssertTrue(seeded.contains("Departed Sensor"), "Output: \(seeded)")

    await manager.syncDeviceInfo([])

    let output = await emit(manager)
    XCTAssertFalse(output.contains("Departed Sensor"), "Output: \(output)")
  }

  /// A re-interview that changes model_id must replace the series, not add a second one.
  func testLabelChangeReplacesSeriesInPlace() async throws {
    let manager = MetricsManager()
    let ieee = "0x3410f4fffefab8c8"

    func device(modelId: String) -> DeviceInfo {
      let base = makeDevice(friendlyName: "Same Name", ieeeAddress: ieee).device
      let renamed = Device(
        disabled: base.disabled,
        friendlyName: base.friendlyName,
        ieeeAddress: base.ieeeAddress,
        interviewCompleted: base.interviewCompleted,
        manufacturer: base.manufacturer,
        modelId: modelId,
        networkAddress: base.networkAddress,
        supported: base.supported,
        type: base.type,
        definition: base.definition
      )
      return DeviceInfo(device: renamed, exposes: makeDevice(friendlyName: "x", ieeeAddress: ieee).exposes)
    }

    await manager.processPayload(["temperature": 21.5], for: device(modelId: "OLD_MODEL"))
    await manager.processPayload(["temperature": 22.5], for: device(modelId: "NEW_MODEL"))

    let output = await emit(manager)
    XCTAssertFalse(output.contains("OLD_MODEL"), "Stale label set should be gone. Output: \(output)")
    XCTAssertTrue(output.contains("NEW_MODEL"), "Output: \(output)")
    XCTAssertEqual(
      output.split(separator: "\n").filter { $0.hasPrefix("mqtt2prom_gauge{") }.count, 1,
      "Expected exactly one reading series. Output: \(output)"
    )
  }

  /// Liveness: every handled message stamps a receipt time, which is the only signal that
  /// can tell a quiet sensor apart from a dead one.
  func testLastMessageTimestampIsRecorded() async throws {
    let manager = MetricsManager()
    let before = Date().timeIntervalSince1970

    await manager.processPayload(
      ["temperature": 20.0],
      for: makeDevice(friendlyName: "Fridge Leak Sensor", ieeeAddress: "0x00158d008b7eb058")
    )

    let output = await emit(manager)
    XCTAssertTrue(
      output.contains("mqtt2prom_device_last_message_timestamp_seconds"),
      "Output: \(output)"
    )

    let line = output.split(separator: "\n").first {
      $0.hasPrefix("mqtt2prom_device_last_message_timestamp_seconds{")
    }
    let stamp = line.flatMap { $0.split(separator: " ").last.flatMap { Double($0) } }
    XCTAssertNotNil(stamp, "Expected a numeric timestamp. Output: \(output)")
    XCTAssertGreaterThanOrEqual(stamp ?? 0, before)
    XCTAssertLessThanOrEqual(stamp ?? 0, Date().timeIntervalSince1970 + 1)
  }
}
