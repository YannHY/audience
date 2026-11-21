import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

enum PlatformClipboard {
    @MainActor static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

#if os(iOS)
import UniformTypeIdentifiers

struct AudienceDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data
    var type: UTType

    init(data: Data, type: UTType) { self.data = data; self.type = type }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        type = configuration.contentType
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Attach only to the visible presentation layer, including settings and the live screen.
struct AudienceDialogs: ViewModifier {
    @Bindable var store: LibraryStore
    var active = true
    func body(content: Content) -> some View {
        content
            .alert("Audience", isPresented: Binding(
                get: { active && store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } })) {
                    Button("OK", role: .cancel) { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "") }
            .fileExporter(isPresented: Binding(
                get: { active && store.exportDocument != nil },
                set: { if !$0 { store.exportDocument = nil } }),
                document: store.exportDocument,
                contentType: store.exportDocument?.type ?? .json,
                defaultFilename: store.exportFilename) { result in
                    switch result {
                    case .success: store.notice = "Fichier exporté."
                    case .failure(let error): store.report(error.localizedDescription)
                    }
                    store.exportDocument = nil
                }
            .sheet(isPresented: Binding(get: { active && store.termsPending }, set: { _ in })) {
                ScrollView { TermsSheet(store: store) }
                    .presentationSizing(.form)
            }
    }
}
#endif
