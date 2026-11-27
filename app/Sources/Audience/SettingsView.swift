#if os(macOS)
import SwiftUI

struct SettingsView: View {
    @Bindable var store: LibraryStore
    @AppStorage("appearance") private var appearance = "system"
    @State private var email = SavedCredentials.email
    @State private var password = ""
    @AppStorage("settingsTab") private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            Tab("Général", systemImage: "gearshape", value: 0) {
                Form {
                    Picker("Apparence", selection: $appearance) {
                        Text("Système").tag("system"); Text("Claire").tag("light"); Text("Sombre").tag("dark")
                    }
                    Section("Sauvegardes") {
                        Text("Les questionnaires sont enregistrés automatiquement sur cet appareil.").foregroundStyle(.secondary)
                        HStack {
                            Button("Importer…") { store.importing = true }
                            Button("Tout exporter…") { store.exportBackup() }
                        }
                        Button("Afficher les données dans le Finder", action: store.revealData)
                    }
                }.formStyle(.grouped)
            }
            Tab("Compte", systemImage: "person.crop.circle", value: 1) {
                Form {
                    Section("Compte Audience") {
                        if store.connected {
                            LabeledContent("Compte", value: store.accountName)
                            Button("Se déconnecter") {
                                Task { await store.disconnect(); password = "" }
                            }.disabled(store.liveCode != nil || store.busy || store.syncing)
                        } else {
                            TextField("Adresse e-mail", text: $email).textContentType(.username).disabled(store.busy)
                            SecureField("Mot de passe", text: $password).textContentType(.password).disabled(store.busy)
                                .onSubmit(connect)
                            HStack {
                                Button("Se connecter", action: connect)
                                    .keyboardShortcut(.defaultAction)
                                    .disabled(store.busy || email.isEmpty || password.isEmpty)
                                if store.busy { ProgressView().controlSize(.small) }
                            }
                            if store.savedLoginPending {
                                Button("Réessayer la connexion enregistrée") { Task { await store.connectSaved() } }
                                    .disabled(store.busy)
                            }
                        }
                    }
                    if store.connected {
                        Section("Synchronisation") {
                            HStack {
                                if store.syncing { ProgressView().controlSize(.small) }
                                Label(store.syncStatus, systemImage: store.syncError == nil ? "arrow.triangle.2.circlepath" : "exclamationmark.icloud")
                            }
                            if let date = store.lastSyncAt {
                                LabeledContent("Dernière synchronisation") { Text(date, style: .time) }
                            }
                            Button("Synchroniser maintenant") { Task { await store.synchronize(showErrors: true) } }
                                .disabled(store.syncing || store.busy || store.liveCode != nil)
                            if let message = store.syncError {
                                Text(message).font(.caption).foregroundStyle(.red).lineLimit(4).textSelection(.enabled)
                            }
                        }
                    }
                }.formStyle(.grouped)
            }
            Tab("Assistants IA", systemImage: "sparkles", value: 3) {
                AIAssistantsMacView()
            }
            Tab("Modèles locaux", systemImage: "internaldrive", value: 2) {
                LocalModelsView()
            }
        }
        .frame(width: 640, height: tab == 2 || tab == 3 ? 680 : 470)
    }
    private func connect() {
        guard !store.busy, !email.isEmpty, !password.isEmpty else { return }
        Task {
            await store.connect(email: email, password: password)
            if store.connected { password = "" }
        }
    }
}

#endif
