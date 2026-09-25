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
    let installed = FileManager.default.fileExists(atPath: Self.plistURL.path)
    guard
      let result = try? FixedCommand.run(
        "/bin/launchctl",
        arguments: ["print", "system/\(Self.label)"]
      ),
      result.status == 0
    else {
      return DaemonRuntimeStatus(installed: installed, loaded: false)
    }
    return LaunchctlStatusParser.parse(result.standardOutput, installed: installed)
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

public enum InstalledDaemonConfigurationLoader {
  public static func load(
    from url: URL = SystemDaemonRuntimeInspector.plistURL
  ) throws -> InstalledDaemonConfiguration? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    let plist = try PropertyListDecoder().decode(LaunchDaemonPlist.self, from: data)
    guard
      let configPath = value(after: "--config", in: plist.programArguments),
      let profileID = value(after: "--profile", in: plist.programArguments)
    else {
      return nil
    }
    return InstalledDaemonConfiguration(
      configURL: URL(fileURLWithPath: configPath),
      profileID: profileID
    )
  }

  private static func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else { return nil }
    return arguments[valueIndex]
  }
}

private struct LaunchDaemonPlist: Decodable {
  let programArguments: [String]

  private enum CodingKeys: String, CodingKey {
    case programArguments = "ProgramArguments"
  }
}
