import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// The assistants of the app, with their connection state. Used in the settings and in the sheet
/// opened from the statistics, so the same four services are connected the same way everywhere.
struct AIAssistantsSection: View {
    #if os(macOS)
    private let deviceLabel = "ce Mac"
    #else
    private let deviceLabel = "cet iPad"
    #endif

    var body: some View {
        Section {
            ForEach(QuizProvider.allCases) { provider in
                NavigationLink { AIProviderSettingsView(provider: provider) } label: { AIProviderRow(provider: provider) }
            }
        } header: {
            Text("Assistants IA")
        } footer: {
            Text("Connectez ChatGPT avec votre compte, ou Claude, Gemini et Groq avec une clé API, pour créer des questionnaires et résumer les résultats. Rien n’est envoyé avant que vous le demandiez ; les connexions sont gardées dans le Trousseau de \(deviceLabel).")
        }
    }
}

struct AIProviderRow: View {
    let provider: QuizProvider
    @ObservedObject private var chatGPT = ChatGPTAuth.shared
    private let keys = AIKeyStore.shared

    private var connected: Bool {
        provider.usesAccount ? chatGPT.activeAccount?.canUsePlan == true : keys.connected.contains(provider)
    }
    private var status: String {
        guard connected else { return "Non connecté" }
        return provider.usesAccount ? (chatGPT.activeAccount?.label ?? "Connecté") : "Clé enregistrée"
    }

    var body: some View {
        HStack(spacing: 14) {
            ProviderLogo(provider: provider, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                HStack(spacing: 6) {
                    Circle().fill(connected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 7, height: 7)
                    Text(status).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct AIProviderSettingsView: View {
    let provider: QuizProvider

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    ProviderLogo(provider: provider, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name).font(.title3.weight(.semibold))
                        Text(provider.company).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Section { AIConnectionPanel(provider: provider) }
            Section {
                Text("Ce service rédige des questionnaires à partir d’un document ou d’une vidéo, et résume les résultats d’un questionnaire dans Statistiques. Le contenu n’est envoyé à \(provider.company) que lorsque vous le demandez.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(provider.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await AIKeyStore.shared.refreshModels(provider) }
    }
}
