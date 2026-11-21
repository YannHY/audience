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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Importer des questionnaires").font(.title2.bold())
            dropZone
            Text("Ou collez le texte d’un questionnaire")
                .font(.headline)
                .padding(.top, 4)
            editor
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Format du texte", isExpanded: $showFormat) {
                Text("""
                # Titre, puis une section « ## Question » par question.
                - [x] bonne réponse · plusieurs [x] → choix multiples
                - Type: question ouverte · nuage de mots · notation en étoiles · classement · texte à trous · vidéo YouTube · légender une image
                - Éléments à classer: A | B | C
                - Texte à trous: Le [chat] dort.
                - URL vidéo: https://youtu.be/…
                Une sauvegarde Audience (JSON) peut aussi être collée.
                """)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            }
            HStack {
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Importer le texte") { finish(store.importText(text)) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640, height: 680)
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
            Button("Choisir dans le Finder…") {
                if let urls = store.chooseImportFiles() { finish(store.importFiles(urls)) }
            }
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

    private var editor: some View {
        TextEditor(text: $text)
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
