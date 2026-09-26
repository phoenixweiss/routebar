import Darwin
import Foundation
import MachO

private let expectedBundleIdentifier = "io.github.phoenixweiss.routebar.menu"

do {
  let applicationURL = try enclosingApplicationURL()
  try validateApplication(at: applicationURL)

  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  process.arguments = [
    "-gj",
    applicationURL.path,
    "--args",
    "--background",
  ]
  try process.run()
  process.waitUntilExit()
  exit(process.terminationStatus)
} catch {
  fputs("RouteBar login launcher failed: \(error.localizedDescription)\n", stderr)
  exit(EXIT_FAILURE)
}

private func enclosingApplicationURL() throws -> URL {
  var capacity: UInt32 = 0
  guard _NSGetExecutablePath(nil, &capacity) == -1 else {
    throw LauncherError(message: "could not determine the executable path size")
  }
  var buffer = [CChar](repeating: 0, count: Int(capacity))
  guard _NSGetExecutablePath(&buffer, &capacity) == 0 else {
    throw LauncherError(message: "could not determine the executable path")
  }

  let executablePath = String(
    decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
    as: UTF8.self
  )
  let executableURL = URL(fileURLWithPath: executablePath)
    .resolvingSymlinksInPath()
  let resourcesURL = executableURL.deletingLastPathComponent()
  let contentsURL = resourcesURL.deletingLastPathComponent()
  let applicationURL = contentsURL.deletingLastPathComponent()
  guard resourcesURL.lastPathComponent == "Resources",
    contentsURL.lastPathComponent == "Contents",
    applicationURL.pathExtension == "app"
  else {
    throw LauncherError(message: "launcher is not inside a macOS application bundle")
  }
  return applicationURL
}

private func validateApplication(at applicationURL: URL) throws {
  let infoURL = applicationURL.appendingPathComponent("Contents/Info.plist")
  let data = try Data(contentsOf: infoURL)
  guard
    let propertyList = try PropertyListSerialization.propertyList(
      from: data,
      format: nil
    ) as? [String: Any],
    propertyList["CFBundleIdentifier"] as? String == expectedBundleIdentifier
  else {
    throw LauncherError(message: "launcher found an unexpected application bundle")
  }
}

private struct LauncherError: LocalizedError {
  let message: String

  var errorDescription: String? { message }
}
