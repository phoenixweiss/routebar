import Foundation
import Security

public enum RouteBarCodeSigningRequirementError: Error, LocalizedError, Equatable {
  case applicationBundleNotFound
  case securityFramework(operation: String, status: OSStatus)
  case emptyRequirement

  public var errorDescription: String? {
    switch self {
    case .applicationBundleNotFound:
      return "The RouteBar application bundle could not be located"
    case .securityFramework(let operation, let status):
      let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
      return "\(operation) failed: \(detail)"
    case .emptyRequirement:
      return "The RouteBar application has an empty code-signing requirement"
    }
  }
}

public enum RouteBarCodeSigningRequirement {
  public static func enclosingApplicationURL(
    forExecutableURL executableURL: URL
  ) throws -> URL {
    var candidate = executableURL.standardizedFileURL.resolvingSymlinksInPath()
    while candidate.path != "/" {
      if candidate.pathExtension.lowercased() == "app" {
        return candidate
      }
      candidate.deleteLastPathComponent()
    }
    throw RouteBarCodeSigningRequirementError.applicationBundleNotFound
  }

  public static func designatedRequirement(forCodeAt codeURL: URL) throws -> String {
    var staticCode: SecStaticCode?
    try check(
      SecStaticCodeCreateWithPath(
        codeURL.standardizedFileURL.resolvingSymlinksInPath() as CFURL,
        [],
        &staticCode
      ),
      operation: "Reading the RouteBar code signature"
    )
    guard let staticCode else {
      throw RouteBarCodeSigningRequirementError.emptyRequirement
    }

    try check(
      SecStaticCodeCheckValidity(staticCode, [], nil),
      operation: "Validating the RouteBar code signature"
    )

    var requirement: SecRequirement?
    try check(
      SecCodeCopyDesignatedRequirement(staticCode, [], &requirement),
      operation: "Reading the RouteBar designated requirement"
    )
    guard let requirement else {
      throw RouteBarCodeSigningRequirementError.emptyRequirement
    }

    var requirementText: CFString?
    try check(
      SecRequirementCopyString(requirement, [], &requirementText),
      operation: "Serializing the RouteBar designated requirement"
    )
    guard let result = requirementText as String?, !result.isEmpty else {
      throw RouteBarCodeSigningRequirementError.emptyRequirement
    }
    return result
  }

  public static func validate(_ requirement: String) throws {
    guard !requirement.isEmpty else {
      throw RouteBarCodeSigningRequirementError.emptyRequirement
    }
    var compiledRequirement: SecRequirement?
    try check(
      SecRequirementCreateWithString(requirement as CFString, [], &compiledRequirement),
      operation: "Compiling the RouteBar client requirement"
    )
    guard compiledRequirement != nil else {
      throw RouteBarCodeSigningRequirementError.emptyRequirement
    }
  }

  private static func check(_ status: OSStatus, operation: String) throws {
    guard status == errSecSuccess else {
      throw RouteBarCodeSigningRequirementError.securityFramework(
        operation: operation,
        status: status
      )
    }
  }
}
