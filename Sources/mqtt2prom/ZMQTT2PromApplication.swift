import Foundation
import Hummingbird
import Logging
import Prometheus

actor ZMQTT2PromApplication {
  private let logger = Logger(label: "zmqtt2prom.app")
  private let mqttConfig: MQTTConfig
  private let httpPort: Int

  private let metricsManager: MetricsManager
  private let mqttService: MQTTService

  private var shutdownRequested = false

  // Signal handling
  private var termSource: DispatchSourceSignal?
  private var intSource: DispatchSourceSignal?

  init(mqttConfig: MQTTConfig, httpPort: Int) {
    self.mqttConfig = mqttConfig
    self.httpPort = httpPort

    // Initialize services
    self.metricsManager = MetricsManager()
    self.mqttService = MQTTService(
      config: mqttConfig,
      metricsManager: metricsManager,
    )
  }

  func run() async throws {
    logger.info("Application starting up")

    setupSignalHandlers()

    do {
      try await mqttService.connect()
      logger.info("MQTT connected, starting HTTP server")

      let app = try await buildApplication(registry: metricsManager.registry)
      try await app.runService()
      logger.debug("HTTP server finished")

      await waitForShutdown()
    } catch {
      logger.error("Application startup failed: \(error)")
      throw error
    }

    // Graceful shutdown
    await shutdown()
  }

  private func buildApplication(registry: PrometheusCollectorRegistry) async throws -> some ApplicationProtocol {
    let applicationConfig = ApplicationConfiguration(address: .hostname("0.0.0.0", port: 8080))

    let router = Router()
    router.addRoutes(MetricsController(registry: registry).endpoints, atPath: "/metrics")
    router.get("/health") { _, _ in
      return HTTPResponse.Status.ok
    }
    router.add(middleware: LogRequestsMiddleware(.info))  // TODO not sure this is working

    let app = Application(router: router, configuration: applicationConfig)
    return app
  }

  private func waitForShutdown() async {
    while !shutdownRequested {
      try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
    }
    logger.info("Shutdown requested")
  }

  private func shutdown() async {
    logger.info("Shutting down application")

    // Cancel signal sources
    termSource?.cancel()
    intSource?.cancel()
    termSource = nil
    intSource = nil

    await mqttService.disconnect()

    logger.info("Application shutdown complete")

    exit(0)
  }

  func requestShutdown() {
    logger.info("Shutdown requested")
    shutdownRequested = true
  }

  private func setupSignalHandlers() {
    let signalQueue = DispatchQueue(label: "signals", qos: .background)

    // SIGTERM handler
    signal(SIGTERM, SIG_IGN)
    let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
    termSource.setEventHandler { [weak self] in
      guard let self = self else { return }
      Task {
        self.logger.info("SIGTERM received - initiating graceful shutdown")
        await self.requestShutdown()
      }
    }
    termSource.resume()
    self.termSource = termSource

    // SIGINT handler (Ctrl+C)
    signal(SIGINT, SIG_IGN)
    let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
    intSource.setEventHandler { [weak self] in
      guard let self = self else { return }
      Task {
        self.logger.info("SIGINT received (Ctrl+C) - initiating graceful shutdown")
        await self.requestShutdown()
      }
    }
    intSource.resume()
    self.intSource = intSource

    logger.debug("Signal handlers configured")
  }
}
