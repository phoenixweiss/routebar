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

    case .ready(let snapshot, _):
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
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
        VStack(alignment: .leading, spacing: 20) {
          sectionTitle("STATUS")
          Text(failure.message)
            .font(routeBarFont(15.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          sectionDivider
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
    case .ready(let snapshot, _): isHealthy(snapshot) ? "checkmark" : "exclamationmark"
    case .failed: "xmark"
    }
  }

  private var statusColor: Color {
    switch model.state {
    case .loading: .secondary
    case .ready(let snapshot, _): isHealthy(snapshot) ? .green : .orange
    case .failed: .red
    }
  }

  private var statusTitle: String {
    switch model.state {
    case .loading: "Checking RouteBar"
    case .ready(let snapshot, _): isHealthy(snapshot) ? "Routes are active" : "Needs attention"
    case .failed: "Status unavailable"
    }
  }

  private var statusSummary: String {
    switch model.state {
    case .loading:
      return "Reading the current gateway and explicit routes"
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
}
