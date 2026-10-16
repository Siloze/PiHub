import Charts
import SwiftUI

// Shared visual primitives; each workspace has its own information architecture.
struct Eyebrow: View {
  let title: String
  var detail = ""
  var body: some View {
    HStack {
      Text(title.uppercased()).tracking(1.4)
      Spacer()
      Text(detail).tracking(0)
    }.font(.system(size: 9, weight: .semibold)).foregroundStyle(HubStyle.muted)
  }
}
struct QuietEmpty: View {
  let title: String
  let detail: String
  let action: () -> Void
  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "circle.hexagongrid").font(.system(size: 38, weight: .ultraLight))
        .foregroundStyle(HubStyle.accent)
      Text(title).font(.system(size: 18, weight: .semibold))
      Text(detail).font(.system(size: 11)).foregroundStyle(HubStyle.muted).multilineTextAlignment(
        .center)
      Button("Explorer le catalogue", action: action).buttonStyle(.borderedProminent)
    }.frame(maxWidth: .infinity).padding(.vertical, 36)
  }
}
struct WorkspaceSearch: View {
  @Binding var text: String
  var prompt = "Rechercher…"
  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundStyle(HubStyle.muted)
      TextField(prompt, text: $text).textFieldStyle(.plain)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
        }.buttonStyle(.plain)
      }
    }.font(.system(size: 11)).padding(10).background(
      Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
  }
}
struct RuntimeControls: View {
  @ObservedObject var store: HubStore
  let item: HubInstance
  var body: some View {
    HStack(spacing: 11) {
      if store.runtime(item)?.managed == true && store.can(item, "stop") {
        Button {
          store.perform("stop", id: item.id)
        } label: {
          Image(systemName: "stop.fill")
        }.help("Arrêter")
      } else if store.adapter(item)?.kind == "agent" && store.can(item, "terminal") {
        Button {
          store.perform("terminal", id: item.id)
        } label: {
          Image(systemName: "terminal")
        }.help("Ouvrir Terminal")
      } else if store.runtime(item)?.ready != true && store.can(item, "start") {
        Button {
          store.perform("start", id: item.id)
        } label: {
          Image(systemName: "play.fill")
        }.help("Démarrer")
      } else if store.can(item, "test") {
        Button {
          store.perform("test", id: item.id)
        } label: {
          Image(systemName: "network")
        }.help("Tester API")
      }
      if store.can(item, "web") {
        Button {
          store.perform("web", id: item.id)
        } label: {
          Image(systemName: "globe")
        }.help("Web UI")
      }
      IntegrationActions(store: store, item: item)
    }.buttonStyle(.borderless).controlSize(.small).font(.system(size: 11)).disabled(store.busy)
  }
}

struct ProvidersWorkspace: View {
  @ObservedObject var store: HubStore
  let items: [HubInstance]
  let edit: (HubInstance) -> Void
  let add: () -> Void
  var importManifest: () -> Void = {}
  var compact = false
  @State private var search = ""
  private var filtered: [HubInstance] {
    items.filter {
      (search.isEmpty
        || ($0.name + " " + (store.runtime($0)?.model ?? "") + " "
          + store.linkedAgents($0).map(\.name).joined(separator: " "))
          .localizedCaseInsensitiveContains(search))
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 15 : 22) {
      HStack {
        WorkspaceSearch(text: $search, prompt: "Rechercher un moteur, un modèle…")
        Menu {
          Button("Ajouter une instance", systemImage: "plus", action: add)
          Button("Importer un dossier…", systemImage: "folder.badge.plus", action: importManifest)
        } label: {
          Image(systemName: "plus").frame(width: 24, height: 24)
        }.menuStyle(.borderlessButton).controlSize(.small).help("Ajouter ou importer un provider")
      }
      if items.isEmpty {
        QuietEmpty(
          title: "Aucun provider",
          detail: "Ajoutez un template, installez un moteur ou connectez une API."
        ) { store.page = "catalog" }
      } else {
        ForEach([true, false], id: \.self) { active in
          let group = filtered.filter { store.isActive($0) == active }
          if !group.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              Eyebrow(title: active ? "En cours" : "Arrêtés", detail: "\(group.count)").padding(
                .bottom, 9)
              ForEach(group) { item in
                if active { runningRow(item) } else { stoppedRow(item) }
                Divider().overlay(HubStyle.line).padding(.leading, compact ? 28 : 36)
              }
            }
          }
        }
        if filtered.isEmpty {
          Text("Aucun résultat.").font(.system(size: 11)).foregroundStyle(HubStyle.muted)
        }
      }
      if !compact {
        Text(
          "Les rattachements indiquent le routage enregistré. Changer un modèle ne redémarre aucun agent sans confirmation."
        ).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
      }
    }
  }
  private func runningRow(_ item: HubInstance) -> some View {
    let runtime = store.runtime(item)
    let configured = item.settings[store.adapter(item)?.model_field ?? "model"] ?? ""
    let actual = runtime?.model ?? ""
    let model = actual.isEmpty ? configured : actual
    let agents = store.linkedAgents(item)
    return VStack(alignment: .leading, spacing: compact ? 8 : 10) {
      HStack(spacing: compact ? 10 : 14) {
        Image(systemName: store.adapter(item)?.icon ?? "server.rack").font(
          .system(size: compact ? 17 : 22)
        ).foregroundStyle(HubStyle.muted).frame(width: compact ? 18 : 22)
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 6) {
            Text(item.name).font(.system(size: compact ? 12 : 14, weight: .semibold))
            Circle().fill(runtime?.ready == true ? Color.mint : .orange).frame(width: 4, height: 4)
            if !compact {
              Text(runtime?.label ?? "").font(.system(size: 10)).foregroundStyle(HubStyle.muted)
            }
          }
          Text(
            model.isEmpty
              ? "Modèle non exposé" : model.split(separator: "/").last.map(String.init) ?? model
          ).font(.system(size: compact ? 9 : 11)).foregroundStyle(HubStyle.muted).lineLimit(1)
            .truncationMode(.middle).help(model)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if !compact {
          VStack(alignment: .trailing, spacing: 5) {
            Text(String(format: "%.0f Mo", runtime?.memory ?? 0))
            Text(String(format: "%.1f %% CPU", runtime?.cpu ?? 0))
          }.font(.system(size: 10, design: .monospaced)).foregroundStyle(HubStyle.muted)
        }
        Button {
          edit(item)
        } label: {
          Image(systemName: "slider.horizontal.3")
        }.buttonStyle(.borderless).help("Configurer")
        RuntimeControls(store: store, item: item)
      }
      HStack(spacing: 8) {
        Image(systemName: "arrow.triangle.branch").foregroundStyle(HubStyle.muted)
        if agents.isEmpty {
          Text("Aucun agent rattaché").foregroundStyle(HubStyle.muted)
        } else {
          Menu {
            ForEach(agents) { agent in
              Button(agent.name + (store.isActive(agent) ? " · en cours" : " · arrêté")) {
                edit(agent)
              }
            }
          } label: {
            Text(agents.map(\.name).joined(separator: " · ")).lineLimit(1).foregroundStyle(
              HubStyle.muted)
          }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        Text(item.settings["port"].map { ":" + $0 } ?? "API").font(
          .system(size: 9, design: .monospaced)
        ).foregroundStyle(HubStyle.muted).help(runtime?.endpoint ?? "")
      }.font(.system(size: 9)).padding(.leading, compact ? 28 : 36)
      if !actual.isEmpty && !configured.isEmpty && actual != configured {
        Text("Prochain lancement : " + configured).font(.system(size: 9)).foregroundStyle(.orange)
          .lineLimit(1).truncationMode(.middle).padding(.leading, compact ? 28 : 36)
      }
    }.padding(.vertical, compact ? 10 : 16)
  }
  private func stoppedRow(_ item: HubInstance) -> some View {
    let isMissingExecutable = store.setupLabel(item) == "Exécutable absent"
    return HStack(spacing: 10) {
      Image(systemName: store.adapter(item)?.icon ?? "server.rack").font(.system(size: 13))
        .foregroundStyle(HubStyle.muted.opacity(0.65)).frame(width: compact ? 18 : 26)
      Text(item.name).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
      if isMissingExecutable {
        Text("Exécutable absent").font(.system(size: 8)).foregroundStyle(
          HubStyle.muted.opacity(0.65))
        Button("Configurer") {
          store.focusExecutableID = item.id
          edit(item)
        }.buttonStyle(.plain).font(.system(size: 8, weight: .medium)).foregroundStyle(
          HubStyle.accent)
      } else {
        Text(store.setupLabel(item)).font(.system(size: 8)).foregroundStyle(
          HubStyle.muted.opacity(0.65)
        ).lineLimit(1)
      }
      if store.runtime(item)?.state == "failed" {
        Image(systemName: "exclamationmark.circle").font(.system(size: 9)).foregroundStyle(.orange)
          .help(store.runtime(item)?.error ?? "Échec")
      }
      Spacer()
      if !compact {
        Text(item.settings["port"].map { ":" + $0 } ?? "API").font(
          .system(size: 9, design: .monospaced)
        ).foregroundStyle(HubStyle.muted.opacity(0.7)).padding(.trailing, 15)
      }
      Button {
        edit(item)
      } label: {
        Image(systemName: "slider.horizontal.3")
      }.buttonStyle(.borderless)
      RuntimeControls(store: store, item: item)
    }.padding(.vertical, compact ? 8 : 10)
  }
}

struct AgentsWorkspace: View {
  @ObservedObject var store: HubStore
  let snapshot: HubSnapshot
  let edit: (HubInstance) -> Void
  let add: () -> Void
  var importManifest: () -> Void = {}
  var compact = false
  @State private var search = ""
  private func route(_ item: HubInstance) -> String {
    if let provider = store.provider(for: item) { return provider.name }
    let target = item.settings[store.adapter(item)?.routing?.provider_field ?? "provider"] ?? ""
    return target == store.adapter(item)?.routing?.unbound_value
      ? store.adapter(item)?.routing?.unbound_label ?? "Compte natif" : "Sans provider"
  }
  private var filtered: [HubInstance] {
    snapshot.config.agents.filter {
      search.isEmpty
        || ($0.name + " " + route($0) + " " + (store.runtime($0)?.model ?? ""))
          .localizedCaseInsensitiveContains(search)
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 17 : 24) {
      HStack {
        WorkspaceSearch(text: $search, prompt: "Rechercher un agent ou son provider")
        Menu {
          Button("Ajouter un agent", systemImage: "plus", action: add)
          Button("Importer un dossier…", systemImage: "folder.badge.plus", action: importManifest)
        } label: {
          Image(systemName: "plus").frame(width: 24, height: 24)
        }.menuStyle(.borderlessButton).controlSize(.small).help("Ajouter ou importer un agent")
      }
      if snapshot.config.agents.isEmpty {
        QuietEmpty(title: "Aucun agent", detail: "Ajoutez un template ou installez un agent.") {
          store.page = "catalog"
        }
      }
      ForEach([true, false], id: \.self) { active in
        let group = filtered.filter { store.isActive($0) == active }
        if !group.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            Eyebrow(title: active ? "En cours" : "Arrêtés", detail: "\(group.count)").padding(
              .bottom, 8)
            ForEach(group) { item in
              agentRow(item, active: active)
              Divider().overlay(HubStyle.line).padding(.leading, compact ? 28 : 38)
            }
          }
        }
      }
      if !snapshot.config.agents.isEmpty && filtered.isEmpty {
        Text("Aucun résultat.").font(.system(size: 11)).foregroundStyle(HubStyle.muted)
      }
    }
  }
  private func agentRow(_ item: HubInstance, active: Bool) -> some View {
    let runtime = store.runtime(item)
    let pinned = item.settings[store.adapter(item)?.routing?.model_field ?? "model"] ?? ""
    return HStack(alignment: active ? .top : .center, spacing: compact ? 10 : 16) {
      Image(systemName: store.adapter(item)?.icon ?? "terminal").font(
        .system(size: active ? 18 : 13)
      ).foregroundStyle(HubStyle.muted.opacity(active ? 1 : 0.65)).frame(width: compact ? 18 : 22)
        .padding(.top, active ? 2 : 0)
      VStack(alignment: .leading, spacing: 7) {
        HStack(spacing: 7) {
          Text(item.name).font(.system(size: active ? 12 : 11, weight: active ? .medium : .regular))
            .foregroundStyle(active ? Color.white : HubStyle.muted)
          if active {
            Circle().fill(runtime?.ready == true ? Color.mint : .orange).frame(width: 4, height: 4)
          }
        }
        if active {
          HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
            Button(route(item)) { if let provider = store.provider(for: item) { edit(provider) } }
              .buttonStyle(.plain).help("Provider rattaché")
          }.font(.system(size: 10)).foregroundStyle(HubStyle.muted)
          let actual = runtime?.model ?? ""
          Text(
            actual.isEmpty
              ? "Modèle non exposé" : actual.split(separator: "/").last.map(String.init) ?? actual
          ).font(.system(size: 9, design: .monospaced)).foregroundStyle(HubStyle.muted).lineLimit(1)
            .truncationMode(.middle).help(actual)
          if !pinned.isEmpty {
            Text("Modèle fixé").font(.system(size: 8)).foregroundStyle(HubStyle.muted)
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      if !active {
        Text(store.setupLabel(item) == "Arrêté" ? route(item) : store.setupLabel(item)).font(
          .system(size: 9)
        ).foregroundStyle(HubStyle.muted.opacity(0.7))
          .lineLimit(1).frame(maxWidth: compact ? 75 : 150, alignment: .trailing)
      } else if !compact {
        VStack(alignment: .trailing, spacing: 6) {
          Text(String(format: "%.0f Mo", runtime?.memory ?? 0))
          Text(String(format: "%.1f %% CPU", runtime?.cpu ?? 0))
          if let thinking = item.settings["thinking"] { Text("Réflexion · " + thinking) }
        }.font(.system(size: 9, design: .monospaced)).foregroundStyle(HubStyle.muted).padding(
          .trailing, 6)
      }
      Button {
        edit(item)
      } label: {
        Image(systemName: "slider.horizontal.3")
      }.buttonStyle(.borderless).help("Configurer")
      RuntimeControls(store: store, item: item)
    }.padding(.vertical, active ? (compact ? 12 : 17) : (compact ? 8 : 10))
  }
}

struct ModelsWorkspace: View {
  @ObservedObject var store: HubStore
  let snapshot: HubSnapshot
  let edit: (HubInstance) -> Void
  let add: () -> Void
  var compact = false
  @State private var search = ""
  @State private var format = "all"
  private var filtered: [HubModel] {
    snapshot.models.filter {
      (format == "all" || $0.format == format)
        && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
          || $0.id.localizedCaseInsensitiveContains(search))
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        WorkspaceSearch(text: $search, prompt: "Nom, format ou identifiant")
        Button(action: add) { Image(systemName: "plus") }
        Button {
          store.perform("rescan")
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }.controlSize(.small)
      HStack(spacing: 5) {
        ForEach(["all", "mlx", "gguf", "ollama", "api"], id: \.self) { value in
          Button {
            format = value
          } label: {
            Text(value == "all" ? "Tout" : value.uppercased()).font(
              .system(size: 9, weight: .medium)
            ).padding(.horizontal, 10).padding(.vertical, 6).background(
              format == value ? Color.cyan.opacity(0.16) : Color.clear, in: Capsule()
            ).foregroundStyle(format == value ? Color.cyan : HubStyle.muted)
          }.buttonStyle(.plain)
        }
        Spacer()
      }
      Eyebrow(title: "Bibliothèque locale", detail: "\(filtered.count) références")
      if filtered.isEmpty {
        Text(
          "Aucun modèle pour ce filtre. Enregistrez une référence ou scannez vos dossiers dans Réglages."
        ).font(.system(size: 11)).foregroundStyle(HubStyle.muted).padding(.vertical, 24)
      }
      ForEach(filtered) { model in
        HStack(spacing: compact ? 10 : 18) {
          VStack(spacing: 5) {
            Image(systemName: model.format == "gguf" ? "cpu" : "cube.transparent").font(
              .system(size: compact ? 19 : 27, weight: .light))
            Text(model.format.uppercased()).font(.system(size: 7, weight: .bold)).tracking(1)
          }.foregroundStyle(model.format == "gguf" ? Color.orange : .cyan).frame(
            width: compact ? 40 : 60)
          VStack(alignment: .leading, spacing: 5) {
            Text(model.name).font(.system(size: compact ? 11 : 14, weight: .medium)).lineLimit(2)
            Text(
              compact
                ? (model.size > 0 ? String(format: "%.1f Go · ", model.size) : "") + model.source
                : model.id
            ).font(.system(size: 9, design: .monospaced)).foregroundStyle(HubStyle.muted).lineLimit(
              1
            ).truncationMode(.middle)
          }.frame(maxWidth: .infinity, alignment: .leading)
          if !compact {
            Text(model.size > 0 ? String(format: "%.1f Go", model.size) : "—").font(
              .system(size: 11, design: .monospaced)
            ).foregroundStyle(HubStyle.muted)
          }
          Menu {
            ForEach(
              snapshot.config.providers.filter {
                store.adapter($0)?.model_format == model.format
                  || store.adapter($0)?.model_format == "any"
              }
            ) { provider in
              Button(provider.name) {
                var draft = provider
                draft.settings[store.adapter(provider)?.model_field ?? "model"] =
                  model.format == "gguf" ? model.path : model.id
                store.perform("save", payload: ["item": HubBridge.object(draft)])
              }
            }
            if model.source != "discovered" {
              Divider()
              Button("Retirer la référence", role: .destructive) {
                store.perform("model-delete", id: model.id)
              }
            }
          } label: {
            Image(systemName: "arrow.up.right")
          }.menuStyle(.borderlessButton).frame(width: 25).help("Affecter à un provider")
        }.padding(.vertical, compact ? 5 : 10)
        modelAttachments(model)
        Divider().overlay(HubStyle.line)
      }
      Text(
        "Références et fichiers locaux uniquement. Affecter un modèle ne redémarre aucun processus automatiquement."
      ).font(.system(size: 9)).foregroundStyle(HubStyle.muted)
    }
  }
  private func modelAttachments(_ model: HubModel) -> some View {
    let bindings = snapshot.model_bindings[model.id] ?? []
    return VStack(alignment: .leading, spacing: 5) {
      if bindings.isEmpty {
        Text("Non rattaché").font(.system(size: 9)).foregroundStyle(HubStyle.muted.opacity(0.65))
      } else {
        ForEach(["provider", "agent"], id: \.self) { kind in
          let group = bindings.filter { $0.kind == kind }
          if !group.isEmpty {
            HStack(alignment: .top, spacing: 7) {
              Image(systemName: kind == "provider" ? "server.rack" : "command").font(
                .system(size: 9)
              ).frame(width: 12)
              Menu {
                ForEach(group) { binding in
                  Button(
                    binding.name + " · " + (binding.active ? "en cours" : "configuré")
                      + (binding.via.isEmpty ? "" : " · via " + binding.via)
                  ) {
                    if let item = (snapshot.config.providers + snapshot.config.agents).first(
                      where: { $0.id == binding.id })
                    {
                      edit(item)
                    }
                  }
                }
              } label: {
                Text(
                  group.map { $0.name + ($0.active ? " · en cours" : " · configuré") }.joined(
                    separator: "  /  ")
                ).font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.leading)
              }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
            }.foregroundStyle(HubStyle.muted)
          }
        }
      }
    }.padding(.leading, compact ? 50 : 78).padding(.bottom, compact ? 8 : 12)
  }
}

struct DashboardWorkspace: View {
  @ObservedObject var store: HubStore
  let snapshot: HubSnapshot
  let edit: (HubInstance) -> Void
  var compact = false
  private var resources: [HubRuntime] { snapshot.providers + snapshot.agents }
  private var prioritized: [HubInstance] {
    (snapshot.config.providers + snapshot.config.agents).sorted {
      (store.runtime($0)?.ready == true ? 0 : 1) < (store.runtime($1)?.ready == true ? 0 : 1)
    }
  }
  private var visibleProviders: [HubInstance] {
    let linkedIDs = Set(
      snapshot.config.agents.compactMap {
        $0.settings[store.adapter($0)?.routing?.provider_field ?? "provider"]
      })
    let important = snapshot.config.providers.filter {
      store.runtime($0)?.ready == true || linkedIDs.contains($0.id)
    }
    return important.isEmpty ? Array(snapshot.config.providers.prefix(3)) : important
  }
  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 17 : 19) {
      HStack(spacing: compact ? 18 : 35) {
        metric("PROVIDERS", "\(snapshot.config.providers.count)", .mint)
        metric("AGENTS", "\(snapshot.config.agents.count)", HubStyle.accent)
        metric("MODÈLES", "\(snapshot.models.count)", .cyan)
        metric(
          "RAM RSS", String(format: "%.1f Go", resources.reduce(0) { $0 + $1.memory } / 1024),
          HubStyle.muted)
        Spacer(minLength: 0)
      }.padding(.vertical, compact ? 12 : 18).overlay(alignment: .top) {
        Rectangle().fill(HubStyle.line).frame(height: 1)
      }.overlay(alignment: .bottom) { Rectangle().fill(HubStyle.line).frame(height: 1) }
      if snapshot.config.providers.isEmpty && snapshot.config.agents.isEmpty {
        QuietEmpty(
          title: "Workspace vide",
          detail:
            "Des templates versionnés, des installations isolées.\nGardez uniquement les intégrations dont vous avez besoin."
        ) { store.page = "catalog" }
      } else if compact {
        Eyebrow(
          title: "En un regard",
          detail: String(format: "%.1f Go RSS", resources.reduce(0) { $0 + $1.memory } / 1024))
        ForEach(Array(prioritized.prefix(5))) { item in
          Button {
            edit(item)
          } label: {
            HStack {
              AdapterMark(adapter: store.adapter(item), small: true)
              Text(item.name).font(.system(size: 11))
              Spacer()
              Text(store.runtime(item)?.label ?? "Arrêté").font(.system(size: 9)).foregroundStyle(
                store.runtime(item)?.ready == true ? Color.mint : HubStyle.muted)
              Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(
                HubStyle.muted)
            }
          }.buttonStyle(.plain)
        }
      } else {
        HStack(alignment: .top, spacing: 28) {
          VStack(alignment: .leading, spacing: 13) {
            Eyebrow(title: "Circuit d’inférence", detail: "PROVIDER → AGENT")
            ForEach(visibleProviders) { provider in
              HStack(alignment: .top, spacing: 10) {
                AdapterMark(adapter: store.adapter(provider), small: true)
                VStack(alignment: .leading, spacing: 7) {
                  Button(provider.name) { edit(provider) }.buttonStyle(.plain).font(
                    .system(size: 12, weight: .semibold))
                  let linked = snapshot.config.agents.filter {
                    $0.settings[store.adapter($0)?.routing?.provider_field ?? "provider"]
                      == provider.id
                  }
                  ForEach(linked) { agent in
                    Button {
                      edit(agent)
                    } label: {
                      Label(agent.name, systemImage: "arrow.turn.down.right").font(
                        .system(size: 10)
                      ).foregroundStyle(HubStyle.muted)
                    }.buttonStyle(.plain)
                  }
                  if linked.isEmpty {
                    Text("Aucun agent relié").font(.system(size: 9)).foregroundStyle(HubStyle.muted)
                  }
                }
                Spacer()
                Circle().fill(
                  store.runtime(provider)?.ready == true ? Color.mint : HubStyle.muted.opacity(0.3)
                ).frame(width: 5, height: 5)
              }.padding(.vertical, 7)
            }
            if snapshot.config.providers.count > visibleProviders.count {
              Button("+ \(snapshot.config.providers.count - visibleProviders.count) autres moteurs")
              { store.page = "providers" }.font(.system(size: 10)).foregroundStyle(HubStyle.muted)
            }
            Button("Voir tous les agents →") { store.page = "agents" }.font(.system(size: 10))
              .padding(.top, 6)
          }.frame(maxWidth: .infinity, alignment: .leading)
          Rectangle().fill(HubStyle.line).frame(width: 1)
          VStack(alignment: .leading, spacing: 18) {
            Eyebrow(title: "Mémoire des processus", detail: "RSS · Go")
            MemoryPlot(store: store).frame(height: 85)
            Text("Mesure des processus suivis, pas de l’allocation Metal exacte.").font(
              .system(size: 9)
            ).foregroundStyle(HubStyle.muted)
            Eyebrow(title: "Dernier mouvement")
            if let event = snapshot.events.first {
              Text(event.name + " · " + event.action).font(.system(size: 12))
              Text(event.time).font(.system(size: 10, design: .monospaced)).foregroundStyle(
                HubStyle.muted)
            } else {
              Text("Aucune opération pour le moment.").font(.system(size: 11)).foregroundStyle(
                HubStyle.muted)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }
  private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(value).font(.system(size: compact ? 24 : 28, weight: .light, design: .rounded))
        .foregroundStyle(color)
      Text(label).font(.system(size: 8, weight: .semibold)).tracking(1.1).foregroundStyle(
        HubStyle.muted)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private var memoryDial: some View {
    ZStack {
      Circle().stroke(Color.cyan.opacity(0.1), lineWidth: 5)
      Circle().trim(
        from: 0,
        to: min(1, resources.reduce(0) { $0 + $1.memory } / 1024 / max(1, snapshot.host.memory))
      ).stroke(Color.cyan, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(
        .degrees(-90))
      VStack(spacing: 4) {
        Text(String(format: "%.1f", resources.reduce(0) { $0 + $1.memory } / 1024)).font(
          .system(size: 21, weight: .light, design: .rounded))
        Text("Go RSS").font(.system(size: 8)).foregroundStyle(HubStyle.muted)
      }
    }.frame(width: 85, height: 85)
  }
}

struct MemoryPlot: View {
  @ObservedObject var store: HubStore
  var body: some View {
    Chart(store.samples) { sample in
      AreaMark(x: .value("Heure", sample.date), y: .value("Go", sample.memory)).foregroundStyle(
        LinearGradient(colors: [.cyan.opacity(0.19), .clear], startPoint: .top, endPoint: .bottom))
      LineMark(x: .value("Heure", sample.date), y: .value("Go", sample.memory)).foregroundStyle(
        Color.cyan
      ).lineStyle(StrokeStyle(lineWidth: 1.5))
    }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: true))
  }
}
struct ActivityWorkspace: View {
  @ObservedObject var store: HubStore
  let snapshot: HubSnapshot
  var compact = false
  @State private var eventsOnly = false
  @State private var metric = "memory"
  @State private var sort = "memory"
  @State private var descending = true
  @State private var activeOnly = true
  private var resources: [HubRuntime] { snapshot.providers + snapshot.agents }
  private var items: [HubInstance] {
    (snapshot.config.providers + snapshot.config.agents)
      .filter { !activeOnly || store.runtime($0)?.ready == true }
      .sorted {
        let lhs = value(store.runtime($0), sort)
        let rhs = value(store.runtime($1), sort)
        if lhs == nil && rhs != nil { return false }
        if lhs != nil && rhs == nil { return true }
        if lhs == rhs { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return descending ? (lhs ?? 0) > (rhs ?? 0) : (lhs ?? 0) < (rhs ?? 0)
      }
  }
  private func value(_ runtime: HubRuntime?, _ key: String) -> Double? {
    guard let runtime else { return nil }
    switch key {
    case "cpu": return runtime.cpu
    case "gpu": return runtime.gpu
    default: return runtime.memory
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 10 : 12) {
      HStack(spacing: 0) {
        metricButton(
          "RAM suivie",
          value: String(format: "%.2f Go", resources.reduce(0) { $0 + $1.memory } / 1024),
          key: "memory")
        metricButton(
          "CPU suivi", value: String(format: "%.1f %%", resources.reduce(0) { $0 + $1.cpu }),
          key: "cpu")
        metricButton(
          "GPU du Mac", value: snapshot.gpu.usage.map { String(format: "%.0f %%", $0) } ?? "—",
          key: "gpu")
      }
      ResourcePlot(store: store, metric: metric).frame(height: compact ? 35 : 50)
      HStack {
        Text(
          metric == "gpu"
            ? (snapshot.gpu.usage == nil
              ? "GPU non exposé par macOS" : snapshot.gpu.name + " · IORegistry · toutes les apps")
            : metric == "cpu"
              ? "Somme CPU des processus suivis · peut dépasser 100 %"
              : "RSS des processus suivis · Go"
        )
        .font(.system(size: 9)).foregroundStyle(HubStyle.muted)
        Spacer()
        if metric == "gpu", let memory = snapshot.gpu.memory, !compact {
          Text(String(format: "%.1f Go GPU · Mac entier", memory / 1024)).font(
            .system(size: 9, design: .monospaced)
          ).foregroundStyle(HubStyle.muted)
        }
      }
      Picker("Affichage", selection: $eventsOnly) {
        Text("Processus").tag(false)
        Text("Journal").tag(true)
      }.pickerStyle(.segmented)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .labelsHidden()
      if !eventsOnly {
        HStack(spacing: 9) {
          Picker("Trier", selection: $sort) {
            Text("RAM").tag("memory")
            Text("CPU").tag("cpu")
            Text("GPU").tag("gpu")
          }.frame(width: compact ? 125 : 150).font(.system(size: 11))
          Button {
            descending.toggle()
          } label: {
            Image(systemName: descending ? "arrow.down" : "arrow.up")
          }.buttonStyle(.borderless).help(
            descending ? "Plus consommateurs d'abord" : "Moins consommateurs d'abord")
          Spacer()
          Button {
            activeOnly.toggle()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: activeOnly ? "checkmark" : "")
                .font(.system(size: 8)).foregroundStyle(
                  activeOnly ? HubStyle.accent : HubStyle.muted)
              Text("Actifs").font(.system(size: 10))
            }.padding(.horizontal, 10).padding(.vertical, 5)
              .background(
                activeOnly ? HubStyle.accent.opacity(0.13) : Color.white.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 8)
              )
              .foregroundStyle(activeOnly ? HubStyle.accent : HubStyle.muted)
          }.buttonStyle(.plain)
        }
        VStack(spacing: 0) {
          HStack {
            Text("PROCESSUS").frame(maxWidth: .infinity, alignment: .leading)
            Text("RAM").frame(width: compact ? 53 : 85, alignment: .trailing)
            Text("CPU").frame(width: compact ? 48 : 75, alignment: .trailing)
            Text("GPU").frame(width: compact ? 35 : 60, alignment: .trailing)
            Color.clear.frame(width: 20)
          }.font(.system(size: 8, weight: .semibold)).foregroundStyle(HubStyle.muted).padding(
            .bottom, 5)
          ForEach(items) { item in
            processRow(item)
            Divider().overlay(HubStyle.line)
          }
        }
        if items.isEmpty {
          Text("Aucun processus dans cette sélection.").font(.system(size: 11)).foregroundStyle(
            HubStyle.muted)
        }
        Text(
          "GPU par agent/provider : uniquement si son handler le mesure. Sinon — ; le GPU du Mac n’est pas attribué arbitrairement aux processus."
        )
        .font(.system(size: 9)).foregroundStyle(HubStyle.muted)
      } else {
        ForEach(Array(snapshot.events.prefix(compact ? 15 : 100))) { event in
          HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
              Circle().fill(HubStyle.muted).frame(width: 5, height: 5)
              Rectangle().fill(HubStyle.line).frame(width: 1, height: 27)
            }.padding(.top, 4)
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(event.name).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(event.time).font(.system(size: 9, design: .monospaced)).foregroundStyle(
                  HubStyle.muted)
              }
              Text(event.action + (event.detail.isEmpty ? "" : " · " + event.detail)).font(
                .system(size: 10)
              ).foregroundStyle(HubStyle.muted)
            }
          }
        }
        if snapshot.events.isEmpty {
          Text("Aucune opération.").font(.system(size: 11)).foregroundStyle(HubStyle.muted)
        }
      }
    }
  }
  private func metricButton(_ label: String, value: String, key: String) -> some View {
    Button {
      metric = key
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        Text(label).font(.system(size: 9)).foregroundStyle(HubStyle.muted)
        Text(value).font(.system(size: compact ? 18 : 23, weight: .medium, design: .rounded))
          .lineLimit(1).minimumScaleFactor(0.8)
        Rectangle().fill(metric == key ? HubStyle.accent : HubStyle.line).frame(height: 2)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, key == "gpu" ? 0 : 15)
    }.buttonStyle(.plain)
  }
  private func processRow(_ item: HubInstance) -> some View {
    let runtime = store.runtime(item)
    return HStack(spacing: 8) {
      HStack(spacing: 7) {
        Circle().fill(
          runtime?.ready == true ? Color.mint.opacity(0.8) : HubStyle.muted.opacity(0.35)
        ).frame(width: 4, height: 4)
        Text(item.name).font(.system(size: compact ? 10 : 12)).lineLimit(1)
      }.frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 4) {
        Rectangle().fill(Color.cyan).frame(width: 3)
        Text(String(format: "%.0f Mo", runtime?.memory ?? 0))
      }.frame(width: compact ? 53 : 85, alignment: .trailing)
      HStack(spacing: 4) {
        Rectangle().fill(Color.mint).frame(width: 3)
        Text(String(format: "%.1f %%", runtime?.cpu ?? 0))
      }.frame(width: compact ? 48 : 75, alignment: .trailing)
      HStack(spacing: 4) {
        Rectangle().fill(Color.purple).frame(width: 3)
        Text(runtime?.gpu.map { String(format: "%.0f %%", $0) } ?? "—")
      }.frame(width: compact ? 35 : 60, alignment: .trailing)
      Group {
        if store.can(item, "logs") {
          Button {
            store.perform("logs", id: item.id)
          } label: {
            Image(systemName: "text.alignleft")
          }.buttonStyle(.borderless).help("Journal")
        } else {
          Color.clear
        }
      }.frame(width: 20)
    }.font(.system(size: compact ? 8 : 10, design: .monospaced)).foregroundStyle(HubStyle.muted)
      .padding(.vertical, compact ? 7 : 9)
  }
}
struct ResourcePlot: View {
  @ObservedObject var store: HubStore
  let metric: String
  private var hasSamples: Bool { metric != "gpu" || store.samples.contains { $0.gpu != nil } }
  var body: some View {
    if hasSamples {
      Chart(store.samples) { sample in
        if let number = measure(sample) {
          LineMark(x: .value("Heure", sample.date), y: .value("Mesure", number)).foregroundStyle(
            HubStyle.accent
          ).lineStyle(StrokeStyle(lineWidth: 1.5))
        }
      }.chartXAxis(.hidden).chartYAxis(.hidden).chartYScale(domain: .automatic(includesZero: true))
    } else {
      HStack {
        Spacer()
        Text("Mesure non disponible").font(.system(size: 10)).foregroundStyle(HubStyle.muted)
        Spacer()
      }.overlay(alignment: .bottom) { Rectangle().fill(HubStyle.line).frame(height: 1) }
    }
  }
  private func measure(_ sample: ResourceSample) -> Double? {
    switch metric {
    case "cpu": return sample.cpu
    case "gpu": return sample.gpu
    default: return sample.memory
    }
  }
}
