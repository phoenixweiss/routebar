import Foundation
import RouteBarCore

@MainActor
final class RulesEditorModel: ObservableObject {
  enum Transition: Equatable {
    case close
    case group(String)
    case newGroup, reload
  }
  enum TransitionChoice { case save, discard, stay }
  @Published private(set) var document: RulesDocument?
  @Published private(set) var selectedID: String?
  @Published var name = ""
  @Published var domains = [String]()
  @Published var profileIDs = Set<String>()
  @Published var domainInput = ""
  @Published private(set) var editingDomain: String?
  @Published private(set) var isBusy = false
  @Published private(set) var isSaving = false
  @Published private(set) var message: String?
  @Published private(set) var hasError = false
  @Published private(set) var domainError: String?
  @Published private(set) var needsReload = false
  @Published private(set) var pendingTransition: Transition?
  @Published private(set) var saveGeneration = 0
  private var snapshot: RulesFileSnapshot?
  let url: URL
  private let store: RulesFileStore

  init(url: URL, store: RulesFileStore = RulesFileStore(), previewSource: String? = nil) {
    self.url = url
    self.store = store
    if let previewSource, let document = try? RulesDocument(source: previewSource) {
      self.document = document
      select(document.configuration.groups.first?.id)
    }
  }

  var groups: [Group] { document?.configuration.groups ?? [] }
  var profiles: [Profile] { document?.configuration.profiles ?? [] }
  var selectedGroup: Group? { groups.first { $0.id == selectedID } }
  var isNewGroup: Bool { selectedID != nil && selectedGroup == nil }
  var isEditable: Bool { selectedID != nil && (selectedGroup?.mode ?? .bypassVPN) == .bypassVPN }
  var hasChanges: Bool {
    guard let selectedID else { return false }
    if !domainInput.isEmpty || editingDomain != nil { return true }
    guard let group = selectedGroup else { return true }
    let memberships = Set(profiles.filter { $0.groups.contains(selectedID) }.map(\.id))
    return group.name != name || group.domains != domains || memberships != profileIDs
  }

  func load() async {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      let url = url
      let store = store
      let loaded = try await Task.detached { try store.load(url: url) }.value
      snapshot = loaded
      document = try RulesDocument(source: loaded.source)
      select(groups.first?.id)
      message = nil
      hasError = false
      needsReload = false
    } catch {
      report(error)
      needsReload = true
    }
  }

  func select(_ id: String?) {
    selectedID = id
    name = selectedGroup?.name ?? ""
    domains = selectedGroup?.domains ?? []
    profileIDs = Set(profiles.filter { $0.groups.contains(id ?? "") }.map(\.id))
    domainInput = ""
    editingDomain = nil
    domainError = nil
    message = nil
    hasError = false
  }

  func newGroup() {
    select("site-\(UUID().uuidString.prefix(8).lowercased())")
    if let first = profiles.first { profileIDs = [first.id] }
    message = nil
    hasError = false
  }

  func discard() {
    select(selectedGroup?.id ?? groups.first?.id)
    message = nil
    hasError = false
  }

  func addDomain() {
    do {
      domains = try domainsIncludingInput()
      domainInput = ""
      editingDomain = nil
      message = nil
      hasError = false
      domainError = nil
    } catch { reportDomain(error) }
  }

  private func domainsIncludingInput() throws -> [String] {
    let domain = try RulesDocument.normalizedDomain(domainInput)
    guard !domains.contains(where: { $0 != editingDomain && $0.lowercased() == domain }) else {
      throw RulesDocument.EditError(message: "This domain is already in the group.")
    }
    var updated = domains
    if let editingDomain, let index = updated.firstIndex(of: editingDomain) {
      updated[index] = domain
    } else {
      updated.append(domain)
    }
    return updated
  }

  func editDomain(_ domain: String) {
    guard domainInput.isEmpty else { return }
    editingDomain = domain
    domainInput = domain
  }

  func cancelDomainEdit() {
    domainInput = ""
    editingDomain = nil
    domainError = nil
  }

  func removeDomain(_ domain: String) {
    if editingDomain == domain { cancelDomainEdit() }
    domains.removeAll { $0 == domain }
  }

  func save(deleting: Bool = false) async -> Bool {
    guard !isBusy, let document, let snapshot, let selectedID else { return false }
    var savingDomains = domains
    if !deleting && (!domainInput.isEmpty || editingDomain != nil) {
      do { savingDomains = try domainsIncludingInput() } catch {
        reportDomain(error)
        return false
      }
    }
    domainError = nil
    isBusy = true
    isSaving = true
    defer {
      isBusy = false
      isSaving = false
    }
    do {
      let edited =
        try deleting
        ? document.deletingGroup(id: selectedID)
        : document.editingGroup(
          id: selectedID, name: name, domains: savingDomains, profileIDs: profileIDs)
      let store = store
      let saved: RulesFileSnapshot
      do {
        saved = try await Task.detached { try store.save(edited, replacing: snapshot) }.value
      } catch {
        needsReload = true
        throw error
      }
      self.snapshot = saved
      self.document = try RulesDocument(source: saved.source)
      select(deleting ? groups.first?.id : selectedID)
      message =
        "File saved. A private backup was created."
      hasError = false
      needsReload = false
      saveGeneration += 1
      return true
    } catch {
      report(error)
      return false
    }
  }

  /// Returns true only when the requested close may proceed.
  func requestTransition(_ transition: Transition) async -> Bool {
    guard !isBusy else { return false }
    if case .group(let id) = transition, id == selectedID { return false }
    if hasChanges {
      pendingTransition = transition
      return false
    }
    return await perform(transition)
  }

  func resolveTransition(_ choice: TransitionChoice) async -> Bool {
    guard !isBusy, let transition = pendingTransition else { return false }
    pendingTransition = nil
    switch choice {
    case .stay: return false
    case .save:
      guard await save() else { return false }
    case .discard: discard()
    }
    return await perform(transition)
  }

  private func perform(_ transition: Transition) async -> Bool {
    switch transition {
    case .close: return true
    case .group(let id): select(id)
    case .newGroup: newGroup()
    case .reload: await load()
    }
    return false
  }

  private func reportDomain(_ error: Error) {
    domainError =
      (error as? RulesDocument.EditError)?.message ?? "Enter a valid domain or website URL."
    message = nil
    hasError = true
  }

  private func report(_ error: Error) {
    message =
      (error as? RulesDocument.EditError)?.message
      ?? (error as? ConfigurationValidationError)?.message
      ?? "Could not read or save this configuration. The editor has not confirmed a successful save."
    hasError = true
  }
}
