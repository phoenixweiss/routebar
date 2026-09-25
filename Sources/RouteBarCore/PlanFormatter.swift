import Foundation

public enum PlanFormatter {
  public static func text(_ plan: RoutePlan) -> String {
    var lines = [
      "READ-ONLY PLAN — no routes were changed",
      "Profile: \(plan.profile.name) (\(plan.profile.id))"
        + (plan.profileWasForced ? " [manual override]" : ""),
      "Wi-Fi: \(plan.network.ssid ?? "unavailable")",
      "Physical gateway: \(plan.network.physicalGateway) via \(plan.network.physicalInterface)",
      "VPN default: "
        + (plan.network.vpnInterfaces.isEmpty
          ? "not detected"
          : plan.network.vpnInterfaces.joined(separator: ", ")),
    ]

    if plan.routeGroups.isEmpty {
      lines.append("Routes: none")
    } else {
      lines.append("Routes:")
      for group in plan.routeGroups {
        lines.append("  \(group.name) (\(group.id))")
        for target in group.targets {
          lines.append(
            "    + \(target.address)/32 via \(plan.network.physicalGateway) "
              + "dev \(plan.network.physicalInterface) [\(target.sources.joined(separator: ", "))]"
          )
        }
      }
    }

    if !plan.checkOnlyGroups.isEmpty {
      lines.append("Checks only (no routes):")
      for group in plan.checkOnlyGroups {
        lines.append("  \(group.name) (\(group.id)): \(group.endpoints.count) endpoint(s)")
      }
    }

    return lines.joined(separator: "\n")
  }
}
