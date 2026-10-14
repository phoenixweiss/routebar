import Foundation
import Yams

/// Edits individual fields without re-serializing the user's complete YAML document.
public struct RulesDocument: Sendable {
  public let source: String
  public let configuration: RouteBarConfiguration

  public struct EditError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
  }

  public init(source: String) throws {
    self.configuration = try ConfigurationLoader.load(source: source)
    self.source = source
  }

  public func editingGroup(
    id: String, name: String, domains: [String], profileIDs: Set<String>
  ) throws -> RulesDocument {
    let root = try editableRoot()
    let lines = source.components(separatedBy: "\n")
    let groups = try collection("groups", in: root, lines: lines)
    let existing = configuration.groups.first { $0.id == id }
    guard existing == nil || existing?.mode == .bypassVPN else {
      throw failure("Check-only groups are read-only in this editor.")
    }
    let normalized = try domains.map { try Self.normalizedDomain($0) }
    guard Set(normalized).count == normalized.count else {
      throw failure("This group already contains that domain. Remove the duplicate before saving.")
    }
    guard profileIDs.isSubset(of: Set(configuration.profiles.map(\.id))) else {
      throw failure("The selected profile no longer exists.")
    }
    var patches = [Patch]()
    if let node = groups.nodes.first(where: { $0["id"]?.string == id }) {
      let end = try endOf(node, nodes: groups.nodes, end: groups.end)
      if name != existing?.name {
        patches.append(
          try field("name", in: node, end: end, lines: lines, values: [name], list: false))
      }
      if normalized != existing?.domains {
        patches.append(try field("domains", in: node, end: end, lines: lines, values: normalized))
      }
    } else {
      let indent = groups.indent
      let prefix = String(repeating: " ", count: indent)
      let block =
        [
          "\(prefix)- id: \(try quoted(id))", "\(prefix)  name: \(try quoted(name))",
          "\(prefix)  mode: bypass-vpn", "\(prefix)  domains:",
        ]
        + (try normalized.map { "\(prefix)    - \(try quoted($0))" })
      patches.append(Patch(range: groups.end..<groups.end, lines: block + [""]))
    }
    try profilePatches(
      root: root, lines: lines, groupID: id, profileIDs: profileIDs, patches: &patches)
    let result = try applying(patches, lines: lines)
    // Existing non-editor settings must remain identical, including checks and addresses.
    if let existing, let edited = result.configuration.groups.first(where: { $0.id == id }) {
      guard existing.addresses == edited.addresses, existing.checks == edited.checks,
        existing.endpoints == edited.endpoints, existing.mode == edited.mode
      else {
        throw failure("The edit would change settings outside this editor. Nothing was saved.")
      }
    }
    return result
  }

  public func deletingGroup(id: String) throws -> RulesDocument {
    let root = try editableRoot()
    let lines = source.components(separatedBy: "\n")
    let groups = try collection("groups", in: root, lines: lines)
    guard let node = groups.nodes.first(where: { $0["id"]?.string == id }),
      configuration.groups.first(where: { $0.id == id })?.mode == .bypassVPN
    else {
      throw failure("This group cannot be deleted here.")
    }
    let start = try line(node)
    let end = try endOf(node, nodes: groups.nodes, end: groups.end)
    var patches = [Patch(range: start..<end, lines: comments(in: Array(lines[start..<end])))]
    try profilePatches(root: root, lines: lines, groupID: id, profileIDs: [], patches: &patches)
    return try applying(patches, lines: lines)
  }

  public static func normalizedDomain(_ input: String) throws -> String {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let domain = Self.hostname(value.contains("://") ? value : "https://\(value)")
    else {
      throw EditError(
        message: "Enter a domain or an HTTP(S) website address. Wildcards and IPs are not domains.")
    }
    return domain
  }

  private static func hostname(_ value: String) -> String? {
    guard let parts = URLComponents(string: value),
      ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
      parts.user == nil, parts.password == nil, let raw = parts.host
    else { return nil }
    let normalized = raw.lowercased()
    let host = normalized.hasSuffix(".") ? String(normalized.dropLast()) : normalized
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    guard host.utf8.count <= 253, !labels.isEmpty, host.utf8.allSatisfy({ $0 < 128 }),
      !host.allSatisfy({ $0.isNumber || $0 == "." }),
      labels.allSatisfy({ label in
        !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
          && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
      })
    else { return nil }
    return host
  }

  private struct Patch {
    let range: Range<Int>
    let lines: [String]
  }
  private struct Collection {
    let nodes: [Node]
    let end: Int
    let indent: Int
  }

  private func editableRoot() throws -> Node {
    var documents = try compose_all(yaml: source)
    guard
      !source.unicodeScalars.contains(where: { [13, 0x85, 0x2028, 0x2029].contains($0.value) }),
      let root = documents.next(),
      documents.next() == nil,
      documents.error == nil
    else {
      throw failure(
        "This YAML layout cannot be edited safely here. Use Open Config; no file was changed.")
    }
    guard let mapping = root.mapping, mapping.allSatisfy({ $0.key.mark?.column == 1 }) else {
      throw failure("The editor requires a block-style root mapping.")
    }
    guard !complex(root) else {
      throw failure("YAML anchors or aliases are not supported by the editor.")
    }
    return root
  }

  private func complex(_ node: Node) -> Bool {
    if node.anchor != nil { return true }
    switch node {
    case .alias: return true
    case .mapping(let pairs): return pairs.contains { complex($0.key) || complex($0.value) }
    case .sequence(let nodes): return nodes.contains { complex($0) }
    case .scalar: return false
    }
  }

  private func collection(_ key: String, in root: Node, lines: [String]) throws -> Collection {
    guard let sequence = root[key]?.sequence, !sequence.isEmpty,
      sequence.allSatisfy({ $0.mapping != nil }), let first = sequence.first,
      let column = first.mark?.column
    else {
      throw failure("The editor requires block-style groups and profiles. No file was changed.")
    }
    let keyLine = try line(root.mapping!.first { $0.key.string == key }!.key)
    let end =
      root.mapping!.compactMap { $0.key.mark.map { $0.line - 1 } }
      .filter { $0 > keyLine }.min()
      ?? lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "..." })
      ?? lines.count
    let nodes = Array(sequence)
    for node in nodes {
      let start = try line(node)
      let prefix = String(repeating: " ", count: max(0, column - 3)) + "- "
      guard lines[start].hasPrefix(prefix) else {
        throw failure("Unsupported group or profile layout. Use Open Config instead.")
      }
    }
    return Collection(nodes: nodes, end: end, indent: max(0, column - 3))
  }

  private func profilePatches(
    root: Node, lines: [String], groupID: String,
    profileIDs: Set<String>, patches: inout [Patch]
  ) throws {
    let profiles = try collection("profiles", in: root, lines: lines)
    for node in profiles.nodes {
      guard let id = node["id"]?.string,
        let original = configuration.profiles.first(where: { $0.id == id })
      else { continue }
      var ids = original.groups.filter { $0 != groupID }
      if profileIDs.contains(id) {
        // Do not reorder existing memberships when only a name or domain changes.
        ids = original.groups.contains(groupID) ? original.groups : ids + [groupID]
      }
      if ids != original.groups {
        patches.append(
          try field(
            "groups", in: node,
            end: endOf(node, nodes: profiles.nodes, end: profiles.end), lines: lines, values: ids))
      }
    }
  }

  private func field(
    _ key: String, in node: Node, end: Int, lines: [String],
    values: [String], list: Bool = true
  ) throws -> Patch {
    guard let mapping = node.mapping, let first = mapping.first, let column = first.key.mark?.column
    else {
      throw failure("Unsupported mapping layout.")
    }
    let indent = String(repeating: " ", count: column - 1)
    let matching = mapping.first { $0.key.string == key }
    guard let matching else {
      return Patch(
        range: end..<end,
        lines: ["\(indent)\(key):"] + (try values.map { "\(indent)  - \(try quoted($0))" }))
    }
    let start = try line(matching.key)
    // Never replace a compact multi-key mapping or a key sharing an entry dash.
    guard lines[start].hasPrefix("\(indent)\(key):"),
      mapping.filter({ $0.key.mark?.line == matching.key.mark?.line }).count == 1
    else {
      throw failure("This field layout cannot be safely edited. Use Open Config instead.")
    }
    let finish =
      mapping.compactMap { $0.key.mark.map { $0.line - 1 } }
      .filter { $0 > start }.min() ?? end
    let old = Array(lines[start..<finish])
    let preserved = comments(in: old)
    let head =
      "\(indent)\(key):" + (list ? (values.isEmpty ? " []" : "") : " \(try quoted(values[0]))")
    return Patch(
      range: start..<finish,
      lines: [head] + preserved
        + (list ? try values.map { "\(indent)  - \(try quoted($0))" } : []))
  }

  private func comments(in lines: [String]) -> [String] {
    lines.compactMap { text in
      if text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
      var quote: Character?
      var escaped = false
      var previous: Character = " "
      for index in text.indices {
        let char = text[index]
        if escaped {
          escaped = false
          previous = char
          continue
        }
        if char == "\\", quote == "\"" {
          escaped = true
        } else if let active = quote {
          if char == active { quote = nil }
        } else if char == "\"" || char == "'" {
          quote = char
        } else if char == "#", previous.isWhitespace {
          return String(text.prefix { $0.isWhitespace }) + String(text[index...])
        }
        previous = char
      }
      return nil
    }
  }

  private func applying(_ patches: [Patch], lines: [String]) throws -> RulesDocument {
    var output = lines
    let sorted = patches.sorted { $0.range.lowerBound > $1.range.lowerBound }
    var boundary = lines.count
    for patch in sorted {
      guard patch.range.upperBound <= boundary else {
        throw failure("Overlapping edits were rejected.")
      }
      output.replaceSubrange(patch.range, with: patch.lines)
      boundary = patch.range.lowerBound
    }
    let result = try RulesDocument(source: output.joined(separator: "\n"))
    _ = try result.editableRoot()
    return result
  }

  private func line(_ node: Node) throws -> Int {
    guard let mark = node.mark else { throw failure("YAML source position is unavailable.") }
    return mark.line - 1
  }
  private func endOf(_ node: Node, nodes: [Node], end: Int) throws -> Int {
    let start = try line(node)
    return nodes.compactMap { $0.mark.map { $0.line - 1 } }.filter { $0 > start }.min() ?? end
  }
  private func quoted(_ value: String) throws -> String {
    String(
      decoding: try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed),
      as: UTF8.self)
  }
  private func failure(_ message: String) -> EditError { EditError(message: message) }
}
