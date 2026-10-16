import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Structured edits preserve unknown manifest keys and optional handlers.
struct ManifestEditor: View {
  @ObservedObject var store: HubStore
  let adapter: HubAdapter
  @Environment(\.dismiss) private var dismiss
  @State private var original: [String: Any] = [:]
  @State private var name = ""
  @State private var icon = ""
  @State private var color = "violet"
  @State private var description = ""
  @State private var executables: [String] = []
  @State private var command: [String] = []
  @State private var environment = "{}"
  @State private var raw = ""
  @State private var tab = "Identité"
  @State private var localError: String?
  @State private var confirmReset = false
  private let symbols = [
    "sparkles", "cpu", "server.rack", "cube.transparent", "flame", "network", "terminal",
    "wand.and.stars", "command", "bolt", "brain", "chevron.left.forwardslash.chevron.right", "leaf",
    "atom", "puzzlepiece.extension", "bird",
  ]
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 15) {
        Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(
          HubStyle.accent)
        VStack(alignment: .leading, spacing: 5) {
          Text("Personnaliser l’intégration").font(.system(size: 20, weight: .semibold))
          Text(adapter.id + " · définition partagée par toutes ses instances").font(
            .system(size: 10)
          ).foregroundStyle(HubStyle.muted)
        }
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
        }.buttonStyle(.plain)
      }.padding(23)
      Picker("Section", selection: $tab) {
        ForEach(["Identité", "Lancement", "JSON"], id: \.self) { Text($0).tag($0) }
      }.pickerStyle(.segmented).padding(.horizontal, 23).padding(.bottom, 18)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          if tab == "Identité" {
            TextField("Nom", text: $name).textFieldStyle(.roundedBorder)
            TextField("Description", text: $description).textFieldStyle(.roundedBorder)
            Eyebrow(title: "Icône SF Symbols")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 9) {
              ForEach(symbols, id: \.self) { symbol in
                Button {
                  icon = symbol
                } label: {
                  Image(systemName: symbol).font(.system(size: 19)).frame(maxWidth: .infinity)
                    .frame(height: 40).background(
                      icon == symbol ? HubStyle.accent.opacity(0.2) : Color.white.opacity(0.025),
                      in: RoundedRectangle(cornerRadius: 8)
                    ).foregroundStyle(icon == symbol ? HubStyle.accent : HubStyle.muted)
                }.buttonStyle(.plain).help(symbol)
              }
            }
            TextField("Autre nom SF Symbol", text: $icon).textFieldStyle(.roundedBorder)
            Picker("Couleur", selection: $color) {
              ForEach(["violet", "mint", "orange", "cyan", "blue"], id: \.self) {
                Text($0.capitalized).tag($0)
              }
            }
          } else if tab == "Lancement" {
            Eyebrow(title: "Exécutables de secours", detail: "DANS L’ORDRE")
            Text(
              "Ces chemins sont testés dans l’ordre seulement si l’instance n’a pas de chemin personnalisé. « {executable} » dans la commande reçoit le chemin retenu."
            ).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
            ForEach(executables.indices, id: \.self) { index in
              HStack {
                TextField("/chemin/exécutable ou nom PATH", text: $executables[index])
                  .textFieldStyle(.roundedBorder).font(.system(size: 10, design: .monospaced))
                Button {
                  let panel = NSOpenPanel()
                  if panel.runModal() == .OK, let url = panel.url { executables[index] = url.path }
                } label: {
                  Image(systemName: "folder")
                }
                Button {
                  executables.remove(at: index)
                } label: {
                  Image(systemName: "minus.circle")
                }
              }
            }
            Button {
              executables.append("")
            } label: {
              Label("Ajouter un chemin", systemImage: "plus")
            }
            Divider()
            Eyebrow(title: "Commande", detail: "UN ARGUMENT PAR LIGNE")
            ForEach(command.indices, id: \.self) { index in
              HStack {
                Text(String(index)).font(.system(size: 9, design: .monospaced)).foregroundStyle(
                  HubStyle.muted
                ).frame(width: 18)
                TextField(index == 0 ? "{executable}" : "Argument", text: $command[index])
                  .textFieldStyle(.roundedBorder).font(.system(size: 10, design: .monospaced))
                Button {
                  command.remove(at: index)
                } label: {
                  Image(systemName: "minus.circle")
                }
              }
            }
            Button {
              command.append("")
            } label: {
              Label("Ajouter un argument", systemImage: "plus")
            }
            Text(
              "Variables : {executable}, {root}, {home} et clés du formulaire. Aucun shell. Un handler spécialisé peut compléter ou remplacer cette commande."
            ).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
            Eyebrow(title: "Environnement", detail: "OBJET JSON")
            TextEditor(text: $environment).font(.system(size: 10, design: .monospaced)).frame(
              height: 110
            ).padding(6).background(
              Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
          } else {
            Text(
              "Éditeur complet : champs, handlers, paramètres et métadonnées. Le JSON doit garder le même id et le même type. Ce code local est exécuté avec les permissions de votre compte."
            ).font(.system(size: 11)).foregroundStyle(HubStyle.muted)
            TextEditor(text: $raw).font(.system(size: 10, design: .monospaced)).frame(
              minHeight: 330
            ).padding(8).background(
              Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
          }
          if let error = localError ?? store.error {
            Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
          }
        }.padding(23)
      }
      Divider()
      HStack {
        Button("Restaurer le template") { confirmReset = true }
        Spacer()
        Button("Annuler") { dismiss() }
        Button("Enregistrer le JSON") { save() }.buttonStyle(.borderedProminent)
      }.controlSize(.small).padding(20).disabled(store.busy || original.isEmpty)
      Text(
        "Dossier personnel : .pihub/integrations/\(adapter.id)/ · sauvegardes automatiques"
      ).font(.system(size: 9)).foregroundStyle(HubStyle.muted).padding(.horizontal, 23).padding(
        .bottom, 16)
    }.frame(width: 650, height: 670).background(HubStyle.background).preferredColorScheme(.dark)
      .tint(HubStyle.accent)
      .onAppear {
        do {
          let data = try Data(contentsOf: URL(fileURLWithPath: adapter.source))
          original = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
          hydrate(original)
        } catch { localError = error.localizedDescription }
      }
      .onChange(of: tab) { next in
        do {
          if next == "JSON" {
            raw = pretty(try structured())
          } else if !raw.isEmpty,
            let value = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]
          {
            original = value
            hydrate(value)
            raw = ""
          }
        } catch {
          localError = error.localizedDescription
          tab = "JSON"
        }
      }
      .confirmationDialog(
        "Restaurer le template livré ? Votre copie actuelle sera sauvegardée dans backups/.",
        isPresented: $confirmReset
      ) {
        Button("Restaurer") {
          store.perform("manifest-reset", id: adapter.id) { if $0 { dismiss() } }
        }
      }
  }
  private func pretty(_ value: Any) -> String {
    guard
      let data = try? JSONSerialization.data(
        withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    else { return "{}" }
    return String(decoding: data, as: UTF8.self)
  }
  private func hydrate(_ value: [String: Any]) {
    name = value["name"] as? String ?? adapter.name
    icon = value["icon"] as? String ?? adapter.icon
    color = value["color"] as? String ?? adapter.color
    description = value["description"] as? String ?? adapter.description
    executables = value["executables"] as? [String] ?? []
    command = value["command"] as? [String] ?? []
    environment = pretty(value["env"] ?? [String: String]())
  }
  private func structured() throws -> [String: Any] {
    var value = original
    value["name"] = name
    value["icon"] = icon
    value["color"] = color
    value["description"] = description
    value["executables"] = executables.filter { !$0.isEmpty }
    value["command"] = command
    value["env"] = try JSONSerialization.jsonObject(with: Data(environment.utf8))
    return value
  }
  private func save() {
    do {
      let value =
        tab == "JSON"
        ? try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] ?? [:]
        : try structured()
      guard value["id"] as? String == adapter.id && value["kind"] as? String == adapter.kind else {
        localError = "L’identifiant et le type doivent rester inchangés."
        return
      }
      store.perform("manifest-save", payload: ["manifest": value]) { if $0 { dismiss() } }
    } catch { localError = error.localizedDescription }
  }
}

struct ManifestImportView: View {
  @ObservedObject var store: HubStore
  let expectedKind: String?
  var compact = false
  var folderOnly = false
  @Environment(\.dismiss) private var dismiss
  @State private var raw = ""
  @State private var filename = ""
  @State private var bundlePath: String?
  @State private var bundleFiles: [String] = []
  @State private var checkingFolder = false
  @State private var step = 0
  @State private var localError: String?
  @State private var confirmReplace = false
  @State private var replaceConfirmed = false
  @State private var pendingCreateInstance = false

  private var manifest: [String: Any]? {
    guard let data = raw.data(using: .utf8),
      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return value
  }
  private var manifestID: String { manifest?["id"] as? String ?? "" }
  private var manifestKind: String { manifest?["kind"] as? String ?? "" }
  private var kindMatches: Bool { expectedKind == nil || expectedKind == manifestKind }
  private var existing: Bool {
    !manifestID.isEmpty && (store.snapshot?.registry.contains { $0.id == manifestID } ?? false)
  }
  private var canReview: Bool {
    guard manifest != nil else { return false }
    return !manifestID.isEmpty && (manifestKind == "provider" || manifestKind == "agent")
      && kindMatches
  }
  private let skeleton = """
  {
    "api_version": 1,
    "id": "mon-integration",
    "kind": "provider",
    "name": "Mon provider",
    "icon": "cpu",
    "color": "violet",
    "description": "Mon moteur local",
    "executables": [],
    "command": ["{executable}", "--port", "{port}"],
    "fields": [
      {"key": "executable", "label": "Chemin de l’exécutable", "group": "Lancement", "type": "file", "default": ""},
      {"key": "port", "label": "Port", "group": "Réseau", "type": "number", "default": "18100"}
    ],
    "handlers": {}
  }
  """

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 13) {
        Image(systemName: "square.and.arrow.down").font(.system(size: 22)).foregroundStyle(
          HubStyle.accent)
        VStack(alignment: .leading, spacing: 4) {
          Text(folderOnly ? "Importer un dossier" : "Importer une intégration")
            .font(.system(size: 18, weight: .semibold))
          Text(folderOnly
            ? "manifest.json et fichiers associés · validation avant copie"
            : "JSON de provider ou d’agent · validation avant enregistrement")
            .font(.system(size: 10)).foregroundStyle(HubStyle.muted)
        }
        Spacer()
        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
          .buttonStyle(.plain).foregroundStyle(HubStyle.muted)
      }.padding(20)
      HStack(spacing: 8) {
        stepMarker(0, "Source")
        Rectangle().fill(HubStyle.line).frame(height: 1)
        stepMarker(1, "Vérifier")
      }.padding(.horizontal, 20).padding(.bottom, 16)
      Divider()
      Group {
        if step == 0 {
          if folderOnly { folderSourcePage } else { sourcePage }
        } else { reviewPage }
      }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      Divider()
      footer.padding(16)
    }.frame(width: compact ? 390 : 650, height: compact ? 510 : 680)
      .background(HubStyle.background).foregroundStyle(.white.opacity(0.92))
      .preferredColorScheme(.dark).tint(HubStyle.accent)
      .confirmationDialog(
        "Une intégration avec cet identifiant existe déjà. L’import va remplacer sa définition partagée. Une copie du dossier personnel précédent sera sauvegardée.",
        isPresented: $confirmReplace
      ) {
        Button("Remplacer la définition") {
          replaceConfirmed = true
          importManifest(createInstance: pendingCreateInstance)
        }
      }
  }

  private func stepMarker(_ index: Int, _ title: String) -> some View {
    HStack(spacing: 6) {
      Circle().fill(step >= index ? HubStyle.accent : HubStyle.muted.opacity(0.35))
        .frame(width: 6, height: 6)
      Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(
        step >= index ? HubStyle.accent : HubStyle.muted)
    }.fixedSize()
  }

  private var sourcePage: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Choisis un fichier ou colle le manifeste").font(.system(size: 14, weight: .medium))
          Text(filename.isEmpty ? "Le fichier ne sera pas modifié." : filename)
            .font(.system(size: 9, design: .monospaced)).foregroundStyle(HubStyle.muted)
        }
        Spacer()
        Button { openFile() } label: { Label("Ouvrir…", systemImage: "folder") }
          .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(HubStyle.accent)
        Button { openBundle() } label: { Label("Dossier…", systemImage: "shippingbox") }
          .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(HubStyle.accent)
      }
      HStack(spacing: 12) {
        Button("Coller") {
          bundlePath = nil
          if let text = NSPasteboard.general.string(forType: .string) { raw = text }
        }.buttonStyle(.plain)
        Button("Charger le squelette JSON") { raw = skeleton; filename = "Squelette PiHub"; bundlePath = nil }
          .buttonStyle(.plain).foregroundStyle(HubStyle.accent)
        Spacer()
        if !raw.isEmpty {
          Button("Effacer") { raw = ""; filename = ""; bundlePath = nil }.buttonStyle(.plain)
            .foregroundStyle(HubStyle.muted)
        }
      }.font(.system(size: 9))
      TextEditor(text: $raw).font(.system(size: 10, design: .monospaced))
        .scrollContentBackground(.hidden).padding(9)
        .background(Color.black.opacity(0.19), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(HubStyle.line))
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: canReview ? "checkmark.circle" : "info.circle")
          .foregroundStyle(canReview ? Color.mint : HubStyle.muted)
        Text(sourceHint).font(.system(size: 9)).foregroundStyle(HubStyle.muted)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let localError { Text(localError).font(.system(size: 10)).foregroundStyle(.orange) }
    }.padding(18)
  }

  private var folderSourcePage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Sélectionnez le dossier de votre intégration")
            .font(.system(size: 14, weight: .medium))
          Text("PiHub attend manifest.json à la racine. Les handlers Python et autres ressources restent à côté, y compris dans des sous-dossiers.")
            .font(.system(size: 10)).foregroundStyle(HubStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        Button { openBundle() } label: {
          Label(bundlePath == nil ? "Choisir un dossier…" : "Changer de dossier…", systemImage: "folder.badge.plus")
            .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.borderedProminent).controlSize(.regular)
        if let bundlePath {
          VStack(alignment: .leading, spacing: 9) {
            Label("Dossier sélectionné", systemImage: "folder.fill")
              .font(.system(size: 10, weight: .semibold)).foregroundStyle(HubStyle.accent)
            Text(bundlePath).font(.system(size: 9, design: .monospaced))
              .foregroundStyle(HubStyle.muted).textSelection(.enabled)
            HStack(spacing: 7) {
              Image(systemName: canReview ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(canReview ? Color.mint : Color.orange)
              Text(sourceHint).font(.system(size: 9)).foregroundStyle(HubStyle.muted)
            }
            if !bundleFiles.isEmpty {
              Text(bundleFiles.joined(separator: "   ·   ")).font(.system(size: 9, design: .monospaced))
                .foregroundStyle(HubStyle.muted).lineLimit(3)
            }
          }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(HubStyle.panel, in: RoundedRectangle(cornerRadius: 11))
        } else {
          VStack(alignment: .leading, spacing: 10) {
            Label("manifest.json", systemImage: "doc.text").foregroundStyle(.white)
            Label("handler.py / handlers/", systemImage: "chevron.left.forwardslash.chevron.right")
              .foregroundStyle(HubStyle.muted)
            Label("autres fichiers utiles", systemImage: "square.stack.3d.up")
              .foregroundStyle(HubStyle.muted)
          }.font(.system(size: 10, design: .monospaced)).padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HubStyle.panel, in: RoundedRectangle(cornerRadius: 11))
        }
        Text("La validation vérifie le même manifeste que PiHub utilise au lancement, ainsi que l’existence des fichiers de handlers référencés. Le dossier est copié dans .pihub/integrations/<id>/.")
          .font(.system(size: 9)).foregroundStyle(HubStyle.muted)
          .fixedSize(horizontal: false, vertical: true)
        if let localError {
          Text(localError).font(.system(size: 10)).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
      }.padding(18)
    }
  }

  private var sourceHint: String {
    guard let manifest else {
      return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "PiHub attend un objet JSON avec au minimum id et kind. Les réglages et handlers sont facultatifs."
        : "JSON illisible ou sa racine n’est pas un objet. Corrige-le avant de continuer."
    }
    if manifestID.isEmpty { return "Le manifeste doit avoir un identifiant id." }
    if manifestKind != "provider" && manifestKind != "agent" {
      return "kind doit valoir provider ou agent."
    }
    if !kindMatches {
      return "Ce fichier est un \(manifestKind), mais tu l’importes depuis la section \(expectedKind ?? "inconnue")."
    }
    return "\(manifest["name"] as? String ?? manifestID) · \(manifestKind) · id \(manifestID)"
  }

  private var reviewPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 15) {
        HStack(spacing: 12) {
          Image(systemName: (manifest?["icon"] as? String) ?? "puzzlepiece.extension")
            .font(.system(size: 24)).foregroundStyle(HubStyle.accent).frame(width: 42, height: 42)
            .background(HubStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
          VStack(alignment: .leading, spacing: 4) {
            Text(manifest?["name"] as? String ?? "Intégration sans nom")
              .font(.system(size: 15, weight: .semibold))
            Text("\(manifestKind.uppercased()) · \(manifestID)")
              .font(.system(size: 9, design: .monospaced)).foregroundStyle(HubStyle.muted)
          }
        }
        HStack(spacing: 8) {
          metadataPill("\((manifest?["fields"] as? [[String: Any]])?.count ?? 0) réglages", icon: "slider.horizontal.3")
          metadataPill("\((manifest?["executables"] as? [String])?.count ?? 0) candidats", icon: "terminal")
          metadataPill("\((manifest?["handlers"] as? [String: String])?.count ?? 0) handlers", icon: "bolt")
        }
        if let bundlePath {
          Label("\(URL(fileURLWithPath: bundlePath).lastPathComponent) · \(bundleFiles.count) éléments au premier niveau", systemImage: "folder")
            .font(.system(size: 9)).foregroundStyle(HubStyle.muted)
        }
        if existing {
          Label("Cet id existe déjà. L’import remplacera le manifeste partagé ; PiHub sauvegarde l’ancien JSON.", systemImage: "exclamationmark.triangle")
            .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 8) {
          Label(folderOnly ? "Dossier vérifié avant la copie." : "Manifeste vérifié avant l’enregistrement.", systemImage: "checkmark.shield")
            .font(.system(size: 11, weight: .medium)).foregroundStyle(.mint)
          Text("PiHub copie manifest.json et ses fichiers dans .pihub/integrations/<id>/. Les modules Python référencés peuvent être chargés lors de la découverte : importez uniquement un dossier de confiance. Vous pouvez créer une instance tout de suite.")
            .font(.system(size: 10)).foregroundStyle(HubStyle.muted)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
          .background(HubStyle.panel, in: RoundedRectangle(cornerRadius: 11))
        VStack(alignment: .leading, spacing: 7) {
          Text("À propos des handlers").font(.system(size: 11, weight: .medium))
          Text("Le dossier contient manifest.json et peut inclure des handlers Python. Les actions et l’installation sont décrites dans ce JSON ; les handlers sont référencés par un chemin relatif, comme handler.py:start.")
            .font(.system(size: 9)).foregroundStyle(HubStyle.muted).fixedSize(horizontal: false, vertical: true)
        }
        if let localError { Text(localError).font(.system(size: 10)).foregroundStyle(.orange) }
      }.padding(18)
    }
  }

  private func metadataPill(_ title: String, icon: String) -> some View {
    Label(title, systemImage: icon).font(.system(size: 8, weight: .medium))
      .foregroundStyle(HubStyle.muted).padding(.horizontal, 8).padding(.vertical, 6)
      .background(HubStyle.panel, in: Capsule())
  }

  @ViewBuilder private var footer: some View {
    HStack(spacing: 9) {
      if step > 0 {
        Button("Retour") { step = 0 }.buttonStyle(.plain).foregroundStyle(HubStyle.muted)
      }
      Spacer()
      if step == 0 {
        Button(checkingFolder ? "Vérification…" : folderOnly ? "Vérifier le dossier" : "Vérifier le JSON") {
          if folderOnly {
            validateFolder()
          } else {
            localError = canReview ? nil : "Le JSON doit contenir un id et un kind valide, compatible avec la section choisie."
            if canReview { step = 1 }
          }
        }.buttonStyle(.borderedProminent).disabled(!canReview || store.busy || checkingFolder)
      } else {
        Button("Importer seulement") { importManifest(createInstance: false) }
          .buttonStyle(.plain).disabled(store.busy)
        Button("Importer et configurer") { importManifest(createInstance: true) }
          .buttonStyle(.borderedProminent).disabled(store.busy)
      }
    }.font(.system(size: 10, weight: .medium))
  }

  private func openFile() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let url = panel.url {
      do {
        raw = try String(contentsOf: url, encoding: .utf8)
        filename = url.lastPathComponent
        bundlePath = url.lastPathComponent == "manifest.json" ? url.deletingLastPathComponent().path : nil
        localError = nil
      } catch { localError = error.localizedDescription }
    }
  }

  private func openBundle() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    if panel.runModal() == .OK, let url = panel.url {
      raw = ""
      filename = ""
      bundlePath = nil
      bundleFiles = []
      replaceConfirmed = false
      do {
        raw = try String(contentsOf: url.appendingPathComponent("manifest.json"), encoding: .utf8)
        filename = url.lastPathComponent + "/manifest.json"
        bundlePath = url.path
        bundleFiles = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
          .filter { !$0.hasPrefix(".") }.sorted() ?? []
        localError = nil
      } catch { localError = "Le dossier doit contenir un manifest.json valide. " + error.localizedDescription }
    }
  }

  private func validateFolder() {
    guard let bundlePath, canReview else { return }
    checkingFolder = true
    localError = nil
    let request: [String: Any] = [
      "action": "bundle-validate", "path": bundlePath,
      "expected_kind": expectedKind ?? manifestKind, "expected_id": manifestID,
    ]
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        _ = try HubBridge.call(request)
        DispatchQueue.main.async {
          checkingFolder = false
          step = 1
        }
      } catch {
        DispatchQueue.main.async {
          checkingFolder = false
          localError = error.localizedDescription
        }
      }
    }
  }

  private func importManifest(createInstance: Bool) {
    guard let manifest else { return }
    if existing && !replaceConfirmed {
      pendingCreateInstance = createInstance
      confirmReplace = true
      return
    }
    let action = bundlePath == nil ? "manifest-import" : "bundle-import"
    var payload: [String: Any] = ["create_instance": createInstance]
    if let bundlePath {
      payload["path"] = bundlePath
      payload["replace"] = replaceConfirmed
      payload["expected_kind"] = expectedKind ?? manifestKind
      payload["expected_id"] = manifestID
      if !folderOnly { payload["manifest"] = manifest }
    } else {
      payload["manifest"] = manifest
    }
    store.perform(
      action, payload: payload
    ) { success in
      if success {
        dismiss()
      } else {
        localError = store.error ?? "PiHub n’a pas pu importer ce manifeste. Vérifie les champs requis."
      }
    }
  }
}
