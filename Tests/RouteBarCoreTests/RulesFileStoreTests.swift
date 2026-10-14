import Foundation
import XCTest

@testable import RouteBarCore

final class RulesFileStoreTests: XCTestCase {
  private func withFiles(_ body: (URL, URL, RulesFileStore) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "rules-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.yaml")
    try rulesFixture.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    try body(
      directory, url, RulesFileStore(backupDirectory: directory.appendingPathComponent("backups")))
  }

  func testSaveFollowsSymlinkAndBacksUpPrivateOriginal() throws {
    try withFiles { directory, target, store in
      let link = directory.appendingPathComponent("linked.yaml")
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
      let snapshot = try store.load(url: link)
      let changed = try RulesDocument(source: snapshot.source).editingGroup(
        id: "web", name: "Updated",
        domains: ["example.net"], profileIDs: ["home"])
      let saved = try store.save(changed, replacing: snapshot)
      XCTAssertEqual(
        try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
      XCTAssertEqual(try ConfigurationLoader.load(from: link).groups[0].name, "Updated")
      XCTAssertEqual(saved.source, changed.source)
      XCTAssertEqual(
        try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int,
        0o600)
      let backups = try FileManager.default.contentsOfDirectory(
        at: store.backupDirectory, includingPropertiesForKeys: nil)
      XCTAssertEqual(backups.count, 1)
      XCTAssertEqual(try String(contentsOf: backups[0], encoding: .utf8), rulesFixture)
      XCTAssertEqual(
        try FileManager.default.attributesOfItem(atPath: backups[0].path)[.posixPermissions]
          as? Int, 0o600)
    }
  }

  func testExternalEditIsNotOverwritten() throws {
    try withFiles { _, url, store in
      let snapshot = try store.load(url: url)
      let changed = try RulesDocument(source: snapshot.source).editingGroup(
        id: "web", name: "Updated",
        domains: ["example.org"], profileIDs: ["home"])
      let external = rulesFixture + "# external edit\n"
      try external.write(to: url, atomically: true, encoding: .utf8)
      XCTAssertThrowsError(try store.save(changed, replacing: snapshot))
      XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), external)
    }
  }

  func testRetargetedLinkWithSameContentsIsRejected() throws {
    try withFiles { directory, target, store in
      let link = directory.appendingPathComponent("linked.yaml")
      let other = directory.appendingPathComponent("other.yaml")
      try rulesFixture.write(to: other, atomically: true, encoding: .utf8)
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
      let snapshot = try store.load(url: link)
      let changed = try RulesDocument(source: snapshot.source).editingGroup(
        id: "web", name: "Updated",
        domains: ["example.org"], profileIDs: ["home"])
      try FileManager.default.removeItem(at: link)
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
      XCTAssertThrowsError(try store.save(changed, replacing: snapshot))
      XCTAssertEqual(try String(contentsOf: other, encoding: .utf8), rulesFixture)
      XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), rulesFixture)
    }
  }

  func testSharedBackupDirectoryIsRefused() throws {
    try withFiles { _, url, store in
      try FileManager.default.createDirectory(
        at: store.backupDirectory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755])
      let snapshot = try store.load(url: url)
      XCTAssertThrowsError(try store.save(RulesDocument(source: rulesFixture), replacing: snapshot))
      XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), rulesFixture)
    }
  }
}
