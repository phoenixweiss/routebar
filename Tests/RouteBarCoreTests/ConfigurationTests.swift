import Foundation
import XCTest

@testable import RouteBarCore

final class ConfigurationTests: XCTestCase {
  func testExampleConfigurationIsValid() throws {
    let url = repositoryRoot.appendingPathComponent("examples/routebar.yaml")

    let configuration = try ConfigurationLoader.load(from: url)

    XCTAssertEqual(configuration.version, 1)
    XCTAssertEqual(configuration.profiles.count, 1)
    XCTAssertEqual(configuration.groups.count, 3)
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

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
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
