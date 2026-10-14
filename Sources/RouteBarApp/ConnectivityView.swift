import SwiftUI

struct ConnectivityView: View {
  @ObservedObject var model: ConnectivityModel
  var check: () -> Void
  var canCheck = true

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("CONNECTIVITY")
          .font(.custom("Manrope", fixedSize: 11.5).weight(.semibold))
          .foregroundStyle(.secondary)
          .tracking(0.8)
        Spacer()
        Button(model.isChecking ? "Checking…" : "Check") { check() }
          .buttonStyle(RouteBarButtonStyle())
          .controlSize(.large)
          .disabled(
            !canCheck || model.isChecking || model.configurationUnavailable || model.jobs.isEmpty
          )
          .help("Check configured services through the current system routes")
      }

      Text("Manual checks through current routes. No routing changes or sign-in.")
        .font(.custom("Manrope", fixedSize: 13.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if model.configurationUnavailable {
        Text("Checks unavailable. Refresh to load a valid configuration and profile.")
          .font(.custom("Manrope", fixedSize: 13.5))
          .foregroundStyle(.secondary)
      } else if model.jobs.isEmpty {
        Text("No connectivity checks are configured for this profile.")
          .font(.custom("Manrope", fixedSize: 14.5))
          .foregroundStyle(.secondary)
      } else {
        ForEach(Array(model.jobs.enumerated()), id: \.element.id) { index, job in
          if index == 0 || model.jobs[index - 1].groupName != job.groupName {
            Text(job.groupName)
              .font(.custom("Manrope", fixedSize: 15.5).weight(.semibold))
              .padding(.top, index == 0 ? 2 : 10)
          }
          checkRow(job)
          if index < model.jobs.count - 1 { Divider().opacity(0.62) }
        }
      }

      if model.isStale {
        Label("Results are out of date. Run checks again.", systemImage: "clock")
          .font(.custom("Manrope", fixedSize: 13.5))
          .foregroundStyle(.secondary)
      } else if let checkedAt = model.checkedAt {
        Text("Checked at \(checkedAt.formatted(date: .omitted, time: .standard)) · manual snapshot")
          .font(.custom("Manrope", fixedSize: 12.5))
          .foregroundStyle(.secondary)
      }
    }
  }

  private func checkRow(_ job: ConnectivityJob) -> some View {
    let result = model.results[job.id]
    let checking = model.isChecking && model.currentJobID == job.id
    return VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(job.target.title)
          .font(.custom("Manrope", fixedSize: 14.5).weight(.medium))
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 6)
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Image(
            systemName: checking
              ? "hourglass"
              : result == nil || model.isStale
                ? "minus.circle"
                : result?.isSuccessful == true ? "checkmark.circle" : "exclamationmark.circle"
          )
          .foregroundStyle(
            model.isStale || result == nil
              ? Color.secondary : result?.isSuccessful == true ? .green : .orange
          )
          .accessibilityHidden(true)
          Text(
            checking
              ? "Checking…" : result?.summary ?? (model.isChecking ? "Waiting" : "Not checked")
          )
          .foregroundStyle(model.isStale || result == nil ? Color.secondary : Color.primary)
        }
        .font(.custom("Manrope", fixedSize: 13.5))
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)
      }
      Text(job.target.detail)
        .font(.custom("Manrope", fixedSize: 12.5))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 3)
  }
}
