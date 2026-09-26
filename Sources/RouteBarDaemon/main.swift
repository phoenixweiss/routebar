import Darwin
import Dispatch
import Foundation
import RouteBarDaemonIPC

let delegate: RouteBarDaemonXPCListenerDelegate
do {
  let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
  let applicationURL = try RouteBarCodeSigningRequirement.enclosingApplicationURL(
    forExecutableURL: executableURL
  )
  let requirement = try RouteBarCodeSigningRequirement.designatedRequirement(
    forCodeAt: applicationURL
  )
  let authenticator = try RouteBarDaemonCodeSigningAuthenticator(
    requirement: requirement
  )
  let helperVersion = ProcessInfo.processInfo.environment["ROUTEBAR_HELPER_VERSION"] ?? "unknown"
  delegate = RouteBarDaemonXPCListenerDelegate(
    handler: RouteBarDaemonReadOnlyHandler(helperVersion: helperVersion),
    clientAuthenticator: authenticator
  )
} catch {
  fputs("RouteBar daemon refused to start: \(error.localizedDescription)\n", stderr)
  exit(EXIT_FAILURE)
}
let listener = NSXPCListener(
  machServiceName: RouteBarDaemonXPCTransport.machServiceName
)
listener.delegate = delegate
listener.resume()
dispatchMain()
