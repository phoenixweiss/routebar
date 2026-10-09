import Darwin
import Foundation
import Network

struct ConnectivityPath: Sendable, Equatable {
  let remoteAddress: String
  let localAddress: String

  func connection(port: NWEndpoint.Port, parameters: NWParameters) -> NWConnection {
    parameters.requiredLocalEndpoint = .hostPort(host: .init(localAddress), port: .any)
    return NWConnection(host: .init(remoteAddress), port: port, using: parameters)
  }
}

enum ConnectivityPathResult: Sendable, Equatable {
  case selected(ConnectivityPath)
  case failed(TCPOutcome)
}

protocol ConnectivityPathSelecting: Sendable {
  func select(host: String, port: Int, timeout: Double) -> ConnectivityPathResult
}

/// Ask the kernel which source address CURRENT routing would use. UDP connect
/// plus getsockname performs route selection without sending a datagram. Do not
/// pin an interface, gateway, Wi-Fi profile or remembered local address.
struct SystemConnectivityPathSelector: ConnectivityPathSelecting {
  private let resolver: @Sendable (String, Int) -> ConnectivityPathResult

  init(resolver: @escaping @Sendable (String, Int) -> ConnectivityPathResult = Self.resolve) {
    self.resolver = resolver
  }

  func select(host: String, port: Int, timeout: Double) -> ConnectivityPathResult {
    guard timeout > 0 else { return .failed(.timeout) }
    let completion = ConnectivityCompletion<ConnectivityPathResult>()
    DispatchQueue.global(qos: .utility).async {
      completion.finish(resolver(host, port))
    }
    return completion.wait(timeout: timeout, timeoutOutcome: .failed(.timeout))
  }

  private static func resolve(host: String, port: Int) -> ConnectivityPathResult {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_DGRAM
    var addresses: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &addresses) == 0 else {
      return .failed(.dnsFailure)
    }
    defer { freeaddrinfo(addresses) }
    // Prefer IPv4 so existing /32 exceptions remain effective. IPv6-only
    // transport endpoints still use their current kernel-selected route.
    for family in [AF_INET, AF_INET6] {
      var current = addresses
      while let pointer = current {
        let info = pointer.pointee
        current = info.ai_next
        guard info.ai_family == family, let remote = info.ai_addr else { continue }
        if let path = sourceAddress(for: remote, length: info.ai_addrlen, family: family) {
          return .selected(path)
        }
      }
    }
    return .failed(.unreachable)
  }

  private static func sourceAddress(
    for remote: UnsafePointer<sockaddr>, length: socklen_t, family: Int32
  ) -> ConnectivityPath? {
    let descriptor = socket(family, SOCK_DGRAM, 0)
    guard descriptor >= 0 else { return nil }
    defer { close(descriptor) }
    guard Darwin.connect(descriptor, remote, length) == 0 else { return nil }
    var local = sockaddr_storage()
    var localLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
    return withUnsafeMutablePointer(to: &local) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { localPointer in
        guard getsockname(descriptor, localPointer, &localLength) == 0,
          let remoteAddress = numericAddress(remote, length: length),
          let localAddress = numericAddress(localPointer, length: localLength)
        else { return nil }
        return ConnectivityPath(remoteAddress: remoteAddress, localAddress: localAddress)
      }
    }
  }

  private static func numericAddress(_ address: UnsafePointer<sockaddr>, length: socklen_t)
    -> String?
  {
    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    guard
      getnameinfo(address, length, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
    else {
      return nil
    }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }
}

struct ConnectivityDeadline {
  private let started = DispatchTime.now().uptimeNanoseconds
  let timeout: Double
  var remaining: Double {
    max(0, timeout - Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000)
  }
}
