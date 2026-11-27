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

/// What the user would otherwise repeat in every request: who they are, their audience, their habits.
/// Sent with each questionnaire request and each summary of results, to whichever assistant is used.
enum AICustomInstructions {
    static let key = "ai.profile"
    static var text: String { UserDefaults.standard.string(forKey: key) ?? "" }
}

struct AICustomInstructionsSection: View {
    @AppStorage(AICustomInstructions.key) private var profile = ""

    var body: some View {
        Section {
            TextEditor(text: $profile)
                .frame(minHeight: 110)
                .overlay(alignment: .topLeading) {
                    if profile.isEmpty {
                        Text("Par exemple : « Je suis professeur de SVT en collège », « Je forme des adultes à la cybersécurité en entreprise » ou « J’anime des quiz de culture générale ». Ajoutez vos habitudes : questions courtes, ton, types de questions…")
                            .foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                    }
                }
                .onChange(of: profile) { _, new in
                    if new.count > QuizAIText.profileLimit { profile = String(new.prefix(QuizAIText.profileLimit)) }
                }
        } header: {
            Text("Instructions personnalisées")
        } footer: {
            Text("Ajoutées à chaque demande faite à l’assistant (création de questionnaire et synthèse des résultats), pour ne pas répéter qui vous êtes, votre public ou vos habitudes. \(profile.count) / \(QuizAIText.profileLimit) caractères.")
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

#if os(macOS)
/// Single-page assistants settings for macOS Settings tabs and sheets (where the window toolbar belongs to TabView).
struct AIAssistantsMacView: View {
    @AppStorage("ai.provider") private var providerID = QuizProvider.chatGPT.rawValue
    private var selected: QuizProvider { QuizProvider(rawValue: providerID) ?? .chatGPT }

    var body: some View {
        Form {
            Section {
                ForEach(QuizProvider.allCases) { provider in
                    Button { providerID = provider.rawValue } label: {
                        HStack {
                            AIProviderRow(provider: provider)
                            Spacer()
                            Image(systemName: provider == selected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(provider == selected ? provider.tint : Color.secondary.opacity(0.4))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Assistants IA")
            } footer: {
                Text("Connectez ChatGPT avec votre compte, ou Claude, Gemini et Groq avec une clé API, pour créer des questionnaires et résumer les résultats. Rien n’est envoyé avant que vous le demandiez ; les connexions sont gardées dans le Trousseau de ce Mac.")
            }
            Section(selected.name) {
                AIConnectionPanel(provider: selected)
                    .id(selected)
            }
            AICustomInstructionsSection()
        }
        .formStyle(.grouped)
        .task(id: providerID) { await AIKeyStore.shared.refreshModels(selected) }
    }
}
#endif
