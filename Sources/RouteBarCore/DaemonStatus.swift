import Foundation

public struct DaemonRuntimeStatus: Sendable, Equatable {
  public let installed: Bool
  public let loaded: Bool
  public let runs: Int?
  public let lastExitCode: Int?
  public let intervalSeconds: Int?

  public init(
    installed: Bool,
    loaded: Bool,
    runs: Int? = nil,
    lastExitCode: Int? = nil,
    intervalSeconds: Int? = nil
  ) {
    self.installed = installed
    self.loaded = loaded
    self.runs = runs
    self.lastExitCode = lastExitCode
    self.intervalSeconds = intervalSeconds
  }
}

public protocol DaemonRuntimeInspecting {
  func status() -> DaemonRuntimeStatus
}

public enum LaunchctlStatusParser {
  public static func parse(_ output: String, installed: Bool) -> DaemonRuntimeStatus {
    DaemonRuntimeStatus(
      installed: installed,
      loaded: true,
      runs: integerValue(for: "runs", in: output),
      lastExitCode: integerValue(for: "last exit code", in: output),
      intervalSeconds: integerValue(for: "run interval", in: output)
    )
  }

  private static func integerValue(for key: String, in output: String) -> Int? {
    for line in output.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("\(key) =") else { continue }
      let value = trimmed.dropFirst(key.count + 2).split(whereSeparator: \.isWhitespace).first
      return value.flatMap { Int($0) }
    }
    return nil
  }
}

public struct SystemDaemonRuntimeInspector: DaemonRuntimeInspecting {
  public static let label = "io.github.phoenixweiss.routebar"
  public static let plistURL = URL(
    fileURLWithPath: "/Library/LaunchDaemons/io.github.phoenixweiss.routebar.plist"
  )

  public init() {}

  public func status() -> DaemonRuntimeStatus {
    let legacyFilesPresent = FileManager.default.fileExists(atPath: Self.plistURL.path)
    guard
      let result = try? FixedCommand.run(
        "/bin/launchctl",
        arguments: ["print", "system/\(Self.label)"]
      ),
      result.status == 0
    else {
      return DaemonRuntimeStatus(installed: legacyFilesPresent, loaded: false)
    }
    return LaunchctlStatusParser.parse(result.standardOutput, installed: true)
  }
}

public struct InstalledDaemonConfiguration: Sendable, Equatable {
  public let configURL: URL
  public let profileID: String

  public init(configURL: URL, profileID: String) {
    self.configURL = configURL
    self.profileID = profileID
  }
}

public enum InstalledDaemonInstallation: Sendable, Equatable {
  case notInstalled
  case legacy(InstalledDaemonConfiguration)
  case bundled
  case unknown
}

public protocol InstalledDaemonInspecting: Sendable {
  func inspect() -> InstalledDaemonInstallation
}

public struct SystemInstalledDaemonInspector: InstalledDaemonInspecting {
  public static let legacyBinaryPath =
    "/Library/PrivilegedHelperTools/io.github.phoenixweiss.routebar"
  public static let bundledProgram = "Contents/Resources/routebar-daemon"

  private let plistURL: URL

  public init(plistURL: URL = SystemDaemonRuntimeInspector.plistURL) {
    self.plistURL = plistURL
  }

  public func inspect() -> InstalledDaemonInstallation {
    Self.inspect(plistAt: plistURL)
  }

  public static func inspect(plistAt url: URL) -> InstalledDaemonInstallation {
    guard FileManager.default.fileExists(atPath: url.path) else { return .notInstalled }
    guard
      let data = try? Data(contentsOf: url),
      let propertyList = try? PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      ),
      let plist = propertyList as? [String: Any],
      plist["Label"] as? String == SystemDaemonRuntimeInspector.label
    else {
      return .unknown
    }

    let rawProgramArguments = plist["ProgramArguments"]
    let programArguments = rawProgramArguments as? [String]
    let bundleProgram = plist["BundleProgram"] as? String
    let machServices = plist["MachServices"] as? [String: Any]

    if rawProgramArguments == nil,
      plist["Program"] == nil,
      bundleProgram == bundledProgram,
      machServices?.count == 1,
      machServices?[SystemDaemonRuntimeInspector.label] as? Bool == true
    {
      return .bundled
    }

    guard plist["Program"] == nil,
      plist["BundleProgram"] == nil,
      plist["MachServices"] == nil,
      let programArguments,
      programArguments.count == 8,
      programArguments[0] == legacyBinaryPath,
      programArguments[1] == "reconcile",
      programArguments[2] == "--apply",
      programArguments[3] == "--quiet",
      programArguments[4] == "--config",
      programArguments[6] == "--profile",
      programArguments[5].hasPrefix("/"),
      !programArguments[7].isEmpty
    else {
      return .unknown
    }

    return .legacy(
      InstalledDaemonConfiguration(
        configURL: URL(fileURLWithPath: programArguments[5]),
        profileID: programArguments[7]
      )
    )
  }
}

public enum InstalledDaemonConfigurationLoader {
  public static func load(
    from url: URL = SystemDaemonRuntimeInspector.plistURL
  ) throws -> InstalledDaemonConfiguration? {
    switch SystemInstalledDaemonInspector.inspect(plistAt: url) {
    case .legacy(let configuration):
      configuration
    case .notInstalled, .bundled:
      nil
    case .unknown:
      throw InstalledDaemonInspectionError.unrecognizedConfiguration
    }
  }
}

public enum InstalledDaemonInspectionError: LocalizedError {
  case unrecognizedConfiguration

  public var errorDescription: String? {
    switch self {
    case .unrecognizedConfiguration:
      "RouteBar found an unrecognized launch daemon configuration. Built-in setup is blocked and no changes were made."
    }
  }
}
