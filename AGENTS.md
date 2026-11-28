# Consignes pour les agents

Le dépôt contient le site web d’Audience (racine) et les apps natives Mac et iPad (`app/`). La documentation de référence est `app/README.md` ; ce fichier ne note que ce qui ne s’en déduit pas.

## « Le site », après une modification des apps

Quand une modification des apps natives doit être reportée « sur le site », ne modifier que la page de l’app Mac, `app.html`, et les images qu’elle seule utilise. Les autres pages, les favicons, le logo et l’image de partage ne changent pas.

Les images de `img/app/` peuvent être partagées entre plusieurs pages : `img/app/icone.png`, par exemple, sert aussi à `nouveautes.html`. Avant d’en remplacer une, vérifier avec `git grep` quelles pages l’utilisent, et créer au besoin un nouveau fichier référencé par `app.html` seul (c’est le cas de `img/app/icone-mac.png`).

`nouveautes.html` est régénéré par `app/scripts/publish-update.sh` à partir de `app/Resources/ReleaseNotes.json` : ne pas le modifier à la main.

## Icône des apps

`app/Resources/AppIcon.icon` (Icon Composer) est commune au Mac et à l’iPad. `app/Resources/AppIcon.md` la décrit, et `app/scripts/generate-icon.py` la régénère.

- `actool` refuse une icône de plus de **quatre groupes**. L’aperçu d’`ictool` ne le signale pas : valider toute modification en compilant les deux cibles.
- La partie Mac de `app.html` montre l’icône dans `img/app/icone-mac.png` et `icone-mac-sombre.png`. Ce sont des rendus macOS d’`ictool` (rendus `Default` et `Dark`), redimensionnés à 432 px sur un fond transparent de 512 px. Ils sont à refaire si l’icône change.

## Publication

Suivre « Préparer une publication Mac et TestFlight » dans `app/README.md` :

- augmenter la version dans `Info.plist` **et** `Info-iPad.plist` ;
- ajouter les notes de version dans `ReleaseNotes.json` ;
- compiler avec signature Developer ID et notarisation ;
- lancer `publish-update.sh` ;
- créer l’archive iPad, puis lancer `prepare-publication.py`.

Le certificat et le profil de notarisation figurent dans le README et restent dans le trousseau du Mac : ne pas les redemander. Les scripts préparent les fichiers sans rien téléverser ; la mise en ligne reste à la charge de l’utilisateur.

Dans le dossier iCloud, la copie `app/build/Audience.app` peut échouer à la vérification de signature à cause des attributs ajoutés par iCloud. Vérifier plutôt l’archive ZIP, décompressée hors iCloud.
