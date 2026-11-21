import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// Pasting a questionnaire written in the website's Markdown format, as in its import dialog.
struct MarkdownPasteSheet: View {
    let store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
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
            Text("Coller du Markdown").font(.title2.bold())
            Text("Collez un questionnaire au format Markdown d’Audience : un titre « # », puis une section « ## Question » par question.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                .accessibilityLabel("Questionnaire en Markdown")
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Autres types de questions", isExpanded: $showFormat) {
                Text("""
                - [x] plusieurs bonnes réponses → choix multiples
                - Type: question ouverte · nuage de mots · notation en étoiles · classement · texte à trous · vidéo YouTube · légender une image
                - Éléments à classer: A | B | C
                - Texte à trous: Le [chat] dort.
                - URL vidéo: https://youtu.be/…
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
                Button("Importer") {
                    if let message = store.importPastedMarkdown(text) { error = message } else { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
    }
}
