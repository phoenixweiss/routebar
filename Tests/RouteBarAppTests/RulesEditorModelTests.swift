import Foundation
import RouteBarCore
import XCTest

@testable import RouteBarApp

final class RulesEditorModelTests: XCTestCase {
  @MainActor
  func testDeferredTransitionsSaveDiscardAndStayKeepOriginalDestination() async throws {
    try await withEditor { model, url in
      model.newGroup()
      model.name = "Second"
      model.domainInput = "https://SECOND.example.org/path"
      let created = await model.save()
      XCTAssertTrue(created)
      let second = try XCTUnwrap(model.selectedID)
      model.name = "Second updated"
      let immediate = await model.requestTransition(.group("web"))
      XCTAssertFalse(immediate)
      XCTAssertEqual(model.pendingTransition, .group("web"))
      _ = await model.resolveTransition(.stay)
      XCTAssertEqual(model.selectedID, second)
      XCTAssertTrue(model.hasChanges)
      XCTAssertNil(model.pendingTransition)
      _ = await model.requestTransition(.group("web"))
      _ = await model.resolveTransition(.save)
      XCTAssertEqual(model.selectedID, "web")
      XCTAssertFalse(model.hasChanges)
      XCTAssertEqual(try ConfigurationLoader.load(from: url).groups.last?.name, "Second updated")
      model.name = "Do not save"
      _ = await model.requestTransition(.newGroup)
      _ = await model.resolveTransition(.discard)
      XCTAssertTrue(model.isNewGroup)
      XCTAssertEqual(model.name, "")
      _ = await model.requestTransition(.close)
      let close = await model.resolveTransition(.discard)
      XCTAssertTrue(close)
      XCTAssertNil(model.pendingTransition)
      XCTAssertFalse(model.hasChanges)
    }
  }

  @MainActor
  func testSaveFailureCancelsTransitionAndPreservesPendingInputAndDraft() async throws {
    try await withEditor { model, url in
      model.name = "Draft"
      model.domainInput = "https://cdn.example.org/path"
      let external = editorFixture + "# changed externally\n"
      try external.write(to: url, atomically: true, encoding: .utf8)
      _ = await model.requestTransition(.close)
      let close = await model.resolveTransition(.save)
      XCTAssertFalse(close)
      XCTAssertNil(model.pendingTransition)
      XCTAssertEqual(model.name, "Draft")
      XCTAssertEqual(model.domainInput, "https://cdn.example.org/path")
      XCTAssertEqual(model.domains, ["example.org"])
      XCTAssertTrue(model.hasChanges)
      XCTAssertTrue(model.needsReload)
      XCTAssertEqual(model.saveGeneration, 0)
      XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), external)
      _ = await model.requestTransition(.reload)
      XCTAssertEqual(model.pendingTransition, .reload)
      _ = await model.resolveTransition(.stay)
      XCTAssertEqual(model.name, "Draft")
      _ = await model.requestTransition(.reload)
      _ = await model.resolveTransition(.discard)
      XCTAssertEqual(model.name, "Web")
      XCTAssertFalse(model.needsReload)
      XCTAssertFalse(model.hasChanges)
    }
  }

  @MainActor
  func testSaveAutomaticallyIncludesInputAndReplacementWithoutAdd() async throws {
    try await withEditor { model, url in
      model.domainInput = "https://CDN.example.org/styles.css"
      let added = await model.save()
      XCTAssertTrue(added)
      XCTAssertEqual(model.domains, ["example.org", "cdn.example.org"])
      model.editDomain("cdn.example.org")
      model.domainInput = "https://STATIC.example.org/image.png"
      let replaced = await model.save()
      XCTAssertTrue(replaced)
      XCTAssertEqual(model.domains, ["example.org", "static.example.org"])
      XCTAssertEqual(model.domainInput, "")
      XCTAssertNil(model.editingDomain)
      XCTAssertFalse(model.hasChanges)
      XCTAssertEqual(try ConfigurationLoader.load(from: url).groups[0].domains, model.domains)
      model.editDomain("static.example.org")
      model.domainInput = "https://EXAMPLE.org/duplicate"
      let duplicateReplacement = await model.save()
      XCTAssertFalse(duplicateReplacement)
      XCTAssertEqual(model.domains, ["example.org", "static.example.org"])
      XCTAssertNotNil(model.domainError)
      XCTAssertEqual(try ConfigurationLoader.load(from: url).groups[0].domains, model.domains)
      model.cancelDomainEdit()
      model.newGroup()
      model.name = "Created on exit"
      model.domainInput = "new.example.org"
      _ = await model.requestTransition(.group("web"))
      _ = await model.resolveTransition(.save)
      XCTAssertEqual(model.selectedID, "web")
      XCTAssertEqual(model.groups.last?.domains, ["new.example.org"])
      XCTAssertEqual(model.saveGeneration, 3)
    }
  }

  @MainActor
  func testInvalidAndDuplicateInputNeverWritesAndKeepsFieldError() async throws {
    try await withEditor { model, url in
      for input in ["*.example.org", "https://EXAMPLE.org/path", "   "] {
        model.domainInput = input
        _ = await model.requestTransition(.newGroup)
        let proceeded = await model.resolveTransition(.save)
        XCTAssertFalse(proceeded)
        XCTAssertFalse(model.isNewGroup)
        XCTAssertEqual(model.domainInput, input)
        XCTAssertNotNil(model.domainError)
        XCTAssertNil(model.message)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), editorFixture)
      }
      model.cancelDomainEdit()
      model.editDomain("example.org")
      model.domainInput = ""
      let emptyReplacement = await model.save()
      XCTAssertFalse(emptyReplacement)
      XCTAssertNotNil(model.domainError)
      XCTAssertEqual(model.domains, ["example.org"])
      XCTAssertEqual(model.editingDomain, "example.org")
    }
  }

  @MainActor
  func testApplicationFeedbackDoesNotMakeSuccessfulSaveDirty() async throws {
    try await withEditor { model, _ in
      model.name = "Renamed"
      let saved = await model.save()
      XCTAssertTrue(saved)
      XCTAssertFalse(model.hasError)
      XCTAssertFalse(model.hasChanges)
      XCTAssertTrue(model.message?.contains("File saved") == true)
      // Applying routes is a separate app-model operation, not part of the editor's transaction.
      let generation = model.saveGeneration
      model.name = "Another draft"
      XCTAssertTrue(model.hasChanges)
      XCTAssertEqual(model.saveGeneration, generation)
      model.discard()
      XCTAssertEqual(model.name, "Renamed")
      let close = await model.requestTransition(.close)
      XCTAssertTrue(close)
    }
  }

  @MainActor
  private func withEditor(
    _ test: (RulesEditorModel, URL) async throws -> Void
  ) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.yaml")
    try editorFixture.write(to: url, atomically: true, encoding: .utf8)
    let model = RulesEditorModel(
      url: url, store: RulesFileStore(backupDirectory: directory.appendingPathComponent("backups")))
    await model.load()
    try await test(model, url)
  }

  @MainActor
  func testLegacySaveFeedbackNeverReusesAnEarlierAppliedResult() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.yaml")
    try editorFixture.replacingOccurrences(
      of: "domains: [example.org]",
      with: "addresses: [203.0.113.10]"
    ).write(to: url, atomically: true, encoding: .utf8)
    let app = RouteBarAppModel(
      previewState: .loading,
      installedDaemon: .legacy(InstalledDaemonConfiguration(configURL: url, profileID: "home")),
      bundledDaemonStatus: .notRegistered,
      configurationReloadState: .applied(
        .init(changedRouteCount: 1, activeRouteCount: 1, conflictCount: 0), at: Date()),
      showInDock: false)
    let feedback = await app.rulesWereSaved()
    XCTAssertEqual(app.configurationReloadState, .idle)
    XCTAssertTrue(feedback.contains("not confirmed"))
  }
  @MainActor
  func testGUIWorkflowAddsNormalizesSavesAndReloadsWithoutDuplicates() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.yaml")
    try editorFixture.write(to: url, atomically: true, encoding: .utf8)
    let model = RulesEditorModel(
      url: url, store: RulesFileStore(backupDirectory: directory.appendingPathComponent("backups")))
    await model.load()
    XCTAssertFalse(model.hasChanges)
    model.domainInput = "https://CDN.example.org/path?example=1"
    model.addDomain()
    XCTAssertEqual(model.domains, ["example.org", "cdn.example.org"])
    XCTAssertTrue(model.hasChanges)
    model.domainInput = "cdn.example.org"
    model.addDomain()
    XCTAssertTrue(model.hasError)
    XCTAssertEqual(model.domains.count, 2)
    model.domainInput = ""
    let saved = await model.save()
    XCTAssertTrue(saved)
    XCTAssertFalse(model.hasChanges)
    XCTAssertEqual(try ConfigurationLoader.load(from: url).groups[0].domains, model.domains)
    model.editDomain("cdn.example.org")
    model.domainInput = "https://static.example.org/styles.css"
    model.addDomain()
    XCTAssertEqual(model.domains, ["example.org", "static.example.org"])
    let updated = await model.save()
    XCTAssertTrue(updated)
    model.name = "Unsaved"
    model.discard()
    XCTAssertEqual(model.name, "Web")
    model.newGroup()
    model.name = "New site"
    model.domainInput = "example.net"
    model.addDomain()
    let created = await model.save()
    XCTAssertTrue(created)
    XCTAssertEqual(model.groups.count, 2)
    let removed = await model.save(deleting: true)
    XCTAssertTrue(removed)
    XCTAssertEqual(model.groups.count, 1)
  }

  @MainActor
  func testInvalidDraftOrExternalChangeNeverOverwritesFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("config.yaml")
    try editorFixture.write(to: url, atomically: true, encoding: .utf8)
    let model = RulesEditorModel(
      url: url, store: RulesFileStore(backupDirectory: directory.appendingPathComponent("backups")))
    await model.load()
    model.name = ""
    let invalid = await model.save()
    XCTAssertFalse(invalid)
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), editorFixture)
    model.name = "Changed"
    let external = editorFixture + "# another editor\n"
    try external.write(to: url, atomically: true, encoding: .utf8)
    let overwritten = await model.save()
    XCTAssertFalse(overwritten)
    XCTAssertTrue(model.hasChanges)
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), external)
  }
}

let editorFixture = """
  version: 1
  profiles:
    - id: home
      name: Home
      match:
        ssids: [Example Wi-Fi]
      groups: [web]
  groups:
    - id: web
      name: Web
      mode: bypass-vpn
      domains: [example.org]
  """ + "\n"
