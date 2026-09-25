import Foundation

struct FixedCommandResult {
  let status: Int32
  let standardOutput: String
  let standardError: String
}

enum FixedCommand {
  static func run(_ executable: String, arguments: [String]) throws -> FixedCommandResult {
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = errors

    try process.run()
    process.waitUntilExit()

    return FixedCommandResult(
      status: process.terminationStatus,
      standardOutput: String(
        data: output.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? "",
      standardError: String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? ""
    )
  }
}
