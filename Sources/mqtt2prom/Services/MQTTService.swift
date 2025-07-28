import Foundation
import Logging
import MQTTNIO
import NIOCore
import NIOPosix

actor DeviceRegistry { 
    private var registry: [String: DeviceInfo] = [:]

    func replace(registry: [String: DeviceInfo]) {
        self.registry = registry
    }

    func contains(deviceFriendlyName: String) -> Bool {
        registry[deviceFriendlyName] != nil
    }

    func getDeviceInfo(deviceFriendlyName: String) -> DeviceInfo? {
        registry[deviceFriendlyName]
    }
}

enum MQTTListenerName: String {
    case connectionClosed = "connection-closed"
    case deviceDiscovery = "device-discovery"
}

struct MQTTService {
    private let logger = Logger(label: "zmqtt2prom.mqtt")
    private let config: MQTTConfig
    private let eventLoopGroup: EventLoopGroup
    private let metricsManager: MetricsManager
    private let client: MQTTClient
    private let deviceRegistry: DeviceRegistry

    init(
        config: MQTTConfig,
        metricsManager: MetricsManager,
    ) {
        self.config = config
        self.metricsManager = metricsManager
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        self.client = MQTTClient(
            host: config.host,
            port: config.port,
            identifier: "zmqtt2prom-\(UUID().uuidString)",
            eventLoopGroupProvider: .shared(eventLoopGroup),
            logger: logger
        )
        self.deviceRegistry = DeviceRegistry()
    }
    
    func connect() async throws {
        logger.info("Connecting to MQTT broker at \(config.host):\(config.port)")
        
        do {
            let previousSessionRestored: Bool
            if let username = config.username {
                let connectConfig = MQTTClient.ConnectConfiguration(
                    userName: username,
                    password: config.password
                )
                previousSessionRestored = try await client.connect(cleanSession: true, connectConfiguration: connectConfig)
            } else {
                previousSessionRestored = try await client.connect(cleanSession: true)
            }
            logger.info("Connected to MQTT broker (clean session: \(previousSessionRestored))")
            
            try await discoverDevices()
        } catch {
            logger.error("Failed to connect to MQTT broker: \(error)")
            await disconnect()
            
            throw MQTTError.connectionFailed(error)
        }
    }
    
    func disconnect() async{
        logger.info("Disconnecting from MQTT broker")
        
        do {
            if client.isActive() { 
                client.removeCloseListener(named: MQTTListenerName.connectionClosed.rawValue)
                try await client.disconnect().get() 
            }
            logger.debug("MQTTClient disconnected successfully")
            try client.syncShutdownGracefully()
            logger.debug("MQTTClient shut down successfully")
        } catch {
            logger.error("Error disconnecting from MQTT: \(error)")
        }
        
            do {
            logger.debug("Shutting down MQTT event loop group synchronously")
            try await eventLoopGroup.shutdownGracefully()
            logger.debug("MQTT event loop group shutdown successfully")
        } catch {
            logger.error("Error shutting down MQTT event loop group: \(error)")
        }
    }
    
    private func discoverDevices() async throws {
        guard client.isActive() else { throw MQTTError.notConnected }
        
        logger.info("Subscribing to zigbee2mqtt/bridge/devices topic for device discovery")
        
        let subscribeInfo = MQTTSubscribeInfo(topicFilter: "zigbee2mqtt/bridge/devices", qos: .atMostOnce)
        _ = try await client.subscribe(to: [subscribeInfo])
        
        client.addCloseListener(named: MQTTListenerName.connectionClosed.rawValue) { result in
            Task { 
                logger.warning("trying to reconnect to MQTT broker...")
                try? await self.connect()
            }
        }
        client.addPublishListener(named: MQTTListenerName.deviceDiscovery.rawValue) { result in
            Task { 
                await self.handleMessage(result)
            }
        }
    }
    
    private func handleMessage(_ result: Result<MQTTPublishInfo, Error>) async {
        switch result {
        case .success(let publishInfo):
            let topic = publishInfo.topicName
            
            if topic == "zigbee2mqtt/bridge/devices" {
                await handleDeviceDiscoveryMessage(publishInfo.payload)
            } else if topic.hasPrefix("zigbee2mqtt/") && !topic.hasPrefix("zigbee2mqtt/bridge/") {
                let deviceName = String(topic.dropFirst("zigbee2mqtt/".count))
                await handleDeviceMessage(deviceName: deviceName, payload: publishInfo.payload)
            }

        case .failure(let error):
            logger.error("MQTT message error: \(error)")
        }
    }
    
    private func handleDeviceDiscoveryMessage(_ payload: ByteBuffer) async {
        // guard let data = payload.getData(at: 0, length: payload.readableBytes) else {
        //     logger.error("Failed to extract data from bridge/devices payload")
        //     return
        // }
        // getData doesn't exist in ByteBuffer on Linux
        guard let bytes = payload.getBytes(at: 0, length: payload.readableBytes) else {
            logger.error("Failed to extract data from device discovery payload")
            return
        }
        let data = Data(bytes)        

        do {
            let devices = try DeviceDiscovery
                .parseDevices(from: data)
                .filter { device in 
                    let eligible = device.isEligible 
                    if !eligible {
                        logger.warning("Filtering out device \(device.friendlyName): supported=\(device.supported), disabled=\(device.disabled), interview_completed=\(device.interviewCompleted)")
                    }
                    return eligible
                }
            let registry = DeviceDiscovery.buildDeviceRegistry(devices)
        
            await self.deviceRegistry.replace(registry: registry)
            
            try await subscribeToDeviceTopics(Array(registry.keys))
            
            logger.info("Device discovery complete. Monitoring \(registry.count) devices:")
            for (name, _) in registry {
                logger.info("\t - \(name)")
                for expose in registry[name]?.exposes ?? [] {
                    logger.info("\t\t - \(expose.property) \(expose.type)")
                }
            }
        } catch {
            logger.error("Error processing device discovery message: \(error)")
        }
    }
    
    private func subscribeToDeviceTopics(_ deviceNames: [String]) async throws {
        guard client.isActive() else { throw MQTTError.notConnected }
        
        let subscribeInfos = deviceNames.map { deviceName in
            MQTTSubscribeInfo(topicFilter: "zigbee2mqtt/\(deviceName)", qos: .atLeastOnce)
        }
        
        _ = try await client.subscribe(to: subscribeInfos)
        logger.info("Subscribed to \(subscribeInfos.count) device topics")
    }
    
    private func handleDeviceMessage(deviceName: String, payload: ByteBuffer) async {
        guard let deviceInfo = await deviceRegistry.getDeviceInfo(deviceFriendlyName: deviceName) else {
            return // skip unregistered devices (probably was not eligible)
        }
        
        // guard let data = payload.getData(at: 0, length: payload.readableBytes) else {
        //     logger.error("Failed to extract data from device payload")
        //     return
        // }
        guard let bytes = payload.getBytes(at: 0, length: payload.readableBytes) else {
            logger.error("Failed to extract data from devices payload")
            return
        }
        let data = Data(bytes)
        
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            guard let jsonDict = json as? [String: Any] else {
                logger.warning("Device payload is not a JSON object")
                return
            }
            
            await metricsManager.processPayload(jsonDict, for: deviceInfo)
            logger.trace("Processed payload for device \(deviceName)")
        } catch {
            logger.error("Error parsing device payload for \(deviceName): \(error)")
        }
    }
}

struct MQTTConfig: Sendable {
    let host: String
    let port: Int
    let username: String?
    let password: String?
    let useTLS: Bool
}

enum MQTTError: Error {
    case notConnected
    case connectionFailed(Error)
    case subscriptionFailed(Error)
} 