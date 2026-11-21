#if DEBUG
import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// Development aid, absent from Release builds: with AUDIENCE_SNAPSHOT_DIR set, the app walks
/// through its main screens and saves a PNG of each window, without screen-recording rights.
@MainActor enum DebugSnapshots {
    static let present = Notification.Name("AudienceDebugPresent")

    static func runIfRequested(store: LibraryStore) {
        guard let dir = ProcessInfo.processInfo.environment["AUDIENCE_SNAPSHOT_DIR"] else { return }
        let output = URL(filePath: dir)
        Task { @MainActor in
            func pause(_ seconds: Double = 1.2) async { try? await Task.sleep(for: .seconds(seconds)) }
            await pause(2)
            snap("1-library", to: output)
            if let folder = store.visibleFolders.first {
                store.sidebar = .folder(folder.id)
                await pause()
                if let quiz = store.listedQuizzes(sort: .modified).first { store.selection = [quiz.code] }
                await pause()
                snap("2-folder-editor", to: output)
            }
            UserDefaults.standard.set(true, forKey: "inspectorVisible")
            await pause()
            snap("3-inspector", to: output)
            store.selection = Set(store.listedQuizzes(sort: .modified).prefix(3).map(\.code))
            await pause()
            snap("4-multiple", to: output)
            UserDefaults.standard.set(false, forKey: "inspectorVisible")
            store.sidebar = .all
            await pause()
            if let quiz = store.listedQuizzes(sort: .modified).first(where: { $0.validationMessage == nil }) {
                store.selection = [quiz.code]
                await pause()
                NotificationCenter.default.post(name: present, object: quiz.code)
                await pause(2)
                snap("5-presentation", to: output)
            }
            // Persistence check: a new folder must reach the disk after the save delay.
            store.createFolder(rename: true)
            await pause(1.5)
            snap("6-new-folder", to: output)
            // Import: the empty sheet, then the questionnaire created from the sample.
            store.sidebar = .all
            store.importing = true
            await pause()
            snap("9-import", to: output)
            store.importing = false
            await pause(0.8)
            _ = store.importText(ImportSheet.example)
            await pause()
            snap("10-pasted-quiz", to: output)
            let file = output.appending(path: "import-test.md")
            try? ImportSheet.example.replacingOccurrences(of: "Titre du questionnaire", with: "Fichier importé")
                .write(to: file, atomically: true, encoding: .utf8)
            if let failure = store.importFiles([file]) { print("import failed:", failure) }
            await pause()
            snap("11-imported-file", to: output)
            renderLiveScreens(to: output)
            FileManager.default.createFile(atPath: output.appending(path: "done").path, contents: nil)
        }
    }

    /// The waiting room and live results, drawn offscreen with sample data (no session is opened).
    private static func renderLiveScreens(to directory: URL) {
        func save<V: View>(_ view: V, _ name: String, size: CGSize) {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height).background(Color.white))
            renderer.scale = 1
            guard let image = renderer.cgImage else { return }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
        }
        if let url = RemoteClient.participantURL(code: "913244") {
            save(LobbyView(title: "Le vocabulaire du théâtre", code: "913244", url: url, participants: 3, scale: 1.2), "7-lobby", size: CGSize(width: 1440, height: 820))
        }
        let question = Question(fields: ["type": .string("multiple"), "question": .string("Que désigne le mot « théâtre » ?"), "correctIndex": .number(1),
                                         "answers": .array([.string("Un lieu où l’on joue de la musique"), .string("Un endroit d’où l’on voit (des gradins)"), .string("Une salle où l’on récite des poèmes")])])
        let result: JSONValue = .object(["results": .array([.number(5), .number(14), .number(2)]), "total": .number(21)])
        save(ResultCard(question: question, index: 0, result: result, compact: true, showCorrect: true, scale: 1.2).padding(30), "8-live-results", size: CGSize(width: 1100, height: 330))
    }

    private typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    /// CGWindowListCreateImage is hidden from the current SDK but still captures this app's own windows.
    private static let windowImage: WindowImage? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(symbol, to: WindowImage.self)
    }()

    static func snap(_ name: String, to directory: URL) {
        for (index, window) in NSApp.windows.enumerated() where window.isVisible && window.frame.width > 300 {
            var image: CGImage?
            if let windowImage {
                // kCGWindowListOptionIncludingWindow = 8, kCGWindowImageBoundsIgnoreFraming = 1
                image = windowImage(.null, 8, UInt32(window.windowNumber), 1)?.takeRetainedValue()
            }
            guard let image else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name)-\(index).png"))
        }
    }
}
#endif
