import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// Connects one assistant: a sign-in with the account for ChatGPT, an API key for the others.
/// Shared by the questionnaire assistant and the settings, so a connection looks and works the same everywhere.
struct AIConnectionPanel: View {
    let provider: QuizProvider
    /// Runs after a fresh connection succeeded, once the panel has shown its confirmation.
    var connected: @MainActor () async -> Void = {}

    @ObservedObject private var chatGPT = ChatGPTAuth.shared
    private let keys = AIKeyStore.shared
    @State private var apiKey = ""
    @State private var busy = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    #if os(macOS)
    private let deviceLabel = "ce Mac"
    private let deviceArticle = "le Mac"
    private let tapVerb = "Cliquez sur"
    private let tapLower = "cliquez sur"
    #else
    private let deviceLabel = "cet iPad"
    private let deviceArticle = "l’iPad"
    private let tapVerb = "Touchez"
    private let tapLower = "touchez"
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if provider.usesAccount { chatGPTPanel } else { keyPanel }
            if let error { AIErrorLabel(text: error) }
        }
        .onDisappear { operation?.cancel() }
    }

    // MARK: ChatGPT

    @ViewBuilder private var chatGPTPanel: some View {
        if let account = chatGPT.activeAccount, account.canUsePlan {
            connectedRow("Compte connecté", account.label)
            Text("Le modèle est choisi automatiquement parmi ceux de votre abonnement.").font(.subheadline).foregroundStyle(.secondary)
            Button("Se déconnecter", role: .destructive) { run { error = try await chatGPT.signOut() } }
                .buttonStyle(.glass).disabled(busy)
        } else {
            Text("Connecter votre compte ChatGPT").font(.headline)
            if chatGPT.activeAccount?.connected == true {
                Label("Votre compte est connecté, mais l’utilisation de l’abonnement n’est pas encore autorisée. Reconnectez-vous et acceptez toutes les autorisations.",
                      systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    numbered(1, "\(tapVerb) le bouton : une fenêtre sécurisée d’OpenAI s’ouvre.")
                    numbered(2, "Connectez-vous et autorisez Audience à utiliser votre abonnement.")
                    numbered(3, "Vous revenez ici automatiquement.")
                }
            }
            if busy {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Connexion en cours… terminez dans la fenêtre ChatGPT.").font(.subheadline)
                    Spacer()
                    Button("Annuler") { operation?.cancel() }.buttonStyle(.glass)
                }
            } else {
                Button("Continuer avec ChatGPT", systemImage: "person.crop.circle.badge.checkmark") {
                    run {
                        try await chatGPT.signIn(reconsent: true)
                        guard chatGPT.activeAccount?.canUsePlan == true else {
                            throw AudienceError.message("Votre compte est connecté, mais ChatGPT n’autorise pas l’utilisation de votre abonnement par Audience. Réessayez en acceptant toutes les autorisations.")
                        }
                        await finish()
                    }
                }.buttonStyle(.glassProminent).controlSize(.large)
            }
            if let warning = chatGPT.storageError { Text(warning).font(.footnote).foregroundStyle(.secondary) }
            AIFootnote(text: "Audience utilise votre abonnement. Votre mot de passe n’est jamais vu par l’app ; la connexion est conservée dans le Trousseau de \(deviceLabel).")
        }
    }

    // MARK: API key

    @ViewBuilder private var keyPanel: some View {
        if keys.connected.contains(provider) {
            connectedRow("Clé enregistrée", "Gardée dans le Trousseau de \(deviceLabel)")
            let models = keys.models[provider] ?? []
            if models.count > 1 {
                Picker("Modèle", selection: Binding(
                    get: { keys.model(for: provider) ?? "" },
                    set: { keys.choose($0, for: provider) })) {
                        ForEach(models) { Text($0.name).tag($0.id) }
                    }.pickerStyle(.menu)
            } else if let model = keys.model(for: provider) {
                LabeledContent("Modèle", value: model)
            }
            if let issue = keys.issues[provider] {
                Label(issue, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.orange)
            }
            Button("Retirer la clé", role: .destructive) {
                do { try keys.disconnect(provider); error = nil } catch { self.error = error.localizedDescription }
            }.buttonStyle(.glass)
        } else {
            Text("Connecter \(provider.name)").font(.headline)
            Text(provider.keyExplanation).font(.subheadline).foregroundStyle(.secondary)
            if let page = provider.keyPage {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        numberBadge(1)
                        Link(destination: page) { Label("Créer une clé sur \(provider.keyPageName)", systemImage: "arrow.up.right.square") }
                    }
                    HStack(spacing: 10) {
                        numberBadge(2)
                        Text("Collez-la ici, puis \(tapLower) Connecter.").font(.subheadline)
                    }
                }
            }
            HStack(spacing: 10) {
                SecureField("Clé API \(provider.name)", text: $apiKey)
                    .codeEntryField().submitLabel(.go)
                    .onSubmit(connectKey)
                PasteButton(payloadType: String.self) { values in
                    let pasted = values.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Task { @MainActor in if !pasted.isEmpty { apiKey = pasted } }
                }.labelStyle(.iconOnly).buttonBorderShape(.capsule)
            }
            .padding(12).background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
            if busy {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Vérification de la clé…").font(.subheadline)
                    Spacer()
                    Button("Annuler") { operation?.cancel() }.buttonStyle(.glass)
                }
            } else {
                Button("Connecter \(provider.name)", systemImage: "link", action: connectKey)
                    .buttonStyle(.glassProminent).controlSize(.large)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            AIFootnote(text: "\(provider.billingNote) La clé est vérifiée, puis enregistrée dans le Trousseau ; elle ne quitte \(deviceArticle) que pour interroger \(provider.company).")
        }
    }

    private func connectKey() {
        let service = provider, key = apiKey
        guard !busy, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        run {
            try await keys.connect(service, key: key)
            apiKey = ""
            await finish()
        }
    }

    // MARK: Pieces

    /// The confirmation stays visible while the caller moves on.
    private func finish() async {
        busy = false
        await connected()
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        error = nil; busy = true
        operation = Task { @MainActor in
            defer { busy = false; operation = nil }
            do { try await action() } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                if provider == .chatGPT { chatGPT.handleAPIError(error) }
                self.error = error.localizedDescription
            }
        }
    }

    private func connectedRow(_ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.title).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func numberBadge(_ number: Int) -> some View {
        Text("\(number)").font(.caption.bold()).foregroundStyle(.white)
            .frame(width: 22, height: 22).background(Color.accentColor, in: .circle).accessibilityHidden(true)
    }

    private func numbered(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            numberBadge(number)
            Text(text).font(.subheadline)
        }
    }
}

struct AIFootnote: View {
    let text: String
    var body: some View { Text(text).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

struct AIErrorLabel: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.12), in: .rect(cornerRadius: 16))
            .accessibilityAddTraits(.updatesFrequently)
    }
}
