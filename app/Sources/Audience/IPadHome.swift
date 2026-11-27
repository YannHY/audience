import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// Landing screen of the app: three ways in, then the questionnaires worked on lately.
struct IPadHomeView: View {
    let store: LibraryStore
    let newQuiz: () -> Void
    let createWithAI: () -> Void
    let openLibrary: () -> Void
    let openQuiz: (String) -> Void
    let showImport: () -> Void
    let showSettings: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var greetingSize = 46.0
    @ScaledMetric(relativeTo: .body) private var tileSize = 56.0
    @ScaledMetric(relativeTo: .body) private var recentWidth = 264.0
    @ScaledMetric(relativeTo: .body) private var recentHeight = 176.0
    @State private var width: CGFloat = 1024
    @State private var shown = false

    /// Side-by-side layout needs room for the large card and a 400-point column.
    private var wide: Bool { width >= 980 && !typeSize.isAccessibilitySize }
    private var greeting: String { Calendar.current.component(.hour, from: .now) >= 18 ? "Bonsoir" : "Bonjour" }

    var body: some View {
        let all = store.quizzes(in: .all)
        let recents = Array(all.sorted { $0.updatedAt > $1.updatedAt }.prefix(10))
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header.reveal(0, shown, reduceMotion)
                    actions(count: all.count).reveal(1, shown, reduceMotion)
                    recentSection(recents).reveal(2, shown, reduceMotion)
                }
                .frame(maxWidth: 1120, alignment: .leading)
                .padding(.horizontal, 32).padding(.top, 12).padding(.bottom, 56)
                .frame(maxWidth: .infinity)
            }
            .background { AudienceBackdrop().ignoresSafeArea() }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("Audience")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(removing: .title)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Réglages", systemImage: "gearshape", action: showSettings)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task { shown = true }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AUDIENCE").font(.footnote.weight(.bold)).tracking(3).foregroundStyle(.tint)
            Text(greeting).font(.system(size: greetingSize, weight: .bold))
            Text("Que souhaitez-vous créer aujourd’hui ?").font(.title3).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Actions

    /// The AI card, then the same column of plain cards beside it or below it.
    @ViewBuilder private func actions(count: Int) -> some View {
        let column = VStack(spacing: 16) { blankCard; importCard; libraryCard(count) }
        if wide {
            HStack(alignment: .top, spacing: 20) {
                aiCard.frame(maxWidth: .infinity)
                column.frame(width: 400)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 20) { aiCard; column }
        }
    }

    private var aiCard: some View {
        Button(action: createWithAI) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Assistant IA", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassEffect(.regular.tint(.white.opacity(0.2)), in: .capsule)
                Spacer(minLength: 24)
                Text("Créer avec une IA").font(.largeTitle.weight(.bold))
                Text("Décrivez le questionnaire voulu, avec ou sans document, photos ou vidéo YouTube. L’assistant le rédige ; vous le relisez avant de l’ajouter.")
                    .font(.title3).foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: 540, alignment: .leading)
                HStack(alignment: .center, spacing: 16) {
                    FlowLayout(spacing: 8) {
                        ForEach(QuizProvider.allCases) { provider in
                            HStack(spacing: 8) {
                                ProviderLogo(provider: provider, size: 24)
                                Text(provider.name).font(.subheadline.weight(.medium))
                            }
                            .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 5)
                            .background(.white.opacity(0.18), in: .capsule)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right").font(.title2.weight(.semibold))
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.tint(.white.opacity(0.25)), in: .circle)
                }
            }
            .foregroundStyle(.white)
            .padding(30)
            .frame(maxWidth: .infinity, minHeight: wide ? 340 : 280, alignment: .leading)
            .background(alignment: .bottomTrailing) {
                Image(systemName: "sparkles").font(.system(size: 280, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.13)).rotationEffect(.degrees(-10))
                    .offset(x: 70, y: 70).accessibilityHidden(true)
            }
            .background { HeroGradient() }
            .clipShape(.rect(cornerRadius: 36, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 36, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 1) }
            .shadow(color: .blue.opacity(0.3), radius: 28, y: 14)
            .contentShape(.rect(cornerRadius: 36, style: .continuous))
            .platformHoverEffect(lift: true)
        }
        .buttonStyle(PressableStyle())
        .disabled(store.readOnly)
        .accessibilityLabel("Créer avec une IA")
        .accessibilityHint("Génère un questionnaire à partir d’un document ou d’une vidéo YouTube.")
    }

    private var blankCard: some View {
        actionCard("Questionnaire vierge", "Partir d’une page blanche", "square.and.pencil", .blue, action: newQuiz)
            .keyboardShortcut("n")
            .disabled(store.readOnly)
    }

    private var importCard: some View {
        actionCard("Importer", "Fichiers ou texte d’un questionnaire", "square.and.arrow.down", .green, action: showImport)
            .disabled(store.readOnly)
    }

    private func libraryCard(_ count: Int) -> some View {
        actionCard("Bibliothèque", count == 0 ? "Aucun questionnaire pour le moment" : count == 1 ? "1 questionnaire" : "\(count) questionnaires",
                   "books.vertical.fill", .orange, action: openLibrary)
    }

    private func actionCard(_ title: String, _ subtitle: String, _ symbol: String, _ tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                HomeTile(symbol: symbol, tint: tint, size: tileSize)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30))
            .contentShape(.rect(cornerRadius: 30))
            .platformHoverEffect()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Recents

    private func recentSection(_ quizzes: [Quiz]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Récents").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                if !quizzes.isEmpty { Button("Tout afficher", action: openLibrary).font(.body.weight(.medium)) }
            }
            if quizzes.isEmpty {
                emptyRecents
            } else {
                ScrollView(.horizontal) {
                    GlassEffectContainer(spacing: 16) {
                        HStack(spacing: 16) { ForEach(quizzes, id: \.code) { recentCard($0) } }.scrollTargetLayout()
                    }
                }
                .scrollIndicators(.hidden).scrollClipDisabled().scrollTargetBehavior(.viewAligned)
            }
        }
    }

    private func recentCard(_ quiz: Quiz) -> some View {
        let tint = store.displayColor(of: quiz)?.color ?? .gray
        let live = store.liveCode == quiz.code
        let count = quiz.questions.count
        return Button { openQuiz(quiz.code) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HomeTile(symbol: quiz.dominantSymbol, tint: tint, size: tileSize * 0.8)
                    Spacer()
                    if live {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.green)
                            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion).accessibilityLabel("En direct")
                    }
                    if quiz.isFavorite { Image(systemName: "star.fill").foregroundStyle(.orange).accessibilityLabel("Favori") }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(quiz.title.isEmpty ? "Sans titre" : quiz.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Text("\(count == 1 ? "1 question" : "\(count) questions") · \(Self.relativeDate(quiz.updatedAt))")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(18)
            .frame(width: recentWidth, height: recentHeight, alignment: .topLeading)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
            .contentShape(.rect(cornerRadius: 28))
            .platformHoverEffect()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre le questionnaire dans l’éditeur.")
    }

    private var emptyRecents: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text("Vos questionnaires récents apparaîtront ici").font(.headline)
            Text("Créez-en un, générez-le avec une IA ou importez-le.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(32)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [7, 7]))
        }
    }

    private static func relativeDate(_ date: Date) -> String {
        guard date != .distantPast else { return "sans date" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "aujourd’hui" }
        if calendar.isDateInYesterday(date) { return "hier" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) { return date.formatted(.dateTime.day().month(.abbreviated)) }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

// MARK: - Pieces

/// Rounded tile in the questionnaire color, showing a symbol.
struct HomeTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 56

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        shape.fill(tint.gradient)
            .frame(width: size, height: size)
            .overlay { Image(systemName: symbol).font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.white) }
            .overlay { shape.strokeBorder(.white.opacity(0.22), lineWidth: 0.75) }
            .shadow(color: tint.opacity(0.32), radius: 8, y: 4)
            .accessibilityHidden(true)
    }
}

/// A provider's logo on a white tile, like an app icon: it stays legible on any background.
struct ProviderLogo: View {
    let provider: QuizProvider
    var size: CGFloat = 44

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        shape.fill(.white)
            .frame(width: size, height: size)
            .overlay { Image(provider.logo).resizable().scaledToFit().foregroundStyle(provider.logoColor).padding(size * 0.2) }
            .overlay { shape.strokeBorder(.black.opacity(0.1), lineWidth: 0.75) }
            .shadow(color: .black.opacity(0.14), radius: size > 30 ? 6 : 2, y: size > 30 ? 3 : 1)
            .accessibilityHidden(true)
    }
}

/// A quiet backdrop in the system's grouped grey with a faint wash of the accent colour at the top,
/// so the home screen sits with the rest of the app.
struct AudienceBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            #if os(macOS)
            Color(nsColor: .windowBackgroundColor)
            #else
            Color(uiColor: .systemGroupedBackground)
            #endif
            RadialGradient(colors: [Color.accentColor.opacity(scheme == .dark ? 0.16 : 0.08), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 900)
        }
        .accessibilityHidden(true)
    }
}

/// The system blue, deepening toward a hint of indigo; dark enough for white text everywhere.
private struct HeroGradient: View {
    var body: some View {
        ZStack {
            MeshGradient(width: 3, height: 3, points: [
                SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
                SIMD2(0, 0.5), SIMD2(0.55, 0.42), SIMD2(1, 0.5),
                SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
            ], colors: [
                Color(hex: 0x1F63EA), Color(hex: 0x2C66F0), Color(hex: 0x4F6BF2),
                Color(hex: 0x1857D6), Color(hex: 0x2F5FE6), Color(hex: 0x5A57E6),
                Color(hex: 0x143FB8), Color(hex: 0x2548CF), Color(hex: 0x4A44D0),
            ])
            LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

/// Press feedback for cards that carry their own surface.
private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(duration: 0.28, bounce: 0.3), value: configuration.isPressed)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Fades and lifts a section in when the screen appears, one after the other.
    func reveal(_ order: Int, _ shown: Bool, _ reduceMotion: Bool) -> some View {
        opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 18)
            .animation(reduceMotion ? nil : .smooth(duration: 0.6).delay(Double(order) * 0.08), value: shown)
    }
}
