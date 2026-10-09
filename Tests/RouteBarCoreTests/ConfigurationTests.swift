import Foundation
import XCTest

@testable import RouteBarCore

final class ConfigurationTests: XCTestCase {
  func testExampleConfigurationIsValid() throws {
    let url = repositoryRoot.appendingPathComponent("examples/routebar.yaml")

    let configuration = try ConfigurationLoader.load(from: url)

    XCTAssertEqual(configuration.version, 1)
    XCTAssertEqual(configuration.profiles.count, 1)
    XCTAssertEqual(configuration.groups.count, 4)
  }

  func testUnknownRootFieldIsRejected() throws {
    let source = validConfiguration.replacingOccurrences(
      of: "version: 1",
      with: "version: 1\nsurprise: true"
    )

    XCTAssertThrowsError(try load(source)) { error in
      XCTAssertTrue(error.localizedDescription.contains("Unknown field(s): surprise"))
    }
  }

  func testUnknownNestedFieldIsRejected() throws {
    let source = validConfiguration.replacingOccurrences(
      of: "name: Home",
      with: "name: Home\n    surprise: true"
    )

    XCTAssertThrowsError(try load(source)) { error in
      XCTAssertTrue(error.localizedDescription.contains("Unknown field(s): surprise"))
    }
  }

  func testUnknownGroupReferenceIsRejected() throws {
    let source = validConfiguration.replacingOccurrences(
      of: "groups: [work, mail]",
      with: "groups: [missing]"
    )

    XCTAssertThrowsError(try load(source)) { error in
      XCTAssertEqual(
        (error as? ConfigurationValidationError)?.message,
        "profile home references unknown group missing"
      )
    }
  }

  func testIPv6FixedAddressIsRejectedInVersionOne() throws {
    let source = validConfiguration.replacingOccurrences(
      of: "addresses: [203.0.113.10]",
      with: "addresses: ['2001:db8::1']"
    )

    XCTAssertThrowsError(try load(source)) { error in
      XCTAssertTrue(error.localizedDescription.contains("invalid IPv4 address"))
    }
  }

  func testCheckOnlyGroupCannotContainRoutes() throws {
    let source = validConfiguration.replacingOccurrences(
      of: "    endpoints:",
      with: "    domains: [mail.example.org]\n    endpoints:"
    )

    XCTAssertThrowsError(try load(source)) { error in
      XCTAssertTrue(error.localizedDescription.contains("must not contain domains"))
    }
  }

  func testModeSpecificFieldsAreRejectedEvenWhenEmpty() throws {
    let source = validConfiguration.replacingOccurrences(
      of: "    endpoints:",
      with: "    addresses: []\n    endpoints:"
    )

    XCTAssertThrowsError(try load(source)) { error in
      XCTAssertTrue(error.localizedDescription.contains("must not contain addresses"))
    }
  }

  func testDuplicateYAMLKeyIsRejected() throws {
    let source = validConfiguration.replacingOccurrences(
      of: "version: 1",
      with: "version: 1\nversion: 1"
    )

    XCTAssertThrowsError(try load(source))
  }

  func testTCPProtocolAndDefaultTimeout() throws {
    let config = try load(
      validConfiguration.replacingOccurrences(of: "protocol: tls", with: "protocol: tcp"))
    let endpoint = try XCTUnwrap(config.groups.last?.endpoints.first)
    XCTAssertEqual(endpoint.protocol, .tcp)
    XCTAssertEqual(endpoint.timeoutSeconds, 5)
  }

  func testCustomTimeoutAndInvalidBounds() throws {
    let source = validConfiguration.replacingOccurrences(
      of: "protocol: tls", with: "protocol: tls\n        timeout_seconds: 0.25")
    XCTAssertEqual(try load(source).groups.last?.endpoints.first?.timeoutSeconds, 0.25)
    for value in ["0", "-1", "31", ".inf", ".nan"] {
      XCTAssertThrowsError(try load(source.replacingOccurrences(of: "0.25", with: value)))
    }
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  func testHTTPSOnlyGroupAndTimeoutDefaults() throws {
    let config = try load(httpsOnlyConfiguration)
    XCTAssertTrue(config.groups[0].endpoints.isEmpty)
    XCTAssertEqual(config.groups[0].checks[0].timeoutSeconds, 5)
    let custom = httpsOnlyConfiguration.replacingOccurrences(
      of: "expected_statuses: [200]",
      with: "expected_statuses: [200]\n        timeout_seconds: 0.25")
    XCTAssertEqual(try load(custom).groups[0].checks[0].timeoutSeconds, 0.25)
    for value in ["0", "31", ".nan"] {
      XCTAssertThrowsError(try load(custom.replacingOccurrences(of: "0.25", with: value)))
    }
  }

  func testUnsafeHTTPSURLsAndEmptyCheckOnlyGroupsAreRejected() throws {
    for url in [
      "http://status.example.org/", "https://user:example@status.example.org/",
      "https://status.example.org/#fragment", "https://status.example.org:0/",
    ] {
      XCTAssertThrowsError(
        try load(
          httpsOnlyConfiguration.replacingOccurrences(of: "https://status.example.org/", with: url))
      )
    }
    let empty =
      httpsOnlyConfiguration.components(separatedBy: "    checks:")[0] + "    checks: []\n"
    XCTAssertThrowsError(try load(empty))
    XCTAssertThrowsError(
      try load(
        httpsOnlyConfiguration.replacingOccurrences(
          of: "expected_statuses: [200]", with: "expected_statuses: [200, 200]")))
  }

  private func load(_ source: String) throws -> RouteBarConfiguration {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.yaml")
    try source.write(to: url, atomically: true, encoding: .utf8)
    return try ConfigurationLoader.load(from: url)
  }
}

let validConfiguration = """
  version: 1
  profiles:
    - id: home
      name: Home
      match:
        ssids: [Example Wi-Fi]
      groups: [work, mail]
  groups:
    - id: work
      name: Work services
      mode: bypass-vpn
      domains: [portal.example.org]
      addresses: [203.0.113.10]
      checks:
        - type: https
          url: https://portal.example.org/
          expected_statuses: [200, 302]
    - id: mail
      name: Mail transport
      mode: check-only
      endpoints:
        - name: IMAP
          host: mail.example.org
          port: 993
          protocol: tls
  """

let httpsOnlyConfiguration = """
  version: 1
  profiles:
    - id: home
      name: Home
      match:
        ssids: [Example Wi-Fi]
      groups: [status]
  groups:
    - id: status
      name: Status
      mode: check-only
      checks:
        - type: https
          url: https://status.example.org/
          expected_statuses: [200]
  """
