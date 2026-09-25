import RouteBarCore
import SwiftUI

struct RouteBarStatusView: View {
  @ObservedObject var model: RouteBarAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      content
      Divider()
      footer
    }
    .frame(minWidth: 380, idealWidth: 460, minHeight: 420, idealHeight: 560)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  @ViewBuilder
  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: statusSymbol)
        .font(.system(size: 26, weight: .semibold))
        .foregroundStyle(statusColor)
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(statusTitle)
          .font(.title3.weight(.semibold))
        Text(statusSummary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 12)

      Button {
        Task { await model.refresh() }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
      }
      .disabled(model.isRefreshing)
      .keyboardShortcut("r", modifiers: .command)
      .help("Refresh status")
    }
    .padding(20)
  }

  @ViewBuilder
  private var content: some View {
    switch model.state {
    case .loading:
      HStack(spacing: 10) {
        ProgressView()
          .controlSize(.small)
        Text("Reading network and route status…")
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(20)

    case .ready(let snapshot, _):
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          networkSection(snapshot)
          routesSection(snapshot)
          daemonSection(snapshot.daemon, checkedAt: snapshot.checkedAt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
      }

    case .failed(let failure):
      VStack(alignment: .leading, spacing: 16) {
        sectionTitle("STATUS")
        Text(failure.message)
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        daemonSection(failure.daemon, checkedAt: failure.checkedAt)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .padding(20)
    }
  }

  private func networkSection(_ snapshot: RouteStatusSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle("NETWORK")
      detailRow("Profile", value: snapshot.profile.name, symbol: "person.crop.circle")
      detailRow(
        "Gateway",
        value: "\(snapshot.network.physicalGateway) · \(snapshot.network.physicalInterface)",
        symbol: "arrow.triangle.branch"
      )
      detailRow(
        "VPN",
        value: snapshot.network.vpnInterfaces.isEmpty
          ? "Not detected"
          : snapshot.network.vpnInterfaces.joined(separator: ", "),
        symbol: "lock.shield"
      )
    }
  }

  @ViewBuilder
  private func routesSection(_ snapshot: RouteStatusSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        sectionTitle("ROUTES")
        Spacer()
        Text("\(snapshot.activeCount) of \(snapshot.routeCount) active")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if snapshot.groups.isEmpty {
        Text("No bypass routes are configured for this profile.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        ForEach(snapshot.groups) { group in
          VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
              Image(
                systemName: group.activeCount == group.targets.count
                  ? "checkmark.circle.fill"
                  : "exclamationmark.circle.fill"
              )
              .foregroundStyle(
                group.activeCount == group.targets.count ? Color.green : Color.orange
              )
              .accessibilityHidden(true)

              Text(group.name)
                .font(.subheadline.weight(.medium))
              Spacer()
              Text("\(group.activeCount)/\(group.targets.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Text(sourceSummary(group))
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.leading, 24)

            ForEach(group.targets.filter { !$0.isActive }.prefix(3)) { target in
              Text(routeProblem(target))
                .font(.caption.monospaced())
                .foregroundStyle(.orange)
                .padding(.leading, 24)
                .lineLimit(1)
            }
          }
        }
      }
    }
  }

  private func daemonSection(_ daemon: DaemonRuntimeStatus, checkedAt: Date) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle("AUTOMATION")
      detailRow("Daemon", value: daemonDescription(daemon), symbol: daemonSymbol(daemon))
      detailRow(
        "Checked",
        value: checkedAt.formatted(date: .omitted, time: .standard),
        symbol: "clock"
      )
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Button("Open Config") {
          model.openConfiguration()
        }

        Button("Reveal in Finder") {
          model.revealConfiguration()
        }

        Spacer()
      }

      Toggle("Show RouteBar in Dock", isOn: $model.showInDock)
        .toggleStyle(.checkbox)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  private var statusSymbol: String {
    switch model.state {
    case .loading: "arrow.triangle.2.circlepath"
    case .ready(let snapshot, _):
      isHealthy(snapshot) ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
    case .failed: "xmark.octagon.fill"
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

  private func isHealthy(_ snapshot: RouteStatusSnapshot) -> Bool {
    snapshot.allRoutesActive
      && snapshot.daemon.installed
      && snapshot.daemon.loaded
      && snapshot.daemon.lastExitCode == 0
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.caption2.weight(.semibold))
      .foregroundStyle(.secondary)
      .tracking(0.6)
  }

  private func detailRow(_ title: String, value: String, symbol: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: symbol)
        .frame(width: 16)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text(title)
        .font(.subheadline)
      Spacer(minLength: 10)
      Text(value)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
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

  private func daemonSymbol(_ daemon: DaemonRuntimeStatus) -> String {
    daemon.installed && daemon.loaded && daemon.lastExitCode == 0
      ? "checkmark.circle"
      : "exclamationmark.circle"
  }
}
