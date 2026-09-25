import Darwin
import Foundation

public struct DNSResolutionError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public protocol DNSResolving {
  func resolveIPv4(hostname: String) throws -> [String]
}

public struct SystemDNSResolver: DNSResolving {
  public init() {}

  public func resolveIPv4(hostname: String) throws -> [String] {
    var hints = addrinfo()
    hints.ai_flags = AI_ADDRCONFIG
    hints.ai_family = AF_INET
    hints.ai_socktype = SOCK_STREAM

    var result: UnsafeMutablePointer<addrinfo>?
    let status = getaddrinfo(hostname, nil, &hints, &result)
    guard status == 0 else {
      throw DNSResolutionError(
        message: "could not resolve \(hostname): \(String(cString: gai_strerror(status)))"
      )
    }
    defer { freeaddrinfo(result) }

    var addresses = Set<String>()
    var current = result
    while let pointer = current {
      let info = pointer.pointee
      if info.ai_family == AF_INET, let socketAddress = info.ai_addr {
        var ipv4 = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
          $0.pointee.sin_addr
        }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        if inet_ntop(AF_INET, &ipv4, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
          let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
          addresses.insert(String(decoding: bytes, as: UTF8.self))
        }
      }
      current = info.ai_next
    }

    guard !addresses.isEmpty else {
      throw DNSResolutionError(message: "\(hostname) has no IPv4 addresses")
    }
    return addresses.sorted(by: ipv4LessThan)
  }

  private func ipv4LessThan(_ left: String, _ right: String) -> Bool {
    left.split(separator: ".").compactMap { Int($0) }
      .lexicographicallyPrecedes(right.split(separator: ".").compactMap { Int($0) })
  }
}
