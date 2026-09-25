import Darwin
import Foundation
import RouteBarCore

private enum ExitCode {
  static let success: Int32 = 0
  static let invalidConfiguration: Int32 = 2
  static let planningFailure: Int32 = 3
  static let conflict: Int32 = 4
  static let usage: Int32 = 64
  static let permission: Int32 = 77
}

private struct Options {
  var configURL = ConfigurationLoader.defaultURL
  var profileID: String?
  var apply = false
  var adoptExisting = false
  var quiet = false
}

private let routeStateURL = URL(fileURLWithPath: "/var/db/routebar/state.json")

private enum CLIError: LocalizedError {
  case usage(String)

  var errorDescription: String? {
    switch self {
    case .usage(let message): message
    }
  }
}

private let help = """
  RouteBar development CLI

  Usage:
    routebar validate [--config PATH]
    routebar plan [--config PATH] [--profile ID]
    routebar reconcile [--config PATH] [--profile ID]
                       [--apply | --adopt-existing] [--quiet]
    routebar cleanup [--apply] [--quiet]
    routebar help

  Commands are read-only unless --apply or --adopt-existing is present.
  Mutating operations require root. Only explicit /32 host routes recorded in
  RouteBar's state are replaced or removed.
  Default configuration: ~/.config/routebar/config.yaml
  Default state: /var/db/routebar/state.json
  """

private func parseOptions(
  _ arguments: ArraySlice<String>,
  allowProfile: Bool,
  allowApply: Bool = false,
  allowAdoption: Bool = false,
  allowQuiet: Bool = false
) throws -> Options {
  var options = Options()
  var index = arguments.startIndex

  while index < arguments.endIndex {
    let argument = arguments[index]
    switch argument {
    case "--config":
      index = arguments.index(after: index)
      guard index < arguments.endIndex else { throw CLIError.usage("--config requires a path") }
      options.configURL = URL(
        fileURLWithPath: NSString(string: arguments[index]).expandingTildeInPath)
    case "--profile" where allowProfile:
      index = arguments.index(after: index)
      guard index < arguments.endIndex else { throw CLIError.usage("--profile requires an id") }
      options.profileID = arguments[index]
    case "--apply" where allowApply:
      options.apply = true
    case "--adopt-existing" where allowAdoption:
      options.adoptExisting = true
    case "--quiet" where allowQuiet:
      options.quiet = true
    case "--help", "-h":
      print(help)
      exit(ExitCode.success)
    default:
      throw CLIError.usage("unknown option: \(argument)")
    }
    index = arguments.index(after: index)
  }
  if options.apply && options.adoptExisting {
    throw CLIError.usage("--apply and --adopt-existing cannot be used together")
  }
  return options
}

private func configurationError(_ error: Error, path: URL, quiet: Bool = false) -> Never {
  if quiet {
    fputs("RouteBar configuration is invalid\n", stderr)
    exit(ExitCode.invalidConfiguration)
  }
  let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  fputs("Configuration error in \(path.path): \(description)\n", stderr)
  exit(ExitCode.invalidConfiguration)
}

private func operationError(_ error: Error, label: String, quiet: Bool) -> Never {
  if quiet {
    fputs("RouteBar \(label.lowercased()) failed\n", stderr)
  } else {
    let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    fputs("\(label) error: \(description)\n", stderr)
  }
  exit(ExitCode.planningFailure)
}

private func requireRoot(for operation: String, quiet: Bool) {
  guard geteuid() == 0 else {
    if quiet {
      fputs("RouteBar requires root privileges\n", stderr)
    } else {
      fputs("\(operation) requires root privileges\n", stderr)
    }
    exit(ExitCode.permission)
  }
}

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else {
  print(help)
  exit(ExitCode.success)
}

do {
  switch command {
  case "help", "--help", "-h":
    print(help)

  case "validate":
    let options = try parseOptions(arguments.dropFirst(), allowProfile: false)
    do {
      let configuration = try ConfigurationLoader.load(from: options.configURL)
      let bypassCount = configuration.groups.filter { $0.mode == .bypassVPN }.count
      let checkOnlyCount = configuration.groups.filter { $0.mode == .checkOnly }.count
      print("Configuration is valid: \(options.configURL.path)")
      print(
        "Profiles: \(configuration.profiles.count); groups: \(configuration.groups.count) "
          + "(bypass: \(bypassCount), checks only: \(checkOnlyCount))"
      )
    } catch {
      configurationError(error, path: options.configURL)
    }

  case "plan":
    let options = try parseOptions(arguments.dropFirst(), allowProfile: true)
    let configuration: RouteBarConfiguration
    do {
      configuration = try ConfigurationLoader.load(from: options.configURL)
    } catch {
      configurationError(error, path: options.configURL)
    }
    do {
      let plan = try RoutePlanner().plan(
        configuration: configuration,
        forcedProfileID: options.profileID
      )
      print(PlanFormatter.text(plan))
    } catch {
      let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      fputs("Planning error: \(description)\n", stderr)
      exit(ExitCode.planningFailure)
    }

  case "reconcile":
    let options = try parseOptions(
      arguments.dropFirst(),
      allowProfile: true,
      allowApply: true,
      allowAdoption: true,
      allowQuiet: true
    )
    let configuration: RouteBarConfiguration
    do {
      configuration = try ConfigurationLoader.load(from: options.configURL)
    } catch {
      configurationError(error, path: options.configURL, quiet: options.quiet)
    }

    do {
      let routePlan = try RoutePlanner().plan(
        configuration: configuration,
        forcedProfileID: options.profileID
      )
      let service = RouteReconciliationService(
        stateStore: FileRouteStateStore(url: routeStateURL)
      )

      if options.adoptExisting {
        requireRoot(for: "Route adoption", quiet: options.quiet)
        let result = try service.adoptExisting(routePlan: routePlan)
        if !options.quiet {
          print(ReconciliationFormatter.adoption(result))
        }
        if !result.conflicts.isEmpty {
          exit(ExitCode.conflict)
        }
      } else {
        if options.apply {
          requireRoot(for: "Route reconciliation", quiet: options.quiet)
        }
        let result =
          try options.apply
          ? service.apply(routePlan: routePlan)
          : service.plan(routePlan: routePlan)
        if !options.quiet {
          print(ReconciliationFormatter.text(result, applied: options.apply))
        }
        if !result.plan.conflicts.isEmpty {
          exit(ExitCode.conflict)
        }
      }
    } catch {
      operationError(error, label: "Reconciliation", quiet: options.quiet)
    }

  case "cleanup":
    let options = try parseOptions(
      arguments.dropFirst(),
      allowProfile: false,
      allowApply: true,
      allowQuiet: true
    )
    if options.apply {
      requireRoot(for: "Route cleanup", quiet: options.quiet)
    }
    do {
      let service = RouteReconciliationService(
        stateStore: FileRouteStateStore(url: routeStateURL)
      )
      let result = try options.apply ? service.cleanup() : service.cleanupPlan()
      if !options.quiet {
        print(ReconciliationFormatter.text(result, applied: options.apply))
      }
      if !result.plan.conflicts.isEmpty {
        exit(ExitCode.conflict)
      }
    } catch {
      operationError(error, label: "Cleanup", quiet: options.quiet)
    }

  default:
    throw CLIError.usage("unknown command: \(command)")
  }
} catch {
  fputs("\(error.localizedDescription)\n\n\(help)\n", stderr)
  exit(ExitCode.usage)
}
