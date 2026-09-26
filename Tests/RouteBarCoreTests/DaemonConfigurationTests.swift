import Foundation
import XCTest

@testable import RouteBarCore

final class DaemonConfigurationTests: XCTestCase {
  func testConfiguresOnlyAnExistingProfileAtTheFixedUserPath() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.service()

    let settings = try await service.configure(clientUID: 501, profileID: "work")

    XCTAssertEqual(
      settings,
      RouteBarDaemonSettings(ownerUID: 501, profileID: "work")
    )
    let storedSettings = try await service.settings()
    XCTAssertEqual(storedSettings, settings)
  }

  func testRejectsAnUnknownProfileWithoutSavingSettings() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.service()

    do {
      try await service.configure(clientUID: 501, profileID: "missing")
      XCTFail("Expected an unknown profile to be rejected")
    } catch let error as RouteBarDaemonConfigurationError {
      XCTAssertTrue(error.message.contains("does not exist"))
    }
    let storedSettings = try await service.settings()
    XCTAssertNil(storedSettings)
  }

  func testRejectsRootAndAnotherUser() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let service = fixture.service()

    await assertThrowsErrorAsync {
      try await service.configure(clientUID: 0, profileID: "work")
    }

    _ = try await service.configure(clientUID: 501, profileID: "work")
    await assertThrowsErrorAsync {
      try await service.configure(clientUID: 502, profileID: "work")
    }
  }

  func testFileStoreUsesPrivatePermissions() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let settings = RouteBarDaemonSettings(ownerUID: 501, profileID: "work")

    try fixture.store.save(settings)

    let attributes = try FileManager.default.attributesOfItem(
      atPath: fixture.settingsURL.path
    )
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    XCTAssertEqual(try fixture.store.load(), settings)
  }
}

private struct Fixture {
  let rootURL: URL
  let homeURL: URL
  let settingsURL: URL
  let store: FileRouteBarDaemonSettingsStore

  init() throws {
    rootURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("routebar-daemon-config-\(UUID().uuidString)", isDirectory: true)
    homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
    settingsURL = rootURL.appendingPathComponent("state/settings.json")
    store = FileRouteBarDaemonSettingsStore(url: settingsURL)
    let configURL = homeURL.appendingPathComponent(
      ".config/routebar/config.yaml",
      isDirectory: false
    )
    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Self.configuration.write(to: configURL, atomically: true, encoding: .utf8)
  }

  func service() -> RouteBarDaemonConfigurationService {
    RouteBarDaemonConfigurationService(
      settingsStore: store,
      homeResolver: FixedHomeResolver(homeURL: homeURL)
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: rootURL)
  }

  private static let configuration = """
    version: 1
    profiles:
      - id: work
        name: Work
        match:
          ssids: [Office]
        groups: [services]
    groups:
      - id: services
        name: Services
        mode: bypass-vpn
        addresses: [192.0.2.10]
    """
}

private struct FixedHomeResolver: UserHomeDirectoryResolving {
  let homeURL: URL

  func homeDirectory(for uid: UInt32) throws -> URL {
    homeURL
  }
}

private func assertThrowsErrorAsync(
  _ expression: () async throws -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    try await expression()
    XCTFail("Expected an error", file: file, line: line)
  } catch {}
}
