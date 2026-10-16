import AppKit
import Foundation
import SwiftUI

struct HubField: Codable, Identifiable {
  let key: String
  let label: String
  let group: String
  let type: String
  let `default`: String
  let options: [String]?
  let option_help: [String: String]?
  let min: Double?
  let max: Double?
  let step: Double?
  var id: String { key }
}

struct HubAdapter: Codable, Identifiable {
  let id: String
  let kind: String
  let name: String
  let icon: String
  let color: String
  let description: String
  let fields: [HubField]
  let source: String
  let external: Bool?
  let modes: [String]?
  let model_format: String?
  let action_labels: [String: String]?
  let primary_actions: [String]?
  let editor_hints: [String: String]?
  let routing: IntegrationRouting?
  let model_field: String?
  let log_channels: [String: String]?
  let executables: [String]?
  let command: [String]?
  let env: [String: String]?
  let requires_model: Bool?
  var tint: Color {
    switch color {
    case "orange": return .orange
    case "cyan": return .cyan
    case "mint": return .mint
    case "blue": return .blue
    default: return Color(red: 0.63, green: 0.53, blue: 1)
    }
  }
}

struct IntegrationOnboarding: Codable, Identifiable {
  let title: String
  let message: String
  let steps: [String]
  let action: String?
  let action_label: String?
  var id: String { title }
}

struct IntegrationRouting: Codable {
  let provider_field: String
  let model_field: String?
  let required: Bool?
  let unbound_value: String?
  let unbound_label: String?
}

struct HubInstance: Codable, Identifiable, Equatable {
  var id: String
  var adapter: String
  var name: String
  var settings: [String: String]
}

struct HubModel: Codable, Identifiable {
  var id: String
  var name: String
  var format: String
  var path: String
  var size: Double
  var source: String
}

struct HubConfiguration: Codable {
  var version: Int
  var providers: [HubInstance]
  var agents: [HubInstance]
  var models: [HubModel]
  var settings: [String: String]
}

struct HubRuntime: Codable, Identifiable {
  var id: String
  var state: String
  var ready: Bool
  var managed: Bool
  var cpu: Double
  var memory: Double
  var gpu: Double?
  var pid: Int
  var uptime: String
  var latency: Double
  var model: String
  var error: String
  var endpoint: String
  var models: [String]
  var gateway_initialized: Bool?
  var label: String {
    if state == "ready" { return managed ? "Prêt" : "Connecté · externe" }
    if state == "running" { return "En session" }
    if state == "loading" { return "Démarrage" }
    if state == "failed" { return "Échec · voir journal" }
    if state == "unavailable" { return "Statut non disponible" }
    return "Arrêté"
  }
}

struct HubEvent: Codable, Identifiable {
  let id: String
  let time: String
  let action: String
  let name: String
  let detail: String
}
struct HubHost: Codable {
  let name: String
  let cores: Int
  let memory: Double
}
struct HubSnapshot: Codable {
  var config: HubConfiguration
  var catalog: IntegrationCatalog
  var gpu: GPUMetrics
  var model_bindings: [String: [ModelBinding]]
  var registry: [HubAdapter]
  var registry_errors: [String]
  var providers: [HubRuntime]
  var agents: [HubRuntime]
  var models: [HubModel]
  var availability: [String: String]
  var capabilities: [String: [String]]
  var model_changes: [ProviderModelChange]
  var events: [HubEvent]
  var root: String
  var data: String
  var host: HubHost
  var timestamp: Double
}

struct ModelBinding: Codable, Identifiable {
  let id: String
  let name: String
  let kind: String
  let configured: Bool
  let active: Bool
  let via: String
}

struct GPUMetrics: Codable {
  let usage: Double?
  let memory: Double?
  let name: String
  let source: String
  let scope: String
}

struct RecipeStep: Codable {
  let label: String
  let argv: [String]?
  let download: String?
  let sha256: String?
}
struct CatalogEntry: Codable, Identifiable {
  let id: String
  let adapter: String
  let kind: String
  let name: String
  let icon: String
  let color: String
  let summary: String
  let repository: String
  let revision: String
  let commit: String?
  let verification: String
  let allow_revision: Bool?
  let prerequisites: [String]
  let min_macos: Int?
  let steps: [RecipeStep]
}
struct InstallJob: Codable, Identifiable {
  let id: String
  let entry_id: String
  let name: String
  let revision: String
  let state: String
  let progress: Double
  let message: String
  var active: Bool { state == "queued" || state == "running" }
}
struct InstalledIntegration: Codable {
  let revision: String
  let resolved_revision: String
  let executable: String
}
struct IntegrationCatalog: Codable {
  let entries: [CatalogEntry]
  let errors: [String]
  let jobs: [InstallJob]
  let installed: [String: InstalledIntegration]
  let detected: [String: DetectedIntegration]
  let templates: [String: CatalogTemplateState]
}

struct CatalogTemplateState: Codable {
  let available: Bool
  let source: String
  let instances: [String]
}

struct DetectedIntegration: Codable {
  let executable: String
  let origin: String
  let instances: [String]
  let version: String
  var label: String {
    switch origin {
    case "pihub": return "Installé par PiHub"
    case "connected": return "API connectée"
    default: return "Détecté sur ce Mac"
    }
  }
}

struct AffectedAgent: Codable, Identifiable {
  let id: String
  let name: String
  let active: Bool
  let pinned: Bool
  let action: String
  let reason: String
  let needs_action: Bool
  let uncertain: Bool
}
struct ProviderModelChange: Codable, Identifiable {
  let id: String
  let provider_id: String
  let provider_name: String
  let before: String
  let after: String
  let provider_ready: Bool
  let provider_restart_available: Bool
  let provider_restart_uncertain: Bool
  let provider_restart_reason: String
  let agents: [AffectedAgent]
}

struct ResourceSample: Identifiable {
  let id = UUID()
  let date: Date
  let memory: Double
  let cpu: Double
  let gpu: Double?
}

enum HubBridge {
  static let root: String =
    ProcessInfo.processInfo.environment["PIHUB_ROOT"]
    ?? Bundle.main.bundleURL.deletingLastPathComponent().path
  static var source: String {
    let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/backend").path
    return FileManager.default.fileExists(atPath: bundled) ? bundled : root + "/pihub-manager/src"
  }
  static func call(_ request: [String: Any]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = ["-m", "pihub_manager.hub"]
    var environment = ProcessInfo.processInfo.environment
    environment["PIHUB_ROOT"] = root
    environment["PYTHONPATH"] = source
    environment["PATH"] =
      "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
    process.environment = environment
    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    input.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: request))
    try input.fileHandleForWriting.close()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      let error =
        String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw NSError(
        domain: "PiHub", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: String(error.suffix(1500)).isEmpty
            ? "Réponse du backend invalide." : String(error.suffix(1500))
        ])
    }
    guard response["ok"] as? Bool == true else {
      throw NSError(
        domain: "PiHub", code: 2,
        userInfo: [
          NSLocalizedDescriptionKey: response["error"] as? String ?? "Opération impossible."
        ])
    }
    return try JSONSerialization.data(withJSONObject: response["data"] ?? [:])
  }
  static func object<T: Encodable>(_ value: T) -> Any {
    (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value))) ?? [:]
  }
}

final class HubStore: ObservableObject {
  @Published var snapshot: HubSnapshot?
  @Published var page = "dashboard"
  @Published var inspectID: String?
  @Published var requestedImportKind: String?
  @Published var search = ""
  @Published var busy = false
  @Published var refreshing = false
  @Published var error: String?
  @Published var notice: String?
  @Published var samples: [ResourceSample] = []
  @Published var logText = ""
  @Published var showingLog = false
  @Published var focusExecutableID: String?
  @Published var onboardingGuide: IntegrationOnboarding?
  var statusChanged: ((Int) -> Void)?
  var inspectRequested: (() -> Void)?
  private var pendingInspectID: String?
  private let queue = DispatchQueue(label: "org.pihub.backend", qos: .utility)

  func adapter(_ item: HubInstance) -> HubAdapter? {
    snapshot?.registry.first { $0.id == item.adapter }
  }
  func can(_ item: HubInstance, _ action: String) -> Bool {
    snapshot?.capabilities[item.id]?.contains(action) == true
  }
  func runtime(_ item: HubInstance) -> HubRuntime? {
    (snapshot?.providers ?? []).first { $0.id == item.id }
      ?? snapshot?.agents.first { $0.id == item.id }
  }
  func isActive(_ item: HubInstance) -> Bool {
    guard let state = runtime(item) else { return false }
    return state.ready || state.state == "running" || state.state == "loading"
      || (state.managed && state.pid > 0)
  }
  func setupLabel(_ item: HubInstance) -> String {
    guard let integration = adapter(item) else { return "Intégration absente" }
    if runtime(item)?.state == "failed" { return "Échec" }
    if !(integration.executables ?? []).isEmpty && (snapshot?.availability[item.id] ?? "").isEmpty {
      return "Exécutable absent"
    }
    if integration.routing?.required == true && provider(for: item) == nil {
      return "Provider à choisir"
    }
    if integration.kind == "provider", integration.external != true,
      integration.requires_model != false,
      integration.fields.contains(where: { $0.key == (integration.model_field ?? "model") }),
      (item.settings[integration.model_field ?? "model"] ?? "").isEmpty
    {
      return "Modèle à choisir"
    }
    if integration.external == true && runtime(item)?.ready != true { return "À connecter" }
    return "Arrêté"
  }
  func provider(for item: HubInstance) -> HubInstance? {
    guard let field = adapter(item)?.routing?.provider_field, let id = item.settings[field] else {
      return nil
    }
    return snapshot?.config.providers.first { $0.id == id }
  }
  func linkedAgents(_ provider: HubInstance) -> [HubInstance] {
    (snapshot?.config.agents ?? []).filter { self.provider(for: $0)?.id == provider.id }
      .sorted { (isActive($0) ? 0 : 1) < (isActive($1) ? 0 : 1) }
  }
  func refresh() {
    guard !refreshing, !busy else { return }
    refreshing = true
    queue.async {
      do {
        let data = try HubBridge.call(["action": "snapshot"])
        let next = try JSONDecoder().decode(HubSnapshot.self, from: data)
        DispatchQueue.main.async {
          self.accept(next)
          self.refreshing = false
        }
      } catch {
        DispatchQueue.main.async {
          self.error = error.localizedDescription
          self.refreshing = false
        }
      }
    }
  }
  private func accept(_ next: HubSnapshot) {
    snapshot = next
    if let id = pendingInspectID,
      (next.config.providers + next.config.agents).contains(where: { $0.id == id })
    {
      pendingInspectID = nil
      inspectRequested?()
      DispatchQueue.main.async { [weak self] in self?.inspectID = id }
    }
    let resources = next.providers + next.agents
    samples.append(
      ResourceSample(
        date: Date(), memory: resources.reduce(0) { $0 + $1.memory } / 1024,
        cpu: resources.reduce(0) { $0 + $1.cpu }, gpu: next.gpu.usage))
    samples = Array(samples.suffix(90))
    statusChanged?(next.providers.filter(\.ready).count)
  }
  func perform(
    _ action: String, id: String = "", payload: [String: Any] = [:],
    completion: ((Bool) -> Void)? = nil
  ) {
    guard !busy else { return }
    busy = true
    error = nil
    notice = nil
    var request = payload
    request["action"] = action
    request["id"] = id
    let captured = request
    queue.async {
      do {
        let data = try HubBridge.call(captured)
        let response = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = response?["message"] as? String ?? "Terminé"
        let guide = action == "save" ? (response?["onboarding"] as? [String: Any]).flatMap {
          try? JSONDecoder().decode(IntegrationOnboarding.self, from: JSONSerialization.data(withJSONObject: $0))
        } : nil
        DispatchQueue.main.async {
          self.busy = false
          if action == "save" { self.onboardingGuide = guide }
          if ["manifest-import", "bundle-import"].contains(action), let instanceID = response?["instance_id"] as? String {
            self.pendingInspectID = instanceID
          }
          if action == "logs" || action == "preview" || action == "catalog-log" {
            self.logText = message
            self.showingLog = true
          } else {
            self.notice = message
          }
          completion?(true)
          self.refresh()
        }
      } catch {
        DispatchQueue.main.async {
          self.busy = false
          self.error = error.localizedDescription
          completion?(false)
        }
      }
    }
  }
}
