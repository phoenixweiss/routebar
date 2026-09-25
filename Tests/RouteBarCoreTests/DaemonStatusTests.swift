import Foundation
import XCTest

@testable import RouteBarCore

final class DaemonStatusTests: XCTestCase {
  func testParsesLaunchctlRuntimeStatus() {
    let output = """
      system/io.github.phoenixweiss.routebar = {
        state = not running
        runs = 14
        last exit code = 0
        run interval = 30 seconds
      }
      """

    XCTAssertEqual(
      LaunchctlStatusParser.parse(output, installed: true),
      DaemonRuntimeStatus(
        installed: true,
        loaded: true,
        runs: 14,
        lastExitCode: 0,
        intervalSeconds: 30
      )
    )
  }

  func testLoadsProfileAndConfigurationPathFromPlist() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("daemon.plist")
    let plist: [String: Any] = [
      "ProgramArguments": [
        "/example/routebar", "reconcile", "--config", "/example/config.yaml",
        "--profile", "home",
      ]
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    try data.write(to: url)

    XCTAssertEqual(
      try InstalledDaemonConfigurationLoader.load(from: url),
      InstalledDaemonConfiguration(
        configURL: URL(fileURLWithPath: "/example/config.yaml"),
        profileID: "home"
      )
    )
  }
}
