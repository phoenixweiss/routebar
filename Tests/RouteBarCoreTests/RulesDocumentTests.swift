import Foundation
import XCTest

@testable import RouteBarCore

final class RulesDocumentTests: XCTestCase {
  func testDomainInputRejectsCredentialsIPsAndWildcards() throws {
    XCTAssertEqual(
      try RulesDocument.normalizedDomain(" https://CDN.example.org/file?a=1 "), "cdn.example.org")
    XCTAssertEqual(try RulesDocument.normalizedDomain("intranet"), "intranet")
    for input in [
      "*.example.org", "https://user:example@example.org/", "127.0.0.1", "[::1]",
      "file:///tmp/example", "bad..example.org",
    ] {
      XCTAssertThrowsError(try RulesDocument.normalizedDomain(input))
    }
  }

  func testDocumentEndMarkerAndMultipleDocuments() throws {
    let withEnd = try RulesDocument(source: rulesFixture + "...\n")
    let added = try withEnd.editingGroup(
      id: "new", name: "New", domains: ["example.net"], profileIDs: ["home"])
    XCTAssertEqual(added.configuration.groups.count, 3)
    XCTAssertTrue(added.source.hasSuffix("...\n"))
    XCTAssertThrowsError(
      try RulesDocument(source: rulesFixture + "---\n" + rulesFixture)
        .editingGroup(id: "web", name: "Updated", domains: ["example.org"], profileIDs: ["home"]))
  }
  func testEditingPreservesCommentsOtherGroupsAndNonEditorSettings() throws {
    let original = try RulesDocument(source: rulesFixture)
    let edited = try original.editingGroup(
      id: "web", name: "Новая группа #1",
      domains: ["https://NEW.example.org/path?query=example", "cdn.example.org"],
      profileIDs: ["home"])
    XCTAssertEqual(edited.configuration.groups[0].name, "Новая группа #1")
    XCTAssertEqual(edited.configuration.groups[0].domains, ["new.example.org", "cdn.example.org"])
    XCTAssertTrue(edited.source.contains("# disabled domain\n      # - offline.example.org"))
    XCTAssertTrue(edited.source.contains("# important inline note"))
    XCTAssertTrue(edited.source.contains("# document comment"))
    XCTAssertEqual(edited.configuration.groups[1], original.configuration.groups[1])
    XCTAssertEqual(
      edited.configuration.groups[0].addresses, original.configuration.groups[0].addresses)
    XCTAssertEqual(edited.configuration.groups[0].checks, original.configuration.groups[0].checks)
    XCTAssertEqual(edited.configuration.profiles, original.configuration.profiles)
  }

  func testUnchangedEditIsByteIdentical() throws {
    let document = try RulesDocument(source: rulesFixture)
    let group = document.configuration.groups[0]
    XCTAssertEqual(
      try document.editingGroup(
        id: group.id, name: group.name,
        domains: group.domains, profileIDs: ["home"]
      ).source, rulesFixture)
  }

  func testCreatingAndDeletingUpdatesProfileMembershipWithoutChangingSSID() throws {
    let document = try RulesDocument(source: rulesFixture)
    let added = try document.editingGroup(
      id: "another", name: "Another",
      domains: ["example.net"], profileIDs: ["home"])
    XCTAssertEqual(added.configuration.profiles[0].groups, ["web", "mail", "another"])
    XCTAssertEqual(added.configuration.profiles[0].match, document.configuration.profiles[0].match)
    let deleted = try added.deletingGroup(id: "web")
    XCTAssertEqual(deleted.configuration.profiles[0].groups, ["mail", "another"])
    XCTAssertEqual(deleted.configuration.groups.map(\.id), ["mail", "another"])
    XCTAssertTrue(deleted.source.contains("# disabled domain"))
  }

  func testDuplicatesEmptyNamesAndLastProfileGroupAreRejected() throws {
    let document = try RulesDocument(source: rulesFixture)
    XCTAssertThrowsError(
      try document.editingGroup(
        id: "web", name: "Web",
        domains: ["EXAMPLE.org", "https://example.org/"], profileIDs: ["home"]))
    XCTAssertThrowsError(
      try document.editingGroup(
        id: "web", name: "",
        domains: ["example.org"], profileIDs: ["home"]))
    let mailOnly = try document.deletingGroup(id: "web")
    XCTAssertThrowsError(
      try mailOnly.editingGroup(
        id: "new", name: "New",
        domains: [], profileIDs: ["home"]))
    XCTAssertThrowsError(
      try document.editingGroup(
        id: "mail", name: "Mail",
        domains: ["example.org"], profileIDs: ["home"]))
    let source = rulesFixture.replacingOccurrences(of: "groups: [web, mail]", with: "groups: [web]")
    XCTAssertThrowsError(try RulesDocument(source: source).deletingGroup(id: "web"))
  }

  func testInlineDomainListAndMissingDomainsOnAddressOnlyGroup() throws {
    let source = rulesFixture.replacingOccurrences(
      of:
        "domains:\n      - example.org # important inline note\n      # disabled domain\n      # - offline.example.org",
      with: "domains: [example.org] # keep this comment")
    let changed = try RulesDocument(source: source).editingGroup(
      id: "web", name: "Web",
      domains: ["example.net"], profileIDs: ["home"])
    XCTAssertEqual(changed.configuration.groups[0].domains, ["example.net"])
    XCTAssertTrue(changed.source.contains("# keep this comment"))
    let missing = source.replacingOccurrences(
      of: "    domains: [example.org] # keep this comment\n", with: "")
    let inserted = try RulesDocument(source: missing).editingGroup(
      id: "web", name: "Web",
      domains: ["example.net"], profileIDs: ["home"])
    XCTAssertEqual(inserted.configuration.groups[0].domains, ["example.net"])
  }

  func testUnsupportedLineEndingsRefuseEditRatherThanReserialize() throws {
    let source = rulesFixture.replacingOccurrences(of: "\n", with: "\r\n")
    XCTAssertThrowsError(
      try RulesDocument(source: source).editingGroup(
        id: "web", name: "Updated",
        domains: ["example.org"], profileIDs: ["home"]))
  }
}

let rulesFixture = """
  # document comment
  version: 1
  profiles:
    - id: home
      name: Home
      match:
        ssids: [Example Wi-Fi]
      groups: [web, mail]

  groups:
    - id: web
      name: Web
      mode: bypass-vpn
      domains:
        - example.org # important inline note
        # disabled domain
        # - offline.example.org
      addresses: [203.0.113.10]
      checks:
        - type: https
          url: https://example.org/health
          expected_statuses: [200]

    - id: mail
      name: Mail
      mode: check-only
      endpoints:
        - name: Mail TLS
          host: mail.example.net
          port: 993
          protocol: tls
  """ + "\n"
