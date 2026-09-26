import Foundation

public enum RouteBarDaemonWireCodecError: Error, LocalizedError, Equatable {
  case unsupportedProtocolVersion(received: Int, supported: Int)
  case invalidPayload

  public var errorDescription: String? {
    switch self {
    case .unsupportedProtocolVersion(let received, let supported):
      "Unsupported daemon protocol version \(received); expected \(supported)"
    case .invalidPayload:
      "The daemon message is invalid"
    }
  }
}

public enum RouteBarDaemonWireCodec {
  public static func encode(_ request: RouteBarDaemonRequest) throws -> Data {
    try encoder.encode(WireEnvelope(payload: request))
  }

  public static func decodeRequest(from data: Data) throws -> RouteBarDaemonRequest {
    try decode(RouteBarDaemonRequest.self, from: data)
  }

  public static func encode(_ response: RouteBarDaemonResponse) throws -> Data {
    try encoder.encode(WireEnvelope(payload: response))
  }

  public static func decodeResponse(from data: Data) throws -> RouteBarDaemonResponse {
    try decode(RouteBarDaemonResponse.self, from: data)
  }

  private static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private static var decoder: JSONDecoder { JSONDecoder() }

  private static func decode<Payload: Codable>(
    _ type: Payload.Type,
    from data: Data
  ) throws -> Payload {
    let envelope: WireEnvelope<Payload>
    do {
      envelope = try decoder.decode(WireEnvelope<Payload>.self, from: data)
    } catch {
      throw RouteBarDaemonWireCodecError.invalidPayload
    }
    guard envelope.protocolVersion == RouteBarDaemonProtocolVersion.current else {
      throw RouteBarDaemonWireCodecError.unsupportedProtocolVersion(
        received: envelope.protocolVersion,
        supported: RouteBarDaemonProtocolVersion.current
      )
    }
    return envelope.payload
  }
}

private struct WireEnvelope<Payload: Codable>: Codable {
  let protocolVersion: Int
  let payload: Payload

  init(payload: Payload) {
    protocolVersion = RouteBarDaemonProtocolVersion.current
    self.payload = payload
  }
}
