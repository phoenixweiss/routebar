import AppKit
import RouteBarCore
import SwiftUI

struct RouteBarStatusView: View {
  @ObservedObject var model: RouteBarAppModel
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      productToolbar
      Divider()
      statusHeader
      Divider()
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      footer
    }
    .frame(minWidth: 470, idealWidth: 510, minHeight: 560, idealHeight: 660)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var productToolbar: some View {
    HStack(spacing: 12) {
      RouteBarBrandMark()
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)

      Text("RouteBar")
        .font(routeBarFont(22, weight: .semibold))
        .foregroundStyle(brandInk)

      Spacer(minLength: 20)

      Button("Refresh") {
        Task { await model.refresh() }
      }
      .font(routeBarFont(13, weight: .medium))
      .controlSize(.large)
      .disabled(model.isRefreshing)
      .keyboardShortcut("r", modifiers: .command)
      .help("Refresh status")
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 12)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var statusHeader: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(statusColor.opacity(colorScheme == .dark ? 0.22 : 0.12))
        Image(systemName: statusSymbol)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(statusColor)
      }
      .frame(width: 38, height: 38)
      .accessibilityHidden(true)

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          statusCopy
          Spacer(minLength: 4)
          updatedText
        }

        statusCopy
      }
    }
    .padding(.horizontal, 30)
    .padding(.vertical, 18)
    .background(Color(nsColor: .textBackgroundColor))
  }

  private var statusCopy: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(statusTitle)
        .font(routeBarFont(23, weight: .semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
      Text(statusSummary)
        .font(routeBarFont(14.5))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .fixedSize(horizontal: true, vertical: false)
  }

  private var updatedText: some View {
    Text(updatedLabel)
      .font(routeBarFont(12))
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.trailing)
      .lineLimit(1)
      .fixedSize(horizontal: true, vertical: false)
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      HStack(spacing: 12) {
        ProgressView()
          .controlSize(.regular)
        Text("Reading network and route status…")
          .font(routeBarFont(15.5))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(30)
      .background(Color(nsColor: .textBackgroundColor))

    case .selectingProfile(let selection):
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          firstRunSection
          sectionDivider
          daemonSection(selection.daemon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 24)
      }
      .background(Color(nsColor: .textBackgroundColor))

    case .ready(let snapshot, _):
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if shouldShowFirstRunGuidance(for: snapshot.daemon) {
            firstRunSection
            sectionDivider
          }
          networkSection(snapshot)
          sectionDivider
          routesSection(snapshot)
          sectionDivider
          daemonSection(snapshot.daemon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 30)
        .padding(.top, 22)
        .padding(.bottom, 24)
      }
      .background(Color(nsColor: .textBackgroundColor))

    case .failed(let failure):
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if isUnknownDaemonInstallation {
            firstRunSection
            sectionDivider
          } else {
            sectionTitle("STATUS")
            Text(failure.message)
              .font(routeBarFont(15.5))
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.top, 20)
            sectionDivider
          }
          daemonSection(failure.daemon)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(30)
      }
      .background(Color(nsColor: .textBackgroundColor))
    }
  }

  private func networkSection(_ snapshot: RouteStatusSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle("NETWORK")
        .padding(.bottom, 10)
      informationRow("Profile", value: snapshot.profile.name)
      rowDivider
      informationRow(
        "Gateway",
        value: "\(snapshot.network.physicalGateway) · \(snapshot.network.physicalInterface)"
      )
      rowDivider
      informationRow(
        "VPN",
        value: snapshot.network.vpnInterfaces.isEmpty
          ? "Not detected"
          : snapshot.network.vpnInterfaces.joined(separator: ", ")
      )
    }
  }

  @ViewBuilder
  private func routesSection(_ snapshot: RouteStatusSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        sectionTitle("ROUTES")
        Spacer()
        Text("\(snapshot.activeCount) of \(snapshot.routeCount) active")
          .font(routeBarFont(13.5, weight: .medium).monospacedDigit())
          .foregroundStyle(.secondary)
      }
      .padding(.bottom, 10)

      if snapshot.groups.isEmpty {
        Text("No bypass routes are configured for this profile.")
          .font(routeBarFont(14.5))
          .foregroundStyle(.secondary)
          .padding(.vertical, 12)
      } else {
        ForEach(Array(snapshot.groups.enumerated()), id: \.element.id) { index, group in
          routeGroup(group)
          if index < snapshot.groups.count - 1 {
            rowDivider
              .padding(.leading, 28)
          }
        }
      }
    }
  }

  private func routeGroup(_ group: RouteGroupStatus) -> some View {
    let active = group.activeCount == group.targets.count

    return VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 10) {
        ZStack {
          Circle()
            .fill((active ? Color.green : Color.orange).opacity(0.13))
          Image(systemName: active ? "checkmark" : "exclamationmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(active ? Color.green : Color.orange)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)

        Text(group.name)
          .font(routeBarFont(15.5, weight: .semibold))
        Spacer(minLength: 12)
        Text("\(group.activeCount) / \(group.targets.count)")
          .font(routeBarFont(13.5, weight: .medium).monospacedDigit())
          .foregroundStyle(.secondary)
      }

      Text(sourceSummary(group))
        .font(routeBarFont(13.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 28)

      ForEach(group.targets.filter { !$0.isActive }.prefix(3)) { target in
        Text(routeProblem(target))
          .font(.system(size: 13.5, design: .monospaced))
          .foregroundStyle(.orange)
          .padding(.leading, 28)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 9)
  }

  private func daemonSection(_ daemon: DaemonRuntimeStatus) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      sectionTitle("AUTOMATION")
        .padding(.bottom, 10)

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text("Daemon")
            .font(routeBarFont(15.5))
          Spacer(minLength: 16)
          daemonValue(daemon)
        }

        VStack(alignment: .leading, spacing: 7) {
          Text("Daemon")
            .font(routeBarFont(15.5))
          daemonValue(daemon)
        }
      }
      .padding(.vertical, 8)

      rowDivider

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          Text("Built-in service")
            .font(routeBarFont(15.5))
          Spacer(minLength: 16)
          bundledDaemonValue
        }

        VStack(alignment: .leading, spacing: 7) {
          Text("Built-in service")
            .font(routeBarFont(15.5))
          bundledDaemonValue
        }
      }
      .padding(.vertical, 8)

      if let guidance = bundledDaemonGuidance(for: daemon) {
        Text(guidance)
          .font(routeBarFont(13.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, 3)
      }
    }
  }

  private func daemonValue(_ daemon: DaemonRuntimeStatus) -> some View {
    HStack(spacing: 8) {
      Circle()
        .fill(daemonColor(daemon))
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
      Text(daemonDescription(daemon))
        .font(routeBarFont(14).monospacedDigit())
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var bundledDaemonValue: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(bundledDaemonColor)
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
      Text(bundledDaemonDescription)
        .font(routeBarFont(14))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var firstRunSection: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: preflightSymbol)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(preflightColor)
        .frame(width: 22)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 5) {
        Text(firstRunTitle)
          .font(routeBarFont(15.5, weight: .semibold))
        Text(firstRunDetail)
          .font(routeBarFont(13.5))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if !model.profileOptions.isEmpty {
          profileSelectionControl
            .padding(.top, 8)
        }
      }
    }
  }

  private var profileSelectionControl: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) {
        Text("Profile")
          .font(routeBarFont(14.5, weight: .medium))
        Spacer(minLength: 16)
        profilePicker
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("Profile")
          .font(routeBarFont(14.5, weight: .medium))
        profilePicker
      }
    }
  }

  private var profilePicker: some View {
    Picker("Profile", selection: profileSelectionBinding) {
      if model.selectedProfileID == nil {
        Text("Choose a profile").tag("")
      }
      ForEach(model.profileOptions) { profile in
        Text(profile.name == profile.id ? profile.name : "\(profile.name) · \(profile.id)")
          .tag(profile.id)
      }
    }
    .labelsHidden()
    .pickerStyle(.menu)
    .controlSize(.large)
    .disabled(model.isRefreshing)
    .frame(maxWidth: 250, alignment: .trailing)
  }

  private var profileSelectionBinding: Binding<String> {
    Binding(
      get: { model.selectedProfileID ?? "" },
      set: { model.selectProfile($0) }
    )
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 14) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          footerActions
          Spacer(minLength: 16)
          dockToggle
        }

        VStack(alignment: .leading, spacing: 12) {
          footerActions
          dockToggle
        }
      }

      Text(lastCheckedLabel)
        .font(routeBarFont(12.5))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 30)
    .padding(.top, 14)
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor))
  }

  private var footerActions: some View {
    HStack(spacing: 10) {
      Button("Open Config") {
        model.openConfiguration()
      }
      .buttonStyle(.borderedProminent)
      .tint(brandInk)

      Button("Reveal in Finder") {
        model.revealConfiguration()
      }
      .buttonStyle(.bordered)
    }
    .font(routeBarFont(13, weight: .medium))
    .controlSize(.large)
  }

  private var dockToggle: some View {
    Toggle("Show in Dock", isOn: $model.showInDock)
      .font(routeBarFont(13))
      .toggleStyle(.switch)
      .tint(brandInk)
  }

  private var statusSymbol: String {
    switch model.state {
    case .loading: "arrow.clockwise"
    case .selectingProfile: "list.bullet.rectangle"
    case .ready(let snapshot, _): isHealthy(snapshot) ? "checkmark" : "exclamationmark"
    case .failed: "xmark"
    }
  }

  private var statusColor: Color {
    switch model.state {
    case .loading: .secondary
    case .selectingProfile: .orange
    case .ready(let snapshot, _): isHealthy(snapshot) ? .green : .orange
    case .failed: .red
    }
  }

  private var statusTitle: String {
    if isUnknownDaemonInstallation {
      return "Setup blocked"
    }
    return switch model.state {
    case .loading: "Checking RouteBar"
    case .selectingProfile: "Choose a profile"
    case .ready(let snapshot, _): isHealthy(snapshot) ? "Routes are active" : "Needs attention"
    case .failed: "Status unavailable"
    }
  }

  private var statusSummary: String {
    if isUnknownDaemonInstallation {
      return "The installed daemon is not recognized"
    }
    switch model.state {
    case .loading:
      return "Reading the current gateway and explicit routes"
    case .selectingProfile:
      return "Select a profile to build a read-only route plan"
    case .ready(let snapshot, _):
      if isHealthy(snapshot) {
        return "\(snapshot.activeCount) routes use the physical gateway"
      }
      return "\(snapshot.activeCount) of \(snapshot.routeCount) routes match the current gateway"
    case .failed(let failure):
      return failure.daemon.loaded
        ? "The daemon is loaded, but status could not be read" : "The daemon is not loaded"
    }
  }

  private var updatedLabel: String {
    switch model.state {
    case .loading:
      return "Updating…"
    case .selectingProfile(let selection):
      return updateDescription(selection.checkedAt)
    case .ready(let snapshot, _):
      return updateDescription(snapshot.checkedAt)
    case .failed(let failure):
      return updateDescription(failure.checkedAt)
    }
  }

  private var lastCheckedLabel: String {
    let date: Date?
    switch model.state {
    case .loading:
      date = nil
    case .selectingProfile(let selection):
      date = selection.checkedAt
    case .ready(let snapshot, _):
      date = snapshot.checkedAt
    case .failed(let failure):
      date = failure.checkedAt
    }
    return date.map {
      "Last checked at \($0.formatted(date: .omitted, time: .standard))"
    } ?? "Waiting for the first status check"
  }

  private var brandInk: Color {
    colorScheme == .dark
      ? Color(red: 0.72, green: 0.88, blue: 0.92)
      : Color(red: 0.09, green: 0.25, blue: 0.30)
  }

  private var sectionDivider: some View {
    Divider()
      .padding(.vertical, 18)
  }

  private var rowDivider: some View {
    Divider()
      .opacity(0.62)
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(routeBarFont(11.5, weight: .semibold))
      .foregroundStyle(Color.secondary)
      .tracking(0.8)
  }

  private func informationRow(_ title: String, value: String) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 18) {
        Text(title)
          .font(routeBarFont(15.5))
        Spacer(minLength: 16)
        Text(value)
          .font(routeBarFont(15.5, weight: .medium).monospacedDigit())
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.trailing)
          .lineLimit(2)
      }

      VStack(alignment: .leading, spacing: 5) {
        Text(title)
          .font(routeBarFont(15.5))
        Text(value)
          .font(routeBarFont(14.5, weight: .medium).monospacedDigit())
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.vertical, 8)
  }

  private func routeBarFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .custom("Manrope", fixedSize: size).weight(weight)
  }

  private func isHealthy(_ snapshot: RouteStatusSnapshot) -> Bool {
    snapshot.allRoutesActive
      && snapshot.daemon.installed
      && snapshot.daemon.loaded
      && snapshot.daemon.lastExitCode == 0
      && !bundledDaemonNeedsAttention
  }

  private var bundledDaemonNeedsAttention: Bool {
    switch model.bundledDaemonConnectionStatus {
    case .versionMismatch, .unavailable: true
    case .notApplicable, .connected: false
    }
  }

  private func updateDescription(_ checkedAt: Date) -> String {
    Date().timeIntervalSince(checkedAt) < 60
      ? "Updated just now"
      : "Updated at \(checkedAt.formatted(date: .omitted, time: .shortened))"
  }

  private func sourceSummary(_ group: RouteGroupStatus) -> String {
    let sources = Set(group.targets.flatMap(\.sources).filter { $0 != "fixed address" }).sorted()
    return sources.isEmpty ? "Fixed addresses" : sources.joined(separator: ", ")
  }

  private func routeProblem(_ target: RouteTargetStatus) -> String {
    let observed = [target.observedGateway, target.observedInterface]
      .compactMap { $0 }
      .joined(separator: " · ")
    return observed.isEmpty
      ? "\(target.address) · route missing" : "\(target.address) · \(observed)"
  }

  private func daemonDescription(_ daemon: DaemonRuntimeStatus) -> String {
    guard daemon.installed else { return "Not installed" }
    guard daemon.loaded else { return "Installed, not loaded" }
    if let exitCode = daemon.lastExitCode, exitCode != 0 {
      return "Last run failed (\(exitCode))"
    }
    let interval = daemon.intervalSeconds.map { "every \($0) s" } ?? "loaded"
    let runs = daemon.runs.map { " · \($0) runs" } ?? ""
    return "OK · \(interval)\(runs)"
  }

  private func daemonColor(_ daemon: DaemonRuntimeStatus) -> Color {
    daemon.installed && daemon.loaded && daemon.lastExitCode == 0 ? .green : .orange
  }

  private var bundledDaemonDescription: String {
    if isUnknownDaemonInstallation {
      return "Blocked by unknown service"
    }
    if isLegacyDaemonInstallation {
      return "Migration required"
    }

    return switch model.bundledDaemonStatus {
    case .checking: "Checking…"
    case .notRegistered: "Not enabled"
    case .enabled:
      switch model.bundledDaemonConnectionStatus {
      case .connected(let helperVersion): "Connected · v\(helperVersion)"
      case .versionMismatch: "Version mismatch"
      case .unavailable: "Enabled, not responding"
      case .notApplicable: "Enabled"
      }
    case .requiresApproval: "Approval required"
    case .notFound: "Not included"
    case .unknown: "Status unavailable"
    }
  }

  private func bundledDaemonGuidance(for daemon: DaemonRuntimeStatus) -> String? {
    if isUnknownDaemonInstallation {
      return "Built-in setup is blocked because the installed service could not be recognized."
    }
    if isLegacyDaemonInstallation {
      return
        "The legacy service remains active. Built-in setup is blocked until it can be migrated safely."
    }

    return switch model.bundledDaemonStatus {
    case .notRegistered:
      daemon.installed
        ? "The current daemon remains active; built-in setup has not been enabled."
        : nil
    case .requiresApproval:
      "macOS is waiting for approval in Login Items."
    case .notFound:
      "This build does not include the bundled routing service."
    case .unknown:
      "The built-in service state could not be read."
    case .enabled:
      switch model.bundledDaemonConnectionStatus {
      case .versionMismatch(let appVersion, let helperVersion):
        "The app is v\(appVersion), but the built-in service is v\(helperVersion). No changes will be applied until they match."
      case .unavailable:
        "macOS reports the built-in service as enabled, but RouteBar could not reach it."
      case .notApplicable, .connected:
        nil
      }
    case .checking:
      nil
    }
  }

  private var bundledDaemonColor: Color {
    if isUnknownDaemonInstallation {
      return .red
    }
    if isLegacyDaemonInstallation {
      return .orange
    }

    return switch model.bundledDaemonStatus {
    case .enabled:
      switch model.bundledDaemonConnectionStatus {
      case .connected: .green
      case .versionMismatch: .orange
      case .unavailable: .red
      case .notApplicable: .secondary
      }
    case .notRegistered, .requiresApproval: .orange
    case .checking, .notFound, .unknown: .secondary
    }
  }

  private func shouldShowFirstRunGuidance(for daemon: DaemonRuntimeStatus) -> Bool {
    if isLegacyDaemonInstallation || isUnknownDaemonInstallation {
      return true
    }
    if model.bundledDaemonStatus == .enabled {
      switch model.bundledDaemonConnectionStatus {
      case .versionMismatch, .unavailable:
        return true
      case .notApplicable, .connected:
        return false
      }
    }
    guard !daemon.installed else { return false }
    return model.bundledDaemonStatus == .notRegistered
      || model.bundledDaemonStatus == .requiresApproval
  }

  private var firstRunTitle: String {
    if isUnknownDaemonInstallation {
      return "Unrecognized daemon installation"
    }
    if isLegacyDaemonInstallation {
      return "Legacy service is still active"
    }
    if case .selectingProfile = model.state {
      return "Choose a routing profile"
    }
    if model.bundledDaemonStatus == .enabled {
      switch model.bundledDaemonConnectionStatus {
      case .versionMismatch:
        return "Built-in service version mismatch"
      case .unavailable:
        return "Built-in service is not responding"
      case .notApplicable, .connected:
        break
      }
    }
    return model.bundledDaemonStatus == .requiresApproval
      ? "Automatic routing needs approval" : "Automatic routing is not enabled"
  }

  private var firstRunDetail: String {
    if isUnknownDaemonInstallation {
      return
        "RouteBar cannot safely distinguish the installed service. Built-in setup is blocked and nothing has been changed."
    }
    if isLegacyDaemonInstallation {
      return
        "Your current automatic routing keeps running. RouteBar will not enable the built-in service until a safe migration is explicitly started."
    }
    if case .selectingProfile = model.state {
      return
        "The configuration is valid. Your selection stays in this app and only builds a read-only plan."
    }
    if model.bundledDaemonStatus == .enabled {
      switch model.bundledDaemonConnectionStatus {
      case .versionMismatch(let appVersion, let helperVersion):
        return
          "The app is v\(appVersion), but the built-in service is v\(helperVersion). RouteBar will not apply changes until they match."
      case .unavailable:
        return
          "macOS reports the service as enabled, but RouteBar could not reach it. No changes were applied."
      case .notApplicable, .connected:
        break
      }
    }
    if model.bundledDaemonStatus == .requiresApproval {
      return
        "Approve RouteBar in System Settings > General > Login Items before setup can continue."
    }
    return
      "The configuration and route plan are available. Enabling the built-in service will require administrator approval."
  }

  private var preflightSymbol: String {
    if isUnknownDaemonInstallation {
      return "exclamationmark.octagon"
    }
    if isLegacyDaemonInstallation {
      return "arrow.triangle.2.circlepath"
    }
    return "gearshape"
  }

  private var preflightColor: Color {
    isUnknownDaemonInstallation ? .red : bundledDaemonColor
  }

  private var isLegacyDaemonInstallation: Bool {
    if case .legacy = model.installedDaemon {
      return true
    }
    return false
  }

  private var isUnknownDaemonInstallation: Bool {
    model.installedDaemon == .unknown
  }
}
