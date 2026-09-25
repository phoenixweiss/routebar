import CoreWLAN
import Darwin
import Foundation

public struct NetworkSnapshot: Sendable, Equatable {
  public let ssid: String?
  public let physicalInterface: String
  public let physicalGateway: String
  public let vpnInterfaces: [String]

  public init(
    ssid: String?,
    physicalInterface: String,
    physicalGateway: String,
    vpnInterfaces: [String] = []
  ) {
    self.ssid = ssid
    self.physicalInterface = physicalInterface
    self.physicalGateway = physicalGateway
    self.vpnInterfaces = vpnInterfaces
  }
}

public struct NetworkDiscoveryError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public protocol NetworkDiscovering {
  func snapshot() throws -> NetworkSnapshot
}

public struct SystemNetworkDiscovery: NetworkDiscovering {
  public init() {}

  public func snapshot() throws -> NetworkSnapshot {
    let routeTable = try run("/usr/sbin/netstat", arguments: ["-rn", "-f", "inet"])
    let gateway = try RouteTableParser.physicalDefaultGateway(from: routeTable)
    let vpnInterfaces = try RouteTableParser.vpnDefaultInterfaces(from: routeTable)
    let ssid = CWWiFiClient.shared().interface(withName: gateway.interface)?.ssid()

    return NetworkSnapshot(
      ssid: ssid,
      physicalInterface: gateway.interface,
      physicalGateway: gateway.address,
      vpnInterfaces: vpnInterfaces
    )
  }

  private func run(_ executable: String, arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = errors

    do {
      try process.run()
    } catch {
      throw NetworkDiscoveryError(
        message: "could not run \(executable): \(error.localizedDescription)")
    }
    process.waitUntilExit()

    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else {
      let detail = String(data: errorData, encoding: .utf8)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      throw NetworkDiscoveryError(
        message: "\(executable) failed" + (detail.map { ": \($0)" } ?? "")
      )
    }
    guard let text = String(data: outputData, encoding: .utf8) else {
      throw NetworkDiscoveryError(message: "\(executable) returned non-UTF-8 output")
    }
    return text
  }
}

public enum RouteTableParser {
  public struct Gateway: Sendable, Equatable {
    public let address: String
    public let interface: String

    public init(address: String, interface: String) {
      self.address = address
      self.interface = interface
    }
  }

  private static let virtualInterfacePrefixes = [
    "utun", "ppp", "ipsec", "gif", "stf", "lo", "bridge",
  ]

  public static func physicalDefaultGateway(from output: String) throws -> Gateway {
    let table = try tableRows(from: output)

    let candidates = table.rows.compactMap { line -> Gateway? in
      let columns = fields(in: line)
      guard columns.count > max(table.gatewayIndex, table.interfaceIndex),
        columns.first == "default"
      else {
        return nil
      }

      let address = columns[table.gatewayIndex]
      let interface = columns[table.interfaceIndex]
      guard isIPv4(address), !isVirtual(interface) else { return nil }
      return Gateway(address: address, interface: interface)
    }

    let unique = Array(Set(candidates.map { "\($0.address)|\($0.interface)" })).sorted()
    guard unique.count == 1, let candidate = candidates.first else {
      if unique.isEmpty {
        throw NetworkDiscoveryError(message: "could not find a physical IPv4 default gateway")
      }
      throw NetworkDiscoveryError(
        message: "multiple physical IPv4 default gateways found: \(unique.joined(separator: ", "))"
      )
    }
    return candidate
  }

  public static func vpnDefaultInterfaces(from output: String) throws -> [String] {
    let table = try tableRows(from: output)
    return Array(
      Set(
        table.rows.compactMap { line -> String? in
          let columns = fields(in: line)
          guard columns.count > table.interfaceIndex, columns.first == "default" else { return nil }
          let interface = columns[table.interfaceIndex]
          return interface.hasPrefix("utun") || interface.hasPrefix("ppp")
            || interface.hasPrefix("ipsec")
            ? interface
            : nil
        })
    ).sorted()
  }

  private struct TableRows {
    let rows: ArraySlice<String>
    let gatewayIndex: Int
    let interfaceIndex: Int
  }

  private static func tableRows(from output: String) throws -> TableRows {
    let lines = output.split(whereSeparator: \.isNewline).map(String.init)
    guard
      let headerIndex = lines.firstIndex(where: { line in
        let columns = fields(in: line)
        return columns.first == "Destination" && columns.contains("Gateway")
          && columns.contains("Netif")
      })
    else {
      throw NetworkDiscoveryError(message: "could not find the IPv4 route table header")
    }

    let header = fields(in: lines[headerIndex])
    guard let gatewayIndex = header.firstIndex(of: "Gateway"),
      let interfaceIndex = header.firstIndex(of: "Netif")
    else {
      throw NetworkDiscoveryError(message: "the IPv4 route table has an unsupported format")
    }
    return TableRows(
      rows: lines.dropFirst(headerIndex + 1),
      gatewayIndex: gatewayIndex,
      interfaceIndex: interfaceIndex
    )
  }

  private static func fields(in line: String) -> [String] {
    line.split(whereSeparator: \.isWhitespace).map(String.init)
  }

  private static func isVirtual(_ interface: String) -> Bool {
    virtualInterfacePrefixes.contains { interface.hasPrefix($0) }
  }

  private static func isIPv4(_ value: String) -> Bool {
    var address = in_addr()
    return value.withCString { inet_pton(AF_INET, $0, &address) } == 1
  }
}
