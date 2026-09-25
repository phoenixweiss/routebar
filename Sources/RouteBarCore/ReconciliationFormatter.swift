import Foundation

public enum ReconciliationFormatter {
  public static func text(_ result: ReconciliationResult, applied: Bool) -> String {
    var lines = [
      applied ? "RECONCILIATION APPLIED" : "READ-ONLY RECONCILIATION PLAN",
      "Unchanged: \(result.plan.unchangedCount)",
      "Actions: \(result.plan.actions.count)",
      "Conflicts: \(result.plan.conflicts.count)",
    ]

    for action in result.plan.actions {
      switch action.kind {
      case .add:
        lines.append("  + \(action.address)/32 via \(action.newGateway ?? "unknown")")
      case .replace:
        lines.append(
          "  ~ \(action.address)/32: \(action.oldGateway ?? "unknown") -> "
            + "\(action.newGateway ?? "unknown")"
        )
      case .remove:
        lines.append("  - \(action.address)/32 via \(action.oldGateway ?? "unknown")")
      case .forgetMissing:
        lines.append("  · forget missing \(action.address)/32")
      }
    }
    for conflict in result.plan.conflicts {
      lines.append("  ! \(conflict.address): \(conflict.reason)")
    }
    return lines.joined(separator: "\n")
  }

  public static func adoption(_ result: AdoptionResult) -> String {
    var lines = [
      "EXISTING ROUTE ADOPTION",
      "Adopted: \(result.adopted.count)",
      "Conflicts: \(result.conflicts.count)",
    ]
    for conflict in result.conflicts {
      lines.append("  ! \(conflict.address): \(conflict.reason)")
    }
    return lines.joined(separator: "\n")
  }
}
