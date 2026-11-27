import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// The single way in for questionnaires: a file chosen in the Finder or dropped here,
/// or text pasted in the website's Markdown format (or an Audience backup in JSON).
struct ImportSheet: View {
    let store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var dropTargeted = false
    @State private var showFormat = false
    @State private var choosingFiles = false

    static let example = """
    # Titre du questionnaire

    ## Question 1
    Capitale de la France ?
    - [ ] Lyon
    - [x] Paris

    ## Question 2
    Un mot pour résumer le cours ?
    - Type: nuage de mots
    """

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    #if os(macOS)
                    // A Mac sheet has no title bar.
                    Text("Importer des questionnaires").font(.title2.bold())
                    #endif
                    dropZone
                    HStack(alignment: .firstTextBaseline) {
                        Text("Ou collez le texte d’un questionnaire").font(.headline)
                        Spacer(minLength: 8)
                        Button("Format", systemImage: "questionmark.circle") { showFormat = true }
                            .buttonStyle(.borderless)
                            .popover(isPresented: $showFormat) { formatHelp }
                    }
                    .padding(.top, 4)
                    editor
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
                .frame(idealWidth: 640, maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Importer des questionnaires")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    #if os(iOS)
                    CloseButton { dismiss() }
                    #else
                    Button("Annuler", role: .cancel) { dismiss() }
                    #endif
                }
                // Files are imported as soon as they are chosen or dropped: this button is for pasted text.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importer", role: .confirm) { finish(store.importText(text)) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!hasText)
                }
            }
        }
        .frame(idealHeight: 680)
        #if os(iOS)
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: LibraryStore.importTypes + [.plainText], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): finish(store.importFiles(urls))
            case .failure(let failure): error = failure.localizedDescription
            }
        }
        #endif
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30))
                .foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
            Text("Glissez un fichier ici")
                .font(.headline)
            Text("Questionnaire Markdown (.md), archive ZIP exportée du site ou sauvegarde Audience (.json)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Choisir un fichier…") {
                #if os(macOS)
                if let urls = store.chooseImportFiles() { finish(store.importFiles(urls)) }
                #else
                choosingFiles = true
                #endif
            }
            #if os(iOS)
            .buttonStyle(.glass)
            #endif
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20).padding(.horizontal, 16)
        .background(dropTargeted ? Color.accentColor.opacity(0.08) : .clear, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1.2, dash: [6, 4]))
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            finish(store.importFiles(files))
            return true
        } isTargeted: { dropTargeted = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zone de dépôt de fichier")
    }

    /// The format at a glance, with the example ready to paste in and adapt.
    private var formatHelp: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Format du texte").font(.headline)
            Text("""
            # Titre, puis une section « ## Question » par question.
            - [x] bonne réponse · plusieurs [x] → choix multiples
            - Type: question ouverte · nuage de mots · notation en étoiles · classement · texte à trous · vidéo YouTube · légender une image
            - Éléments à classer: A | B | C
            - Texte à trous: Le [chat] dort.
            - URL vidéo: https://youtu.be/…
            """)
            .font(.callout.monospaced())
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            Button("Partir de l’exemple", systemImage: "doc.on.clipboard") { text = Self.example; showFormat = false }
                .disabled(hasText)
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }

    private var editor: some View {
        TextEditor(text: $text)
            .frame(minHeight: 270) // room for the whole example shown as a placeholder
            .font(.body.monospaced())
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(.background.secondary, in: .rect(cornerRadius: 8))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(Self.example)
                        .font(.body.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: text) { error = nil }
            .accessibilityLabel("Texte du questionnaire")
    }

    /// Closes the sheet on success; otherwise shows why, keeping what was pasted.
    private func finish(_ failure: String?) {
        if let failure { error = failure } else { dismiss() }
    }
}
