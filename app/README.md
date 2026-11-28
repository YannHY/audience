# Audience pour macOS et iPad

Application native SwiftUI pour **macOS 26 ou ultérieur**, sans Electron, WebView, Node.js ni serveur local. Le site PHP situé dans le dossier parent reste indépendant.

## Ouvrir l’application

Sur Mac et iPad, l’accueil (Liquid Glass, clair et sombre, du texte standard aux tailles d’accessibilité) propose trois entrées : **Créer avec une IA**, **Questionnaire vierge** et **Bibliothèque**, puis les questionnaires récents. **Importer** et **Réglages** sont dans la barre du haut ; le fond reprend le gris système et l’accent bleu du reste de l’app. Dans la bibliothèque et l’éditeur, **‹ Accueil** (⌘[) ramène à l’accueil et retrouve le questionnaire en cours. Le parcours **Créer avec une IA** (aussi accessible via ⌥⌘N sur Mac) utilise directement l’assistant connecté (changeable depuis la barre d’outils ; la connexion des assistants se fait dans **Réglages → Assistants IA**, auquel la feuille renvoie si aucun n’est connecté) et se fait en deux temps : **Contenu** (document PDF, Word `.docx`, TXT ou Markdown, ou adresse YouTube ; nombre de questions et consignes repliés dans **Options**), **Questionnaire** (liste des questions relue avant l’ajout, Markdown modifiable). Pour une vidéo YouTube, Gemini reçoit directement l’adresse ; les autres services demandent aussi la transcription. Aucune source n’est envoyée avant **Générer le questionnaire**, et une question à corriger est signalée avant l’ajout à la bibliothèque.

**ChatGPT** se connecte avec le compte (OAuth, comme dans Scénarisation) ; les jetons sont conservés dans le Trousseau. **Claude**, **Gemini** et **Groq** n’offrent pas de connexion par compte aux applications tierces : ils se connectent avec une **clé API**, collée une seule fois. Audience la vérifie en demandant la liste des modèles, propose le plus adapté (modifiable) et conserve la clé dans le Trousseau du Mac ou de l’iPad ; **Retirer la clé** l’efface. La clé n’est envoyée qu’au service concerné, et sa facturation dépend de l’offre API de ce service, pas de l’abonnement grand public.

Les mêmes connexions se gèrent aussi dans **Réglages → Assistants IA** (connecter, changer de modèle, retirer), sans passer par la création d’un questionnaire. Elles servent aussi à la **synthèse des résultats** : dans Statistiques, **Générer la synthèse** envoie à l’assistant choisi les énoncés, les chiffres et les réponses les plus fréquentes (réponses libres comprises), jamais les noms ni les identifiants des participants, et seulement à l’action sur le bouton. Même consigne que la synthèse Ollama du Mac ; la synthèse est conservée pendant la session et invalidée quand les résultats changent.

Les logos des assistants (`Resources/iPad.xcassets/Logo*.imageset`) sont les SVG officiels du paquet [@lobehub/icons-static-svg](https://github.com/lobehub/lobe-icons) 1.106.0 (licence MIT), reproduits sans modification de forme ; seuls l’en-tête et l’écriture des arcs ont été normalisés pour le compilateur de catalogues, et ChatGPT, Gemini et Groq sont monochromes, teintés à l’affichage. OpenAI, ChatGPT, Claude, Anthropic, Gemini, Google et Groq sont des marques de leurs propriétaires, utilisées uniquement pour désigner le service auquel l’utilisateur se connecte. Vérifier les chartes de marque de chacun avant une publication sur l’App Store.

L’archive prête à utiliser est `build/Publication-1.3.5-12/mac/Audience-macOS.zip` : décompressez-la puis ouvrez **Audience.app**. Une copie est également disponible dans `build/Audience.app` :

```sh
open build/Audience.app
```

Le binaire est universel : Apple Silicon et Intel. Par défaut, les scripts appliquent une signature locale ad hoc. Pour produire une version signée avec le compte développeur Apple et notarisée, utilisez les variables ci-dessous.

## Organisation des fichiers

Le dossier `build` garde quatre entrées visibles :

- `Publication-1.3.5-12/` : les fichiers de la version actuelle à publier, avec les instructions.
- `Audience.app` : l’application Mac à ouvrir.
- `archives/` : les dossiers de publication des anciennes versions.
- `travail/` : les fichiers techniques de compilation, les exports intermédiaires, l’historique Sparkle et les captures de vérification.

La préparation d’une nouvelle version range automatiquement les précédents dossiers `Publication-*` dans `archives/`. Conserver `build/travail/updates/` : son historique sert à produire les mises à jour Mac.

## Développer et compiler

Ouvrez `Audience.xcodeproj` avec Xcode 26 ou ultérieur, sélectionnez le schéma **Audience**, puis lancez avec ⌘R. La première compilation télécharge Sparkle 2.10.1, le composant de mise à jour (licence MIT).

Depuis le dossier `app` :

```sh
./scripts/build.sh
./scripts/test.sh
```

La compilation produit `build/Audience.app` et `build/travail/Audience-macOS.zip`. La signature de l’application contenue dans le ZIP est vérifiée avant sa création, hors du dossier iCloud. Pour une compilation dans un environnement qui interdit le sandbox imbriqué des macros Swift :

```sh
./scripts/build.sh OTHER_SWIFT_FLAGS=-disable-sandbox
```

Le projet Swift Package permet aussi `swift build` et `swift test`. Pour ajouter des fichiers au projet Xcode, exécutez `python3 scripts/generate-project.py`.

## Version iPad

Le schéma **Audience-iPad** du même projet Xcode produit une application native pour **iPadOS 26 ou ultérieur**. La bibliothèque, l’éditeur, les résultats, les statistiques et la synchronisation utilisent le même code et les mêmes formats que sur Mac.

- Navigation adaptative en portrait, paysage et fenêtre partagée. Ouvrir un questionnaire donne tout l’écran à l’éditeur, comme un document ; le bouton système en haut à gauche réaffiche les listes, qui reviennent d’elles-mêmes quand aucun questionnaire n’est ouvert. **Éditeur**, **Résultats** et **Statistiques** sont dans la barre de titre. La liste des questions reste visible à côté de l’éditeur dès que la largeur le permet (réordonnement par glisser-déposer, menu contextuel pour le reste) ; dans une fenêtre étroite, un bandeau numéroté passe d’une question à l’autre et **Organiser les questions** ouvre la liste. Temps de réponse et visibilité des résultats sont regroupés en bas, sous **Réglages de la question**. Dans la liste des questionnaires, la recherche est en tête de colonne, et le menu **…** regroupe le tri, **Importer…** et **Réglages**. Le compte et l’état de synchronisation se trouvent dans **Réglages** ; tirer la liste des questionnaires vers le bas lance une synchronisation.
- Import Markdown, JSON et ZIP depuis **Fichiers**, collage de texte et images intégrées ; export des sauvegardes JSON et des résultats CSV vers Fichiers.
- Présentation en plein écran, correction, réponses reçues, QR code, salle d’attente et commandes tactiles du direct. L’iPad reste éveillé tant que la présentation est ouverte. Une connexion au compte Audience est nécessaire pour la participation en ligne.
- Compte et apparence dans **Réglages** ; mot de passe dans le trousseau iPadOS. Quand la session du site expire, l’app se reconnecte d’elle-même avec ce mot de passe et renvoie la requête interrompue (Mac et iPad). Si c’est impossible (hors ligne, mot de passe changé), elle repasse à l’état déconnecté sans rien effacer : **Réglages** propose aussitôt de se reconnecter, sans passer par « Se déconnecter ». Les bibliothèques Mac et iPad sont locales et distinctes : le compte Audience les synchronise via le site. Sur iPad, les synthèses des résultats passent par l’assistant connecté dans **Réglages → Assistants IA** ; Ollama reste réservé au Mac.

Dans Xcode, sélectionnez **Audience-iPad**, choisissez un simulateur iPad, puis lancez avec ⌘R. L’équipe Apple **Yann Houry (`D73WW234K6`)**, utilisée pour l’application Mac, est déjà sélectionnée avec la signature automatique **Apple Development**. Pour installer sur votre iPad, branchez l’appareil et lancez le même schéma. Le certificat Developer ID utilisé pour macOS ne permet pas l’installation sur iPad ; le certificat Apple Development existant de la même équipe est utilisé avec un profil de développement iOS ([types de certificats Apple](https://developer.apple.com/help/account/certificates/certificates-overview)).

Depuis le dossier `app` :

```sh
./scripts/build-ipad.sh simulator
./scripts/build-ipad.sh device
./scripts/build-ipad.sh archive
./scripts/build-ipad.sh export
```

Le premier script produit `build/travail/iPad/Simulator/Audience-iPad.app`. Le mode `archive` prépare `build/travail/iPad/Audience-iPad.xcarchive`. Le mode `export` utilise cette archive pour produire `build/travail/iPad/Export/Audience.ipa`, signé avec le certificat Apple Development existant de Yann Houry et installable sur les appareils enregistrés dans son profil. Ce fichier de développement n’est pas une distribution TestFlight ou App Store. Pour vérifier la compilation destinée aux appareils sans signer, ajoutez `CODE_SIGNING_ALLOWED=NO` au mode `device` ; ce résultat n’est pas directement installable.

Vérifications : compilation simulateur et appareil iOS, compilation Mac et 87 tests du noyau partagés réussis ; captures de l’éditeur, des résultats, de l’import et de la présentation inspectées sur simulateur iPad 11 pouces. L’archive a ensuite été signée avec l’équipe `D73WW234K6`, sa signature vérifiée et l’IPA de développement exporté avec succès. La connexion au site avec un compte réel et l’installation sur un appareil restent à vérifier.

Les données sont enregistrées dans `Library/Application Support/AudienceNative/library.json` du conteneur privé de l’app. Les fichiers importés utilisent les autorisations temporaires de Fichiers. En Debug uniquement, `AUDIENCE_IPAD_PREVIEW` (`editor`, `results`, `statistics`, `presentation`, `settings`, `import`, `inspector`) ouvre un écran avec des données d’exemple si `AUDIENCE_LIBRARY` pointe vers une bibliothèque de test distincte.

## Préparer une publication Mac et TestFlight

La version de publication courante est **1.3.5 (build 12)** sur Mac et iPad. Après compilation Mac signée/notarisée, génération du flux avec `scripts/publish-update.sh` et création de l’archive iPad, exécuter :

```sh
python3 scripts/prepare-publication.py
```

La préparation vérifie que les versions Mac et iPad correspondent et contrôle la signature de l’archive iPad avant de la compresser. Si l’export `build/travail/TestFlight/Export/Audience.ipa` est présent, sa version est également vérifiée avant son ajout au dossier de publication.

Le dossier `build/Publication-1.3.5-12/mac/` contient uniquement les fichiers de téléchargement et de mise à jour Mac : téléchargement courant, archives versionnées, correctifs Sparkle, notes de version, flux et sources natives correspondantes. La préparation en place aussi une copie au premier niveau du site, dans `audience/mac/` : c’est ce dossier qu’il suffit de glisser dans `/apps/audience/` sur le serveur, en publiant `appcast.xml` en dernier. Il est remplacé à chaque nouvelle version et exclu de Git. Les pages, feuilles de style, scripts et images du site existant ne sont pas recopiés dans le dossier de publication.

Pour préparer l’iPad avec une configuration App Store Connect distincte de celle des appareils de développement :

```sh
./scripts/build-ipad.sh testflight-archive
./scripts/build-ipad.sh testflight-export -allowProvisioningUpdates
```

L’archive originale se trouve dans `build/travail/TestFlight/Audience-iPad.xcarchive`. L’export utilise `Resources/ExportOptions-TestFlight.plist`, la méthode `app-store-connect` et la destination `export` : **aucun envoi à Apple n’est effectué**. Un compte Apple développeur connecté à Xcode et un profil App Store correspondant sont nécessaires à la signature de distribution.

Le dossier `build/Publication-1.3.5-12/iPad-TestFlight/` fournit l’archive compressée pour préserver sa signature lors des copies iCloud, l’IPA de distribution dans `Export-AppStoreConnect/`, la configuration d’export, un script de réexport et les textes pour la fiche bêta. L’IPA 1.3.5 (12) reste à exporter depuis Xcode Organizer (certificat Cloud Managed Apple Distribution, profil App Store de l’équipe `D73WW234K6`) à partir de `build/travail/TestFlight/Audience-iPad.xcarchive` ; l’export de la 1.3.2 (9) est conservé dans `build/travail/TestFlight/Export-1.3.2-9/`. Ne pas déposer ce dossier sur le serveur web. Après envoi à App Store Connect, le build doit être traité par Apple avant d’être sélectionné dans TestFlight.

## Signature Apple Developer

Le certificat existant `Developer ID Application: Yann Houry (D73WW234K6)` et le profil de notarisation `scenarisation-notary` peuvent être réutilisés pour Audience. Ils restent dans le trousseau du Mac ; aucun mot de passe ni clé privée n’est enregistré dans le projet.

Depuis le dossier `app`, pour signer et notariser la version déjà compilée :

```sh
SIGN_IDENTITY='Developer ID Application: Yann Houry (D73WW234K6)' \
NOTARY_PROFILE=scenarisation-notary ./scripts/package.sh
```

Pour recompiler également, remplacez `./scripts/package.sh` par `./scripts/build.sh`. Pour signer sans notarisation, omettez `NOTARY_PROFILE`.

Le script signe avec le runtime renforcé et un horodatage Apple, vérifie la signature des deux architectures, soumet l’archive à Apple si demandé, puis agrafe et vérifie le ticket de notarisation. Il produit `build/Audience.app` et `build/travail/Audience-macOS.zip`. Le résultat de notarisation est conservé dans `build/travail/Audience-notarization.json` ; un refus interrompt la préparation. Pour distribuer ou installer l’app depuis ce projet iCloud, utilisez le ZIP et décompressez-le hors iCloud (par exemple dans Téléchargements), puis déplacez l’app dans Applications. Le script signale si les attributs ajoutés par iCloud empêchent de valider la copie `.app` du projet ; le ZIP contient la version vérifiée hors iCloud.

Références : [certificats Developer ID](https://developer.apple.com/help/account/certificates/create-developer-id-certificates), [notarisation macOS](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Mises à jour automatiques

Comme Scénarisation, Audience utilise [Sparkle 2](https://sparkle-project.org/documentation/) : vérification quotidienne et commande **Audience → Rechercher les mises à jour…**. Sparkle propose l’installation et le redémarrage ; l’utilisateur peut autoriser les installations automatiques dans sa fenêtre. Les recherches et le redémarrage sont différés pendant une session en direct. Les données locales sont enregistrées avant le redémarrage.

Le flux est prévu à `https://www.ralentirtravaux.com/apps/audience/mac/appcast.xml`. Les archives sont vérifiées avec la clé publique EdDSA d’`Resources/Info.plist`, en plus de la signature Apple. La clé privée propre à Audience reste dans le trousseau de session, compte `audience-mac` ; aucune clé privée ne doit être ajoutée au dépôt.

Pour préparer chaque version, depuis `app` :

1. Augmenter `CFBundleShortVersionString` **et** `CFBundleVersion` dans `Resources/Info.plist` (Sparkle compare le second).
2. Compiler, signer et notariser :

   ```sh
   SIGN_IDENTITY='Developer ID Application: Yann Houry (D73WW234K6)' \
   NOTARY_PROFILE=scenarisation-notary ./scripts/build.sh
   ```

3. Exécuter `./scripts/publish-update.sh`. Le script vérifie la signature, la notarisation et la correspondance de la clé, puis prépare une archive nommée avec la version et le numéro de build ainsi qu’`appcast.xml` dans `build/travail/updates/`. Il refuse de remplacer une archive de même version par un contenu différent. Les notes de version se rédigent dans `Resources/ReleaseNotes.json` (une entrée par version, la plus récente en tête) : le script en tire, avec `scripts/release-notes.py`, une page HTML aux couleurs du site pour chaque version, et régénère la page publique `nouveautes.html` à la racine du site (liée depuis `app.html`), à déposer avec les autres pages. Comme Sparkle n’affiche que la page de la dernière version, chacune reprend tout l’historique antérieur. Le script refuse de publier un build sans entrée dans ce fichier.
4. Déposer les archives et les éventuelles notes de version sur le serveur dans `apps/audience/mac/`, puis **le flux `appcast.xml` en dernier**. Conserver le dossier `build/travail/updates/` entre les versions pour préserver l’historique du flux ; ne pas téléverser `old_updates/`. Le script prépare les fichiers localement et ne publie rien sur le serveur. Lors de la première signature, macOS peut demander d’autoriser `generate_appcast` à accéder à la clé dans le trousseau.

La version 1.3.0 (build 7) introduit ce mécanisme. Les versions antérieures doivent être remplacées une première fois manuellement. Le flux doit être publié avec cette première version avant sa distribution.

Pour sauvegarder la clé privée dans un emplacement sécurisé hors du dépôt, utiliser une fois `build/travail/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account audience-mac -x /chemin/securise/audience-sparkle.key`. Une clé perdue empêcherait de signer les prochaines archives pour les installations existantes.

## Utilisation

- **Bibliothèque** : dossiers colorés, étiquettes, couleurs de questionnaire, favoris, tri, recherche (titre, code ou étiquette), sélection multiple, duplication, corbeille et vidage de la corbeille. Glissez un questionnaire sur un dossier, une étiquette, les Favoris ou la Corbeille dans la barre latérale.
- **Inspecteur** (bouton à droite de la barre d’outils ou ⌥⌘I) : dossier, couleur, étiquettes, réglages de participation et informations du questionnaire.
- **Éditeur** : liste des questions à gauche (réorganisation par glisser-déposer, touche Suppr, menu contextuel), choix unique, choix multiples, réponse libre, nuage de mots, évaluation, texte à trous, vidéo YouTube, classement et image à légender. Images intégrées aux sauvegardes, limite de 2 Mo, ajout par glisser-déposer possible.
- **Présentation** : fenêtre native indépendante, plein écran (⌃⌘F), flèches gauche/droite ou espace, correction (C) et réponses reçues (R). Les éléments d’un classement sont mélangés jusqu’à la correction. **Présenter** affiche d’abord la salle d’attente sur Mac et iPad : QR code généré localement, adresse et code en grand. **Lancer en direct** prépare la participation en ligne sans afficher de question et ajoute le nombre de participants connectés. Sans direct, **Commencer** ouvre la première question en aperçu. Les téléphones affichent « Merci de patienter » jusqu’à **Commencer** (Entrée ou espace), qui ouvre la première question et son minuteur. Pendant la session, le bouton Participer réaffiche le QR code.
- **Résultats** : barres par réponse (lettre, nombre, pourcentage, bonne réponse en vert) et réponses textuelles, récupérés depuis le site ou une sauvegarde. **Exporter en CSV** enregistre le même tableau que le bilan final du site (une ligne par question, une colonne par participant). Les résultats du direct sont actualisés toutes les trois secondes tant que la fenêtre de présentation reste ouverte.
- **Statistiques** : nombre de soumissions, réponses justes/fausses, taux de réussite sur les réponses évaluées et réponses les plus fréquentes par question. La correction des choix multiples exige toutes les bonnes réponses sans choix supplémentaire. Les réponses libres, sondages et données insuffisantes restent non évalués. Les anciens totaux par choix ne permettent pas toujours de retrouver le nombre de soumissions.
- **Synthèse des résultats** : dans Statistiques, par un assistant IA connecté (**ChatGPT**, **Claude**, **Gemini** ou **Groq**, configurés dans **Réglages → Assistants IA**) sur Mac et iPad, ou en **Synthèse locale** hors ligne avec Ollama sur ce Mac. Ouvrez **Modèles…** dans Statistiques ou **Réglages → Modèles locaux** pour détecter les modèles installés et télécharger Qwen, Gemma, DeepSeek ou un autre modèle local, avec progression et annulation. Installez et ouvrez [Ollama](https://ollama.com/download/mac) au préalable. Le téléchargement nécessite Internet ; les synthèses locales fonctionnent ensuite hors ligne, sans clé API ni transmission des noms et identifiants des participants. Les données agrégées sont limitées à environ 24 000 caractères, 60 questions et 8 réponses fréquentes par question. Les synthèses sont conservées pendant la session de l’app, copiables et invalidées quand les résultats changent ; leurs interprétations restent à vérifier.
- **Réglages** : apparence système/claire/sombre, sauvegardes, connexion au site, assistants IA (Mac et iPad) et modèles locaux (Mac).
- **Aide** : intégrée à l’app, sans passer par la page web. Sur Mac, **Aide → Aide Audience** (⌘?) ouvre une fenêtre à part avec la liste des rubriques et une recherche ; sur iPad, **Réglages → Aide Audience**. Le texte (`Sources/AudienceCore/HelpContent.swift`) est écrit pour chaque plateforme, avec les gestes et raccourcis qui lui sont propres, et offre le questionnaire d’exemple à copier pour le donner à une IA ; `HelpContentTests` vérifie que cet exemple reste importable. La page `aide.html` du site reste celle de la plateforme web.

Raccourcis : ⌘N nouveau questionnaire, ⌥⌘N créer avec une IA, ⇧⌘N nouveau dossier (avec la sélection), ⌘[ retour à l’accueil, ⌘F rechercher dans la liste, ⌘D dupliquer, ⌥⌘P présenter, ⌘R synchroniser.

La navigation utilise `NavigationSplitView`, l’inspecteur système, les barres d’outils et leurs matériaux Liquid Glass. Les contrôles flottants de présentation utilisent `GlassEffectContainer` et `glassEffect`. SF Symbols, menus, champs, dialogues de fichiers et raccourcis suivent les conventions macOS. La transparence est gérée par le système et ses réglages d’accessibilité.

## Données et ancienne application

Les données natives sont enregistrées de façon atomique dans :

```text
~/Library/Application Support/AudienceNative/library.json
```

Au premier démarrage, si ce fichier n’existe pas, l’application recherche `~/Library/Application Support/Audience/audience-local-store.json`. Elle récupère les questionnaires, les réponses et les images disponibles dans l’ancien dossier `uploads`, sans supprimer les fichiers d’origine. Un fichier illisible bloque les écritures pour éviter de l’écraser.

Les sauvegardes JSON Electron (version 1) sont importables. Un import ajoute les questionnaires et crée un nouveau code en cas de doublon, avec leurs résultats associés. Les champs supplémentaires des anciennes questions sont préservés. « Fichier → Importer… » (⇧⌘I) ouvre une seule fenêtre : choisir un fichier dans le Finder, le glisser-déposer, ou coller le texte d’un questionnaire. Elle accepte les sauvegardes JSON, les questionnaires au format Markdown du site (`.md`, plusieurs à la fois) et l’archive ZIP produite par l’export du site ; un texte Markdown collé crée un questionnaire rangé comme un nouveau ; la lecture suit les mêmes règles que `parseQuizMarkdown` dans `audience.js`.

Les énoncés des questions se saisissent en Markdown : `**gras**`, `*italique*` (ou `_italique_`), `<u>souligné</u>`, et `- ` en début de ligne pour une liste ; un aperçu apparaît sous l’énoncé dès qu’il est mis en forme. L’app enregistre et envoie le HTML que le site produit avec son propre éditeur, si bien que les participants voient la même mise en forme. Les énoncés déjà en Markdown (imports) sont convertis à l’envoi, et la mise en forme faite sur le site s’affiche et se modifie dans l’app. Les astérisques entre deux chiffres (`2*3*4`) et les tirets bas de « ______ » restent du texte ; `\*` garde un astérisque littéral. Les réponses et les titres restent en texte simple, comme sur le site. L’export inclut les images intégrées et les réponses, sans identifiants ni cookies de connexion.

## Connexion et participation

Dans **Audience → Réglages → Compte**, connectez-vous avec votre adresse e-mail et votre mot de passe habituels. L’adresse du site Audience est intégrée à l’application. L’adresse e-mail est retenue dans les préférences et le mot de passe dans le trousseau de session macOS (élément « Audience », service `fr.audience.native.account`) : l’app se reconnecte seule à chaque lancement. Hors ligne au lancement, elle réessaie quand sa fenêtre redevient active ou depuis le bouton de la barre latérale. Un mot de passe refusé par le site est effacé du trousseau ; **Se déconnecter** l’efface aussi. Les cookies de session restent en mémoire.

Avec une signature ad hoc, macOS peut redemander l’autorisation d’accéder au trousseau à chaque nouvelle compilation. Une signature Developer ID conserve l’identité de l’app entre les versions signées avec la même équipe. Au passage de la signature ad hoc à Developer ID, macOS peut demander de nouveau l’accès : saisissez le mot de passe de session du Mac et choisissez **Toujours autoriser**.

La bibliothèque est synchronisée automatiquement après la connexion. Les questionnaires du site apparaissent progressivement, avec leurs résultats disponibles. Les modifications locales sont envoyées après deux secondes sans nouvelle saisie ; l’app vérifie aussi le site toutes les trente secondes et quand sa fenêtre redevient active. **Synchroniser maintenant** permet de relancer immédiatement un échange.

La synchronisation met à jour les questionnaires en conservant leur code, leurs favoris et leur état dans la corbeille. Les dossiers (nom et couleur), le rangement, la couleur et les étiquettes de chaque questionnaire sont échangés avec la bibliothèque du site via `quiz_organize.php` ; si les deux côtés ont changé, la version du Mac l’emporte. Un dossier créé hors ligne est créé sur le site à la connexion suivante. Un questionnaire dont la date sur le site et le contenu local n’ont pas changé n’est pas retéléchargé : une vérification complète a lieu à la connexion, toutes les dix minutes et avec **Synchroniser maintenant**. Les résultats sont actualisés à l’ouverture de l’onglet Résultats. Les suppressions définitives confirmées dans l’app sont mises en attente hors ligne puis répercutées sur le compte. Les questionnaires incomplets restent locaux jusqu’à ce qu’ils soient valides. Les résultats sont téléchargés depuis le site ; les anciennes réponses issues d’une sauvegarde restent consultables localement.

L’app conserve une référence de la dernière version échangée pour distinguer les changements locaux et distants. Si les deux versions ont changé, celle du Mac est conservée dans un questionnaire séparé portant la mention « conflit sur ce Mac ». Les saisies faites pendant un téléchargement restent intactes. Les données de comptes différents ne sont pas envoyées au compte nouvellement connecté.

Une image ou des résultats indisponibles ne bloquent pas l’affichage du questionnaire. Les erreurs partielles apparaissent dans l’état de synchronisation et sont réessayées lors du prochain échange. Une session en direct suspend les envois automatiques pour préserver son déroulement.

La préparation et la présentation fonctionnent hors ligne. Pour recueillir les réponses des participants, connectez-vous au site puis utilisez **Lancer en direct** dans la présentation. Choisissez **Nouvelle session** (les réponses précédentes sont effacées, comme sur le site) ou **Conserver les réponses précédentes**. Chaque lancement crée une nouvelle séance : un participant peut donc répondre de nouveau. Pendant le direct, l’en-tête affiche le nombre de participants connectés, le nombre de réponses à la question en cours et le temps restant ; une réponse envoyée après ce délai est refusée par le site. **Relancer** (T) redonne du temps pour la question affichée. Fermer cette fenêtre arrête la session distante ; quitter l’app demande d’abord de l’arrêter.

## Périmètre de cette version

L’éditeur natif modifie le texte simple ; la mise en forme HTML des anciennes questions est conservée jusqu’à leur édition. Les formules LaTeX sont conservées comme texte et restent prises en charge par le site participant. Les vidéos YouTube se lisent directement dans l’aperçu et la présentation, avec les limites de début et de fin configurées. Une connexion Internet est nécessaire et un bouton permet aussi de les ouvrir sur YouTube. Les rapports PDF individuels ne disposent pas d’une interface native dans cette version.

La synchronisation utilise les endpoints existants du site, sans nouvelle API à déployer. Leurs listes sont actuellement limitées à 300 questionnaires actifs et 100 éléments dans la corbeille. Une absence dans ces listes ne provoque jamais de recréation automatique d’un questionnaire déjà synchronisé. La suppression définitive effectuée directement sur le site peut donc laisser une copie locale. Les envois revérifient la version distante, mais le serveur actuel ne fournit pas de comparaison atomique de versions : une modification intervenant exactement entre cette vérification et l’écriture reste une limite de cette API.

L’enregistrement local est différé de 0,4 s et effectué hors du fil principal, puis forcé à la mise en arrière-plan et en quittant l’app.

Pour le développement, la variable d’environnement `AUDIENCE_LIBRARY` ouvre une autre bibliothèque que celle de l’utilisateur ; en Debug, `AUDIENCE_SNAPSHOT_DIR` enregistre des captures des principaux écrans.

Vérifications effectuées : compilation universelle Xcode, signature locale et 58 tests portant notamment sur les dossiers, étiquettes et couleurs dans les deux sens, la synchronisation incrémentale, le décodage des entités HTML, portant notamment sur la connexion, les mises à jour dans les deux sens, les conflits, les saisies concurrentes, la corbeille, les favoris, la reprise hors ligne, l’isolation des comptes et les réponses HTTP partielles. La synchronisation sur un compte réel reste à confirmer après installation.

## Licence

Code sous [GNU GPL version 3](../LICENSE) ou ultérieure ; icône, textes et documentation sous [CC BY-SA 4.0](../LICENSE-CONTENT.txt). Voir le [README du projet](../README.md#licence).
