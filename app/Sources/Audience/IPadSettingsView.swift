#if os(iOS)
import SwiftUI

struct IPadSettingsView: View {
    @Bindable var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"
    @State private var email = SavedCredentials.email
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Apparence") {
                    Picker("Thème", selection: $appearance) {
                        Text("Système").tag("system")
                        Text("Clair").tag("light")
                        Text("Sombre").tag("dark")
                    }
                }
                Section("Compte Audience") {
                    if store.connected {
                        LabeledContent("Compte", value: store.accountName)
                        Button("Se déconnecter") { Task { await store.disconnect() } }
                            .disabled(store.busy || store.syncing || store.liveCode != nil)
                    } else {
                        TextField("Adresse e-mail", text: $email)
                            .keyboardType(.emailAddress).textContentType(.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Mot de passe", text: $password).textContentType(.password)
                            .onSubmit(connect)
                        Button("Se connecter", action: connect)
                            .disabled(store.busy || email.isEmpty || password.isEmpty)
                        if store.busy { ProgressView("Connexion…") }
                        if store.savedLoginPending {
                            Button("Réessayer la connexion enregistrée") { Task { await store.connectSaved() } }
                                .disabled(store.busy)
                        }
                    }
                    Text("Le mot de passe est conservé dans le trousseau de cet iPad. Se déconnecter l’efface.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.connected {
                    Section("Synchronisation") {
                        Label(store.syncStatus, systemImage: "arrow.triangle.2.circlepath")
                        if let date = store.lastSyncAt { LabeledContent("Dernière synchronisation") { Text(date, style: .time) } }
                        if let error = store.syncError { Text(error).foregroundStyle(.red) }
                        Button("Synchroniser maintenant") { Task { await store.synchronize(showErrors: true) } }
                            .disabled(store.syncing || store.busy || store.liveCode != nil)
                    }
                }
                Section("Sauvegardes") {
                    Text("Les questionnaires sont enregistrés automatiquement sur cet iPad.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Importer…", systemImage: "square.and.arrow.down") { store.importing = true }.disabled(store.readOnly)
                    Button("Exporter la bibliothèque…", systemImage: "square.and.arrow.up") { store.exportBackup() }
                }
                Section {
                    Link("Aide Audience", destination: URL(string: "https://www.ralentirtravaux.com/apps/audience/aide.html")!)
                    Text("Les synthèses Ollama sont disponibles dans l’application Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Réglages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        }
        .sheet(isPresented: $store.importing) { ImportSheet(store: store) }
        .modifier(AudienceDialogs(store: store, active: !store.importing))
    }
    private func connect() {
        guard !store.busy, !email.isEmpty, !password.isEmpty else { return }
        Task {
            await store.connect(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            if store.connected { password = "" }
        }
    }
}
#endif
