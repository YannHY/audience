# Audience pour macOS

Application native SwiftUI pour **macOS 26 ou ultérieur**, sans Electron, WebView, Node.js ni serveur local. Le site PHP situé dans le dossier parent reste indépendant.

## Ouvrir l’application

L’archive prête à utiliser est `build/Audience-macOS.zip` : décompressez-la puis ouvrez **Audience.app**. Une copie est également disponible dans `build/Audience.app` :

```sh
open build/Audience.app
```

Le binaire est universel : Apple Silicon et Intel. Il est signé localement, sans certificat Developer ID ni notarisation. Pour une distribution publique, utilisez votre identité Developer ID et notarisez l’archive depuis Xcode.

## Développer et compiler

Ouvrez `Audience.xcodeproj` avec Xcode 26 ou ultérieur, sélectionnez le schéma **Audience**, puis lancez avec ⌘R. Aucun téléchargement de dépendance n’est nécessaire.

Depuis le dossier `app` :

```sh
./scripts/build.sh
./scripts/test.sh
```

La compilation produit `build/Audience.app` et `build/Audience-macOS.zip`. La signature de l’application contenue dans le ZIP est vérifiée avant sa création, hors du dossier iCloud. Pour une compilation dans un environnement qui interdit le sandbox imbriqué des macros Swift :

```sh
./scripts/build.sh OTHER_SWIFT_FLAGS=-disable-sandbox
```

Le projet Swift Package permet aussi `swift build` et `swift test`. Pour ajouter des fichiers au projet Xcode, exécutez `python3 scripts/generate-project.py`.

## Utilisation

- **Bibliothèque** : dossiers colorés, étiquettes, couleurs de questionnaire, favoris, tri, recherche (titre, code ou étiquette), sélection multiple, duplication, corbeille et vidage de la corbeille. Glissez un questionnaire sur un dossier, une étiquette, les Favoris ou la Corbeille dans la barre latérale.
- **Inspecteur** (bouton à droite de la barre d’outils ou ⌥⌘I) : dossier, couleur, étiquettes, réglages de participation et informations du questionnaire.
- **Éditeur** : liste des questions à gauche (réorganisation par glisser-déposer, touche Suppr, menu contextuel), choix unique, choix multiples, réponse libre, nuage de mots, évaluation, texte à trous, vidéo YouTube, classement et image à légender. Images intégrées aux sauvegardes, limite de 2 Mo, ajout par glisser-déposer possible.
- **Présentation** : fenêtre native indépendante, plein écran (⌃⌘F), flèches gauche/droite ou espace, correction (C) et réponses reçues (R). Les éléments d’un classement sont mélangés jusqu’à la correction. Le bouton Participer affiche un QR code généré localement pendant une session en ligne.
- **Résultats** : graphiques Swift Charts et réponses textuelles, récupérés depuis le site ou une sauvegarde. Les résultats du direct sont actualisés toutes les trois secondes tant que la fenêtre de présentation reste ouverte.
- **Réglages** : apparence système/claire/sombre, sauvegardes et connexion au site.

Raccourcis : ⌘N nouveau questionnaire, ⇧⌘N nouveau dossier (avec la sélection), ⌘D dupliquer, ⌥⌘P présenter, ⌘R synchroniser.

La navigation utilise `NavigationSplitView`, l’inspecteur système, les barres d’outils et leurs matériaux Liquid Glass. Les contrôles flottants de présentation utilisent `GlassEffectContainer` et `glassEffect`. SF Symbols, menus, champs, dialogues de fichiers et raccourcis suivent les conventions macOS. La transparence est gérée par le système et ses réglages d’accessibilité.

## Données et ancienne application

Les données natives sont enregistrées de façon atomique dans :

```text
~/Library/Application Support/AudienceNative/library.json
```

Au premier démarrage, si ce fichier n’existe pas, l’application recherche `~/Library/Application Support/Audience/audience-local-store.json`. Elle récupère les questionnaires, les réponses et les images disponibles dans l’ancien dossier `uploads`, sans supprimer les fichiers d’origine. Un fichier illisible bloque les écritures pour éviter de l’écraser.

Les sauvegardes JSON Electron (version 1) sont importables. Un import ajoute les questionnaires et crée un nouveau code en cas de doublon, avec leurs résultats associés. Les champs supplémentaires des anciennes questions sont préservés. L’export inclut les images intégrées et les réponses, sans identifiants ni cookies de connexion.

## Connexion et participation

Dans **Audience → Réglages → Compte**, connectez-vous avec votre adresse e-mail et votre mot de passe habituels. L’adresse du site Audience est intégrée à l’application. Le mot de passe et les cookies restent en mémoire pendant la session.

La bibliothèque est synchronisée automatiquement après la connexion. Les questionnaires du site apparaissent progressivement, avec leurs résultats disponibles. Les modifications locales sont envoyées après deux secondes sans nouvelle saisie ; l’app vérifie aussi le site toutes les trente secondes et quand sa fenêtre redevient active. **Synchroniser maintenant** permet de relancer immédiatement un échange.

La synchronisation met à jour les questionnaires en conservant leur code, leurs favoris et leur état dans la corbeille. Les dossiers (nom et couleur), le rangement, la couleur et les étiquettes de chaque questionnaire sont échangés avec la bibliothèque du site via `quiz_organize.php` ; si les deux côtés ont changé, la version du Mac l’emporte. Un dossier créé hors ligne est créé sur le site à la connexion suivante. Un questionnaire dont la date sur le site et le contenu local n’ont pas changé n’est pas retéléchargé : une vérification complète a lieu à la connexion, toutes les dix minutes et avec **Synchroniser maintenant**. Les résultats sont actualisés à l’ouverture de l’onglet Résultats. Les suppressions définitives confirmées dans l’app sont mises en attente hors ligne puis répercutées sur le compte. Les questionnaires incomplets restent locaux jusqu’à ce qu’ils soient valides. Les résultats sont téléchargés depuis le site ; les anciennes réponses issues d’une sauvegarde restent consultables localement.

L’app conserve une référence de la dernière version échangée pour distinguer les changements locaux et distants. Si les deux versions ont changé, celle du Mac est conservée dans un questionnaire séparé portant la mention « conflit sur ce Mac ». Les saisies faites pendant un téléchargement restent intactes. Les données de comptes différents ne sont pas envoyées au compte nouvellement connecté.

Une image ou des résultats indisponibles ne bloquent pas l’affichage du questionnaire. Les erreurs partielles apparaissent dans l’état de synchronisation et sont réessayées lors du prochain échange. Une session en direct suspend les envois automatiques pour préserver son déroulement.

La préparation et la présentation fonctionnent hors ligne. Pour recueillir les réponses des participants, connectez-vous au site puis utilisez **Lancer en direct** dans la présentation. Choisissez **Nouvelle session** (les réponses précédentes sont effacées, comme sur le site) ou **Conserver les réponses précédentes**. Chaque lancement crée une nouvelle séance : un participant peut donc répondre de nouveau. Pendant le direct, l’en-tête affiche le nombre de participants connectés, le nombre de réponses à la question en cours et le temps restant ; une réponse envoyée après ce délai est refusée par le site. **Relancer** (T) redonne du temps pour la question affichée. Fermer cette fenêtre arrête la session distante ; quitter l’app demande d’abord de l’arrêter.

## Périmètre de cette version

L’éditeur natif modifie le texte simple ; la mise en forme HTML des anciennes questions est conservée jusqu’à leur édition. Les formules LaTeX sont conservées comme texte et restent prises en charge par le site participant. Les vidéos YouTube s’ouvrent dans le navigateur, avec leur position de départ ; la limite de fin reste transmise au site. Les rapports PDF individuels ne disposent pas d’une interface native dans cette version.

La synchronisation utilise les endpoints existants du site, sans nouvelle API à déployer. Leurs listes sont actuellement limitées à 300 questionnaires actifs et 100 éléments dans la corbeille. Une absence dans ces listes ne provoque jamais de recréation automatique d’un questionnaire déjà synchronisé. La suppression définitive effectuée directement sur le site peut donc laisser une copie locale. Les envois revérifient la version distante, mais le serveur actuel ne fournit pas de comparaison atomique de versions : une modification intervenant exactement entre cette vérification et l’écriture reste une limite de cette API.

L’enregistrement local est différé de 0,4 s et effectué hors du fil principal, puis forcé à la mise en arrière-plan et en quittant l’app.

Pour le développement, la variable d’environnement `AUDIENCE_LIBRARY` ouvre une autre bibliothèque que celle de l’utilisateur ; en Debug, `AUDIENCE_SNAPSHOT_DIR` enregistre des captures des principaux écrans.

Vérifications effectuées : compilation universelle Xcode, signature locale et 53 tests portant notamment sur les dossiers, étiquettes et couleurs dans les deux sens, la synchronisation incrémentale, le décodage des entités HTML, portant notamment sur la connexion, les mises à jour dans les deux sens, les conflits, les saisies concurrentes, la corbeille, les favoris, la reprise hors ligne, l’isolation des comptes et les réponses HTTP partielles. La synchronisation sur un compte réel reste à confirmer après installation.
