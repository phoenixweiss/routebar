import Foundation
import Network
import XCTest

@testable import RouteBarCore

final class SMTPStartTLSTests: XCTestCase {
  func testReplySequenceAndMultilineResponses() {
    var handshake = SMTPStartTLSHandshake()
    XCTAssertEqual(handshake.receive(line: data("220-localhost\r\n")), .wait)
    XCTAssertEqual(handshake.receive(line: data("220 Ready\r\n")), .sendEHLO)
    XCTAssertEqual(handshake.receive(line: data("250-localhost\r\n")), .wait)
    XCTAssertEqual(handshake.receive(line: data("250-STARTTLS\r\n")), .wait)
    XCTAssertEqual(handshake.receive(line: data("250 AUTH LOGIN\r\n")), .sendSTARTTLS)
    XCTAssertEqual(handshake.receive(line: data("220 Ready\r\n")), .upgrade)
    XCTAssertEqual(handshake.receive(line: data("220 Ready\r\n")), .fail(.protocolFailure))
  }

  func testNoDowngradeOrFalseCapabilityMatch() {
    for reply in [
      "250 STARTTLS\r\n", "250-localhost\r\n250 XSTARTTLS\r\n",
      "250-localhost\r\n250 AUTH STARTTLS\r\n",
    ] {
      var handshake = SMTPStartTLSHandshake()
      XCTAssertEqual(handshake.receive(line: data("220 localhost\r\n")), .sendEHLO)
      let lines = reply.components(separatedBy: "\r\n").filter { !$0.isEmpty }
      var action = SMTPStartTLSHandshake.Action.wait
      for line in lines { action = handshake.receive(line: data(line + "\r\n")) }
      XCTAssertEqual(action, .fail(.unsupported))
    }
  }

  func testMalformedAndOversizedRepliesAreRejected() {
    for line in [
      "220 bad\n", "abc bad\r\n", "220\tbad\r\n", "220 bad\rtext\r\n",
      "220 " + String(repeating: "x", count: 507) + "\r\n",
    ] {
      var handshake = SMTPStartTLSHandshake()
      XCTAssertEqual(handshake.receive(line: data(line)), .fail(.protocolFailure))
    }
    var mixed = SMTPStartTLSHandshake()
    XCTAssertEqual(mixed.receive(line: data("220-first\r\n")), .wait)
    XCTAssertEqual(mixed.receive(line: data("250 last\r\n")), .fail(.protocolFailure))
    var endless = SMTPStartTLSHandshake()
    for _ in 0..<64 { XCTAssertEqual(endless.receive(line: data("220-more\r\n")), .wait) }
    XCTAssertEqual(endless.receive(line: data("220-more\r\n")), .fail(.protocolFailure))
  }

  func testLocalUpgradeAndNoAuthenticationOrMail() throws {
    let context = TestSMTPContext(mode: .good)
    let server = try LocalTLSServer(framerOptions: context.options)
    defer { server.stop() }
    XCTAssertEqual(SMTPStartTLSProbe(testAnchors: [server.ca]).check(endpoint(server)), .reachable)
    XCTAssertEqual(context.commands, ["EHLO routebar.invalid", "STARTTLS"])
    XCTAssertTrue(server.closedWithoutApplicationData())
  }

  func testFragmentedRepliesAndOversizedWireResponse() throws {
    for (mode, expected) in [
      (TestSMTPContext.Mode.fragmented, SMTPStartTLSOutcome.reachable),
      (.oversized, .protocolFailure), (.badTLS, .handshakeFailure),
    ] {
      let context = TestSMTPContext(mode: mode)
      let server = try LocalTLSServer(framerOptions: context.options)
      defer { server.stop() }
      XCTAssertEqual(
        SMTPStartTLSProbe(testAnchors: [server.ca]).check(endpoint(server)), expected,
        "Mode: \(mode), commands: \(context.commands)")
    }
  }

  func testMissingCapabilityAndRejectedUpgradeNeverFallBack() throws {
    for (mode, expected) in [
      (TestSMTPContext.Mode.unsupported, SMTPStartTLSOutcome.unsupported),
      (.rejected, .rejected), (.malformed, .protocolFailure),
    ] {
      let context = TestSMTPContext(mode: mode)
      let server = try LocalTLSServer(framerOptions: context.options)
      defer { server.stop() }
      XCTAssertEqual(SMTPStartTLSProbe().check(endpoint(server)), expected)
      XCTAssertEqual(
        context.commands,
        mode == .rejected ? ["EHLO routebar.invalid", "STARTTLS"] : ["EHLO routebar.invalid"])
    }
  }

  func testUntrustedExpiredAndWrongHostnameCertificatesAreRejected() throws {
    for kind in 0..<3 {
      let context = TestSMTPContext(mode: .good)
      let server = try LocalTLSServer(expired: kind == 1, framerOptions: context.options)
      defer { server.stop() }
      let probe = kind == 0 ? SMTPStartTLSProbe() : SMTPStartTLSProbe(testAnchors: [server.ca])
      XCTAssertEqual(
        probe.check(endpoint(server, host: kind == 2 ? "127.0.0.1" : "localhost")),
        .certificateFailure)
    }
  }

  func testTimeoutDuringUpgradeIsBounded() throws {
    let context = TestSMTPContext(mode: .silent)
    let server = try LocalTLSServer(framerOptions: context.options)
    defer { server.stop() }
    let start = Date()
    XCTAssertEqual(SMTPStartTLSProbe().check(endpoint(server, timeout: 0.2)), .timeout)
    XCTAssertLessThan(Date().timeIntervalSince(start), 2)
  }

  func testServiceSelectsOnlySTARTTLSEndpointsAndRejectsUnknownProfile() throws {
    let config = try ConfigurationLoader.load(
      source: validConfiguration.replacingOccurrences(
        of: "protocol: tls", with: "protocol: starttls-smtp"))
    let probe = RecordingSMTPProbe()
    let results = try SMTPStartTLSCheckService(probe: probe).check(
      configuration: config, profileID: "home")
    XCTAssertEqual(results.map(\.outcome), [.unsupported])
    XCTAssertEqual(probe.names, ["IMAP"])
    XCTAssertThrowsError(
      try SMTPStartTLSCheckService(probe: probe).check(configuration: config, profileID: "missing"))
    let tlsConfig = try ConfigurationLoader.load(source: validConfiguration)
    XCTAssertTrue(
      try SMTPStartTLSCheckService(probe: probe).check(configuration: tlsConfig, profileID: "home")
        .isEmpty)
    XCTAssertEqual(probe.names.count, 1)
  }

  func testInvalidEndpointDoesNotConnect() {
    XCTAssertEqual(
      SMTPStartTLSProbe().check(
        Endpoint(name: "Invalid", host: "localhost", port: 587, protocol: .tls)), .invalidEndpoint)
    XCTAssertEqual(
      SMTPStartTLSProbe().check(
        Endpoint(
          name: "Invalid", host: "localhost", port: 587, protocol: .startTLSSMTP,
          timeoutSeconds: .nan)), .invalidEndpoint)
  }

  private func data(_ text: String) -> Data { Data(text.utf8) }
  private func endpoint(_ server: LocalTLSServer, host: String = "localhost", timeout: Double = 3)
    -> Endpoint
  {
    Endpoint(
      name: "Local SMTP", host: host, port: server.port, protocol: .startTLSSMTP,
      timeoutSeconds: timeout)
  }
}

private final class RecordingSMTPProbe: SMTPStartTLSProbing {
  var names: [String] = []
  func check(_ endpoint: Endpoint) -> SMTPStartTLSOutcome {
    names.append(endpoint.name)
    return .unsupported
  }
}

private final class TestSMTPContext: @unchecked Sendable {
  enum Mode { case good, unsupported, rejected, malformed, silent, fragmented, oversized, badTLS }
  let mode: Mode
  private let lock = NSLock()
  private var recorded: [String] = []
  var tls: NWProtocolTLS.Options?
  init(mode: Mode) { self.mode = mode }
  var commands: [String] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }
  func record(_ command: String) {
    lock.lock()
    defer { lock.unlock() }
    recorded.append(command)
  }
  func options(_ tls: NWProtocolTLS.Options) -> NWProtocolFramer.Options {
    self.tls = tls
    let options = NWProtocolFramer.Options(definition: TestSMTPFramer.definition)
    options["context"] = self
    return options
  }
}

private final class TestSMTPFramer: NWProtocolFramerImplementation {
  static let label = "Test SMTP server"
  static let definition = NWProtocolFramer.Definition(implementation: TestSMTPFramer.self)
  let context: TestSMTPContext
  private var finished = false
  init(framer: NWProtocolFramer.Instance) {
    context = framer.options["context"] as! TestSMTPContext
  }
  func start(framer: NWProtocolFramer.Instance) -> NWProtocolFramer.StartResult {
    if context.mode == .fragmented {
      framer.writeOutput(data: Data("220-local".utf8))
      delayedWrite(Data("host\r\n220 Ready\r\n".utf8), framer: framer)
    } else {
      framer.writeOutput(data: Data("220-localhost\r\n220 Ready\r\n".utf8))
    }
    return .willMarkReady
  }
  func handleInput(framer: NWProtocolFramer.Instance) -> Int {
    while !finished {
      var line: String?
      _ = framer.parseInput(minimumIncompleteLength: 1, maximumLength: 512) { buffer, _ in
        guard let buffer, buffer.count >= 2 else { return 0 }
        for index in 1..<buffer.count where buffer[index - 1] == 13 && buffer[index] == 10 {
          line = String(decoding: buffer.prefix(index - 1), as: UTF8.self)
          return index + 1
        }
        return 0
      }
      guard let line else { return 1 }
      context.record(line)
      if line == "EHLO routebar.invalid" {
        let reply: String
        switch context.mode {
        case .unsupported: reply = "250-localhost\r\n250 AUTH LOGIN\r\n"
        case .malformed: reply = "250-localhost\r\n220 STARTTLS\r\n"
        case .oversized: reply = "250-" + String(repeating: "x", count: 600)
        case .fragmented:
          reply = "250-localhost\r\n250 STA"
          delayedWrite(Data("RTTLS\r\n".utf8), framer: framer)
        default: reply = "250-localhost\r\n250 STARTTLS\r\n"
        }
        framer.writeOutput(data: Data(reply.utf8))
      } else if line == "STARTTLS" {
        if context.mode == .silent { return 1 }
        if context.mode == .rejected {
          framer.writeOutput(data: Data("454 Not available\r\n".utf8))
          return 1
        }
        framer.writeOutput(data: Data("220 Ready for TLS\r\n".utf8))
        if context.mode == .badTLS {
          finished = true
          // TLS fatal handshake_failure alert, not SMTP text.
          delayedWrite(Data([21, 3, 3, 0, 2, 2, 40]), framer: framer)
          framer.passThroughInput()
          framer.passThroughOutput()
          framer.markReady()
          return 0
        }
        do {
          try framer.prependApplicationProtocol(options: context.tls!)
          finished = true
          framer.passThroughInput()
          framer.passThroughOutput()
          framer.markReady()
        } catch { framer.markFailed(error: .posix(.EPROTO)) }
      } else {
        framer.markFailed(error: .posix(.EPROTO))
        return 0
      }
    }
    return 0
  }
  func handleOutput(
    framer: NWProtocolFramer.Instance, message: NWProtocolFramer.Message, messageLength: Int,
    isComplete: Bool
  ) {}
  func wakeup(framer: NWProtocolFramer.Instance) {
  }
  private func delayedWrite(_ data: Data, framer: NWProtocolFramer.Instance) {
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) {
      framer.async { framer.writeOutput(data: data) }
    }
  }
  func stop(framer: NWProtocolFramer.Instance) -> Bool { true }
  func cleanup(framer: NWProtocolFramer.Instance) {}
}
