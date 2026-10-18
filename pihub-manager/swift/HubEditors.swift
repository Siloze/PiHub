import AppKit
import SwiftUI

struct InstanceEditor: View {
  @ObservedObject var store: HubStore
  let original: HubInstance
  @Environment(\.dismiss) private var dismiss
  @State private var item: HubInstance
  @State private var group = ""
  @State private var confirmDelete = false
  @State private var confirmCautiousRestart = false
  @State private var cautiousRestartIsExternal = false
  @State private var onboarding: IntegrationOnboarding?
  @State private var toolToAdd = ""
  @State private var editManifest = false
  private var isLastAdapterInstance: Bool {
    ((store.snapshot?.config.providers ?? []) + (store.snapshot?.config.agents ?? []))
      .filter { $0.adapter == item.adapter }.count <= 1
  }
  private var hasManagedRuntime: Bool {
    let catalogID =
      store.snapshot?.catalog.entries.first { $0.adapter == item.adapter }?.id ?? item.adapter
    return store.snapshot?.catalog.installed[catalogID] != nil
  }
  init(store: HubStore, original: HubInstance) {
    self.store = store
    self.original = original
    _item = State(initialValue: original)
  }
  private var adapter: HubAdapter? { store.adapter(item) }
  private var groups: [String] {
    var groups = [String]()
    for f in adapter?.fields ?? [] where !groups.contains(f.group) { groups.append(f.group) }
    return groups + ["Intégration", "Diagnostic"]
  }
  private var exists: Bool {
    ((store.snapshot?.config.providers ?? []) + (store.snapshot?.config.agents ?? [])).contains {
      $0.id == item.id
    }
  }
  private var hasCustomExecutable: Bool {
    !(item.settings["executable"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  private var compatibleModels: [HubModel] {
    let provider = store.snapshot?.config.providers.first {
      $0.id == item.settings[adapter?.routing?.provider_field ?? "provider"]
    }
    let format =
      adapter?.kind == "provider"
      ? adapter?.model_format : provider.flatMap { store.adapter($0)?.model_format }
    return (store.snapshot?.models ?? []).filter {
      format == nil || format == "any" || $0.format == format
    }
  }
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        AdapterMark(adapter: adapter)
        VStack(alignment: .leading, spacing: 4) {
          TextField("Nom de l’instance", text: $item.name).font(
            .system(size: 21, weight: .semibold)
          ).textFieldStyle(.plain)
          Text(adapter?.description ?? item.adapter).font(.system(size: 11)).foregroundStyle(
            HubStyle.muted)
        }
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(
            HubStyle.muted)
        }.buttonStyle(.plain)
      }.padding(24)
      Divider()
      HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(groups, id: \.self) { name in
            Button {
              group = name
            } label: {
              HStack {
                Text(name)
                Spacer()
              }.font(.system(size: 12)).padding(11).background(
                group == name ? HubStyle.accent.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9))
            }.buttonStyle(.plain)
          }
          Spacer()
          Text(item.id).font(.system(size: 8, design: .monospaced)).foregroundStyle(HubStyle.muted)
        }.padding(14).frame(width: 155)
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 21) {
            if group == "Diagnostic" {
              diagnostics
            } else if group == "Intégration" {
              Eyebrow(title: "Identité & lancement")
              Text(
                "Personnalisez l’icône, la couleur, les exécutables, la commande et les handlers de ce type d’intégration."
              ).font(.system(size: 13))
              Text(
                "Cette définition est partagée par toutes les instances de \(adapter?.name ?? item.adapter). Les réglages de cette instance restent indépendants et sont enregistrés dans config.json."
              ).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
              Button("Personnaliser l’intégration…") { editManifest = true }.buttonStyle(
                .borderedProminent)
              Text(adapter?.source ?? "").font(.system(size: 10, design: .monospaced))
                .foregroundStyle(HubStyle.muted).textSelection(.enabled)
            } else {
              Text(group.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.5)
                .foregroundStyle(HubStyle.muted)
              ForEach((adapter?.fields ?? []).filter { $0.group == group }) { field in
                fieldView(field)
              }
              if let hint = adapter?.editor_hints?[group] {
                Label(hint, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(
                  HubStyle.muted)
              }
              if group == "Avancé" {
                Text(
                  "Arguments : liste JSON, par exemple [\"--seed\", \"42\"]. Ils sont passés directement au processus, sans shell. Ne répétez pas les options déjà configurées."
                ).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
              }
            }
          }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      Divider()
      if let error = store.error {
        Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled).frame(
          maxWidth: .infinity, alignment: .leading
        ).padding(12)
      }
      HStack {
        if exists {
          Button(role: .destructive) {
            confirmDelete = true
          } label: {
            Image(systemName: "trash")
          }
        }
        Text("Réglages appliqués au prochain lancement.").font(.system(size: 10)).foregroundStyle(
          HubStyle.muted)
        Spacer()
        Button("Annuler") { dismiss() }
        Button("Enregistrer") {
          let isNew = !exists
          store.perform("save", payload: ["item": HubBridge.object(item)]) { success in
            if success {
              if isNew, let guide = store.onboardingGuide {
                onboarding = guide
              } else {
                dismiss()
              }
            }
          }
        }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
      }.padding(20).disabled(store.busy)
    }.frame(width: 710, height: 610).background(HubStyle.background).preferredColorScheme(.dark)
      .tint(HubStyle.accent)
      .onAppear {
        if store.focusExecutableID == item.id {
          group = groups.contains("Avancé") ? "Avancé" : (groups.first ?? "Diagnostic")
          store.focusExecutableID = nil
        } else {
          group = groups.first ?? "Diagnostic"
        }
      }
      .sheet(isPresented: $editManifest) {
        if let adapter { ManifestEditor(store: store, adapter: adapter) }
      }
      .sheet(isPresented: $store.showingLog) {
        VStack(alignment: .leading, spacing: 15) {
          HStack {
            Text("Console PiHub").font(.headline)
            Spacer()
            Button("Copier") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(store.logText, forType: .string)
            }
            Button("Fermer") { store.showingLog = false }
          }
          ScrollView {
            Text(store.logText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }.padding(24).frame(width: 650, height: 450).preferredColorScheme(.dark)
      }
      .sheet(item: $onboarding) { guide in
        IntegrationOnboardingView(store: store, itemID: item.id, guide: guide)
      }
      .confirmationDialog(
        "Retirer \(item.name) ? Choisissez si vous souhaitez aussi retirer son JSON personnel ou le runtime PiHub.",
        isPresented: $confirmDelete
      ) {
        Button("Retirer l’instance seulement", role: .destructive) {
          store.perform("delete", id: item.id) { success in if success { dismiss() } }
        }
        if isLastAdapterInstance {
          Button("Retirer l’instance et le JSON personnel", role: .destructive) {
            store.perform("delete", id: item.id, payload: ["remove_manifest": true]) { success in
              if success { dismiss() }
            }
          }
          if hasManagedRuntime {
            Button("Retirer le JSON et le runtime PiHub", role: .destructive) {
              store.perform(
                "delete", id: item.id,
                payload: ["remove_manifest": true, "remove_runtime": true]
              ) { success in if success { dismiss() } }
            }
          }
        }
      }
      .alert("Tenter cette relance ?", isPresented: $confirmCautiousRestart) {
        Button("Relancer", role: .destructive) {
          store.perform("restart", id: item.id, payload: ["confirm_external": cautiousRestartIsExternal])
        }
        Button("Annuler", role: .cancel) {}
      } message: {
        Text(cautiousRestartIsExternal
             ? "PiHub va tenter de prendre en charge le processus détecté, l’arrêter, puis le relancer avec la commande configurée. Comme ce processus n’a pas été lancé par PiHub, la relance peut échouer. Un processus qui ne correspond pas à l’exécutable et au port configurés ne sera pas ciblé."
             : "PiHub va arrêter puis relancer cette instance avec son exécutable personnalisé. Cet exécutable peut ne pas respecter les arguments ou le comportement attendus ; la relance peut échouer.")
      }
  }
  private func setting(_ field: HubField) -> Binding<String> {
    Binding(
      get: { item.settings[field.key] ?? field.default }, set: { item.settings[field.key] = $0 })
  }
  @ViewBuilder private func fieldView(_ field: HubField) -> some View {
    let value = setting(field)
    VStack(alignment: .leading, spacing: 9) {
      if field.key == "executable" {
        Text(
          "Chemin de cette instance, sans arguments. Il a priorité sur les candidats du manifeste. La commande et ses arguments se règlent dans Intégration → Lancement."
        ).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
      }
      if field.type == "toggle" {
        Toggle(
          field.label,
          isOn: Binding(
            get: { value.wrappedValue == "true" },
            set: { value.wrappedValue = $0 ? "true" : "false" })
        ).toggleStyle(.switch).controlSize(.small)
      } else {
        Text(field.key == "executable" ? "Chemin de l’exécutable" : field.label)
          .font(.system(size: 12, weight: .medium))
        switch field.type {
        case "multi_select":
          multiSelectField(field, value: value)
        case "select":
          Picker(field.label, selection: value) {
            ForEach(field.options ?? [], id: \.self) { Text($0.capitalized).tag($0) }
          }.labelsHidden()
        case "provider":
          Picker(field.label, selection: value) {
            if let unbound = adapter?.routing?.unbound_value, !unbound.isEmpty {
              Text(adapter?.routing?.unbound_label ?? "Configuration native").tag(unbound)
            }
            Text("Choisir un moteur…").tag("")
            ForEach(store.snapshot?.config.providers ?? []) { Text($0.name).tag($0.id) }
          }.labelsHidden()
        case "slider":
          HStack {
            Slider(
              value: Binding(
                get: { Double(value.wrappedValue) ?? Double(field.default) ?? 0 },
                set: { value.wrappedValue = String(format: "%g", $0) }),
              in: (field.min ?? 0)...(field.max ?? 100), step: field.step ?? 1)
            TextField("", text: value).frame(width: 62).textFieldStyle(.roundedBorder).font(
              .system(size: 11, design: .monospaced))
          }
        case "model":
          TextField("Identifiant ou chemin", text: value).textFieldStyle(.roundedBorder).font(
            .system(size: 11, design: .monospaced))
          Menu("Choisir dans le catalogue") {
            ForEach(compatibleModels) { model in
              Button(model.name + " · " + model.format.uppercased()) {
                value.wrappedValue = model.path.isEmpty ? model.id : model.path
              }
            }
            if adapter?.kind == "provider", let runtime = store.runtime(item) {
              ForEach(runtime.models, id: \.self) { model in
                Button(model) { value.wrappedValue = model }
              }
            }
            if let id = item.settings[adapter?.routing?.provider_field ?? "provider"],
              let runtime = store.snapshot?.providers.first(where: { $0.id == id })
            {
              ForEach(runtime.models, id: \.self) { model in
                Button(model) { value.wrappedValue = model }
              }
            }
          }.font(.system(size: 11))
        case "file", "directory":
          HStack {
            TextField("Chemin local", text: value).textFieldStyle(.roundedBorder).font(
              .system(size: 11, design: .monospaced))
            Button {
              let panel = NSOpenPanel()
              panel.canChooseDirectories = field.type == "directory"
              panel.canChooseFiles = field.type == "file"
              if panel.runModal() == .OK, let url = panel.url { value.wrappedValue = url.path }
            } label: {
              Image(systemName: "folder")
            }
          }
        default:
          TextField(field.default, text: value).textFieldStyle(.roundedBorder).font(
            .system(size: 11, design: .monospaced))
        }
      }
    }
  }
  @ViewBuilder private func multiSelectField(_ field: HubField, value: Binding<String>) -> some View {
    let selected = Set(tokens(value.wrappedValue))
    VStack(alignment: .leading, spacing: 9) {
      Text(field.label).font(.system(size: 12, weight: .medium))
      Text("Choisissez les propositions utiles ou ajoutez un nom d’outil. La valeur est transmise à l’agent comme liste séparée par des virgules.")
        .font(.system(size: 10)).foregroundStyle(HubStyle.muted)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 7)], alignment: .leading, spacing: 7) {
        ForEach(field.options ?? [], id: \.self) { option in
          let enabled = selected.contains(option)
          Button {
            var updated = tokens(value.wrappedValue)
            if enabled {
              updated.removeAll { $0 == option }
            } else {
              updated.append(option)
            }
            value.wrappedValue = updated.joined(separator: ",")
          } label: {
            HStack(spacing: 6) {
              Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
              Text(option).lineLimit(1)
              Spacer(minLength: 0)
            }.font(.system(size: 11, weight: enabled ? .medium : .regular))
              .padding(.horizontal, 9).padding(.vertical, 7)
              .background(enabled ? HubStyle.accent.opacity(0.17) : HubStyle.panel, in: RoundedRectangle(cornerRadius: 8))
          }.buttonStyle(.plain).foregroundStyle(enabled ? HubStyle.accent : HubStyle.muted)
            .help(field.option_help?[option] ?? option)
        }
      }
      HStack(spacing: 8) {
        TextField("Ajouter un outil ou un motif", text: $toolToAdd)
          .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
          .onSubmit { addTools(from: toolToAdd, to: value) }
        Text("Entrée pour ajouter").font(.system(size: 10)).foregroundStyle(HubStyle.muted)
      }
      let custom = tokens(value.wrappedValue).filter { !(field.options ?? []).contains($0) }
      if !custom.isEmpty {
        HStack(spacing: 7) {
          Text("Ajoutés :").font(.system(size: 10)).foregroundStyle(HubStyle.muted)
          ForEach(custom, id: \.self) { token in
            Button {
              value.wrappedValue = tokens(value.wrappedValue).filter { $0 != token }.joined(separator: ",")
            } label: {
              Label(token, systemImage: "xmark.circle.fill").font(.system(size: 10, design: .monospaced))
            }.buttonStyle(.plain).foregroundStyle(HubStyle.accent)
          }
        }
      }
    }
  }
  private func tokens(_ text: String) -> [String] {
    Array(Set(text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
      .sorted { lhs, rhs in
        let order = ["read", "bash", "edit", "write", "grep", "find", "ls"]
        let left = order.firstIndex(of: lhs) ?? order.count
        let right = order.firstIndex(of: rhs) ?? order.count
        return left == right ? lhs < rhs : left < right
      }
  }
  private func addTools(from text: String, to value: Binding<String>) {
    let additions = tokens(text)
    guard !additions.isEmpty else { return }
    var updated = tokens(value.wrappedValue)
    for addition in additions where !updated.contains(addition) { updated.append(addition) }
    value.wrappedValue = updated.joined(separator: ",")
    toolToAdd = ""
  }
  private var diagnostics: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("DIAGNOSTIC & CYCLE DE VIE").font(.system(size: 9, weight: .semibold)).foregroundStyle(
        HubStyle.muted)
      RuntimeBadge(state: store.runtime(item))
      Text("Exécutable détecté").font(.system(size: 12, weight: .medium))
      Text(
        store.snapshot?.availability[item.id].flatMap { $0.isEmpty ? nil : $0 }
          ?? "Runtime absent · indiquez son chemin dans Avancé."
      ).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).foregroundStyle(
        HubStyle.muted)
      Text("Manifeste").font(.system(size: 12, weight: .medium))
      Text(adapter?.source ?? "").font(.system(size: 10, design: .monospaced)).textSelection(
        .enabled
      ).foregroundStyle(HubStyle.muted)
      if exists {
        if adapter?.id == "hermes", store.can(item, "gateway") {
          let initialized = store.runtime(item)?.gateway_initialized
          VStack(alignment: .leading, spacing: 9) {
            Label(
              initialized == true ? "Gateway PiHub configuré" : "Configuration PiHub manquante",
              systemImage: initialized == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(initialized == true ? .green : .orange)
            Text(
              initialized == true
                ? "Le gateway Hermes hôte sert le profil dédié à cette instance. Réappliquez la configuration après un changement de moteur ou de modèle."
                : "Hermes utilise un gateway hôte partagé. Cette initialisation configure le profil PiHub puis redémarre ce gateway pour le prendre en charge."
            ).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
            Button(initialized == true ? "Réappliquer la configuration PiHub" : "Initialiser le gateway PiHub") {
              store.perform("gateway", id: item.id)
            }.buttonStyle(.borderedProminent)
          }
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background((initialized == true ? Color.green : Color.orange).opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
        }
        HStack {
          if store.can(item, "preview") {
            Button("Commande") { store.perform("preview", id: item.id) }
          }
          if store.can(item, "logs") { Button("Journal") { store.perform("logs", id: item.id) } }
          if store.can(item, "test") { Button("Tester API") { store.perform("test", id: item.id) } }
        }
        if store.can(item, "logs"), adapter?.log_channels?["web"] != nil {
          Button("Journal du dashboard") {
            store.perform("logs", id: item.id, payload: ["channel": "web"])
          }
        }
        if store.runtime(item)?.managed == true {
          HStack {
            if store.can(item, "restart") {
              Button(hasCustomExecutable ? "Tenter le redémarrage" : "Redémarrer") {
                if hasCustomExecutable {
                  cautiousRestartIsExternal = false
                  confirmCautiousRestart = true
                } else {
                  store.perform("restart", id: item.id)
                }
              }
            }
            if store.can(item, "stop") { Button("Arrêter") { store.perform("stop", id: item.id) } }
          }
        } else if store.can(item, "adopt"), (store.runtime(item)?.pid ?? 0) > 0 {
          HStack {
            Button("Prendre en charge ce processus local") { store.perform("adopt", id: item.id) }
            if adapter?.kind == "provider", store.can(item, "restart") {
              Button("Tenter le redémarrage") {
                cautiousRestartIsExternal = true
                confirmCautiousRestart = true
              }
                .foregroundStyle(.orange)
            }
          }
          Text("Un redémarrage externe peut échouer ou ne pas libérer correctement le port. PiHub ne tente l’opération qu’après confirmation.")
            .font(.system(size: 10)).foregroundStyle(.orange)
        }
        if store.can(item, "web") {
          HStack {
            Button("Dashboard web") { store.perform("web", id: item.id) }
            if store.can(item, "stop-web") {
              Button("Arrêter le web") { store.perform("stop-web", id: item.id) }
            }
          }
        }
        HStack {
          if store.can(item, "load") {
            Button("Charger le modèle") { store.perform("load", id: item.id) }
          }
          if store.can(item, "unload") {
            Button("Libérer le modèle") { store.perform("unload", id: item.id) }
          }
        }
        IntegrationActions(store: store, item: item)
      }
      Text(
        "Ces actions utilisent la dernière configuration enregistrée. Une instance externe est observée en lecture seule."
      ).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
      if let error = store.runtime(item)?.error, !error.isEmpty {
        Text(error).font(.system(size: 10, design: .monospaced)).foregroundStyle(HubStyle.muted)
          .textSelection(.enabled)
      }
    }.disabled(store.busy)
  }
}

private struct IntegrationOnboardingView: View {
  @ObservedObject var store: HubStore
  let itemID: String
  let guide: IntegrationOnboarding
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 17) {
      HStack {
        Image(systemName: "sparkles").foregroundStyle(HubStyle.accent)
        Eyebrow(title: "PREMIER DÉMARRAGE")
        Spacer()
        Button("Plus tard") { dismiss() }.buttonStyle(.plain).foregroundStyle(HubStyle.muted)
      }
      Text(guide.title).font(.system(size: 23, weight: .semibold))
      Text(guide.message).font(.system(size: 12)).foregroundStyle(HubStyle.muted)
      VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
          HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)").font(.system(size: 10, weight: .semibold, design: .rounded))
              .foregroundStyle(HubStyle.accent).frame(width: 20, height: 20)
              .background(HubStyle.accent.opacity(0.14), in: Circle())
            Text(step).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }.padding(14).background(HubStyle.panel, in: RoundedRectangle(cornerRadius: 11))
      if let error = store.error, !error.isEmpty {
        Text(error).font(.system(size: 10)).foregroundStyle(.orange).textSelection(.enabled)
      }
      Spacer(minLength: 0)
      HStack {
        Spacer()
        if let action = guide.action {
          Button(guide.action_label ?? action) {
            store.perform(action, id: itemID) { success in if success { dismiss() } }
          }.buttonStyle(.borderedProminent).disabled(store.busy)
        } else {
          Button("Terminé") { dismiss() }.buttonStyle(.borderedProminent)
        }
      }
    }
    .padding(25).frame(width: 520, height: 460).background(HubStyle.background)
    .preferredColorScheme(.dark).tint(HubStyle.accent)
  }
}

struct AdapterPicker: View {
  @ObservedObject var store: HubStore
  let kind: String
  let select: (HubInstance) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        VStack(alignment: .leading, spacing: 7) {
          Eyebrow(title: "Nouvelle instance")
          Text(kind == "provider" ? "Choisir un moteur." : "Choisir un assistant.").font(
            .system(size: 26, weight: .light))
        }
        Spacer()
        Button("Fermer") { dismiss() }
      }
      WorkspaceSearch(text: $search, prompt: "Filtrer les templates")
      ScrollView {
        VStack(spacing: 0) {
          ForEach(
            (store.snapshot?.registry ?? []).filter {
              $0.kind == kind
                && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
            }
          ) { adapter in
            Button {
              var settings = Dictionary(
                uniqueKeysWithValues: adapter.fields.map { ($0.key, $0.default) })
              if kind == "provider" { settings[adapter.model_field ?? "model"] = "" }
              if adapter.routing?.required == true {
                settings[adapter.routing?.provider_field ?? "provider"] = ""
              }
              if let installed = store.snapshot?.catalog.detected[adapter.id],
                !installed.executable.isEmpty
              {
                settings["executable"] = installed.executable
              }
              select(
                HubInstance(
                  id: adapter.id + "-" + UUID().uuidString.prefix(6).lowercased(),
                  adapter: adapter.id, name: adapter.name, settings: settings))
            } label: {
              HStack(spacing: 14) {
                AdapterMark(adapter: adapter, small: true)
                VStack(alignment: .leading, spacing: 5) {
                  Text(adapter.name).font(.system(size: 13, weight: .semibold))
                  Text(adapter.description).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
                    .lineLimit(2)
                }
                Spacer()
                Image(systemName: "plus").foregroundStyle(adapter.tint)
              }.padding(.vertical, 14)
            }.buttonStyle(.plain)
            Divider().overlay(HubStyle.line)
          }
        }
      }
      HStack(spacing: 13) {
        Image(systemName: "arrow.down.circle").font(.system(size: 23, weight: .light))
          .foregroundStyle(HubStyle.accent)
        VStack(alignment: .leading, spacing: 5) {
          Text("Besoin d’installer le runtime ?").font(.system(size: 12, weight: .medium))
          Text("Les templates créent une configuration, pas une installation.").font(
            .system(size: 10)
          ).foregroundStyle(HubStyle.muted)
        }
        Spacer()
        Button("Explorer") {
          store.page = "catalog"
          dismiss()
        }
      }.padding(.top, 8)
    }.padding(25).frame(width: 570, height: 540).background(HubStyle.background)
      .preferredColorScheme(.dark)
  }
}

struct ModelEditor: View {
  @ObservedObject var store: HubStore
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var identifier = ""
  @State private var format = ""
  @State private var customFormat = ""
  private var formatOptions: [String] {
    let declared = store.snapshot?.registry.compactMap(\.model_format).filter {
      !$0.isEmpty && $0 != "any"
    } ?? []
    let existing = store.snapshot?.models.map(\.format).filter { !$0.isEmpty } ?? []
    return Array(Set(declared + existing)).sorted()
  }
  private var persistedFormat: String { format == "other" ? customFormat : format }
  private func label(for value: String) -> String { value.uppercased() }
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Enregistrer un modèle").font(.title2.bold())
      Text("Une référence partagée par toutes vos intégrations.").font(.system(size: 12))
        .foregroundStyle(HubStyle.muted)
      TextField("Nom affiché", text: $name).textFieldStyle(.roundedBorder)
      Picker("Format", selection: $format) {
        ForEach(formatOptions, id: \.self) { value in
          Text(label(for: value)).tag(value)
        }
        Text("Autre / personnalisé").tag("other")
      }
      if format == "other" {
        TextField("Format personnalisé (ex. exl2, vllm)", text: $customFormat)
          .textFieldStyle(.roundedBorder)
      }
      HStack {
        TextField(
          persistedFormat == "gguf" ? "/chemin/model.gguf" : "identifiant ou chemin du modèle", text: $identifier
        ).textFieldStyle(.roundedBorder)
        Button {
          let panel = NSOpenPanel()
          if panel.runModal() == .OK, let url = panel.url {
            identifier = url.path
            if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
          }
        } label: {
          Image(systemName: "folder")
        }
      }
      if let error = store.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
      HStack {
        Button("Annuler") { dismiss() }
        Spacer()
        Button("Enregistrer") {
          let model = HubModel(
            id: identifier, name: name, format: persistedFormat,
            path: identifier.hasPrefix("/") ? identifier : "",
            size: 0, source: "personal")
          store.perform("model-save", payload: ["model": HubBridge.object(model)]) { success in
            if success { dismiss() }
          }
        }.buttonStyle(.borderedProminent).disabled(name.isEmpty || identifier.isEmpty || persistedFormat.isEmpty || store.busy)
      }
    }.padding(28).frame(width: 540).preferredColorScheme(.dark)
      .onAppear { if format.isEmpty { format = formatOptions.first ?? "other" } }
  }
}

struct SettingsView: View {
  @ObservedObject var store: HubStore
  let snapshot: HubSnapshot
  @State private var roots = ""
  @State private var section = "Bibliothèque"
  var body: some View {
    VStack(alignment: .leading, spacing: 27) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: "desktopcomputer").font(.system(size: 25, weight: .ultraLight))
          .foregroundStyle(HubStyle.accent)
        Text(snapshot.host.name).font(.system(size: 23, weight: .light))
        Spacer()
        Text("\(snapshot.host.cores) CPU · \(Int(snapshot.host.memory)) Go").font(
          .system(size: 11, design: .monospaced)
        ).foregroundStyle(HubStyle.muted)
      }
      Picker("Section", selection: $section) {
        ForEach(["Bibliothèque", "Intégrations", "Données"], id: \.self) { Text($0).tag($0) }
      }.pickerStyle(.segmented).labelsHidden()
      if section == "Bibliothèque" {
        preference("Découverte", icon: "folder.badge.gearshape") {
          VStack(alignment: .leading, spacing: 12) {
            Text("Dossiers à scanner, un par ligne. Caches Hugging Face et fichiers GGUF.").font(
              .system(size: 12))
            TextEditor(text: $roots).font(.system(size: 11, design: .monospaced)).frame(height: 130)
              .padding(8).background(HubStyle.panel, in: RoundedRectangle(cornerRadius: 10))
            HStack {
              Button("Ajouter un dossier…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                  roots += (roots.isEmpty ? "" : "\n") + url.path
                }
              }
              Spacer()
              Button("Enregistrer") {
                store.perform("settings", payload: ["settings": ["model_roots": roots]])
              }.buttonStyle(.borderedProminent)
            }.controlSize(.small)
            Text(
              "Aucun poids téléchargé implicitement. Les références personnelles sont gérées dans Modèles."
            ).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
          }
        }
      } else if section == "Intégrations" {
        preference("Personnalisation", icon: "puzzlepiece.extension") {
          VStack(alignment: .leading, spacing: 16) {
            Text(
              "Icône, exécutables, commande et handlers : ouvrez une instance, puis la section Intégration. La définition est partagée par ses instances ; leurs réglages restent indépendants."
            ).font(.system(size: 12))
            ForEach(snapshot.registry) { adapter in
              ManifestSettingsRow(store: store, adapter: adapter)
            }
            Divider()
            HStack {
              Button("Catalogue d’installation") { store.page = "catalog" }
              Button("Extensions locales") { store.perform("reveal", id: "extensions") }
            }.controlSize(.small)
            ForEach(snapshot.registry_errors, id: \.self) {
              Text($0).font(.system(size: 10)).foregroundStyle(.orange)
            }
          }
        }
      } else {
        preference("Workspace", icon: "externaldrive") {
          VStack(alignment: .leading, spacing: 16) {
            Text(snapshot.data).font(.system(size: 11, design: .monospaced)).foregroundStyle(
              HubStyle.muted
            ).textSelection(.enabled)
            HStack {
              Button("Exporter JSON") { store.perform("export") }
              Button("Importer…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.json]
                if panel.runModal() == .OK, let url = panel.url {
                  do {
                    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
                    store.perform("import", payload: ["config": object])
                  } catch { store.error = error.localizedDescription }
                }
              }
            }.controlSize(.small)
            Text(
              "L’export contient la configuration des instances. Chaque intégration possède son dossier integrations/<id>/ avec manifest.json et ses handlers. Les versions installées sont dans installations.json et les sauvegardes dans backups/."
            ).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
            Divider()
            HStack {
              Button("Données locales") { store.perform("reveal", id: "data") }
              Button("Journaux") { store.perform("reveal", id: "logs") }
              Button("Projet & documentation") { store.perform("reveal", id: "root") }
            }.controlSize(.small)
            Label(
              "Les extensions et recettes sont du code de confiance. Gardez les clés API dans votre environnement, pas dans les JSON.",
              systemImage: "lock.shield"
            ).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
          }
        }
      }
      Spacer(minLength: 5)
      Divider()
      HStack {
        Text("PiHub · SwiftUI natif").font(.system(size: 10))
        Spacer()
        Text("Votre machine. Vos choix.").font(.system(size: 10)).foregroundStyle(HubStyle.muted)
      }
    }.onAppear { roots = snapshot.config.settings["model_roots"] ?? snapshot.root + "/models" }
  }
  private func preference<Content: View>(
    _ title: String, icon: String, @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .top, spacing: 25) {
      VStack(alignment: .leading, spacing: 12) {
        Image(systemName: icon).font(.system(size: 23, weight: .light)).foregroundStyle(
          HubStyle.accent)
        Text(title).font(.system(size: 13, weight: .medium))
      }.frame(width: 125, alignment: .leading)
      content().frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
struct ManifestSettingsRow: View {
  @ObservedObject var store: HubStore
  let adapter: HubAdapter
  @State private var editing = false
  var body: some View {
    Button {
      editing = true
    } label: {
      HStack {
        AdapterMark(adapter: adapter, small: true)
        Text(adapter.name).font(.system(size: 12))
        Spacer()
        Text(adapter.kind == "agent" ? "Agent" : "Moteur").font(.system(size: 10))
          .foregroundStyle(HubStyle.muted)
        Image(systemName: "slider.horizontal.3").foregroundStyle(HubStyle.accent)
      }
    }.buttonStyle(.plain).sheet(isPresented: $editing) {
      ManifestEditor(store: store, adapter: adapter)
    }
  }
}
