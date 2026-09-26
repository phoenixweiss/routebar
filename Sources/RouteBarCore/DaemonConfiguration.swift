import Darwin
import Foundation

public struct RouteBarDaemonSettings: Codable, Sendable, Equatable {
  public static let currentVersion = 1

  public let version: Int
  public let ownerUID: UInt32
  public let profileID: String
  public let automaticReconciliationEnabled: Bool

  public init(
    version: Int = currentVersion,
    ownerUID: UInt32,
    profileID: String,
    automaticReconciliationEnabled: Bool = false
  ) {
    self.version = version
    self.ownerUID = ownerUID
    self.profileID = profileID
    self.automaticReconciliationEnabled = automaticReconciliationEnabled
  }
}

public struct RouteBarDaemonConfigurationError: LocalizedError, Equatable {
  public let message: String

  public var errorDescription: String? { message }
}

public protocol RouteBarDaemonSettingsStoring: Sendable {
  func load() throws -> RouteBarDaemonSettings?
  func save(_ settings: RouteBarDaemonSettings) throws
}

public struct FileRouteBarDaemonSettingsStore: RouteBarDaemonSettingsStoring {
  public static let defaultURL = URL(
    fileURLWithPath: "/var/db/routebar/settings.json"
  )

  public let url: URL

  public init(url: URL = defaultURL) {
    self.url = url
  }

  public func load() throws -> RouteBarDaemonSettings? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    let settings = try JSONDecoder().decode(RouteBarDaemonSettings.self, from: data)
    guard settings.version == RouteBarDaemonSettings.currentVersion else {
      throw RouteBarDaemonConfigurationError(
        message: "unsupported daemon settings version: \(settings.version)"
      )
    }
    return settings
  }

  public func save(_ settings: RouteBarDaemonSettings) throws {
    guard settings.version == RouteBarDaemonSettings.currentVersion else {
      throw RouteBarDaemonConfigurationError(
        message: "refusing to save unsupported daemon settings"
      )
    }
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(settings)
    data.append(0x0A)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }
}

public protocol UserHomeDirectoryResolving: Sendable {
  func homeDirectory(for uid: UInt32) throws -> URL
}

public struct SystemUserHomeDirectoryResolver: UserHomeDirectoryResolving {
  public init() {}

  public func homeDirectory(for uid: UInt32) throws -> URL {
    let recommendedSize = sysconf(_SC_GETPW_R_SIZE_MAX)
    let bufferSize = recommendedSize > 0 ? Int(recommendedSize) : 16_384
    var buffer = [CChar](repeating: 0, count: bufferSize)
    var record = passwd()
    var result: UnsafeMutablePointer<passwd>?

    let status = buffer.withUnsafeMutableBufferPointer { pointer in
      getpwuid_r(uid_t(uid), &record, pointer.baseAddress, pointer.count, &result)
    }
    guard status == 0, result != nil, let home = record.pw_dir else {
      throw RouteBarDaemonConfigurationError(
        message: "could not resolve the home directory for uid \(uid)"
      )
    }
    let path = String(cString: home)
    guard path.hasPrefix("/"), path != "/" else {
      throw RouteBarDaemonConfigurationError(
        message: "refusing an invalid home directory for uid \(uid)"
      )
    }
    return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
  }
}

public actor RouteBarDaemonConfigurationService {
  private let settingsStore: any RouteBarDaemonSettingsStoring
  private let homeResolver: any UserHomeDirectoryResolving
  private let routePlanner: any RoutePlanning

  public init(
    settingsStore: any RouteBarDaemonSettingsStoring =
      FileRouteBarDaemonSettingsStore(),
    homeResolver: any UserHomeDirectoryResolving =
      SystemUserHomeDirectoryResolver(),
    routePlanner: any RoutePlanning = RoutePlanner()
  ) {
    self.settingsStore = settingsStore
    self.homeResolver = homeResolver
    self.routePlanner = routePlanner
  }

  public func settings() throws -> RouteBarDaemonSettings? {
    try settingsStore.load()
  }

  @discardableResult
  public func configure(clientUID: UInt32, profileID: String) throws
    -> RouteBarDaemonSettings
  {
    guard clientUID != 0 else {
      throw RouteBarDaemonConfigurationError(
        message: "refusing to configure RouteBar for the root account"
      )
    }

    if let existing = try settingsStore.load(), existing.ownerUID != clientUID {
      throw RouteBarDaemonConfigurationError(
        message: "RouteBar is already configured for another user"
      )
    }

    let configuration = try ConfigurationLoader.load(
      from: configurationURL(for: clientUID)
    )
    guard configuration.profiles.contains(where: { $0.id == profileID }) else {
      throw RouteBarDaemonConfigurationError(
        message: "profile \(profileID) does not exist in the RouteBar configuration"
      )
    }

    let previousSettings = try settingsStore.load()
    let settings = RouteBarDaemonSettings(
      ownerUID: clientUID,
      profileID: profileID,
      automaticReconciliationEnabled:
        previousSettings?.profileID == profileID
        && previousSettings?.automaticReconciliationEnabled == true
    )
    try settingsStore.save(settings)
    return settings
  }

  public func configurationURL(for clientUID: UInt32) throws -> URL {
    try homeResolver.homeDirectory(for: clientUID)
      .appendingPathComponent(".config/routebar/config.yaml", isDirectory: false)
  }

  public func routePlan() throws -> RoutePlan {
    guard let settings = try settingsStore.load() else {
      throw RouteBarDaemonConfigurationError(
        message: "RouteBar has not been configured"
      )
    }
    let configuration = try ConfigurationLoader.load(
      from: configurationURL(for: settings.ownerUID)
    )
    return try routePlanner.plan(
      configuration: configuration,
      forcedProfileID: settings.profileID
    )
  }

  public func requireOwner(_ clientUID: UInt32) throws -> RouteBarDaemonSettings {
    guard let settings = try settingsStore.load() else {
      throw RouteBarDaemonConfigurationError(
        message: "RouteBar has not been configured"
      )
    }
    guard settings.ownerUID == clientUID else {
      throw RouteBarDaemonConfigurationError(
        message: "RouteBar is configured for another user"
      )
    }
    return settings
  }

  public func setAutomaticReconciliationEnabled(_ enabled: Bool) throws {
    guard let settings = try settingsStore.load() else {
      throw RouteBarDaemonConfigurationError(
        message: "RouteBar has not been configured"
      )
    }
    try settingsStore.save(
      RouteBarDaemonSettings(
        ownerUID: settings.ownerUID,
        profileID: settings.profileID,
        automaticReconciliationEnabled: enabled
      )
    )
  }
}
