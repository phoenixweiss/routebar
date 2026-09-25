import RouteBarCore
import SwiftUI

struct RouteBarMenuView: View {
  @ObservedObject var model: RouteBarAppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      actions
    }
    .frame(width: 360)
    .background(.regularMaterial)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: statusSymbol)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(statusColor)
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text(statusTitle)
          .font(.headline)
        Text(statusSummary)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Button {
        Task { await model.refresh() }
      } label: {
        Image(systemName: "arrow.clockwise")
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .disabled(model.isRefreshing)
      .accessibilityLabel("Refresh status")
      .help("Refresh status")
    }
    .padding(16)
  }

  private var actions: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Button("Open Window") {
          model.showStatusWindow()
        }
        .keyboardShortcut("o", modifiers: .command)

        Toggle("Show in Dock", isOn: $model.showInDock)
          .toggleStyle(.checkbox)

        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      Divider()

      HStack(spacing: 14) {
        Button("Open Config") {
          model.openConfiguration()
        }
        .buttonStyle(.plain)

        Button("Show in Finder") {
          model.revealConfiguration()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)

        Spacer()

        Button("Quit") {
          model.quit()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
      }
      .font(.subheadline)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
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
}
