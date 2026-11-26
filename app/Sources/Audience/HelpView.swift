import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// The help, inside the app: a window of the Mac Help menu, and a page of the iPad settings
/// (so it needs the navigation stack that shows it). The text comes from `HelpContent`.
struct HelpView: View {
    #if os(macOS)
    private let topics = HelpContent.topics(for: .mac)
    @State private var selection: String? = "start"
    #else
    private let topics = HelpContent.topics(for: .iPad)
    #endif
    @State private var search = ""

    private var shown: [HelpTopic] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? topics : topics.filter { $0.searchableText.localizedStandardContains(query) }
    }

    #if os(macOS)
    var body: some View {
        NavigationSplitView {
            List(shown, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.symbol)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
            .overlay { if shown.isEmpty { ContentUnavailableView.search(text: search) } }
        } detail: {
            if let topic = shown.first(where: { $0.id == selection }) ?? shown.first {
                HelpTopicView(topic: topic).id(topic.id)
            } else {
                ContentUnavailableView("Aucune rubrique", systemImage: "questionmark.circle",
                                       description: Text("Essayez d’autres mots."))
            }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Rechercher dans l’aide")
        // Searching narrows the list: keep the selection on a topic that is still shown.
        .onChange(of: search) {
            if !shown.contains(where: { $0.id == selection }) { selection = shown.first?.id }
        }
        .frame(minWidth: 760, minHeight: 480)
        .navigationTitle("Aide Audience")
    }
    #else
    var body: some View {
        List(shown) { topic in
            NavigationLink(value: topic) { Label(topic.title, systemImage: topic.symbol) }
        }
        .overlay { if shown.isEmpty { ContentUnavailableView.search(text: search) } }
        .searchable(text: $search, prompt: "Rechercher dans l’aide")
        .navigationDestination(for: HelpTopic.self) { HelpTopicView(topic: $0) }
        .navigationTitle("Aide Audience")
        .navigationBarTitleDisplayMode(.inline)
    }
    #endif
}

struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(topic.title, systemImage: topic.symbol)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(topic.blocks.enumerated()), id: \.offset) { _, block in
                    HelpBlockView(block: block)
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
        #if os(iOS)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct HelpBlockView: View {
    let block: HelpBlock
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var termWidth = 190.0

    var body: some View {
        switch block {
        case .text(let text):
            Text(Self.markdown(text)).fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(Self.markdown(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .rows(let rows):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.horizontal, 14) }
                    rowView(row)
                }
            }
            .background(.quinary, in: .rect(cornerRadius: 12))
        case .note(let text):
            Label {
                Text(Self.markdown(text)).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill").foregroundStyle(.tint)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 12))
        case .example(let label, let code):
            HelpExample(label: label, code: code)
        }
    }

    @ViewBuilder private func rowView(_ row: HelpRow) -> some View {
        let term = Text(Self.markdown(row.term)).fontWeight(.semibold)
        let detail = Text(Self.markdown(row.detail))
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) { term; detail }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    term.frame(width: termWidth, alignment: .leading)
                    detail.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    /// Inline Markdown (bold, italic, code) only: the help text never needs blocks.
    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct HelpExample: View {
    let label: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(copied ? "Exemple copié" : label, systemImage: copied ? "checkmark" : "doc.on.doc") {
                PlatformClipboard.copy(code)
                copied = true
            }
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
            DisclosureGroup("Voir l’exemple") {
                ScrollView(.horizontal) {
                    Text(code)
                        .font(.callout.monospaced())
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(.quinary, in: .rect(cornerRadius: 10))
                .padding(.top, 6)
            }
        }
    }
}
