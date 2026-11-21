import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

struct QuizInspector: View {
    @Bindable var store: LibraryStore
    let code: String
    @State private var newTag = ""
    private var quiz: Quiz { store.archive.quizzes[code] ?? Quiz(code: code) }

    var body: some View {
        Form {
            Section("Rangement") {
                Picker("Dossier", selection: Binding(get: { store.folder(of: quiz)?.id }, set: { store.move([code], to: $0) })) {
                    Text("Aucun").tag(String?.none)
                    if !store.visibleFolders.isEmpty { Divider() }
                    ForEach(store.visibleFolders) { folder in
                        Label(folder.name, systemImage: "folder.fill").tag(Optional(folder.id))
                    }
                }
                LabeledContent("Couleur") { ColorSwatches(selection: Binding(get: { quiz.cardColor }, set: { store.setColor([code], $0) }),
                                                          inherited: store.folder(of: quiz)?.quizColor) }
                Toggle("Favori", isOn: Binding(get: { quiz.isFavorite }, set: { store.setFavorite([code], $0) }))
            }
            Section("Étiquettes") {
                if !quiz.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(quiz.tags, id: \.self) { tag in
                            HStack(spacing: 3) {
                                Text("#\(tag)").lineLimit(1)
                                Button("Retirer \(tag)", systemImage: "xmark") { store.removeTag(tag, from: [code]) }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless).font(.caption2.weight(.bold))
                            }
                            .font(.callout)
                            .padding(.leading, 9).padding(.trailing, 6).padding(.vertical, 4)
                            .background(.fill.tertiary, in: .capsule)
                        }
                    }
                }
                HStack {
                    TextField("Ajouter une étiquette", text: $newTag, prompt: Text("Ajouter une étiquette"))
                        .labelsHidden()
                        .onSubmit(addTag)
                    let suggestions = store.allTags.filter { tag in !quiz.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
                    if !suggestions.isEmpty {
                        Menu {
                            ForEach(suggestions, id: \.self) { tag in Button("#\(tag)") { store.addTag(tag, to: [code]) } }
                        } label: { Label("Étiquettes existantes", systemImage: "tag") }
                        .labelStyle(.iconOnly).menuIndicator(.hidden).fixedSize()
                        .help("Ajouter une étiquette existante")
                    }
                }
                .disabled(quiz.tags.count >= 12)
                if quiz.tags.count >= 12 {
                    Text("12 étiquettes au maximum.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Participation") {
                Toggle("Demander le nom des participants", isOn: quizBool("requireParticipantName", fallback: true))
                Toggle("Autoriser le rapport individuel", isOn: quizBool("participantReportEnabled"))
            }
            Section("Informations") {
                LabeledContent("Code") {
                    HStack(spacing: 6) {
                        Text(quiz.code).monospaced().textSelection(.enabled)
                        Button("Copier le code", systemImage: "doc.on.doc") {
                            PlatformClipboard.copy(quiz.code)
                            store.notice = "Code copié."
                        }.labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                LabeledContent("Questions", value: "\(quiz.questions.count)")
                LabeledContent("Modifié") { Text(quiz.updatedAt, format: .dateTime.day().month().year().hour().minute()) }
                if store.connected {
                    LabeledContent("Site") {
                        Text(store.archive.synchronization.records[code] == nil ? "Pas encore envoyé"
                             : store.isPending(quiz) ? "Modifications en attente" : "À jour")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(store.liveCode == code || store.readOnly)
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        store.addTag(tag, to: [code])
        newTag = ""
    }
    private func quizBool(_ key: String, fallback: Bool = false) -> Binding<Bool> {
        Binding(get: { quiz.fields[key]?.bool ?? fallback }, set: { value in store.update(code) { $0[key] = .bool(value) } })
    }
}

struct ColorSwatches: View {
    @Binding var selection: QuizColor?
    var inherited: QuizColor?
    var body: some View {
        #if os(iOS)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
            swatch(nil)
            ForEach(QuizColor.allCases) { swatch($0) }
        }
        #else
        HStack(spacing: 5) {
            swatch(nil)
            ForEach(QuizColor.allCases) { swatch($0) }
        }
        #endif
    }
    private func swatch(_ color: QuizColor?) -> some View {
        let selected = selection == color
        return Button {
            selection = color
        } label: {
            ZStack {
                if let color {
                    Circle().fill(color.color.gradient)
                } else {
                    Circle().strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [2.5]))
                    if let inherited { Circle().fill(inherited.color.opacity(0.35)).padding(4) }
                }
                if selected {
                    Circle().strokeBorder(Color.primary.opacity(0.85), lineWidth: 2).padding(-3)
                }
            }
            #if os(iOS)
            .frame(width: 24, height: 24).padding(10)
            #else
            .frame(width: 16, height: 16)
            #endif
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(color?.title ?? "Automatique (couleur du dossier)")
        .accessibilityLabel(color?.title ?? "Automatique")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Wraps its children onto several lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
