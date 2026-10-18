import AppKit
import SwiftUI

/// A small control surface, not a scaled-down desktop dashboard.
struct HubCompactView: View {
  @ObservedObject var store: HubStore
  let expand: () -> Void
  let editInstance: (HubInstance) -> Void
  let importFolder: (String) -> Void
  let openInWindow: (HubWindowAction) -> Void
  private let tabs = [
    ("dashboard", "Résumé", "square.grid.2x2"), ("providers", "Moteurs", "server.rack"),
    ("agents", "Agents", "command"), ("models", "Modèles", "cube"),
    ("catalog", "Explorer", "square.grid.3x3"), ("activity", "Activité", "waveform.path"),
    ("settings", "Réglages", "slider.horizontal.3"),
  ]
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "circle.hexagongrid.fill").font(.system(size: 22)).foregroundStyle(
          HubStyle.accent)
        Text("PiHub").font(.system(size: 16, weight: .bold))
        Text("CONTROL ROOM").font(.system(size: 7, weight: .semibold)).tracking(1.5)
          .foregroundStyle(HubStyle.muted)
        Spacer()
        if store.busy || store.refreshing { ProgressView().controlSize(.mini) }
        Button(action: expand) { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help(
          "Agrandir")
      }.buttonStyle(.borderless).font(.system(size: 12)).padding(.horizontal, 17).padding(
        .vertical, 17)
      HStack(spacing: 0) {
        ForEach(tabs, id: \.0) { tab in
          Button {
            store.page = tab.0
          } label: {
            VStack(spacing: 6) {
              Image(systemName: tab.2).font(.system(size: 14))
              Text(tab.1).font(.system(size: 7, weight: .medium)).lineLimit(1)
              Capsule().fill(store.page == tab.0 ? HubStyle.accent : Color.clear).frame(
                width: 16, height: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 46).contentShape(Rectangle()).foregroundStyle(
              store.page == tab.0 ? Color.white : HubStyle.muted)
          }.buttonStyle(.plain).frame(maxWidth: .infinity).contentShape(Rectangle()).help(tab.1)
        }
      }.padding(.horizontal, 10).padding(.bottom, 8)
      Divider().overlay(HubStyle.line)
      if let error = store.error { banner(error, error: true) }
      if let notice = store.notice { banner(notice, error: false) }
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if let s = store.snapshot {
            if !s.model_changes.isEmpty {
              Button {
                openInWindow(.showMain)
              } label: {
                HStack(spacing: 9) {
                  Image(systemName: "arrow.triangle.branch").foregroundStyle(HubStyle.accent)
                  Text("Changements de modèle à appliquer")
                  Spacer()
                  Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8)).foregroundStyle(HubStyle.muted)
                }.font(.system(size: 10, weight: .medium)).padding(11)
                  .background(HubStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
              }.buttonStyle(.plain)
            }
            switch store.page {
            case "providers":
              ProvidersWorkspace(
                store: store, items: s.config.providers, edit: editInstance,
                add: { openInWindow(.addInstance("provider")) },
                importManifest: { importFolder("provider") }, compact: true)
            case "agents":
              AgentsWorkspace(
                store: store, snapshot: s, edit: editInstance, add: { openInWindow(.addInstance("agent")) },
                importManifest: { importFolder("agent") }, compact: true)
            case "models":
              ModelsWorkspace(
                store: store, snapshot: s, edit: editInstance, add: { openInWindow(.editModels) },
                compact: true)
            case "catalog": CatalogWorkspace(
              store: store, compact: true, edit: editInstance, openInWindow: openInWindow)
            case "activity": ActivityWorkspace(store: store, snapshot: s, compact: true)
            case "settings": compactSettings(s)
            default:
              DashboardWorkspace(store: store, snapshot: s, edit: editInstance, compact: true)
            }
          } else {
            ProgressView("Connexion…").frame(maxWidth: .infinity, minHeight: 220)
          }
        }.padding(17)
      }
      Divider().overlay(HubStyle.line)
      HStack(spacing: 7) {
        Circle().fill(store.snapshot == nil ? HubStyle.muted : Color.mint).frame(
          width: 4, height: 4)
        Text(store.snapshot?.host.name ?? "Connexion").lineLimit(1)
        Spacer()
        Text("4 s")
        Button {
          store.refresh()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        Button {
          NSApp.terminate(nil)
        } label: {
          Image(systemName: "power")
        }
      }.buttonStyle(.borderless).font(.system(size: 9)).foregroundStyle(HubStyle.muted).padding(
        .horizontal, 17
      ).padding(.vertical, 11)
    }.frame(width: 420).frame(maxHeight: .infinity).background(HubStyle.background).foregroundStyle(
      Color.white.opacity(0.92)
    ).preferredColorScheme(.dark).tint(HubStyle.accent)
      .onChange(of: store.showingLog) { shown in
        if shown { openInWindow(.showLog) }
      }
  }
  private func banner(_ text: String, error: Bool) -> some View {
    HStack(alignment: .top) {
      Image(systemName: error ? "exclamationmark.circle" : "checkmark.circle").foregroundStyle(
        error ? Color.orange : .mint)
      Text(text).lineLimit(3)
      Spacer()
      Button {
        if error { store.error = nil } else { store.notice = nil }
      } label: {
        Image(systemName: "xmark")
      }.buttonStyle(.plain)
    }.font(.system(size: 10)).padding(10).background(
      (error ? Color.orange : Color.mint).opacity(0.06))
  }
  private func compactSettings(_ s: HubSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      Eyebrow(title: "Votre machine")
      HStack(alignment: .lastTextBaseline) {
        Text("\(Int(s.host.memory))").font(.system(size: 40, weight: .ultraLight, design: .rounded))
        Text("Go unifiés").font(.system(size: 11)).foregroundStyle(HubStyle.muted)
        Spacer()
        Text("\(s.host.cores) CPU").font(.system(size: 11, design: .monospaced)).foregroundStyle(
          HubStyle.muted)
      }
      Divider()
      settingsLink("Extensions personnelles", "puzzlepiece.extension") {
        store.perform("reveal", id: "extensions")
      }
      settingsLink("Configuration & données", "externaldrive") {
        store.perform("reveal", id: "data")
      }
      settingsLink("Exporter le workspace", "square.and.arrow.up") { store.perform("export") }
      settingsLink("Installer une intégration", "arrow.down.circle") { store.page = "catalog" }
      Divider()
      ForEach(s.registry_errors, id: \.self) {
        Text($0).font(.system(size: 10)).foregroundStyle(.orange)
      }
      Text(
        "Icônes, commandes et exécutables : Configurer → Intégration. Les changements sont persistés dans les JSON locaux."
      ).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
      Button("Ouvrir tous les réglages", action: expand).font(.system(size: 11))
    }
  }
  private func settingsLink(_ label: String, _ icon: String, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: 11) {
        Image(systemName: icon).foregroundStyle(HubStyle.accent).frame(width: 19)
        Text(label)
        Spacer()
        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(HubStyle.muted)
      }.font(.system(size: 11)).padding(.vertical, 3)
    }.buttonStyle(.plain)
  }
}
