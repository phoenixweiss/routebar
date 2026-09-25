import Foundation

public enum SwiftBarFormatter {
  private static let visibleTargetsPerGroup = 8

  public static func success(_ plan: RoutePlan, configURL: URL) -> String {
    let routeCount = plan.routeGroups.reduce(0) { $0 + $1.targets.count }
    var lines = [
      "RouteBar · \(routeCount) | sfimage=network",
      "---",
      "Read-only preview | sfimage=eye",
      menuLine(
        "Profile: \(plan.profile.name)" + (plan.profileWasForced ? " (manual)" : ""),
        parameters: "sfimage=person.crop.circle"
      ),
      menuLine("Wi-Fi: \(plan.network.ssid ?? "unavailable")", parameters: "sfimage=wifi"),
      menuLine(
        "Gateway: \(plan.network.physicalGateway) via \(plan.network.physicalInterface)",
        parameters: "sfimage=arrow.triangle.branch"
      ),
      menuLine(
        "VPN: \(plan.network.vpnInterfaces.isEmpty ? "not detected" : plan.network.vpnInterfaces.joined(separator: ", "))",
        parameters: "sfimage=lock.shield"
      ),
      "---",
      "Planned host routes | badge=\(routeCount) sfimage=point.3.connected.trianglepath.dotted",
    ]

    if plan.routeGroups.isEmpty {
      lines.append("--None")
    } else {
      for group in plan.routeGroups {
        lines.append(menuLine("--\(group.name)", parameters: "badge=\(group.targets.count)"))
        for target in group.targets.prefix(visibleTargetsPerGroup) {
          lines.append(
            menuLine(
              "----\(target.address)/32  ←  \(target.sources.joined(separator: ", "))",
              parameters: "font=Menlo size=11"
            )
          )
        }
        let hiddenCount = group.targets.count - visibleTargetsPerGroup
        if hiddenCount > 0 {
          lines.append("----\(hiddenCount) more…")
        }
      }
    }

    if !plan.checkOnlyGroups.isEmpty {
      lines.append("---")
      lines.append("Connectivity checks | sfimage=waveform.path.ecg")
      for group in plan.checkOnlyGroups {
        lines.append(menuLine("--\(group.name)", parameters: "badge=\(group.endpoints.count)"))
      }
    }

    lines.append(contentsOf: [
      "---",
      "Refresh | refresh=true sfimage=arrow.clockwise",
      "Open configuration | href=\(configURL.absoluteURL.absoluteString) sfimage=doc.text",
    ])
    return lines.joined(separator: "\n")
  }

  public static func failure(_ message: String, configURL: URL) -> String {
    [
      "RouteBar ! | sfimage=exclamationmark.triangle",
      "---",
      "Read-only preview unavailable | sfimage=exclamationmark.triangle",
      menuLine(message, parameters: "length=100"),
      "---",
      "Refresh | refresh=true sfimage=arrow.clockwise",
      "Open configuration | href=\(configURL.absoluteURL.absoluteString) sfimage=doc.text",
    ].joined(separator: "\n")
  }

  private static func menuLine(_ title: String, parameters: String? = nil) -> String {
    let safeTitle =
      title
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "|", with: "¦")
    guard let parameters else { return safeTitle }
    return "\(safeTitle) | \(parameters)"
  }
}
