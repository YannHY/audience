#if os(macOS)
import Combine
import Sparkle
import SwiftUI

/// Sparkle vérifie le flux quotidiennement et authentifie les archives avec la clé d’Info.plist.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    private var controller: SPUStandardUpdaterController?
    private var observation: AnyCancellable?
    private weak var store: LibraryStore?
    private var pendingInstallation: (() -> Void)?

    func start(store: LibraryStore) {
        self.store = store
        // swift run et les tests n’ont pas le bundle de distribution.
        guard controller == nil, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
        controller.startUpdater()
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if store?.liveCode != nil {
            throw NSError(domain: "fr.audience.native.updates", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "La recherche de mises à jour reprendra après la session en direct."
            ])
        }
    }

    // Une mise à jour déjà téléchargée attend la fin du direct avant de quitter l’app.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard store?.liveCode != nil else { store?.flush(); return false }
        pendingInstallation = installHandler
        return true
    }

    func resumeInstallationIfPossible() {
        guard store?.liveCode == nil, let install = pendingInstallation else { return }
        pendingInstallation = nil
        store?.flush()
        install()
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) { store?.flush() }
}

struct AppUpdateCommands: Commands {
    let store: LibraryStore
    @ObservedObject private var updater = AppUpdater.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Rechercher les mises à jour…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates || store.liveCode != nil)
        }
    }
}

#endif
