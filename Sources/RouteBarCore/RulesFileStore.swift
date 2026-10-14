import Darwin
import Foundation

public struct RulesFileSnapshot: Sendable {
  public let url: URL
  public let target: URL
  public let source: String
  let inode: UInt64
  let permissions: mode_t
}

/// Coordinates edits, follows the existing symlink, and atomically replaces only its target.
public struct RulesFileStore: Sendable {
  public let backupDirectory: URL
  public init(
    backupDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/RouteBar/ConfigBackups")
  ) {
    self.backupDirectory = backupDirectory
  }

  public func load(url: URL) throws -> RulesFileSnapshot {
    let target = url.resolvingSymlinksInPath()
    let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
    else {
      throw error("The configuration must be a regular file owned by the current user.")
    }
    let handle = try FileHandle(forReadingFrom: target)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
    guard data.count <= 1024 * 1024, let source = String(data: data, encoding: .utf8) else {
      throw error("The configuration must be UTF-8 and no larger than 1 MiB.")
    }
    _ = try RulesDocument(source: source)
    return RulesFileSnapshot(
      url: url, target: target, source: source,
      inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
      permissions: mode_t((attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o600))
  }

  public func save(_ document: RulesDocument, replacing snapshot: RulesFileSnapshot) throws
    -> RulesFileSnapshot
  {
    _ = try RulesDocument(source: document.source)
    guard document.source.utf8.count <= 1024 * 1024 else {
      throw error("The edited file exceeds 1 MiB.")
    }
    var coordinationError: NSError?
    var outcome: Result<RulesFileSnapshot, Error>?
    NSFileCoordinator().coordinate(
      writingItemAt: snapshot.target, options: .forReplacing,
      error: &coordinationError
    ) { target in
      outcome = Result {
        try checkUnchanged(snapshot)
        guard target.standardizedFileURL == snapshot.target.standardizedFileURL else {
          throw error("The configuration target changed. Reload before saving.")
        }
        let manager = FileManager.default
        try manager.createDirectory(
          at: backupDirectory, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        let backupAttributes = try manager.attributesOfItem(atPath: backupDirectory.path)
        guard backupAttributes[.type] as? FileAttributeType == .typeDirectory,
          (backupAttributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
          ((backupAttributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0) & 0o077 == 0
        else {
          throw error("The backup directory must be private and owned by the current user.")
        }
        let backup = backupDirectory.appendingPathComponent("config-\(UUID().uuidString).yaml")
        guard
          manager.createFile(
            atPath: backup.path, contents: Data(snapshot.source.utf8),
            attributes: [.posixPermissions: 0o600])
        else { throw error("Could not create a configuration backup.") }
        let temporary = target.deletingLastPathComponent().appendingPathComponent(
          ".routebar-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
          throw error("Could not prepare the atomic configuration save.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
          try? handle.close()
          try? manager.removeItem(at: temporary)
        }
        try handle.write(contentsOf: Data(document.source.utf8))
        guard fchmod(descriptor, snapshot.permissions) == 0, fsync(descriptor) == 0 else {
          throw error("Could not finish writing the configuration. The original was not replaced.")
        }
        try checkUnchanged(snapshot)
        guard rename(temporary.path, target.path) == 0 else {
          throw error("Could not replace the configuration. The original was not changed.")
        }
        let reread = try load(url: snapshot.url)
        guard reread.source == document.source else {
          throw error("The file changed immediately after saving. Reload it before continuing.")
        }
        return reread
      }
    }
    if let coordinationError { throw coordinationError }
    guard let outcome else { throw error("The configuration save was not completed.") }
    return try outcome.get()
  }

  private func checkUnchanged(_ snapshot: RulesFileSnapshot) throws {
    let current = try load(url: snapshot.url)
    guard current.target == snapshot.target, current.inode == snapshot.inode,
      current.source == snapshot.source, current.permissions == snapshot.permissions
    else {
      throw error(
        "The YAML file or its link changed outside RouteBar. Reload before saving; no edits were overwritten."
      )
    }
  }
  private func error(_ message: String) -> RulesDocument.EditError { .init(message: message) }
}
