import SwiftUI
#if SWIFT_PACKAGE
import AudienceCore
#endif

/// Asked once per account, like on the website: the synchronization waits for the answer.
struct TermsSheet: View {
    let store: LibraryStore
    @State private var agreed = false

    private static let termsURL = RemoteClient.siteURL.appending(path: "conditions-utilisation.html")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Conditions d’utilisation", systemImage: "checkmark.shield")
                .font(.title2.bold())
            Text("Bienvenue sur Audience ! Avant de synchroniser vos questionnaires, merci de prendre connaissance des conditions d’utilisation. En résumé :")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                point("Le site est fourni « en l’état », sans garantie de disponibilité : exportez régulièrement vos questionnaires.")
                point("Vous êtes seul(e) responsable des contenus que vous publiez (questions, images, vidéos, liens) et de leur usage.")
                point("Vous vous engagez à respecter le droit d’auteur, le droit à l’image et les données personnelles de vos participants.")
            }
            Link("Lire les conditions d’utilisation complètes", destination: Self.termsURL)
            Toggle("J’ai lu et j’accepte les conditions d’utilisation", isOn: $agreed)
                .toggleStyle(.checkbox)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: .rect(cornerRadius: 10))
            HStack {
                Button("Refuser et se déconnecter", role: .destructive) { Task { await store.disconnect() } }
                    .disabled(store.busy)
                Spacer()
                if store.busy { ProgressView().controlSize(.small) }
                Button("Accepter") { Task { await store.acceptTerms() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!agreed || store.busy)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 500)
        .interactiveDismissDisabled()
    }

    private func point(_ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.secondary)
        }
        .labelStyle(.titleAndIcon)
    }
}
