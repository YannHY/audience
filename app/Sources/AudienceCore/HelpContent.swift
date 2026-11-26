import Foundation

/// The in-app help. It lives in the core so the same text feeds the Mac help window and the
/// iPad settings, and so tests can check it (unique topics, the Markdown example it offers).
public enum HelpPlatform: Sendable { case mac, iPad }

public struct HelpRow: Equatable, Sendable {
    public let term: String
    public let detail: String
    public init(_ term: String, _ detail: String) { self.term = term; self.detail = detail }
}

/// Inline Markdown (`**bold**`, `` `code` ``) is allowed in every string except `example`'s code.
public enum HelpBlock: Equatable, Sendable {
    case text(String)
    case bullets([String])
    case rows([HelpRow])
    case note(String)
    /// A text the reader can copy, folded away until asked for.
    case example(label: String, code: String)
}

public struct HelpTopic: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let symbol: String
    public let blocks: [HelpBlock]

    public static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Every word of the topic, to filter the list while searching.
    public var searchableText: String {
        ([title] + blocks.flatMap { block -> [String] in
            switch block {
            case .text(let text), .note(let text): [text]
            case .bullets(let items): items
            case .rows(let rows): rows.flatMap { [$0.term, $0.detail] }
            case .example(let label, _): [label]
            }
        }).joined(separator: " ")
    }
}

public enum HelpContent {
    public static func topics(for platform: HelpPlatform) -> [HelpTopic] {
        let mac = platform == .mac
        return [start(mac), create(mac), questionTypes, formatting, timing, present(mac), results(mac), library(mac),
         importExport(mac), assistant(mac), account(mac), shortcuts(mac), tips]
    }

    // MARK: Topics

    private static func start(_ mac: Bool) -> HelpTopic {
        HelpTopic(id: "start", title: "Premiers pas", symbol: "hand.wave", blocks: [
            .text("Audience prépare des questionnaires, les présente à un groupe et recueille en direct les réponses du public, depuis son téléphone."),
            .bullets([
                mac ? "**Créez** un questionnaire avec **Nouveau questionnaire** (⌘N), ou importez-en un (⇧⌘I)."
                    : "**Créez** un questionnaire depuis l’accueil : **Créer avec une IA**, **Questionnaire vierge** ou **Bibliothèque**.",
                "**Présentez-le** avec le bouton **Présenter** : un QR code et un code s’affichent pour que le public rejoigne la session.",
                "**Consultez** les réponses dans **Résultats** et **Statistiques**, ou exportez-les en CSV."
            ]),
            .note("La préparation et la présentation fonctionnent hors ligne. Une connexion au compte Audience n’est nécessaire que pour recueillir les réponses du public (**Lancer en direct**) et synchroniser vos questionnaires avec le site.")
        ])
    }

    private static func create(_ mac: Bool) -> HelpTopic {
        var blocks: [HelpBlock] = [
            .text(mac ? "**Nouveau questionnaire** (⌘N) ajoute un questionnaire vide à la bibliothèque. Donnez-lui un titre, puis ajoutez des questions avec **Ajouter une question**."
                      : "**Questionnaire vierge** (ou le bouton **Nouveau questionnaire** de la bibliothèque) ajoute un questionnaire vide. Donnez-lui un titre, puis ajoutez des questions avec **Ajouter une question**."),
            .bullets([
                "Pour chaque question, choisissez le **Format**, saisissez l’**énoncé** et réglez le **Temps de réponse**.",
                mac ? "La liste des questions, à gauche de l’éditeur, permet de les réordonner par glisser-déposer. Le menu contextuel propose **Dupliquer**, **Monter**, **Descendre** et **Supprimer…** ; la touche Suppr supprime la question sélectionnée."
                    : "La liste des questions permet de les réordonner. Dans une fenêtre étroite, un bandeau numéroté passe d’une question à l’autre et **Organiser les questions** ouvre la liste. Le menu contextuel d’une question (appui long) propose **Dupliquer**, **Monter**, **Descendre** et **Supprimer…**.",
                "Une icône d’avertissement signale une question incomplète. Tant qu’une question est incomplète, le questionnaire ne peut pas être présenté et reste sur cet appareil, sans être synchronisé.",
                "Les modifications sont enregistrées automatiquement."
            ])
        ]
        if !mac {
            blocks.append(.text("Le bouton **‹ Accueil** (⌘[) ramène à l’écran d’accueil ; le questionnaire en cours est retrouvé en y revenant."))
        }
        return HelpTopic(id: "create", title: "Créer un questionnaire", symbol: "square.and.pencil", blocks: blocks)
    }

    private static let questionTypes = HelpTopic(id: "types", title: "Types de questions", symbol: "list.bullet.rectangle", blocks: [
        .rows([
            HelpRow("Choix unique", "Une seule bonne réponse parmi plusieurs propositions. **Sondage sans bonne réponse** recueille un avis sans correction."),
            HelpRow("Choix multiples", "Plusieurs bonnes réponses : cochez-les toutes. La correction exige toutes les bonnes réponses et aucune autre."),
            HelpRow("Réponse libre", "Texte libre saisi par le participant. Avec **Format de réponse → Mathématiques (LaTeX)**, il répond avec un clavier mathématique."),
            HelpRow("Nuage de mots", "Mots-clés collectés en direct et affichés ensemble."),
            HelpRow("Évaluation", "Une note de 1 à 5 étoiles."),
            HelpRow("Texte à trous", "Le texte à compléter, avec `[réponse]` pour chaque trou, ou `{{réponse, autre choix}}` pour un choix proposé."),
            HelpRow("Vidéo", "Une vidéo YouTube, lue directement dans l’aperçu et la présentation (connexion Internet requise). Un bouton permet aussi de l’ouvrir sur YouTube."),
            HelpRow("Classement", "Des éléments à remettre dans l’ordre. Placez-les dans l’ordre attendu : ils sont mélangés jusqu’à la correction."),
            HelpRow("Image à légender", "Une image (2 Mo au maximum, choisie ou glissée) et des étiquettes que les participants placent dessus. La position de chaque étiquette se règle en pourcentage de l’image.")
        ]),
        .note("**Montrer les résultats aux participants** s’active question par question, dans l’éditeur.")
    ])

    private static let formatting = HelpTopic(id: "format", title: "Mettre en forme le texte", symbol: "textformat", blocks: [
        .text("L’énoncé d’une question se saisit en Markdown léger. Un aperçu apparaît sous l’énoncé dès qu’il est mis en forme, et les participants voient la même mise en forme."),
        .rows([
            HelpRow("`**gras**`", "**gras**"),
            HelpRow("`*italique*` ou `_italique_`", "*italique*"),
            HelpRow("`<u>souligné</u>`", "texte souligné"),
            HelpRow("`- ` en début de ligne", "élément d’une liste à puces")
        ]),
        .text("Les astérisques entre deux chiffres (`2*3*4`) restent du texte ; `\\*` garde un astérisque. Les titres et les réponses restent en texte simple."),
        .text("**Formules mathématiques.** Écrivez-les en LaTeX entre `\\(` et `\\)`, par exemple `\\(\\hat{y} = wx + b\\)`. L’app conserve ces formules mais ne les met pas en forme à l’écran : elles y apparaissent comme du texte, alors que le site des participants les affiche en mathématiques.")
    ])

    private static let timing = HelpTopic(id: "timing", title: "Temps de réponse", symbol: "timer", blocks: [
        .text("Chaque question a son propre temps de réponse, choisi dans l’éditeur : 5, 10, 15, 20, 30, 45 ou 90 secondes, ou 1, 2, 3 ou 4 minutes. La durée par défaut est de **30 secondes**."),
        .text("Pendant une session en direct, le temps restant s’affiche dans l’en-tête de la présentation. Une réponse envoyée après ce délai est refusée par le site. **Relancer** redonne du temps pour la question affichée.")
    ])

    private static func present(_ mac: Bool) -> HelpTopic {
        HelpTopic(id: "present", title: "Présenter en direct", symbol: "play.rectangle", blocks: [
            .text(mac ? "**Présenter** (⌥⌘P) ouvre la présentation dans sa propre fenêtre, qui peut passer en plein écran (⌃⌘F)."
                      : "**Présenter** ouvre la présentation en plein écran. L’iPad reste éveillé tant qu’elle est ouverte."),
            .text("Elle commence par une **salle d’attente** : QR code, adresse et code de la session, en grand, à montrer au public."),
            .bullets([
                "**Commencer** (Entrée ou espace) ouvre la première question. Sans session en direct, c’est un aperçu pour vous seul.",
                "**Lancer en direct** recueille les réponses du public. Il demande d’être connecté au compte Audience. Choisissez **Nouvelle session** (les réponses précédentes sont effacées) ou **Conserver les réponses précédentes**.",
                "Les participants scannent le QR code, ou ouvrent l’adresse et saisissent le code. Ils saisissent leur nom si le questionnaire le demande, puis voient « Merci de patienter » jusqu’à **Commencer**.",
                "Pendant le direct, l’en-tête affiche le nombre de participants connectés, le nombre de réponses à la question en cours et le temps restant. **Participer** réaffiche le QR code ; **Copier le lien** copie l’adresse de participation.",
                "**Arrêter** met fin à la session. Fermer la présentation l’arrête aussi, et quitter l’app demande d’abord de l’arrêter."
            ]),
            .rows([
                HelpRow("→ ou espace", "Question suivante"),
                HelpRow("←", "Question précédente"),
                HelpRow("C", "Afficher ou masquer la correction"),
                HelpRow("R", "Afficher les réponses reçues"),
                HelpRow("T", "Relancer le minuteur de la question")
            ]),
            mac ? .note("Pendant une session en direct, l’édition du questionnaire et la synchronisation sont suspendues, pour ne pas perturber le déroulement.")
                : .note("Pendant une session en direct, l’édition du questionnaire et la synchronisation sont suspendues. Avec un clavier, les raccourcis ci-dessus fonctionnent aussi ; au toucher, utilisez les boutons de la barre de commandes.")
        ])
    }

    private static func results(_ mac: Bool) -> HelpTopic {
        var blocks: [HelpBlock] = [
            .text("Le sélecteur **Éditeur / Résultats / Statistiques** change l’affichage du questionnaire."),
            .bullets([
                "**Résultats** : une barre par réponse (lettre, nombre, pourcentage, bonne réponse en vert) et les réponses textuelles. **Actualiser** relit le site ; pendant le direct, les résultats se mettent à jour toutes les trois secondes.",
                "**Exporter en CSV** enregistre le bilan : une ligne par question, une colonne par participant.",
                "**Statistiques** : nombre de réponses, justes et fausses, taux de réussite et réponses les plus fréquentes pour chaque question. Les réponses libres et les sondages ne sont pas évalués, et le taux ne porte que sur les réponses évaluées."
            ])
        ]
        blocks.append(mac
            ? .text("**Synthèse locale** (dans Statistiques) : avec Ollama installé sur ce Mac, un modèle local résume les résultats, les difficultés observées et les pistes de reprise. **Modèles…** permet de détecter ou de télécharger un modèle. Les noms des participants ne quittent pas votre Mac. Vérifiez toujours les interprétations du modèle.")
            : .text("**Synthèse par un assistant IA** (dans Statistiques) : l’assistant que vous avez connecté (ChatGPT avec votre compte, Claude, Gemini ou Groq avec une clé API) résume les résultats, les difficultés observées et les pistes de reprise. Connectez-le d’abord dans **Réglages → Assistants IA**. Rien n’est envoyé avant que vous touchiez **Générer la synthèse** ; les noms et identifiants des participants ne le sont jamais, mais les réponses libres les plus fréquentes, si. Vérifiez toujours les interprétations du modèle."))
        blocks.append(.note("Les résultats sont téléchargés depuis le site quand vous êtes connecté ; ceux d’une sauvegarde importée restent consultables sans connexion."))
        return HelpTopic(id: "results", title: "Résultats et statistiques", symbol: "chart.bar", blocks: blocks)
    }

    private static func library(_ mac: Bool) -> HelpTopic {
        HelpTopic(id: "library", title: "Organiser vos questionnaires", symbol: "folder", blocks: [
            .bullets([
                mac ? "**Dossiers** : **Nouveau dossier** (⇧⌘N) crée un dossier, avec la sélection si elle existe. Glissez un questionnaire sur un dossier pour le ranger ; le menu contextuel d’un dossier permet de le renommer, de lui donner une couleur ou de le supprimer (ses questionnaires sont conservés)."
                    : "**Dossiers** : **Nouveau dossier**, dans la barre latérale, crée un dossier. Glissez un questionnaire dessus pour le ranger ; le menu contextuel d’un dossier permet de le renommer, de lui donner une couleur ou de le supprimer (ses questionnaires sont conservés).",
                "**Étiquettes** : ajoutez-en jusqu’à 12 à un questionnaire, dans l’inspecteur. Chaque étiquette devient une entrée de la barre latérale.",
                "**Favoris**, **couleur** du questionnaire (Automatique reprend celle du dossier) et **tri** de la liste.",
                "**Recherche** par titre, code ou étiquette.",
                mac ? "**Sélection multiple** : déplacez, mettez en favori, exportez ou placez dans la corbeille plusieurs questionnaires à la fois. **Dupliquer** : ⌘D."
                    : "Le menu contextuel d’un questionnaire (appui long) propose **Dupliquer**, **Déplacer vers**, **Couleur** et **Placer dans la corbeille**.",
                "**Corbeille** : **Remettre en place** annule la suppression. **Supprimer définitivement** et **Vider la corbeille** sont irréversibles : les réponses recueillies sont supprimées aussi, sur cet appareil et sur le compte synchronisé."
            ]),
            .text(mac ? "**L’inspecteur** (bouton à droite de la barre d’outils, ⌥⌘I) regroupe les réglages du questionnaire sélectionné."
                      : "**Réglages du questionnaire** (menu **Actions** de l’éditeur) regroupe les réglages du questionnaire ouvert."),
            .rows([
                HelpRow("Rangement", "Dossier, favori, étiquettes."),
                HelpRow("Demander le nom des participants", "Les participants saisissent un nom ou un prénom avant la première question. Ce nom apparaît dans l’export CSV."),
                HelpRow("Autoriser le rapport individuel", "À la fin du questionnaire, chaque participant peut consulter, puis télécharger en PDF, un récapitulatif de ses réponses : bonnes, fausses, non notées, et la réponse attendue quand une réponse corrigée automatiquement est fausse."),
                HelpRow("Informations", "Le code du questionnaire, qui se copie.")
            ])
        ])
    }

    private static func importExport(_ mac: Bool) -> HelpTopic {
        HelpTopic(id: "import", title: "Importer et exporter", symbol: "square.and.arrow.down", blocks: [
            .text(mac ? "**Fichier → Importer…** (⇧⌘I) ouvre une fenêtre unique : choisissez des fichiers, glissez-les, ou collez le texte d’un questionnaire."
                      : "**Importer**, en haut de l’accueil et dans la barre du bas de la bibliothèque, ouvre une fenêtre unique : choisissez des fichiers dans **Fichiers**, ou collez le texte d’un questionnaire."),
            .bullets([
                "Fichiers acceptés : questionnaires **Markdown** (`.md`, plusieurs à la fois), archive **ZIP** exportée du site et sauvegarde **Audience** (`.json`).",
                mac ? "**Fichier → Exporter une sauvegarde…** (⇧⌘E) ou **Tout exporter…** dans les réglages enregistre toute la bibliothèque ; **Exporter…** n’enregistre que la sélection. Les images et les réponses sont incluses, sans identifiant de connexion."
                    : "**Exporter la bibliothèque…**, dans les réglages, enregistre une sauvegarde dans **Fichiers**. Les images et les réponses sont incluses, sans identifiant de connexion.",
                "Un questionnaire importé reçoit un nouveau code s’il existe déjà."
            ]),
            .text("**Le format Markdown** d’un questionnaire :"),
            .rows([
                HelpRow("`# Titre`", "Le titre du questionnaire."),
                HelpRow("`## Question 1`", "Une section par question, avec l’énoncé en dessous."),
                HelpRow("`- [ ]` et `- [x]`", "Les réponses, la bonne étant cochée. Plusieurs cases cochées donnent des choix multiples."),
                HelpRow("`- Type:`", "Pour les autres formats : question ouverte, nuage de mots, notation en étoiles (1 à 5), classement, texte à trous, vidéo YouTube, légender une image."),
                HelpRow("`- Format de réponse:`", "`mathématique`, après `- Type: question ouverte`, pour une réponse mathématique."),
                HelpRow("`- Texte à trous:`", "Le texte à compléter. De même pour les éléments d’un classement (`- Éléments à classer:`) et l’adresse d’une vidéo (`- URL vidéo:`) : voir l’exemple complet.")
            ]),
            .example(label: "Copier l’exemple complet", code: QuizMarkdown.generationExample),
            .note("Vous pouvez demander à une IA générative de rédiger un questionnaire dans ce format. Donnez-lui l’exemple complet ci-dessus pour qu’elle en reprenne la structure, puis collez le résultat dans la fenêtre d’import.")
        ])
    }

    /// The assistant exists on iPad only; the Mac topic points to the Markdown import instead.
    private static func assistant(_ mac: Bool) -> HelpTopic {
        guard !mac else {
            return HelpTopic(id: "assistant", title: "Créer avec une IA", symbol: "sparkles", blocks: [
                .text("L’assistant qui rédige un questionnaire à partir d’un document ou d’une vidéo est disponible sur iPad. Sur Mac, demandez à une IA générative de rédiger un questionnaire au format Markdown d’Audience (voir **Importer et exporter**), puis importez-le.")
            ])
        }
        return HelpTopic(id: "assistant", title: "Créer avec une IA", symbol: "sparkles", blocks: [
            .text("**Créer avec une IA**, depuis l’accueil, rédige un questionnaire à partir d’un document ou d’une vidéo. Vous le relisez avant de l’ajouter à la bibliothèque."),
            .rows([
                HelpRow("1. Service", "Choisissez ChatGPT, Claude, Gemini ou Groq. ChatGPT se connecte avec votre compte ; les trois autres se connectent avec une **clé API** collée une seule fois. Vous pouvez aussi les connecter, les changer ou les retirer dans **Réglages → Assistants IA**."),
                HelpRow("2. Contenu", "Un document PDF, Word (`.docx`), TXT ou Markdown (12 Mo au maximum), ou l’adresse d’une vidéo YouTube. Le nombre de questions est facultatif. Gemini regarde directement la vidéo ; les autres services demandent sa transcription."),
                HelpRow("3. Questionnaire", "La liste des questions à relire, avec le Markdown modifiable. Une question à corriger est signalée avant l’ajout.")
            ]),
            .bullets([
                "Rien n’est envoyé avant **Générer le questionnaire**.",
                "La clé API est vérifiée, puis conservée dans le Trousseau de l’iPad. **Retirer la clé** l’efface. Elle n’est envoyée qu’au service concerné.",
                "La facturation d’une clé API dépend de l’offre API du service, pas de l’abonnement grand public."
            ])
        ])
    }

    private static func account(_ mac: Bool) -> HelpTopic {
        HelpTopic(id: "account", title: "Compte et synchronisation", symbol: "arrow.triangle.2.circlepath", blocks: [
            .text(mac ? "Dans **Audience → Réglages → Compte**, connectez-vous avec l’adresse e-mail et le mot de passe de votre compte Audience. Le mot de passe est conservé dans le trousseau de ce Mac : l’app se reconnecte seule à chaque lancement."
                      : "Dans **Réglages → Compte Audience**, connectez-vous avec l’adresse e-mail et le mot de passe de votre compte Audience. Le mot de passe est conservé dans le trousseau de cet iPad : l’app se reconnecte seule à chaque lancement."),
            .bullets([
                "Une fois connecté, la bibliothèque se synchronise automatiquement avec le site : vos questionnaires, dossiers, étiquettes, favoris et corbeille.",
                mac ? "**Synchroniser maintenant** (⌘R) relance un échange sans attendre."
                    : "Tirez la liste des questionnaires vers le bas, ou utilisez **Synchroniser maintenant** dans les réglages, pour relancer un échange sans attendre.",
                "Les bibliothèques du Mac et de l’iPad sont locales et distinctes : c’est le compte qui les rapproche, via le site.",
                mac ? "Si un questionnaire a changé des deux côtés, la version de ce Mac est conservée dans un questionnaire séparé, marqué « conflit sur ce Mac »."
                    : "Si un questionnaire a changé des deux côtés, la version de cet iPad est conservée dans un questionnaire séparé, marqué « conflit sur cet iPad ».",
                "Hors ligne, tout continue de fonctionner sauf le direct ; la synchronisation reprend dès que la connexion revient."
            ]),
            .text(mac ? "**Se déconnecter** efface le mot de passe du trousseau."
                      : "**Se déconnecter** efface le mot de passe du trousseau de l’iPad.")
        ])
    }

    private static func shortcuts(_ mac: Bool) -> HelpTopic {
        let appearance = mac ? "**Audience → Réglages → Général → Apparence**" : "**Réglages → Apparence → Thème**"
        var rows = [
            HelpRow("⌘N", "Nouveau questionnaire")
        ]
        if mac {
            rows += [
                HelpRow("⇧⌘N", "Nouveau dossier (avec la sélection)"),
                HelpRow("⌘D", "Dupliquer"),
                HelpRow("⌥⌘P", "Présenter"),
                HelpRow("⇧⌘I", "Importer"),
                HelpRow("⇧⌘E", "Exporter une sauvegarde"),
                HelpRow("⌘R", "Synchroniser maintenant"),
                HelpRow("⌥⌘I", "Afficher ou masquer l’inspecteur"),
                HelpRow("⌃⌘F", "Plein écran (présentation)"),
                HelpRow("⌘?", "Ouvrir cette aide")
            ]
        } else {
            rows += [
                HelpRow("⌘[", "Retour à l’accueil"),
                HelpRow("⇧⌘L", "Masquer ou afficher la liste des questionnaires")
            ]
        }
        return HelpTopic(id: "shortcuts", title: "Raccourcis et apparence", symbol: "keyboard", blocks: [
            .rows(rows),
            .text("**Apparence** : Système, Clair ou Sombre, dans \(appearance).")
        ])
    }

    private static let tips = HelpTopic(id: "tips", title: "Conseils pratiques", symbol: "lightbulb", blocks: [
        .bullets([
            "Préparez votre questionnaire avant la séance pour gagner du temps.",
            "Testez une question avant de lancer la session en classe : **Commencer** sans direct ouvre un aperçu.",
            "Exportez régulièrement vos questionnaires : une sauvegarde est vite faite.",
            "Une session en direct demande une connexion Internet, pour l’appareil qui présente comme pour le public : vérifiez-la avant de commencer."
        ])
    ])
}
