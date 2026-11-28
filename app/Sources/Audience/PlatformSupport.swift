import SwiftUI
#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif
#if SWIFT_PACKAGE
import AudienceCore
#endif

extension RichText {
    /// A statement with its bold, italic and underlined parts, for Text. The size and weight stay the view's.
    static func attributed(_ text: String) -> AttributedString { attributed(runs: runs(text)) }
    /// An answer with its inline emphasis (*italique*, **gras**), for Text.
    static func attributedAnswer(_ text: String) -> AttributedString { attributed(runs: answerRuns(text)) }
    private static func attributed(runs: [Run]) -> AttributedString {
        runs.reduce(into: AttributedString()) { result, run in
            var piece = AttributedString(run.text)
            var intent: InlinePresentationIntent = []
            if run.bold { intent.insert(.stronglyEmphasized) }
            if run.italic { intent.insert(.emphasized) }
            if !intent.isEmpty { piece.inlinePresentationIntent = intent }
            if run.underline { piece.swiftUI.underlineStyle = .single }
            result += piece
        }
    }
}

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

/// Width shared by the list columns (sidebar, questionnaires, questions) so they line up as one grid.
enum IPadColumn {
    static let width: CGFloat = 280
    static let maximum: CGFloat = 380
}

/// Closes a sheet or a screen: the system cross on the iPad, the word on the Mac.
/// VoiceOver still reads « Fermer ».
struct CloseButton: View {
    let action: () -> Void
    var body: some View {
        #if os(iOS)
        Button("Fermer", systemImage: "xmark", role: .close, action: action).labelStyle(.iconOnly)
        #else
        Button("Fermer", action: action)
        #endif
    }
}

/// Confirms and closes a sheet: the system checkmark on the iPad, the word on the Mac.
/// VoiceOver still reads « Terminé ».
struct DoneButton: View {
    let action: () -> Void
    var body: some View {
        #if os(iOS)
        Button("Terminé", systemImage: "checkmark", role: .confirm, action: action).labelStyle(.iconOnly)
        #else
        Button("Terminé", action: action)
        #endif
    }
}

extension View {
    /// Shows only the icon of a labelled button on the iPad, where its symbol speaks for itself;
    /// the Mac keeps the word. The title remains the accessibility label.
    func iPadIconOnly() -> some View {
        #if os(iOS)
        labelStyle(.iconOnly)
        #else
        self
        #endif
    }

    func platformHoverEffect(lift: Bool = false) -> some View {
        #if os(iOS)
        hoverEffect(lift ? .lift : .highlight)
        #else
        self
        #endif
    }

    func codeEntryField(url: Bool = false) -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .keyboardType(url ? .URL : .default)
            .autocorrectionDisabled()
        #else
        autocorrectionDisabled()
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
