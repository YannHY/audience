import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

@MainActor @Observable
final class LocalAIStore {
    struct Synthesis {
        let statistics: QuizStatistics
        let title: String
        let text: String
        let model: String
        let date: Date
    }
    var syntheses: [String: Synthesis] = [:]
    var models: [LocalModel] = []
    var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "statisticsModel") }
    }
    var checking = false
    var available = false
    var error: String?
    var downloading: String?
    var progress: ModelDownloadProgress?
    private var downloadTask: Task<Void, Never>?
    let client = OllamaClient()

    init() { selectedModel = UserDefaults.standard.string(forKey: "statisticsModel") ?? "" }

    func refresh() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            let found = try await client.models()
            try Task.checkCancellation()
            models = found
            available = true
            if !found.contains(where: { $0.name == selectedModel }) { selectedModel = found.first?.name ?? "" }
            error = nil
        } catch is CancellationError {} catch {
            available = false
            self.error = message(error)
        }
    }
    func download(_ name: String) {
        guard downloading == nil else { return }
        do { try OllamaClient.validateModel(name) } catch { self.error = error.localizedDescription; return }
        downloading = name
        progress = nil
        error = nil
        downloadTask = Task {
            defer { downloading = nil; progress = nil; downloadTask = nil }
            do {
                try await client.pull(name) { [weak self] value in
                    await self?.updateProgress(value)
                }
                try Task.checkCancellation()
                await refresh()
                if models.contains(where: { $0.name == name }) { selectedModel = name }
            } catch is CancellationError {} catch {
                if !Task.isCancelled { self.error = message(error) }
            }
        }
    }
    func cancelDownload() { downloadTask?.cancel() }
    private func updateProgress(_ value: ModelDownloadProgress) { progress = value }
    func message(_ error: Error) -> String {
        if let error = error as? URLError, [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .timedOut].contains(error.code) {
            return "Ollama est indisponible. Ouvrez Ollama sur ce Mac, puis réessayez."
        }
        return error.localizedDescription
    }
}

struct LocalModelsView: View {
    @Environment(LocalAIStore.self) private var ai
    @State private var customModel = ""
    private let catalog: [(String, String)] = [
        ("qwen3:4b", "Qwen 3 · 4B"), ("qwen3:8b", "Qwen 3 · 8B"),
        ("gemma3:1b", "Gemma 3 · 1B"), ("gemma3:4b", "Gemma 3 · 4B"),
        ("deepseek-r1:1.5b", "DeepSeek R1 · 1,5B"), ("deepseek-r1:8b", "DeepSeek R1 · 8B")
    ]
    var body: some View {
        @Bindable var ai = ai
        Form {
            Section("Ollama sur ce Mac") {
                Text("Installez et ouvrez Ollama pour télécharger des modèles et générer vos synthèses localement.").foregroundStyle(.secondary)
                HStack {
                    Link("Installer Ollama", destination: URL(string: "https://ollama.com/download/mac")!)
                    Spacer()
                    Button("Actualiser les modèles") { Task { await ai.refresh() } }.disabled(ai.checking || ai.downloading != nil)
                    if ai.checking { ProgressView().controlSize(.small) }
                }
                if ai.available { Label("Ollama connecté", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                if let error = ai.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            }
            Section("Modèles installés") {
                if ai.models.isEmpty { Text("Aucun modèle local détecté.").foregroundStyle(.secondary) }
                else {
                    Picker("Modèle pour les synthèses", selection: $ai.selectedModel) {
                        ForEach(ai.models) { model in
                            Text("\(model.name) · \(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file))").tag(model.name)
                        }
                    }
                }
            }
            Section("Télécharger un modèle") {
                Text("Les modèles occupent de quelques centaines de Mo à plusieurs Go. Les variantes 1B et 1,5B sont plus légères ; les plus grandes demandent davantage de mémoire.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(catalog, id: \.0) { name, label in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(label)
                            Text(name).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if ai.models.contains(where: { $0.name == name }) {
                            Label("Installé", systemImage: "checkmark").foregroundStyle(.secondary)
                        } else {
                            Button("Télécharger", systemImage: "arrow.down.circle") { ai.download(name) }
                                .disabled(!ai.available || ai.downloading != nil)
                        }
                    }
                }
                HStack {
                    TextField("Autre modèle Ollama (nom:version)", text: $customModel)
                    Button("Télécharger") { ai.download(customModel.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .disabled(!ai.available || ai.downloading != nil || customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let name = ai.downloading {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Téléchargement de \(name)")
                            Spacer()
                            Button("Annuler", action: ai.cancelDownload)
                        }
                        if let fraction = ai.progress?.fraction { ProgressView(value: fraction) }
                        else { ProgressView().controlSize(.small) }
                        Text(ai.progress?.status ?? "Préparation…").font(.caption).foregroundStyle(.secondary)
                        if let progress = ai.progress, progress.total > 0 {
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(progress.completed), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(progress.total), countStyle: .file))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Text("Les synthèses utilisent uniquement le service local de ce Mac. Les noms et identifiants des participants ne sont pas transmis au modèle. Le téléchargement nécessite Internet ; une fois installé, le modèle fonctionne hors ligne.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await ai.refresh() }
    }
}
