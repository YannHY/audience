import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

@main
struct AudienceApp: App {
    @NSApplicationDelegateAdaptor(AudienceAppDelegate.self) private var appDelegate
    @State private var store = LibraryStore()
    @AppStorage("appearance") private var appearance = "system"
    private var colorScheme: ColorScheme? { appearance == "system" ? nil : appearance == "dark" ? .dark : .light }

    var body: some Scene {
        Window("Audience", id: "library") {
            LibraryView(store: store)
                .onAppear {
                    appDelegate.store = store
                    #if DEBUG
                    DebugSnapshots.runIfRequested(store: store)
                    #endif
                }
                .preferredColorScheme(colorScheme)
        }
        .defaultSize(width: 1320, height: 840)
        .windowResizability(.contentMinSize)
        .commands { LibraryCommands(store: store) }

        WindowGroup("Présentation", id: "presentation", for: String.self) { $code in
            if let code { PresentationView(store: store, code: code).preferredColorScheme(colorScheme) }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commandsRemoved()

        Settings {
            SettingsView(store: store)
                .preferredColorScheme(colorScheme)
        }
    }
}

struct LibraryCommands: Commands {
    let store: LibraryStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        SidebarCommands()
        ToolbarCommands()
        InspectorCommands()
        CommandGroup(replacing: .newItem) {
            Button("Nouveau questionnaire", action: store.create)
                .keyboardShortcut("n")
                .disabled(store.readOnly)
            Button("Nouveau dossier") { store.createFolder(with: Set(store.selectedQuizzes.filter { !$0.isDeleted }.map(\.code))) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(store.readOnly)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Importer une sauvegarde…", action: store.importBackup)
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Exporter une sauvegarde…") { store.exportBackup() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandMenu("Questionnaire") {
            let quizzes = store.selectedQuizzes.filter { !$0.isDeleted }
            let codes = Set(quizzes.map(\.code))
            Button("Présenter") {
                guard let quiz = store.selectedQuiz else { return }
                if let message = quiz.validationMessage { store.report(message) }
                else { openWindow(id: "presentation", value: quiz.code) }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(store.selectedQuiz == nil || store.selectedQuiz?.isDeleted == true)
            Divider()
            Button("Dupliquer") { store.duplicate(codes) }
                .keyboardShortcut("d")
                .disabled(codes.isEmpty)
            let allFavorite = !quizzes.isEmpty && quizzes.allSatisfy(\.isFavorite)
            Button(allFavorite ? "Retirer des favoris" : "Ajouter aux favoris") { store.setFavorite(codes, !allFavorite) }
                .disabled(codes.isEmpty)
            Menu("Déplacer vers") {
                Button("Aucun dossier") { store.move(codes, to: nil) }
                Divider()
                ForEach(store.visibleFolders) { folder in Button(folder.name) { store.move(codes, to: folder.id) } }
            }
            .disabled(codes.isEmpty)
            Button("Placer dans la corbeille") { store.moveToTrash(codes) }
                .disabled(codes.isEmpty)
            Divider()
            Button("Synchroniser maintenant") { Task { await store.synchronize(showErrors: true) } }
                .keyboardShortcut("r")
                .disabled(!store.connected || store.syncing || store.busy || store.liveCode != nil)
            Button("Afficher les données dans le Finder", action: store.revealData)
        }
        CommandGroup(replacing: .help) {
            Link("Aide Audience", destination: URL(string: "https://www.ralentirtravaux.com/apps/audience/aide.html")!)
        }
    }
}

@MainActor
final class AudienceAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: LibraryStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        guard store.liveCode != nil else { store.flush(); return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Une session est en direct"
        alert.informativeText = "Arrêter la participation en ligne avant de quitter Audience ?"
        alert.addButton(withTitle: "Arrêter et quitter")
        alert.addButton(withTitle: "Annuler")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        Task {
            await store.stopLive()
            store.flush()
            sender.reply(toApplicationShouldTerminate: store.liveCode == nil)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { store?.flush() }
}
