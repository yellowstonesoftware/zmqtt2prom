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
}
