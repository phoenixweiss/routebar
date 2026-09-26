import Darwin
import Dispatch
import Foundation
import RouteBarCore
import RouteBarDaemonIPC

let configurationService = RouteBarDaemonConfigurationService()
let operationService = RouteBarDaemonOperationService(
  configurationService: configurationService
)
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
    handlerFactory: { clientUID in
      RouteBarDaemonConfiguredHandler(
        helperVersion: helperVersion,
        clientUID: clientUID,
        configurationService: configurationService,
        operationService: operationService
      )
    },
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
let reconciliationTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
reconciliationTimer.schedule(deadline: .now() + 30, repeating: 30)
reconciliationTimer.setEventHandler {
  Task {
    _ = try? await operationService.reconcileAutomatically()
  }
}
reconciliationTimer.resume()
dispatchMain()
