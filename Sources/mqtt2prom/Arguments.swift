import ArgumentParser
import Foundation
import Logging 
@main
struct ZMQTT2Prom: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "zmqtt2prom",
        abstract: "Bridge Zigbee IoT device data from MQTT to Prometheus metrics",
        discussion: """
        zmqtt2prom connects to an MQTT broker, discovers Zigbee devices from Zigbee2MQTT,
        and exposes their data as Prometheus metrics via an HTTP endpoint at /metrics.
        
        The service automatically discovers devices from the 'zigbee2mqtt/bridge/devices' topic,
        subscribes to individual device topics, and transforms the data into Prometheus-compatible
        metrics based on the device expose schemas.
        """,
        version: "__version__"
    )
    
    @Option(name: .long, help: "MQTT broker hostname")
    var mqttHost: String?
    
    @Option(name: .long, help: "MQTT broker port")
    var mqttPort: Int?
    
    @Option(name: .long, help: "MQTT username (optional)")
    var mqttUsername: String?
    
    @Option(name: .long, help: "MQTT password (optional)")
    var mqttPassword: String?
    
    @Flag(name: .long, help: "Use TLS for MQTT connection")
    var mqttTls: Bool = false
    
    @Option(name: .long, help: "HTTP server port for /metrics endpoint")
    var httpPort: Int = 8080
    
    @Option(name: .long, help: "Log level (trace, debug, info, notice, warning, error, critical)")
    var logLevel: String = "info"
    
    /// Validate arguments
    mutating func validate() throws {
        if mqttPort != nil && (mqttPort! < 1 || mqttPort! > 65535) {
            throw ValidationError("MQTT port must be between 1 and 65535")
        }
        
        if httpPort < 1 || httpPort > 65535 {
            throw ValidationError("HTTP port must be between 1 and 65535")
        }
        
        let validLogLevels = ["trace", "debug", "info", "notice", "warning", "error", "critical"]
        if !validLogLevels.contains(logLevel.lowercased()) {
            throw ValidationError("Invalid log level. Must be one of: \(validLogLevels.joined(separator: ", "))")
        }
    }
    
    /// Convert to configuration objects
    var mqttConfig: MQTTConfig {
        MQTTConfig(
            host: mqttHost ?? ProcessInfo.processInfo.environment["Z2P_MQTT_HOST"] ?? "localhost",
            port: mqttPort ?? Int(ProcessInfo.processInfo.environment["Z2P_MQTT_PORT"] ?? "1883") ?? 1883,
            username: mqttUsername ?? ProcessInfo.processInfo.environment["Z2P_MQTT_USERNAME"],
            password: mqttPassword ?? ProcessInfo.processInfo.environment["Z2P_MQTT_PASSWORD"],
            useTLS: mqttTls || ((ProcessInfo.processInfo.environment["Z2P_MQTT_TLS"] ?? "false") == "true")
        )
    }
    
    /// Main entry point
    func run() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = parseLogLevel(logLevel)
            return handler
        }
        
        let logger = Logger(label: ".main")
        logger.info("Starting zmqtt2prom")
        logger.info("MQTT: \(mqttConfig.host):\(mqttConfig.port)")
        logger.info("HTTP: 0.0.0.0:\(httpPort)")
        
        let app = ZMQTT2PromApplication(
            mqttConfig: mqttConfig,
            httpPort: httpPort
        )
        
        try await app.run()
    }
    
    private func parseLogLevel(_ level: String) -> Logger.Level {
        switch level.lowercased() {
        case "trace": return .trace
        case "debug": return .debug
        case "info": return .info
        case "notice": return .notice
        case "warning": return .warning
        case "error": return .error
        case "critical": return .critical
        default: return .info
        }
    }
}
