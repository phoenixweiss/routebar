import RouteBarCore
import SwiftUI

struct RulesEditorView: View {
  @StateObject var model: RulesEditorModel
  var serviceNote: String
  var onSaved: () async -> String
  var registerCloseRequest: (((() -> Void)?) -> Void)? = nil
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var confirmingDelete = false
  @State private var applicationFeedback: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        RouteBarBrandMark().frame(width: 36, height: 36).accessibilityHidden(true)
        Text("Rules").font(.custom("Manrope", fixedSize: 22).weight(.semibold))
          .foregroundStyle(brandInk)
        Spacer()
      }.padding(.horizontal, 30).padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
      Divider()
      HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 12) {
          Text("GROUPS").font(.custom("Manrope", size: 12).weight(.semibold))
            .tracking(0.8).foregroundStyle(.secondary)
          ScrollView {
            VStack(alignment: .leading, spacing: 6) {
              ForEach(model.groups, id: \.id) { group in
                Button {
                  transition(.group(group.id))
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(group.name).fontWeight(.semibold).foregroundStyle(.primary)
                    Text(
                      group.mode == .bypassVPN ? "\(group.domains.count) domains" : "Checks only"
                    )
                    .font(.custom("Manrope", size: 12)).foregroundStyle(.secondary)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.vertical, 12).padding(.horizontal, 12)
                  .background(model.selectedID == group.id ? brandInk.opacity(0.12) : .clear)
                  .clipShape(RoundedRectangle(cornerRadius: 8))
                  .overlay(alignment: .leading) {
                    if model.selectedID == group.id {
                      RoundedRectangle(cornerRadius: 2).fill(brandInk)
                        .frame(width: 3).padding(.vertical, 12)
                    }
                  }
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
              }
            }
          }
          Button {
            transition(.newGroup)
          } label: {
            Label("New Group", systemImage: "plus")
          }
          .disabled(model.document == nil || model.isBusy)
          .buttonStyle(RouteBarButtonStyle())
        }
        .padding(16).frame(width: 200)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        Divider()
        ScrollView {
          editor.padding(20).frame(maxWidth: .infinity, alignment: .topLeading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .frame(minHeight: 200)
      Divider()
      VStack(alignment: .leading, spacing: 12) {
        if let message = model.message, model.hasError || !model.hasChanges {
          Label(message, systemImage: model.hasError ? "exclamationmark.triangle" : "doc")
            .font(.custom("Manrope", size: 13))
            .foregroundStyle(model.hasError ? Color.red : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if model.needsReload && model.document != nil { recoveryButton }
        Text(
          model.hasChanges
            ? "Unsaved changes"
            : (applicationFeedback ?? serviceNote)
        )
        .font(.custom("Manrope", size: 13)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
          Button(model.isNewGroup ? "Cancel" : "Close") { transition(.close) }
            .keyboardShortcut(.cancelAction)
            .disabled(model.isBusy)
            .buttonStyle(RouteBarButtonStyle())
          Spacer()
          if model.hasChanges || model.isSaving {
            Button(
              model.isSaving ? "Saving…" : (model.isNewGroup ? "Create Group" : "Save Changes")
            ) {
              Task { if await model.save() { reportSaved() } }
            }
            .buttonStyle(RouteBarButtonStyle(prominent: true))
            .disabled(!model.isEditable || model.isBusy)
          }
        }
      }.padding(.horizontal, 30).padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    .controlSize(.large)
    .font(.custom("Manrope", fixedSize: 15.5))
    .background(Color(nsColor: .textBackgroundColor))
    .tint(brandInk)
    .frame(minWidth: 720, idealWidth: 820, maxWidth: 1000, minHeight: 570, idealHeight: 640)
    .task { if model.document == nil { await model.load() } }
    .onAppear {
      registerCloseRequest?({ transition(.close) })
    }
    .onDisappear { registerCloseRequest?(nil) }
    .interactiveDismissDisabled(model.hasChanges || model.isBusy)
    .alert("Delete this group?", isPresented: $confirmingDelete) {
      Button("Cancel", role: .cancel) {}
      Button("Delete Group", role: .destructive) {
        Task {
          if await model.save(deleting: true) { reportSaved() }
        }
      }
    } message: {
      Text(
        "This removes the whole group, including its fixed addresses and checks, and removes its profile memberships. Enabled automation may remove its owned routes."
      )
    }
    .alert(
      "Unsaved changes",
      isPresented: Binding(get: { model.pendingTransition != nil }, set: { _ in })
    ) {
      Button(model.isNewGroup ? "Create and Continue" : "Save and Continue") {
        resolve(.save)
      }
      Button("Discard and Continue", role: .destructive) { resolve(.discard) }
      Button("Stay in Editor", role: .cancel) { resolve(.stay) }
    } message: {
      Text("Save this group before continuing, discard its changes, or keep editing.")
    }
  }

  private func transition(_ target: RulesEditorModel.Transition) {
    Task { if await model.requestTransition(target) { dismiss() } }
  }

  private func resolve(_ choice: RulesEditorModel.TransitionChoice) {
    Task {
      let generation = model.saveGeneration
      let close = await model.resolveTransition(choice)
      if model.saveGeneration != generation { reportSaved() }
      if close { dismiss() }
    }
  }

  private func reportSaved() {
    let generation = model.saveGeneration
    applicationFeedback = "File saved. Waiting for service confirmation."
    // An explicit task survives closing the editor after Save and Continue.
    Task {
      let feedback = await onSaved()
      if model.saveGeneration == generation { applicationFeedback = feedback }
    }
  }

  private var brandInk: Color {
    colorScheme == .dark
      ? Color(red: 0.72, green: 0.88, blue: 0.92)
      : Color(red: 0.09, green: 0.25, blue: 0.30)
  }

  @ViewBuilder private var editor: some View {
    if model.isBusy && model.document == nil {
      ProgressView("Loading rules…")
    } else if model.selectedID == nil {
      VStack(alignment: .leading, spacing: 12) {
        Text("Rules could not be loaded. Correct invalid YAML using Open Config, then reload.")
          .foregroundStyle(.secondary)
        recoveryButton
      }
    } else if !model.isEditable {
      VStack(alignment: .leading, spacing: 12) {
        Text(model.name).font(.title2)
        Text(
          "This group contains connectivity checks, not bypass domains. Its settings are preserved; use Open Config to edit them."
        )
        .foregroundStyle(.secondary)
      }
    } else {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(model.selectedGroup == nil ? "New group" : "Edit group")
            .font(.custom("Manrope", fixedSize: 15.5).weight(.semibold))
          Spacer()
          Button("Delete Group…", role: .destructive) { confirmingDelete = true }
            .buttonStyle(RouteBarButtonStyle(destructive: true))
            .disabled(model.selectedGroup == nil || model.hasChanges || model.isBusy)
        }
        VStack(alignment: .leading, spacing: 6) {
          Text("Group name").font(.custom("Manrope", size: 12).weight(.medium))
            .foregroundStyle(.secondary)
          TextField("Group name", text: $model.name).textFieldStyle(.roundedBorder)
            .frame(minHeight: 32)
        }
        HStack {
          Text("Domains").font(.custom("Manrope", fixedSize: 15.5).weight(.semibold))
          Text("\(model.domains.count)").font(.custom("Manrope", size: 12))
            .foregroundStyle(.secondary)
        }.padding(.top, 4)
        HStack(spacing: 8) {
          TextField("Domain or website URL", text: $model.domainInput)
            .textFieldStyle(.roundedBorder).frame(minHeight: 32)
            .onSubmit { model.addDomain() }
          Button(model.editingDomain == nil ? "Add" : "Update") { model.addDomain() }
            .buttonStyle(RouteBarButtonStyle())
            .disabled(model.domainInput.isEmpty)
          if model.editingDomain != nil {
            Button("Cancel") { model.cancelDomainEdit() }
              .buttonStyle(RouteBarButtonStyle())
          }
        }
        if let error = model.domainError {
          Label(error, systemImage: "exclamationmark.triangle")
            .font(.custom("Manrope", size: 13)).foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text("URLs become exact hostnames. Subdomains and separate CDNs need their own entries.")
          .font(.custom("Manrope", size: 12)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            if model.domains.isEmpty {
              Text("No domains yet").foregroundStyle(.secondary).padding(12)
            }
            ForEach(model.domains, id: \.self) { host in
              HStack(alignment: .center, spacing: 8) {
                Text(host).font(.system(size: 13.5, design: .monospaced))
                  .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                  model.editDomain(host)
                } label: {
                  Image(systemName: "pencil").frame(width: 18, height: 18)
                }
                .buttonStyle(RouteBarButtonStyle(compact: true))
                .disabled(!model.domainInput.isEmpty)
                .help("Edit \(host)").accessibilityLabel("Edit \(host)")
                Button {
                  model.removeDomain(host)
                } label: {
                  Image(systemName: "minus").frame(width: 18, height: 18)
                }.buttonStyle(RouteBarButtonStyle(destructive: true, compact: true))
                  .help("Remove \(host)").accessibilityLabel("Remove \(host)")
              }
              .padding(.vertical, 6).padding(.horizontal, 8)
              .background(model.editingDomain == host ? brandInk.opacity(0.08) : .clear)
              Divider().opacity(0.5)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(height: min(220, max(80, CGFloat(model.domains.count) * 43)))
          .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.10)))
        Text("Used in profiles").font(.custom("Manrope", fixedSize: 15.5).weight(.semibold))
          .padding(.top, 4)
        ForEach(model.profiles, id: \.id) { profile in
          Toggle(
            profile.name,
            isOn: Binding(
              get: { model.profileIDs.contains(profile.id) },
              set: { enabled in
                if enabled {
                  model.profileIDs.insert(profile.id)
                } else {
                  model.profileIDs.remove(profile.id)
                }
              })
          ).toggleStyle(.checkbox)
        }
        if let group = model.selectedGroup, !group.addresses.isEmpty || !group.checks.isEmpty {
          Text(
            "\(group.addresses.count) fixed addresses and \(group.checks.count) HTTPS checks are preserved unchanged."
          )
          .font(.custom("Manrope", size: 12)).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
      }.disabled(model.isBusy)
    }
  }

  private var recoveryButton: some View {
    Button("Reload File…") { transition(.reload) }
      .buttonStyle(RouteBarButtonStyle())
      .disabled(model.isBusy)
  }
}
