import Foundation
import Hummingbird
import Logging
import Prometheus

struct MetricsController {
  let registry: PrometheusCollectorRegistry

  var endpoints: RouteCollection<BasicRequestContext> {
    return RouteCollection(context: BasicRequestContext.self)
      .get(use: self.list)
  }

  @Sendable func list(request: Request, context: some RequestContext) async throws -> String {
    var buffer = [UInt8]()
    buffer.reserveCapacity(20 * 1024)  // TODO reasonable default?
    registry.emit(into: &buffer)

    return String(decoding: buffer, as: Unicode.UTF8.self)
  }
}
