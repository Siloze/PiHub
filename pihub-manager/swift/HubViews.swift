import AppKit
import Charts
import SwiftUI

enum HubStyle {
  static let background = Color(red: 0.045, green: 0.055, blue: 0.075)
  static let panel = Color(red: 0.075, green: 0.088, blue: 0.115)
  static let accent = Color(red: 0.65, green: 0.57, blue: 1)
  static let muted = Color(red: 0.55, green: 0.61, blue: 0.71)
  static let line = Color.white.opacity(0.07)
}

struct HubPanel<Content: View>: View {
  var padding: CGFloat = 18
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
      .background(HubStyle.panel, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(HubStyle.line))
  }
}

struct AdapterMark: View {
  let adapter: HubAdapter?
  var small = false
  var body: some View {
    Image(systemName: adapter?.icon ?? "puzzlepiece.extension")
      .font(.system(size: small ? 16 : 23, weight: .medium))
      .foregroundStyle(adapter?.tint ?? HubStyle.accent)
      .frame(width: small ? 34 : 48, height: small ? 34 : 48)
      .background(
        (adapter?.tint ?? HubStyle.accent).opacity(0.12),
        in: RoundedRectangle(cornerRadius: small ? 10 : 14))
  }
}

struct RuntimeBadge: View {
  let state: HubRuntime?
  var body: some View {
    HStack(spacing: 5) {
      Circle().fill(active ? Color.mint : HubStyle.muted).frame(width: 5, height: 5)
      Text(state?.label ?? "Non lancé").font(.system(size: 10, weight: .medium))
    }.foregroundStyle(active ? Color.mint : HubStyle.muted).padding(.horizontal, 9).padding(
      .vertical, 5
    )
    .background((active ? Color.mint : HubStyle.muted).opacity(0.09), in: Capsule())
  }
  var active: Bool { state?.ready == true }
}

struct HubRootView: View {
  @ObservedObject var store: HubStore
  let detach: () -> Void
  @State private var editing: HubInstance?
  @State private var addKind: String?
  @State private var manifestImportKind: String?
  @State private var modelSheet = false
  @State private var pinned = false
  var pinChanged: (Bool) -> Void = { _ in }
  private let navigation = [
    ("dashboard", "Vue d’ensemble", "square.grid.2x2"), ("providers", "Providers", "server.rack"),
    ("agents", "Agents", "command"), ("models", "Modèles", "square.stack.3d.up"),
    ("catalog", "Explorer", "square.grid.3x3"), ("activity", "Activité", "waveform.path"),
    ("settings", "Réglages", "slider.horizontal.3"),
  ]

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Rectangle().fill(HubStyle.line).frame(width: 1)
      VStack(spacing: 0) {
        header
        Divider().overlay(HubStyle.line)
        if let error = store.error {
          HStack(alignment: .top) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(error).font(.system(size: 12)).textSelection(.enabled)
            Spacer()
            Button {
              store.error = nil
            } label: {
              Image(systemName: "xmark")
            }.buttonStyle(.plain)
          }.padding(12).background(Color.orange.opacity(0.09))
        }
        if let notice = store.notice {
          HStack {
            Image(systemName: "checkmark.circle").foregroundStyle(.mint)
            Text(notice).lineLimit(2)
            Spacer()
            Button {
              store.notice = nil
            } label: {
              Image(systemName: "xmark")
            }.buttonStyle(.plain)
          }.font(.system(size: 11)).padding(10).background(Color.mint.opacity(0.06))
        }
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if let snapshot = store.snapshot {
              ForEach(snapshot.model_changes) { plan in
                ModelChangePrompt(
                  store: store, plan: plan,
                  configureProvider: {
                    editing = snapshot.config.providers.first { $0.id == plan.provider_id }
                  }
                ).id(plan.id)
              }
              switch store.page {
              case "providers":
                ProvidersWorkspace(
                  store: store, items: snapshot.config.providers, edit: { editing = $0 },
                  add: { addKind = "provider" },
                  importManifest: { manifestImportKind = "provider" })
              case "agents":
                AgentsWorkspace(
                  store: store, snapshot: snapshot, edit: { editing = $0 },
                  add: { addKind = "agent" },
                  importManifest: { manifestImportKind = "agent" })
              case "models":
                ModelsWorkspace(
                  store: store, snapshot: snapshot, edit: { editing = $0 },
                  add: { modelSheet = true })
              case "catalog": CatalogWorkspace(store: store, edit: { editing = $0 })
              case "activity": ActivityWorkspace(store: store, snapshot: snapshot)
              case "settings": SettingsView(store: store, snapshot: snapshot)
              default: DashboardWorkspace(store: store, snapshot: snapshot, edit: { editing = $0 })
              }
            } else {
              VStack(spacing: 15) {
                ProgressView()
                Text("Connexion au centre de contrôle…").foregroundStyle(HubStyle.muted)
              }.frame(maxWidth: .infinity, minHeight: 400)
            }
          }.padding(24)
        }
        footer
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(HubStyle.background).foregroundStyle(Color.white.opacity(0.92))
    .preferredColorScheme(.dark)
    .font(.system(size: 13)).tint(HubStyle.accent)
    .sheet(item: $editing) { item in InstanceEditor(store: store, original: item) }
    .onReceive(store.$inspectID) { identifier in
      if let id = identifier, let snapshot = store.snapshot,
        let item = (snapshot.config.providers + snapshot.config.agents).first(where: { $0.id == id }
        )
      {
        editing = item
        DispatchQueue.main.async { store.inspectID = nil }
      }
    }
    .onReceive(store.$requestedImportKind) { kind in
      guard let kind else { return }
      manifestImportKind = kind
      DispatchQueue.main.async { store.requestedImportKind = nil }
    }
    .sheet(isPresented: Binding(get: { addKind != nil }, set: { if !$0 { addKind = nil } })) {
      AdapterPicker(store: store, kind: addKind ?? "provider") { instance in
        addKind = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { editing = instance }
      }
    }
    .sheet(isPresented: $modelSheet) { ModelEditor(store: store) }
    .sheet(isPresented: Binding(
      get: { manifestImportKind != nil }, set: { if !$0 { manifestImportKind = nil } }
    )) {
      ManifestImportView(store: store, expectedKind: manifestImportKind, folderOnly: true)
    }
    .sheet(
      isPresented: Binding(
        get: { store.showingLog && editing == nil }, set: { store.showingLog = $0 })
    ) {
      VStack(alignment: .leading, spacing: 15) {
        HStack {
          Label("Console PiHub", systemImage: "terminal").font(.headline)
          Spacer()
          Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(store.logText, forType: .string)
          } label: {
            Text("Copier").font(.system(size: 10, weight: .medium))
          }.buttonStyle(.plain).foregroundStyle(HubStyle.accent)
          Button {
            store.showingLog = false
          } label: {
            Text("Fermer").font(.system(size: 10, weight: .medium))
          }.buttonStyle(.plain).foregroundStyle(HubStyle.muted)
        }
        ScrollView {
          Text(store.logText).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }.padding(24).frame(width: 730, height: 490).preferredColorScheme(.dark)
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "circle.hexagongrid.fill").font(.system(size: 29)).foregroundStyle(
          HubStyle.accent)
        VStack(alignment: .leading, spacing: 2) {
          Text("PiHub").font(.system(size: 23, weight: .bold))
          Text("LOCAL AI WORKSPACE").font(.system(size: 8, weight: .semibold)).tracking(1.5)
            .foregroundStyle(HubStyle.muted)
        }
      }.padding(.vertical, 28).padding(.horizontal, 20)
      Text("CONTROL CENTER").font(.system(size: 9, weight: .semibold)).tracking(1.2)
        .foregroundStyle(HubStyle.muted).padding(.horizontal, 20).padding(.bottom, 12)
      ForEach(navigation, id: \.0) { entry in
        Button {
          store.page = entry.0
          store.search = ""
        } label: {
          HStack(spacing: 11) {
            Image(systemName: entry.2).frame(width: 19)
            Text(entry.1).font(
              .system(size: 12, weight: store.page == entry.0 ? .semibold : .regular))
            Spacer()
            if entry.0 == "providers" {
              Text("\(store.snapshot?.config.providers.count ?? 0)").font(
                .system(size: 10, design: .monospaced)
              ).foregroundStyle(HubStyle.muted)
            }
            if entry.0 == "agents" {
              Text("\(store.snapshot?.config.agents.count ?? 0)").font(
                .system(size: 10, design: .monospaced)
              ).foregroundStyle(HubStyle.muted)
            }
          }.foregroundStyle(store.page == entry.0 ? Color.white : HubStyle.muted).padding(
            .horizontal, 12
          ).padding(.vertical, 12)
            .background(
              store.page == entry.0 ? HubStyle.accent.opacity(0.13) : Color.clear,
              in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
      }
      Spacer()
      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 6) {
          Circle().fill(Color.mint).frame(width: 5, height: 5)
          Text("Votre machine. Vos modèles.").font(.system(size: 10))
        }
        Text(store.snapshot?.host.name ?? "Apple Silicon").font(
          .system(size: 10, design: .monospaced)
        ).foregroundStyle(HubStyle.muted).lineLimit(1)
        HStack {
          Text("PiHub 2.0").font(.system(size: 9)).foregroundStyle(HubStyle.muted)
          Spacer()
          Button {
            NSApplication.shared.terminate(nil)
          } label: {
            Image(systemName: "power").foregroundStyle(HubStyle.muted)
          }.buttonStyle(.plain).help("Quitter PiHub · les moteurs continuent de tourner")
        }
      }.padding(17).background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .padding(12)
    }.frame(width: 190).background(Color.black.opacity(0.13))
  }

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(navigation.first { $0.0 == store.page }?.1 ?? "PiHub").font(
          .system(size: 20, weight: .semibold))
        Text(subtitle).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
      }
      Spacer()
      if store.busy || store.refreshing { ProgressView().controlSize(.small) }
      Button {
        store.refresh()
      } label: {
        Image(systemName: "arrow.clockwise")
      }.help("Actualiser ⌘R").keyboardShortcut("r")
      Button {
        pinned.toggle()
        pinChanged(pinned)
      } label: {
        Image(systemName: pinned ? "pin.fill" : "pin")
      }.help("Garder l’overlay ouvert")
      Button(action: detach) { Image(systemName: "arrow.down.right.and.arrow.up.left") }.help(
        "Revenir à l’overlay compact")
    }.buttonStyle(.borderless).padding(.horizontal, 24).padding(.vertical, 20)
  }
  private var subtitle: String {
    switch store.page {
    case "providers": return "Vos moteurs d’inférence, indépendants et simultanés."
    case "agents": return "Un espace de travail pour chaque assistant."
    case "models": return "Catalogue local, modèles personnels et compatibilité."
    case "catalog": return "Templates versionnés et runtimes à installer à la carte."
    case "activity": return "Consommation mesurée et journal des opérations."
    case "settings": return "Un hub portable, ouvert et personnalisable."
    default: return "Toute votre infrastructure IA, en un regard."
    }
  }
  private var footer: some View {
    HStack(spacing: 6) {
      Image(systemName: "circle.dotted.circle").foregroundStyle(HubStyle.accent)
      Text(store.busy ? "Opération en cours…" : "Actualisation automatique · 4 s").foregroundStyle(
        HubStyle.muted)
      Spacer()
      Text("Apple Silicon · Metal / MLX").foregroundStyle(HubStyle.muted)
    }.font(.system(size: 9)).padding(.horizontal, 24).padding(.vertical, 10).background(
      Color.black.opacity(0.1))
  }

}
