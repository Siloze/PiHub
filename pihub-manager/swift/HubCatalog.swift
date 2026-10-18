import AppKit
import SwiftUI

enum CatalogSheet: Identifiable {
  case detail(CatalogEntry)
  case guide
  case importJSON
  var id: String {
    switch self {
    case .detail(let entry): return "detail-" + entry.id
    case .guide: return "guide"
    case .importJSON: return "import-json"
    }
  }
}

struct CatalogWorkspace: View {
  @ObservedObject var store: HubStore
  var compact = false
  let edit: (HubInstance) -> Void
  var openInWindow: ((HubWindowAction) -> Void)?
  @State private var search = ""
  @State private var kind = "all"
  @State private var installedOnly = false
  @State private var sheet: CatalogSheet?
  private var entries: [CatalogEntry] {
    (store.snapshot?.catalog.entries ?? []).filter {
      (kind == "all" || $0.kind == kind)
        && (!installedOnly || isPresent($0))
        && (search.isEmpty
          || ($0.name + " " + $0.summary + " " + $0.repository).localizedCaseInsensitiveContains(
            search))
    }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 15 : 20) {
      WorkspaceSearch(text: $search, prompt: "Rechercher un runtime, un agent…")
      HStack {
        Picker("Catégorie", selection: $kind) {
          Text("Tout").tag("all")
          Text("Moteurs").tag("provider")
          Text("Agents").tag("agent")
        }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: compact ? .infinity : 280)
        Spacer(minLength: 10)
        Toggle("Présents", isOn: $installedOnly).toggleStyle(.button).controlSize(.small).help(
          "Instances configurées, JSON personnel ou runtime détecté")
      }
      HStack(spacing: 10) {
        Button { present(.catalogGuide) { sheet = .guide } } label: {
          Label("Guide pas à pas", systemImage: "map")
        }.buttonStyle(.plain).foregroundStyle(HubStyle.accent)
        Spacer()
        Button { present(.catalogImport) { sheet = .importJSON } } label: {
          Label("Importer une intégration", systemImage: "square.and.arrow.down")
        }.buttonStyle(.plain).foregroundStyle(HubStyle.muted)
      }.font(.system(size: compact ? 9 : 10, weight: .medium))
      if let jobs = store.snapshot?.catalog.jobs, !jobs.isEmpty {
        VStack(alignment: .leading, spacing: 12) {
          Eyebrow(title: "Installations")
          ForEach(Array(jobs.prefix(compact ? 2 : 3))) { job in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Image(
                  systemName: job.state == "done"
                    ? "checkmark.circle"
                    : job.state == "failed" ? "exclamationmark.circle" : "arrow.down.circle"
                ).foregroundStyle(job.state == "failed" ? Color.orange : HubStyle.muted)
                Text(job.name).font(.system(size: 11, weight: .medium))
                Spacer()
                if job.active {
                  Button {
                    store.perform("catalog-cancel", id: job.id)
                  } label: {
                    Text("Annuler").font(.system(size: 9))
                  }.buttonStyle(.plain).foregroundStyle(HubStyle.accent)
                }
                if job.state == "failed" || job.state == "cancelled" {
                  Button {
                    store.perform("catalog-dismiss", id: job.id)
                  } label: {
                    Image(systemName: "xmark.circle")
                  }.buttonStyle(.borderless).help("Effacer cette erreur résolue")
                }
                Button {
                  store.perform("catalog-log", id: job.id)
                } label: {
                  Image(systemName: "text.alignleft")
                }.buttonStyle(.borderless).help("Journal")
              }
              if job.active { ProgressView(value: job.progress) }
              Text(job.message).font(.system(size: 9)).foregroundStyle(
                job.state == "failed" ? Color.orange : HubStyle.muted
              ).lineLimit(2)
            }
          }
          Divider()
        }
      }
      ForEach(["provider", "agent"], id: \.self) { category in
        let group = entries.filter { $0.kind == category }
        if !group.isEmpty {
          VStack(alignment: .leading, spacing: 0) {
            HStack {
              Text(category == "provider" ? "Moteurs" : "Agents").font(
                .system(size: 12, weight: .semibold))
              Spacer()
              Text("\(group.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(
                HubStyle.muted)
            }.padding(.bottom, 9)
            ForEach(group) { entry in
              catalogRow(entry)
              Divider().overlay(HubStyle.line).padding(.leading, compact ? 29 : 39)
            }
          }
        }
      }
      if entries.isEmpty {
        Text("Aucun résultat.").font(.system(size: 11)).foregroundStyle(HubStyle.muted).padding(
          .vertical, 20)
      }
      HStack {
        Text("Templates JSON versionnés · runtimes installés séparément").font(.system(size: 9))
          .foregroundStyle(HubStyle.muted)
        Spacer()
        if !compact {
          Button("Extensions locales") { store.perform("reveal", id: "extensions") }.font(
            .system(size: 10))
        }
      }.padding(.top, 2)
      ForEach(store.snapshot?.catalog.errors ?? [], id: \.self) { error in
        Text(error).font(.system(size: 10)).foregroundStyle(.orange).textSelection(.enabled)
      }
    }.sheet(item: $sheet) { presentation in
      switch presentation {
      case .detail(let entry):
        CatalogDetail(store: store, entry: entry, compact: compact, edit: edit)
      case .guide:
        CatalogGuideView(store: store, compact: compact) {
          sheet = nil
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { sheet = .importJSON }
        }
      case .importJSON:
        ManifestImportView(store: store, expectedKind: nil, compact: compact)
      }
    }
  }
  private func catalogRow(_ entry: CatalogEntry) -> some View {
    let found = store.snapshot?.catalog.detected[entry.id]
    let templateInstalled = store.snapshot?.catalog.installed[entry.id] != nil
    let matchingInstance = matchingInstance(entry)
    return HStack(spacing: 8) {
      Button {
        present(.catalogDetail(entry.id)) { sheet = .detail(entry) }
      } label: {
        HStack(spacing: compact ? 11 : 16) {
          Image(systemName: entry.icon).font(.system(size: compact ? 16 : 22, weight: .regular))
            .foregroundStyle(HubStyle.muted).frame(width: compact ? 18 : 24)
          VStack(alignment: .leading, spacing: 5) {
            Text(entry.name).font(.system(size: compact ? 12 : 13, weight: .medium))
            Text(entry.summary).font(.system(size: compact ? 9 : 10)).foregroundStyle(
              HubStyle.muted
            )
            .lineLimit(1)
            HStack(spacing: 6) {
              statusText(
                found: found, templateInstalled: templateInstalled,
                entry: entry)
              if compact {
                Text("· " + shortReference(entry)).font(.system(size: 8, design: .monospaced))
                  .foregroundStyle(HubStyle.muted.opacity(0.75))
              }
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
          if !compact {
            VStack(alignment: .trailing, spacing: 5) {
              Text(shortReference(entry)).font(.system(size: 10, design: .monospaced))
              if let instance = matchingInstance {
                Text(store.setupLabel(instance)).font(.system(size: 9)).foregroundStyle(
                  store.setupLabel(instance).contains("configurer") || store.setupLabel(instance) == "Exécutable absent" ? .orange : HubStyle.muted
                ).lineLimit(1)
              }
            }.frame(width: 100, alignment: .trailing)
          }
          Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
            .foregroundStyle(HubStyle.muted.opacity(0.7)).frame(width: 12)
        }.contentShape(Rectangle()).padding(.vertical, compact ? 12 : 17)
      }.buttonStyle(.plain).help("Informations, installation et versions")
      if let instance = matchingInstance {
        Button {
          edit(instance)
        } label: {
          Image(systemName: "slider.horizontal.3").font(.system(size: 10, weight: .medium))
            .foregroundStyle(HubStyle.accent).frame(width: 25, height: 25)
            .background(HubStyle.accent.opacity(0.10), in: Circle())
        }.buttonStyle(.plain).help("Configurer cette instance")
      }
    }
  }
  private func present(_ action: HubWindowAction, local: () -> Void) {
    if compact, let openInWindow { openInWindow(action) } else { local() }
  }
  private func matchingInstance(_ entry: CatalogEntry) -> HubInstance? {
    let all = (store.snapshot?.config.providers ?? []) + (store.snapshot?.config.agents ?? [])
    return all.first { $0.adapter == entry.adapter }
  }
  private func isPresent(_ entry: CatalogEntry) -> Bool {
    store.snapshot?.catalog.templates[entry.id]?.source == "personal"
      || !(store.snapshot?.catalog.templates[entry.id]?.instances.isEmpty ?? true)
      || store.snapshot?.catalog.detected[entry.id] != nil
      || store.snapshot?.catalog.installed[entry.id] != nil
  }
  private func statusText(
    found: DetectedIntegration?, templateInstalled: Bool,
    entry: CatalogEntry
  ) -> some View {
    let template = store.snapshot?.catalog.templates[entry.id]
    let instance = matchingInstance(entry)
    let label: String
    let color: Color
    if let instance {
      let setup = store.setupLabel(instance)
      label =
        store.runtime(instance)?.ready == true
        ? "Instance · connectée"
        : setup == "Arrêté" ? "Instance · configurée" : "Instance · " + setup.lowercased()
      color = setup.contains("configurer") || setup == "Exécutable absent" ? .orange : .mint
    } else if template?.source == "personal" {
      label = "JSON personnel · sans instance"
      color = .mint
    } else if found != nil {
      label =
        found?.origin == "connected"
        ? "API connectée · template prêt" : "Runtime présent · template prêt"
      color = .mint
    } else if template?.available == true {
      label = "Template prêt · runtime absent"
      color = HubStyle.muted
    } else {
      label = entry.steps.isEmpty ? "Sans runtime" : "Runtime à installer"
      color = HubStyle.muted
    }
    return Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(color)
  }
  private func shortReference(_ entry: CatalogEntry) -> String {
    "ref · " + (entry.revision.count > 18 ? String(entry.revision.prefix(8)) : entry.revision)
  }
}

struct CatalogDetail: View {
  @ObservedObject var store: HubStore
  let entry: CatalogEntry
  var compact: Bool
  let edit: (HubInstance) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var revision = ""
  @State private var acknowledged = false
  @State private var confirm = false
  @State private var confirmUninstall = false
  @State private var showCommands = false
  private var different: Bool { !revision.isEmpty && revision != entry.revision }
  private var matchingInstance: HubInstance? {
    let all = (store.snapshot?.config.providers ?? []) + (store.snapshot?.config.agents ?? [])
    return all.first { $0.adapter == entry.adapter }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 14) {
        Image(systemName: entry.icon).font(.system(size: 30, weight: .light)).foregroundStyle(
          HubStyle.accent)
        VStack(alignment: .leading, spacing: 4) {
          Text(entry.name).font(.system(size: 23, weight: .semibold))
          Text(entry.kind == "agent" ? "AGENT · CATALOGUE" : "MOTEUR · CATALOGUE")
            .font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(HubStyle.muted)
        }
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark.circle.fill")
        }.buttonStyle(.plain)
      }.padding(22)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 19) {
          Text(entry.summary).font(.system(size: 13))
          if let url = URL(string: entry.repository), !entry.repository.isEmpty {
            Link(destination: url) {
              Label(
                entry.repository.replacingOccurrences(of: "https://github.com/", with: "")
                  .replacingOccurrences(of: ".git", with: ""), systemImage: "arrow.up.right.square"
              ).font(.system(size: 11))
            }
          }
          VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title: "Fichier de configuration")
            let template = store.snapshot?.catalog.templates[entry.id]
            Label(
              template?.source == "personal"
                ? "JSON personnel déjà présent"
                : template?.available == true
                  ? "Template livré avec PiHub" : "Template indisponible",
              systemImage: "doc.text"
            ).font(.system(size: 11, weight: .medium))
            if let instance = matchingInstance {
              Label("Instance : " + store.setupLabel(instance), systemImage: "slider.horizontal.3")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(
                  store.setupLabel(instance).contains("configurer") || store.setupLabel(instance) == "Exécutable absent" ? .orange : HubStyle.muted)
              Text("\(instance.name) · \(instance.id)").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(HubStyle.muted).textSelection(.enabled)
            } else {
              Text(
                "Aucune instance configurée. Ajoutez le template pour créer ses réglages locaux."
              )
              .font(.system(size: 10)).foregroundStyle(HubStyle.muted)
            }
            if let installed = store.snapshot?.catalog.installed[entry.id] {
              Label("Runtime PiHub · " + installed.revision, systemImage: "checkmark.circle")
                .font(.system(size: 10)).foregroundStyle(.mint)
            } else if store.snapshot?.catalog.detected[entry.id] != nil {
              Label(
                store.snapshot?.catalog.detected[entry.id]?.label ?? "Runtime détecté",
                systemImage: "checkmark.circle"
              )
              .font(.system(size: 10)).foregroundStyle(.mint)
            } else {
              Label("Runtime non détecté", systemImage: "circle.dashed")
                .font(.system(size: 10)).foregroundStyle(HubStyle.muted)
            }
            Eyebrow(title: "Référence du template")
            Text(entry.revision).font(.system(size: 11, design: .monospaced)).textSelection(
              .enabled)
            if let commit = entry.commit {
              Text("Commit : " + commit).font(.system(size: 9, design: .monospaced))
                .foregroundStyle(HubStyle.muted).textSelection(.enabled)
            }
            Text(
              entry.verification == "runtime-tested"
                ? "Handlers exercés avec un runtime local. L’installation neuve et les options dépendent des prérequis ci-dessous."
                : entry.verification == "source-reviewed"
                  ? "Recette basée sur les sources déclarées ; runtime non exercé sur ce Mac."
                  : "Intégration locale : version de référence fournie par son auteur."
            ).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
          }
          if let presence = store.snapshot?.catalog.detected[entry.id] {
            VStack(alignment: .leading, spacing: 8) {
              Label(presence.label, systemImage: "checkmark.circle").font(
                .system(size: 11, weight: .medium))
              if !presence.executable.isEmpty {
                Text(presence.executable).font(.system(size: 10, design: .monospaced))
                  .foregroundStyle(HubStyle.muted).textSelection(.enabled)
              }
              Text(
                presence.version.isEmpty
                  ? "Version non vérifiée. La présence du fichier exécutable ne garantit pas sa compatibilité avec cette recette."
                  : "Version enregistrée par PiHub : " + presence.version
              ).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
              Text(
                "Détection : chemin personnalisé d’une instance, reçu d’installation valide, puis candidats du manifeste / PATH. Une API sans runtime local est reconnue par son statut prêt."
              ).font(.system(size: 9)).foregroundStyle(HubStyle.muted)
            }
          }
          if !entry.steps.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Eyebrow(title: "Prérequis")
              Text(
                entry.prerequisites.isEmpty
                  ? "Aucun gestionnaire de paquets requis."
                  : entry.prerequisites.joined(separator: " · ")
              ).font(.system(size: 11, design: .monospaced))
              if let version = entry.min_macos {
                Text("macOS \(version)+ · Apple Silicon").font(.system(size: 10)).foregroundStyle(
                  .orange)
              }
              Text(
                "Installation dans .pihub/packages. Aucun sudo, aucun lancement automatique et aucun modèle téléchargé par PiHub. Les dépendances tierces peuvent nécessiter du réseau et de l’espace disque."
              ).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
            }
            if entry.allow_revision == true {
              VStack(alignment: .leading, spacing: 8) {
                Text("Version / révision à installer").font(.system(size: 11, weight: .medium))
                TextField(entry.revision, text: $revision).textFieldStyle(.roundedBorder).font(
                  .system(size: 11, design: .monospaced))
                if different {
                  Label(
                    "Révision hors référence : les commandes et handlers peuvent être incompatibles.",
                    systemImage: "exclamationmark.triangle"
                  ).font(.system(size: 10)).foregroundStyle(.orange)
                  Toggle("J’accepte ce risque de compatibilité", isOn: $acknowledged).font(
                    .system(size: 10))
                }
              }
            }
            DisclosureGroup("Voir les étapes et commandes", isExpanded: $showCommands) {
              VStack(alignment: .leading, spacing: 15) {
                ForEach(Array(entry.steps.enumerated()), id: \.offset) { index, step in
                  VStack(alignment: .leading, spacing: 5) {
                    Text("\(index + 1). " + step.label).font(.system(size: 11, weight: .medium))
                    Text(step.argv?.joined(separator: " ") ?? step.download ?? "").font(
                      .system(size: 9, design: .monospaced)
                    ).foregroundStyle(HubStyle.muted).textSelection(.enabled)
                    if let hash = step.sha256 {
                      Text("SHA-256 " + hash).font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(HubStyle.muted).textSelection(.enabled)
                    }
                  }
                }
              }.padding(.top, 10)
            }.font(.system(size: 11))
          }
          Text(
            "Ajouter une instance crée uniquement la configuration locale. Installer ou mettre à jour prépare le runtime déclaré par cette recette ; l’exécutable est ensuite renseigné dans l’instance."
          ).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
          if let error = store.error {
            Text(error).font(.system(size: 10)).foregroundStyle(.orange).textSelection(.enabled)
          }
        }.padding(22)
      }
      Divider()
      HStack {
        Button("Exporter le dossier") { store.perform("catalog-export", id: entry.id) }
        Spacer()
        if let instance = matchingInstance {
          Button("Configurer") {
            dismiss()
            edit(instance)
          }
        } else {
          Button("Ajouter une instance") {
            store.perform("catalog-template", id: entry.id) { if $0 { dismiss() } }
          }
        }
        if !entry.steps.isEmpty {
          let installed = store.snapshot?.catalog.installed[entry.id]
          let action =
            installed == nil
            ? "Installer…"
            : installed?.revision == entry.revision ? "Réinstaller…" : "Mettre à jour…"
          Button(action) { confirm = true }
            .buttonStyle(.borderedProminent).disabled(different && !acknowledged)
        }
        if matchingInstance == nil, store.snapshot?.catalog.installed[entry.id] != nil {
          Button("Désinstaller") { confirmUninstall = true }.foregroundStyle(.orange)
        }
      }.controlSize(.small).padding(18).disabled(store.busy)
    }.frame(width: compact ? 395 : 620, height: compact ? 500 : 670).background(HubStyle.background)
      .preferredColorScheme(.dark).tint(HubStyle.accent)
      .onAppear { revision = entry.revision }
      .onChange(of: revision) { _ in acknowledged = false }
      .confirmationDialog(
        "Installer ou mettre à jour \(entry.name) depuis sa source déclarée ? Les étapes affichées exécutent du code tiers et téléchargent ses dépendances.",
        isPresented: $confirm
      ) {
        Button("Confirmer l’installation") {
          store.perform(
            "catalog-install", id: entry.id,
            payload: [
              "confirmed": true, "revision": revision, "acknowledge_unverified": acknowledged,
            ]
          ) { if $0 { dismiss() } }
        }
      }
      .confirmationDialog(
        "Supprimer les fichiers runtime installés par PiHub pour \(entry.name) ? Cette action est disponible sans instance configurée.",
        isPresented: $confirmUninstall
      ) {
        Button("Supprimer le runtime PiHub", role: .destructive) {
          store.perform("catalog-delete-installation", id: entry.id)
        }
      }
  }
}

private struct GuideStep {
  let eyebrow: String
  let title: String
  let detail: String
  let icon: String
  let points: [(String, String)]
}

struct CatalogGuideView: View {
  @ObservedObject var store: HubStore
  var compact = false
  let importJSON: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var page = 0

  private let steps: [GuideStep] = [
    GuideStep(
      eyebrow: "01 · CHOISIR SON PARCOURS",
      title: "JSON et exécutable, deux choses distinctes",
      detail: "Le manifeste décrit à PiHub comment présenter et piloter une intégration. Le runtime est le programme réel qui tourne sur votre Mac ou un service déjà accessible sur le réseau.",
      icon: "point.3.connected.trianglepath.dotted",
      points: [
        ("Template PiHub", "Recette prête dans le catalogue ; ajoutez une instance puis configurez-la."),
        ("Votre exécutable", "Importez le JSON puis indiquez le chemin de votre binaire dans l’instance."),
        ("Votre intégration", "Importez ou écrivez un manifeste JSON personnalisé, sans installer de runtime."),
      ]),
    GuideStep(
      eyebrow: "02 · TEMPLATE + RUNTIME",
      title: "Installer la recette, puis le runtime si besoin",
      detail: "Dans une fiche du catalogue, “Ajouter une instance” crée seulement la configuration locale. “Installer” exécute les étapes de la recette PiHub après confirmation ; aucun serveur n’est lancé automatiquement.",
      icon: "shippingbox",
      points: [
        ("Runtime déjà détecté", "Configurez l’instance existante ; PiHub recherche le chemin personnalisé, les candidats du manifeste et le PATH."),
        ("Runtime absent", "Installez-le depuis sa fiche si une recette est disponible, ou fournissez votre propre exécutable."),
        ("Après installation", "Retournez dans Moteurs/Agents → Configurer pour vérifier le chemin, le port et le modèle."),
      ]),
    GuideStep(
      eyebrow: "03 · EXÉCUTABLE PERSONNEL",
      title: "Le chemin personnalisé prend la priorité",
      detail: "Chaque instance conserve ses propres réglages. Renseigner son exécutable ne modifie pas le template partagé et permet d’utiliser une build ou une installation atypique.",
      icon: "terminal",
      points: [
        ("Où le saisir", "Moteur ou Agent → Configurer → section Exécutable / intégration et lancement."),
        ("Quel format", "Chemin absolu vers le binaire, par exemple /opt/homebrew/bin/llama-server."),
        ("Candidats", "Ce sont des suggestions de détection (PATH, chemins connus, manifeste), pas votre chemin personnalisé."),
      ]),
    GuideStep(
      eyebrow: "04 · MANIFESTE JSON",
      title: "Décrivez seulement ce que votre intégration sait faire",
      detail: "Le squelette dans l’importateur est le méta-modèle de départ. Les champs créent les réglages, la commande lance le runtime, et les handlers ajoutent des capacités spécifiques. Les handlers sont optionnels.",
      icon: "curlybraces",
      points: [
        ("Essentiels", "api_version, id unique, kind (provider/agent), name et description. Dans l’interface, provider est appelé moteur."),
        ("Lancement", "executables et command ; utilisez {executable}, {port} et les clés de settings dans les arguments."),
        ("Réglages / actions", "Chaque intégration est un dossier : manifest.json décrit les réglages, les handlers et la recette install optionnelle. Les fichiers Python sont fournis dans le même dossier."),
      ]),
    GuideStep(
      eyebrow: "05 · IMPORTER ET CONFIGURER",
      title: "Validez avant d’enregistrer",
      detail: "L’import lit un fichier ou le texte collé, vérifie l’objet et son type, puis le backend valide le manifeste complet. Il n’exécute pas la commande déclarée.",
      icon: "checkmark.seal",
      points: [
        ("Importer seulement", "Ajoute la définition JSON ; vous pourrez créer une instance plus tard."),
        ("Importer et configurer", "Crée aussi une instance vide et ouvre directement ses réglages."),
        ("Même identifiant", "PiHub demande confirmation et sauvegarde le JSON personnel précédent avant remplacement."),
      ]),
  ]

  var body: some View {
    let current = steps[page]
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("EXPLORER · GUIDE").font(.system(size: 8, weight: .semibold)).tracking(1.1)
            .foregroundStyle(HubStyle.accent)
          Text("Connecter une intégration").font(.system(size: 18, weight: .semibold))
        }
        Spacer()
        Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
          .buttonStyle(.plain).foregroundStyle(HubStyle.muted)
      }.padding(20)
      Divider()
      VStack(alignment: .leading, spacing: 17) {
        HStack(spacing: 5) {
          ForEach(steps.indices, id: \.self) { index in
            Capsule().fill(index == page ? HubStyle.accent : HubStyle.line)
              .frame(height: 3).onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { page = index } }
          }
          Text("\(page + 1) / \(steps.count)").font(.system(size: 8, design: .monospaced))
            .foregroundStyle(HubStyle.muted).fixedSize().padding(.leading, 6)
        }
        HStack(alignment: .top, spacing: 13) {
          Image(systemName: current.icon).font(.system(size: 20, weight: .medium))
            .foregroundStyle(HubStyle.accent).frame(width: 42, height: 42)
            .background(HubStyle.accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
          VStack(alignment: .leading, spacing: 7) {
            Text(current.eyebrow).font(.system(size: 8, weight: .semibold)).tracking(0.7)
              .foregroundStyle(HubStyle.muted)
            Text(current.title).font(.system(size: 16, weight: .semibold))
          }
        }
        Text(current.detail).font(.system(size: 10)).foregroundStyle(HubStyle.muted)
          .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(current.points.enumerated()), id: \.offset) { index, point in
            HStack(alignment: .top, spacing: 11) {
              Text(String(format: "%02d", index + 1)).font(.system(size: 9, design: .monospaced))
                .foregroundStyle(HubStyle.accent).frame(width: 22, alignment: .leading).padding(.top, 1)
              VStack(alignment: .leading, spacing: 4) {
                Text(point.0).font(.system(size: 10, weight: .semibold))
                Text(point.1).font(.system(size: 9)).foregroundStyle(HubStyle.muted)
                  .fixedSize(horizontal: false, vertical: true)
              }
              Spacer(minLength: 0)
            }.padding(.vertical, 11)
            if index < current.points.count - 1 { Divider().overlay(HubStyle.line).padding(.leading, 33) }
          }
        }.padding(.horizontal, 13).background(HubStyle.panel, in: RoundedRectangle(cornerRadius: 12))
        if let error = store.error {
          Text(error).font(.system(size: 9)).foregroundStyle(.orange).textSelection(.enabled)
        }
        Spacer(minLength: 0)
        HStack {
          Button("Importer mon JSON", systemImage: "square.and.arrow.down") {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { importJSON() }
          }.buttonStyle(.plain).font(.system(size: 9, weight: .medium)).foregroundStyle(HubStyle.accent)
          Spacer()
          Button { withAnimation(.easeInOut(duration: 0.18)) { page = max(0, page - 1) } } label: {
            Image(systemName: "chevron.left").frame(width: 26, height: 25)
          }.buttonStyle(.plain).disabled(page == 0).foregroundStyle(page == 0 ? HubStyle.line : HubStyle.muted)
          Button(page == steps.count - 1 ? "Terminé" : "Suivant") {
            if page == steps.count - 1 { dismiss() }
            else { withAnimation(.easeInOut(duration: 0.18)) { page += 1 } }
          }.buttonStyle(.borderedProminent).controlSize(.small)
        }
      }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }.frame(width: compact ? 395 : 620, height: compact ? 510 : 660)
      .background(HubStyle.background).foregroundStyle(.white.opacity(0.92))
      .preferredColorScheme(.dark).tint(HubStyle.accent)
  }
}
