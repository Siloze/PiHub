import SwiftUI

/// Additional actions come from the manifest; the UI knows no integration names.
struct IntegrationActions: View {
    @ObservedObject var store: HubStore
    let item: HubInstance
    private var actions: [String] {
        let primary = Set(store.adapter(item)?.primary_actions ?? [])
        return (store.snapshot?.capabilities[item.id] ?? []).filter { !primary.contains($0) }.sorted()
    }
    private func label(_ action: String) -> String {
        store.adapter(item)?.action_labels?[action] ?? ["start": "Démarrer", "stop": "Arrêter", "terminal": "Ouvrir le terminal", "web": "Ouvrir le Web UI", "logs": "Lire le journal", "test": "Tester la connexion", "restart": "Redémarrer", "preview": "Voir la commande", "adopt": "Prendre en charge", "load": "Charger le modèle", "unload": "Libérer le modèle", "set_model": "Préparer le modèle actuel", "stop-web": "Arrêter le Web UI"][action] ?? action
    }
    var body: some View {
        if !actions.isEmpty {
            Menu { ForEach(actions, id: \.self) { action in Button(label(action)) { store.perform(action, id: item.id) } } } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 18).help("Actions de l’intégration")
        }
    }
}
