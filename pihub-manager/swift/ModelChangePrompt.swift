import SwiftUI

struct ModelChangePrompt: View {
    @ObservedObject var store: HubStore
    let plan: ProviderModelChange
    var configureProvider: () -> Void
    @State private var expanded = true
    @State private var confirmation: Confirmation?
    @State private var selection: Set<String> = []
    private var eligible: [AffectedAgent] { plan.agents.filter(\.needs_action) }
    private var selectedNeedsWarning: Bool {
        eligible.contains { selection.contains($0.id) && $0.uncertain }
    }

    private enum Confirmation: Equatable {
        case agents
        case provider
        case providerAndAgents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(HubStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.provider_name + " · nouveau modèle").font(.system(size: 11, weight: .semibold))
                    Text(plan.after).font(.system(size: 8, design: .monospaced)).foregroundStyle(HubStyle.muted).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.up" : "chevron.down") }.buttonStyle(.plain)
            }
            if expanded {
                if plan.provider_restart_available {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: plan.provider_restart_uncertain ? "exclamationmark.triangle" : "arrow.clockwise")
                            .foregroundStyle(plan.provider_restart_uncertain ? .orange : HubStyle.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.provider_name).font(.system(size: 10, weight: .medium))
                            Text(plan.provider_restart_reason).font(.system(size: 9)).foregroundStyle(plan.provider_restart_uncertain ? .orange : HubStyle.muted)
                        }
                    }
                    Divider()
                }
                ForEach(plan.agents) { agent in
                    HStack(alignment: .top, spacing: 7) {
                        if agent.needs_action {
                            Toggle("", isOn: Binding(get: { selection.contains(agent.id) }, set: { if $0 { selection.insert(agent.id) } else { selection.remove(agent.id) } })).labelsHidden().toggleStyle(.checkbox)
                        } else { Image(systemName: agent.pinned ? "pin" : "info.circle").foregroundStyle(HubStyle.muted) }
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(agent.name).font(.system(size: 10, weight: .medium))
                                if agent.uncertain { Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8)).foregroundStyle(.orange).help("Exécutable personnalisé : le redémarrage peut échouer.") }
                            }
                            Text(agent.uncertain && agent.needs_action ? agent.reason + " La relance de cet exécutable personnalisé n’est pas garantie." : agent.reason).font(.system(size: 9)).foregroundStyle(agent.uncertain && agent.needs_action ? .orange : HubStyle.muted)
                        }
                    }
                }
            }
            if !plan.provider_ready {
                Text("Chargez d’abord ce modèle sur le moteur. Les agents restent actifs.").font(.system(size: 9)).foregroundStyle(.orange)
            }
            HStack(spacing: 9) {
                if plan.provider_restart_available {
                    Button(plan.provider_restart_uncertain ? "Tenter le moteur seul" : "Relancer seulement le moteur") {
                        confirmation = .provider
                    }.disabled(store.busy)
                    if !eligible.isEmpty {
                        Button("Moteur + \(selection.count) agent(s)") { confirmation = .providerAndAgents }
                            .disabled(selection.isEmpty || store.busy)
                            .buttonStyle(.borderedProminent)
                    }
                } else if !eligible.isEmpty {
                    Button(selectedNeedsWarning ? "Tenter la relance de \(selection.count) agent(s)" : "Mettre à jour \(selection.count) agent(s)") { confirmation = .agents }.disabled(!plan.provider_ready || selection.isEmpty || store.busy).buttonStyle(.borderedProminent)
                } else { Text("Aucune relance automatique nécessaire / disponible.").font(.system(size: 9)).foregroundStyle(HubStyle.muted) }
                if !plan.provider_ready { Button("Moteur…", action: configureProvider) }
                Spacer(minLength: 0)
                Button("Ignorer") { store.perform("dismiss-model-change", id: plan.id) }.buttonStyle(.plain).foregroundStyle(HubStyle.muted)
            }.font(.system(size: 9)).controlSize(.mini)
        }.padding(12).background(HubStyle.accent.opacity(0.075)).overlay(alignment: .leading) { Rectangle().fill(HubStyle.accent.opacity(0.6)).frame(width: 2) }
        .onAppear { selection = Set(eligible.map(\.id)) }
        .confirmationDialog(
            confirmation == .provider ? "Relancer le moteur ?" : confirmation == .providerAndAgents ? "Relancer le moteur et les agents liés ?" : "Appliquer le modèle aux agents sélectionnés ?",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            titleVisibility: .visible
        ) {
            if confirmation == .provider {
                Button("Confirmer la relance du moteur", role: .destructive) {
                    store.perform("apply-model-change", id: plan.id, payload: ["restart_provider": true, "confirm_uncertain": plan.provider_restart_uncertain])
                }
            } else if confirmation == .providerAndAgents {
                Button("Relancer le moteur puis \(selection.count) agent(s)", role: .destructive) {
                    store.perform("apply-model-change", id: plan.id, payload: [
                        "restart_provider": true,
                        "agents": Array(selection),
                        "confirm_uncertain": plan.provider_restart_uncertain || selectedNeedsWarning,
                    ])
                }
            } else {
                Button("Appliquer aux \(selection.count) agent(s)") {
                    store.perform("apply-model-change", id: plan.id, payload: ["agents": Array(selection), "confirm_uncertain": selectedNeedsWarning])
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            if confirmation == .provider {
                Text(plan.provider_restart_uncertain
                     ? "PiHub va tenter d’arrêter puis de relancer le processus externe/personnalisé. Il peut ne pas répondre à la commande ou ne pas reprendre le nouveau modèle. Vérifiez son état avant de relancer les agents."
                     : "Le processus du moteur va être arrêté puis relancé. Vérifiez qu’il sert le nouveau modèle avant de relancer les agents.")
            } else if confirmation == .providerAndAgents {
                Text(plan.provider_restart_uncertain || selectedNeedsWarning
                     ? "PiHub va d’abord tenter de relancer le moteur, attendre que le nouveau modèle soit prêt, puis appeler le handler de chaque agent sélectionné. Un exécutable personnalisé peut refuser la relance ; aucun agent ne sera arrêté tant que le moteur n’est pas prêt."
                     : "PiHub relance d’abord le moteur et attend qu’il serve le nouveau modèle. Il appelle ensuite le handler propre à chaque agent sélectionné ; les agents non sélectionnés ne seront pas modifiés.")
            } else {
                Text(selectedNeedsWarning
                     ? "PiHub va fermer les sessions actives et tenter de les rouvrir avec leur exécutable personnalisé. Cette commande peut échouer. Les autres agents ne seront pas affectés."
                     : "La relance ferme les sessions actives sélectionnées et les rouvre avec le nouveau modèle. Aucun agent non sélectionné ou à modèle fixé ne sera modifié.")
            }
        }
    }
}
