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

  func testReportsMissingDaemonAsNotInstalled() {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)

    XCTAssertEqual(
      SystemInstalledDaemonInspector.inspect(plistAt: url),
      .notInstalled
    )
  }

  func testClassifiesLegacyDaemonAndLoadsItsConfiguration() throws {
    let url = try writePlist([
      "Label": SystemDaemonRuntimeInspector.label,
      "ProgramArguments": legacyArguments,
      "RunAtLoad": true,
      "StartInterval": 30,
    ])
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    let expected = InstalledDaemonConfiguration(
      configURL: URL(fileURLWithPath: "/example/config.yaml"),
      profileID: "home"
    )
    XCTAssertEqual(
      SystemInstalledDaemonInspector.inspect(plistAt: url),
      .legacy(expected)
    )
    XCTAssertEqual(try InstalledDaemonConfigurationLoader.load(from: url), expected)
  }

  func testClassifiesBundledDaemon() throws {
    let url = try writePlist([
      "Label": SystemDaemonRuntimeInspector.label,
      "BundleProgram": SystemInstalledDaemonInspector.bundledProgram,
      "MachServices": [SystemDaemonRuntimeInspector.label: true],
      "RunAtLoad": true,
    ])
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    XCTAssertEqual(
      SystemInstalledDaemonInspector.inspect(plistAt: url),
      .bundled
    )
    XCTAssertNil(try InstalledDaemonConfigurationLoader.load(from: url))
  }

  func testRejectsMixedLegacyAndBundledDaemon() throws {
    let url = try writePlist([
      "Label": SystemDaemonRuntimeInspector.label,
      "ProgramArguments": legacyArguments,
      "BundleProgram": SystemInstalledDaemonInspector.bundledProgram,
      "MachServices": [SystemDaemonRuntimeInspector.label: true],
    ])
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    XCTAssertEqual(SystemInstalledDaemonInspector.inspect(plistAt: url), .unknown)
  }

  func testRejectsUnexpectedLabel() throws {
    let url = try writePlist([
      "Label": "example.unrelated.daemon",
      "ProgramArguments": legacyArguments,
    ])
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    XCTAssertEqual(SystemInstalledDaemonInspector.inspect(plistAt: url), .unknown)
  }

  func testRejectsLegacyDaemonWithUnexpectedArguments() throws {
    let url = try writePlist([
      "Label": SystemDaemonRuntimeInspector.label,
      "ProgramArguments": legacyArguments + ["--unexpected"],
    ])
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    XCTAssertEqual(SystemInstalledDaemonInspector.inspect(plistAt: url), .unknown)
    XCTAssertThrowsError(try InstalledDaemonConfigurationLoader.load(from: url))
  }

  func testRejectsLegacyDaemonWithRelativeConfigurationPath() throws {
    var arguments = legacyArguments
    arguments[5] = "config.yaml"
    let url = try writePlist([
      "Label": SystemDaemonRuntimeInspector.label,
      "ProgramArguments": arguments,
    ])
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    XCTAssertEqual(SystemInstalledDaemonInspector.inspect(plistAt: url), .unknown)
  }

  func testRejectsBundledDaemonWithMalformedProgramArguments() throws {
    let url = try writePlist([
      "Label": SystemDaemonRuntimeInspector.label,
      "ProgramArguments": "unexpected",
      "BundleProgram": SystemInstalledDaemonInspector.bundledProgram,
      "MachServices": [SystemDaemonRuntimeInspector.label: true],
    ])
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

    XCTAssertEqual(SystemInstalledDaemonInspector.inspect(plistAt: url), .unknown)
  }

  func testRejectsMalformedPropertyList() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("daemon.plist")
    try Data("not a plist".utf8).write(to: url)

    XCTAssertEqual(SystemInstalledDaemonInspector.inspect(plistAt: url), .unknown)
  }

  private var legacyArguments: [String] {
    [
      SystemInstalledDaemonInspector.legacyBinaryPath,
      "reconcile",
      "--apply",
      "--quiet",
      "--config",
      "/example/config.yaml",
      "--profile",
      "home",
    ]
  }

  private func writePlist(_ plist: [String: Any]) throws -> URL {
    let directory = try temporaryDirectory()
    let url = directory.appendingPathComponent("daemon.plist")
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    try data.write(to: url)
    return url
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }
}
