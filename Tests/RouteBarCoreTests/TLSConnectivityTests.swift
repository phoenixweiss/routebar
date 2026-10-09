import Foundation
import Network
import Security
import XCTest

@testable import RouteBarCore

final class TLSConnectivityTests: XCTestCase {
  func testTrustedCertificateCompletesLocalHandshake() throws {
    let server = try LocalTLSServer()
    defer { server.stop() }
    XCTAssertEqual(TLSProbe(testAnchors: [server.ca]).check(server.endpoint()), .reachable)
    XCTAssertTrue(server.closedWithoutApplicationData())
  }

  func testUntrustedCertificateIsRejectedByProductionProbe() throws {
    let server = try LocalTLSServer()
    defer { server.stop() }
    XCTAssertEqual(TLSProbe().check(server.endpoint()), .certificateFailure)
  }

  func testHostnameMismatchIsRejectedEvenWithTrustedCA() throws {
    let server = try LocalTLSServer()
    defer { server.stop() }
    XCTAssertEqual(
      TLSProbe(testAnchors: [server.ca]).check(server.endpoint(host: "127.0.0.1")),
      .certificateFailure)
  }

  func testExpiredCertificateIsRejectedEvenWithTrustedCA() throws {
    let server = try LocalTLSServer(expired: true)
    defer { server.stop() }
    XCTAssertEqual(TLSProbe(testAnchors: [server.ca]).check(server.endpoint()), .certificateFailure)
  }

  func testSilentTCPServerTimesOutDuringTLSHandshake() throws {
    let listener = try NWListener(using: .tcp, on: .any)
    let ready = expectation(description: "Silent listener ready")
    let holder = ConnectionHolder()
    listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
    listener.newConnectionHandler = { holder.keep($0) }
    listener.start(queue: DispatchQueue(label: "routebar.test.silent-tls"))
    defer {
      listener.cancel()
      holder.cancel()
    }
    wait(for: [ready], timeout: 3)
    let endpoint = Endpoint(
      name: "Silent", host: "127.0.0.1", port: Int(try XCTUnwrap(listener.port).rawValue),
      protocol: .tls, timeoutSeconds: 0.2)
    let start = Date()
    XCTAssertEqual(TLSProbe().check(endpoint), .timeout)
    XCTAssertLessThan(Date().timeIntervalSince(start), 2)
  }

  func testTLSDeadlineIgnoresLateSuccess() {
    let completion = ConnectivityCompletion<TLSOutcome>()
    XCTAssertEqual(completion.wait(timeout: 0.01, timeoutOutcome: .timeout), .timeout)
    completion.finish(.reachable)
    XCTAssertEqual(completion.wait(timeout: 0, timeoutOutcome: .timeout), .timeout)
  }

  func testTLSAndTransportErrorCategoriesRemainSeparate() {
    XCTAssertEqual(TLSOutcome.classify(.tls(errSSLProtocol)), .handshakeFailure)
    XCTAssertEqual(TLSOutcome.classify(.dns(-65538)), .dnsFailure)
    XCTAssertEqual(TLSOutcome.classify(.posix(.ECONNREFUSED)), .refused)
    XCTAssertEqual(TLSOutcome.classify(.posix(.ETIMEDOUT)), .timeout)
    XCTAssertEqual(TLSOutcome.classify(.posix(.ENETUNREACH)), .unreachable)
  }

  func testInvalidEndpointAndUnsupportedProtocolsDoNotConnect() {
    for proto in [EndpointProtocol.tcp, .startTLSSMTP] {
      XCTAssertEqual(
        TLSProbe().check(
          Endpoint(name: "Unsupported", host: "localhost", port: 443, protocol: proto)),
        .invalidEndpoint)
    }
    for timeout in [0, .infinity, .nan, 31] {
      XCTAssertEqual(
        TLSProbe().check(
          Endpoint(
            name: "Invalid", host: "localhost", port: 443, protocol: .tls,
            timeoutSeconds: timeout)), .invalidEndpoint)
    }
  }

  func testServiceChecksOnlyImplicitTLSInSelectedCheckOnlyGroups() throws {
    let source =
      validConfiguration + """

              - name: Plain
                host: localhost
                port: 80
                protocol: tcp
              - name: STARTTLS
                host: localhost
                port: 587
                protocol: starttls-smtp
        """
    let config = try ConfigurationLoader.load(source: source)
    let probe = RecordingTLSProbe()
    let results = try TLSCheckService(probe: probe).check(configuration: config, profileID: "home")
    XCTAssertEqual(probe.endpoints.map(\.name), ["IMAP"])
    XCTAssertEqual(results.map(\.outcome), [.certificateFailure])
    XCTAssertThrowsError(
      try TLSCheckService(probe: probe).check(configuration: config, profileID: "missing"))
    XCTAssertEqual(probe.endpoints.count, 1)
  }
}

private final class RecordingTLSProbe: TLSProbing {
  var endpoints: [Endpoint] = []
  func check(_ endpoint: Endpoint) -> TLSOutcome {
    endpoints.append(endpoint)
    return .certificateFailure
  }
}

private final class ConnectionHolder: @unchecked Sendable {
  private let lock = NSLock()
  private var connections: [NWConnection] = []
  private var receivedData = false
  private var cancelled = false
  private let received = DispatchSemaphore(value: 0)
  func keep(_ connection: NWConnection, handler: (@Sendable (NWConnection) -> Void)? = nil) {
    lock.lock()
    guard !cancelled else {
      lock.unlock()
      connection.cancel()
      return
    }
    defer { lock.unlock() }
    connections.append(connection)
    connection.start(queue: DispatchQueue(label: "routebar.test.silent-connection"))
    if let handler {
      handler(connection)
      return
    }
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
      self.lock.lock()
      self.receivedData = self.receivedData || !(data?.isEmpty ?? true)
      self.lock.unlock()
      self.received.signal()
    }
  }
  func closedWithoutApplicationData() -> Bool {
    guard received.wait(timeout: .now() + 3) == .success else { return false }
    lock.lock()
    defer { lock.unlock() }
    return !receivedData
  }
  func cancel() {
    lock.lock()
    cancelled = true
    let active = connections
    connections.removeAll()
    lock.unlock()
    for connection in active { connection.cancel() }
  }
}

/// Keys and certificates are generated per test, never committed or installed
/// into the user's trust store. The server listens only on loopback.
final class LocalTLSServer {
  let directory: URL
  let ca: SecCertificate
  let port: Int
  let listener: NWListener
  private let connections = ConnectionHolder()

  init(
    expired: Bool = false,
    framerOptions: ((NWProtocolTLS.Options) -> NWProtocolFramer.Options)? = nil,
    connectionHandler: (@Sendable (NWConnection) -> Void)? = nil
  ) throws {
    guard #available(macOS 15, *) else {
      throw XCTSkip(
        "The local TLS fixture requires memory-only identity import on macOS 15 or newer.")
    }
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "routebar-tls-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let workingDirectory = directory
    var started: NWListener?
    do {
      try Self.openssl(
        [
          "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
          "-subj", "/CN=RouteBar Test CA", "-addext", "basicConstraints=critical,CA:TRUE",
          "-keyout", "ca.key", "-out", "ca.pem",
        ], in: directory)
      try Self.openssl(
        [
          "req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=localhost",
          "-keyout", "server.key", "-out", "server.csr",
        ], in: directory)
      try """
      [server]
      basicConstraints=critical,CA:FALSE
      subjectAltName=DNS:localhost
      keyUsage=critical,digitalSignature,keyEncipherment
      extendedKeyUsage=serverAuth
      """.write(
        to: directory.appendingPathComponent("extensions"), atomically: true, encoding: .utf8)
      if expired {
        try """
        [ca]
        default_ca=test
        [test]
        database=index
        serial=serial
        new_certs_dir=.
        certificate=ca.pem
        private_key=ca.key
        default_md=sha256
        policy=policy
        [policy]
        commonName=supplied
        """.write(
          to: directory.appendingPathComponent("ca.conf"), atomically: true, encoding: .utf8)
        try "".write(
          to: directory.appendingPathComponent("index"), atomically: true, encoding: .utf8)
        try "01\n".write(
          to: directory.appendingPathComponent("serial"), atomically: true, encoding: .utf8)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        try Self.openssl(
          [
            "ca", "-batch", "-config", "ca.conf", "-in", "server.csr", "-out", "server.pem",
            "-startdate", formatter.string(from: Date().addingTimeInterval(-172800)),
            "-enddate", formatter.string(from: Date().addingTimeInterval(-86400)),
            "-extfile", "extensions", "-extensions", "server",
          ], in: directory)
      } else {
        try Self.openssl(
          [
            "x509", "-req", "-in", "server.csr", "-CA", "ca.pem", "-CAkey", "ca.key",
            "-CAcreateserial", "-days", "1", "-extfile", "extensions", "-extensions", "server",
            "-out", "server.pem",
          ], in: directory)
      }
      try Self.openssl(
        ["x509", "-in", "ca.pem", "-outform", "DER", "-out", "ca.der"], in: directory)
      ca = try XCTUnwrap(
        SecCertificateCreateWithData(
          nil, Data(contentsOf: directory.appendingPathComponent("ca.der")) as CFData))
      let fixturePassphrase = "routebar-test-only"
      try Self.openssl(
        [
          "pkcs12", "-export", "-inkey", "server.key", "-in", "server.pem",
          "-out", "server.p12", "-passout", "pass:\(fixturePassphrase)",
          "-keypbe", "PBE-SHA1-3DES", "-certpbe", "PBE-SHA1-3DES", "-macalg", "sha1",
        ],
        in: directory)
      var importedItems: CFArray?
      // Never import ephemeral test certificates or keys into the user's Keychain.
      let status = SecPKCS12Import(
        try Data(contentsOf: directory.appendingPathComponent("server.p12")) as CFData,
        [
          kSecImportExportPassphrase as String: fixturePassphrase,
          kSecImportToMemoryOnly as String: true,
        ] as CFDictionary, &importedItems)
      guard status == errSecSuccess else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
      }
      let item = try XCTUnwrap((importedItems as? [[String: Any]])?.first)
      let identityValue = try XCTUnwrap(item[kSecImportItemIdentity as String])
      guard CFGetTypeID(identityValue as CFTypeRef) == SecIdentityGetTypeID() else {
        throw NSError(domain: "LocalTLSServer", code: 2)
      }
      let identity = identityValue as! SecIdentity
      let tls = NWProtocolTLS.Options()
      sec_protocol_options_set_local_identity(
        tls.securityProtocolOptions, try XCTUnwrap(sec_identity_create(identity)))
      let parameters: NWParameters
      if let framerOptions {
        parameters = .tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(framerOptions(tls), at: 0)
      } else {
        parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
      }
      parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
      listener = try NWListener(using: parameters)
      started = listener
      let ready = DispatchSemaphore(value: 0)
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready, .failed: ready.signal()
        default: break
        }
      }
      let holder = connections
      listener.newConnectionHandler = { holder.keep($0, handler: connectionHandler) }
      listener.start(queue: DispatchQueue(label: "routebar.test.tls-server"))
      guard ready.wait(timeout: .now() + 3) == .success, let boundPort = listener.port else {
        throw NSError(domain: "LocalTLSServer", code: 1)
      }
      port = Int(boundPort.rawValue)
    } catch {
      started?.cancel()
      try? FileManager.default.removeItem(at: workingDirectory)
      throw error
    }
  }

  func endpoint(host: String = "localhost") -> Endpoint {
    Endpoint(name: "Local TLS", host: host, port: port, protocol: .tls, timeoutSeconds: 3)
  }

  func closedWithoutApplicationData() -> Bool { connections.closedWithoutApplicationData() }

  func stop() {
    listener.cancel()
    connections.cancel()
    try? FileManager.default.removeItem(at: directory)
  }

  private static func openssl(_ arguments: [String], in directory: URL) throws {
    let command = Process()
    command.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    command.currentDirectoryURL = directory
    command.arguments = arguments
    command.standardOutput = FileHandle.nullDevice
    command.standardError = FileHandle.nullDevice
    try command.run()
    command.waitUntilExit()
    guard command.terminationStatus == 0 else {
      throw NSError(domain: "TestCertificate", code: Int(command.terminationStatus))
    }
  }

}
