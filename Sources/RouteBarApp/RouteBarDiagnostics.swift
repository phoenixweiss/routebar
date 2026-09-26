import AppKit
import Foundation
import RouteBarCore
import SwiftUI

struct RouteBarDiagnostics: Equatable {
  struct Section: Identifiable, Equatable {
    let title: String
    let rows: [Row]

    var id: String { title }
  }

  struct Row: Identifiable, Equatable {
    let label: String
    let value: String

    var id: String { label }
  }

  let generatedAt: Date
  let sections: [Section]

  init(
    generatedAt: Date = Date(),
    appVersion: String,
    systemVersion: String,
    architecture: String,
    state: RouteBarAppState,
    installedDaemon: InstalledDaemonInstallation,
    bundledDaemonStatus: BundledDaemonServiceStatus,
    bundledDaemonConnectionStatus: BundledDaemonConnectionStatus,
    reconciliationDiagnostics: BundledDaemonReconciliationDiagnostics
  ) {
    self.generatedAt = generatedAt

    let runtime = Self.runtime(from: state)
    sections = [
      Section(
        title: "APPLICATION",
        rows: [
          Row(label: "RouteBar", value: "v\(appVersion)"),
          Row(label: "macOS", value: systemVersion),
          Row(label: "Architecture", value: architecture),
          Row(label: "Status", value: Self.appStatus(from: state)),
        ]
      ),
      Section(
        title: "ROUTING",
        rows: [
          Row(label: "Profile", value: Self.profileStatus(from: state)),
          Row(label: "Physical interface", value: runtime.physicalInterface),
          Row(label: "Physical gateway", value: runtime.gatewayStatus),
          Row(label: "VPN", value: runtime.vpnStatus),
          Row(label: "Host routes", value: runtime.routeStatus),
        ]
      ),
      Section(
        title: "AUTOMATION",
        rows: [
          Row(label: "Service mode", value: Self.serviceMode(installedDaemon)),
          Row(
            label: "Built-in service",
            value: Self.bundledServiceStatus(
              bundledDaemonStatus,
              installedDaemon: installedDaemon
            )
          ),
          Row(
            label: "Helper version",
            value: Self.helperVersion(
              from: bundledDaemonConnectionStatus,
              installedDaemon: installedDaemon
            )
          ),
          Row(label: "Daemon", value: Self.daemonStatus(runtime.daemon)),
          Row(
            label: "Configuration",
            value: Self.configurationStatus(reconciliationDiagnostics)
          ),
          Row(
            label: "Last reconciliation",
            value: Self.reconciliationStatus(reconciliationDiagnostics)
          ),
        ]
      ),
    ]
  }

  var redactedReport: String {
    var lines = [
      "RouteBar diagnostics",
      "Generated: \(generatedAt.formatted(.iso8601))",
    ]
    for section in sections {
      lines.append("")
      lines.append(section.title)
      lines.append(contentsOf: section.rows.map { "\($0.label): \($0.value)" })
    }
    lines.append("")
    lines.append("Sensitive network addresses and configuration contents are omitted.")
    return lines.joined(separator: "\n")
  }

  private struct Runtime {
    let daemon: DaemonRuntimeStatus
    let physicalInterface: String
    let gatewayStatus: String
    let vpnStatus: String
    let routeStatus: String
  }

  private static func runtime(from state: RouteBarAppState) -> Runtime {
    switch state {
    case .ready(let snapshot, _):
      return Runtime(
        daemon: snapshot.daemon,
        physicalInterface: snapshot.network.physicalInterface,
        gatewayStatus: "Detected",
        vpnStatus: snapshot.network.vpnInterfaces.isEmpty
          ? "Not detected" : "Detected (\(snapshot.network.vpnInterfaces.count))",
        routeStatus: "\(snapshot.activeCount) of \(snapshot.routeCount) active"
      )
    case .selectingProfile(let selection):
      return unavailableRuntime(daemon: selection.daemon)
    case .failed(let failure):
      return unavailableRuntime(daemon: failure.daemon)
    case .loading:
      return unavailableRuntime(daemon: DaemonRuntimeStatus(installed: false, loaded: false))
    }
  }

  private static func unavailableRuntime(daemon: DaemonRuntimeStatus) -> Runtime {
    Runtime(
      daemon: daemon,
      physicalInterface: "Unavailable",
      gatewayStatus: "Unavailable",
      vpnStatus: "Unavailable",
      routeStatus: "Unavailable"
    )
  }

  private static func appStatus(from state: RouteBarAppState) -> String {
    switch state {
    case .loading: "Checking"
    case .selectingProfile: "Profile selection required"
    case .ready(let snapshot, _): snapshot.allRoutesActive ? "Routes active" : "Needs attention"
    case .failed: "Status unavailable"
    }
  }

  private static func profileStatus(from state: RouteBarAppState) -> String {
    switch state {
    case .loading: "Checking"
    case .selectingProfile: "Selection required"
    case .ready: "Selected"
    case .failed: "Unavailable"
    }
  }

  private static func serviceMode(_ installation: InstalledDaemonInstallation) -> String {
    switch installation {
    case .notInstalled: "Not installed"
    case .legacy: "Legacy"
    case .bundled: "Built-in"
    case .unknown: "Unrecognized"
    }
  }

  private static func bundledServiceStatus(
    _ status: BundledDaemonServiceStatus,
    installedDaemon: InstalledDaemonInstallation
  ) -> String {
    if case .legacy = installedDaemon {
      return "Not enabled"
    }
    if case .unknown = installedDaemon {
      return "Blocked"
    }
    return switch status {
    case .checking: "Checking"
    case .notRegistered: "Not enabled"
    case .enabled: "Enabled"
    case .requiresApproval: "Approval required"
    case .notFound: "Not included"
    case .unknown: "Unavailable"
    }
  }

  private static func helperVersion(
    from status: BundledDaemonConnectionStatus,
    installedDaemon: InstalledDaemonInstallation
  ) -> String {
    if case .legacy = installedDaemon {
      return "Not running"
    }
    if case .unknown = installedDaemon {
      return "Unavailable"
    }
    return switch status {
    case .connected(let helperVersion): "v\(helperVersion)"
    case .versionMismatch(_, let helperVersion): "v\(helperVersion) (version mismatch)"
    case .unavailable: "Not responding"
    case .notApplicable: "Not running"
    }
  }

  private static func daemonStatus(_ daemon: DaemonRuntimeStatus) -> String {
    guard daemon.installed else { return "Not installed" }
    guard daemon.loaded else { return "Installed, not loaded" }
    if let exitCode = daemon.lastExitCode, exitCode != 0 {
      return "Last run failed (code \(exitCode))"
    }
    let schedule = daemon.intervalSeconds.map { "every \($0) s" } ?? "loaded"
    return "OK · \(schedule)"
  }

  private static func configurationStatus(
    _ diagnostics: BundledDaemonReconciliationDiagnostics
  ) -> String {
    switch diagnostics.configurationRequiresReload {
    case true: "Changed, awaiting confirmation"
    case false: "Current"
    case nil: "Not reported"
    }
  }

  private static func reconciliationStatus(
    _ diagnostics: BundledDaemonReconciliationDiagnostics
  ) -> String {
    if diagnostics.lastError != nil {
      return "Failed"
    }
    if let result = diagnostics.lastResult {
      return result.conflictCount == 0
        ? "OK · \(result.activeRouteCount) active"
        : "Conflict · \(result.conflictCount)"
    }
    return "Not reported"
  }
}

struct RouteBarDiagnosticsView: View {
  let diagnostics: RouteBarDiagnostics

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          ForEach(diagnostics.sections) { section in
            diagnosticSection(section)
          }
        }
        .padding(28)
      }

      Divider()
      footer
    }
    .frame(minWidth: 440, idealWidth: 480, minHeight: 500, idealHeight: 560)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(spacing: 12) {
      RouteBarBrandMark()
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 2) {
        Text("Diagnostics")
          .font(routeBarFont(19, weight: .semibold))
          .foregroundStyle(brandInk)
        Text("Safe technical summary")
          .font(routeBarFont(12.5))
          .foregroundStyle(.secondary)
      }

      Spacer()

      Button("Close") {
        dismiss()
      }
      .controlSize(.large)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 14)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func diagnosticSection(_ section: RouteBarDiagnostics.Section) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(section.title)
        .font(routeBarFont(11.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .tracking(0.8)
        .padding(.bottom, 8)

      ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
        HStack(alignment: .firstTextBaseline, spacing: 18) {
          Text(row.label)
            .font(routeBarFont(14.5))
          Spacer(minLength: 12)
          Text(row.value)
            .font(routeBarFont(13.5, weight: .medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 7)

        if index < section.rows.count - 1 {
          Divider()
            .opacity(0.62)
        }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text(copied ? "Copied to Clipboard" : "Ready to share")
          .font(routeBarFont(12.5, weight: .medium))
        Text("Domains, addresses, SSIDs, paths, and YAML contents are omitted.")
          .font(routeBarFont(11.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 12)

      Button(copied ? "Copied" : "Copy Report") {
        copyReport()
      }
      .buttonStyle(.borderedProminent)
      .tint(brandInk)
      .controlSize(.large)
      .disabled(copied)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 14)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private func copyReport() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.setString(diagnostics.redactedReport, forType: .string) else { return }
    copied = true
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      copied = false
    }
  }

  private func routeBarFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .custom("Manrope", fixedSize: size).weight(weight)
  }

  private var brandInk: Color {
    colorScheme == .dark
      ? Color(red: 0.72, green: 0.88, blue: 0.92)
      : Color(red: 0.09, green: 0.25, blue: 0.30)
  }
}

enum RouteBarRuntimeArchitecture {
  static var current: String {
    #if arch(arm64)
      "Apple silicon"
    #elseif arch(x86_64)
      "Intel"
    #else
      "Unknown"
    #endif
  }
}
