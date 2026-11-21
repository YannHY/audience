# Audience

Audience permet de créer des questionnaires et de recueillir en direct les réponses d’un public. Le projet comprend :

- le **site web** (PHP, HTML, CSS, JavaScript), à la racine du dépôt ;
- l’**application macOS** native (SwiftUI), dans le dossier [`app`](app/README.md).

## Installer le site

1. Copiez les fichiers sur un serveur PHP avec MySQL.
2. Créez `config.local.php` (ignoré par Git) ou définissez les variables de [`.env.example`](.env.example) : connexion à la base et adresse publique du site.
3. Ouvrez `setup_admin.php` pour créer le premier compte administrateur.

## Licence

Audience est un logiciel libre, créé par Yann Houry.

- **Code source** (PHP, JavaScript, CSS, Swift, scripts) : [GNU GPL version 3](LICENSE) ou toute version ultérieure. Vous pouvez l’utiliser, l’étudier, le modifier et le redistribuer, à condition de diffuser vos versions modifiées sous la même licence, avec leur code source.
- **Contenus** (textes des pages et de l’aide, documentation, logos, illustrations, captures d’écran) : [Creative Commons Attribution – Partage dans les mêmes conditions 4.0](LICENSE-CONTENT.txt) (CC BY-SA 4.0), la licence de Wikipédia. Vous pouvez les réutiliser en citant l’auteur et en partageant vos adaptations sous la même licence.

Les bibliothèques et polices chargées depuis des services externes (Font Awesome, Google Fonts, etc.) restent sous leurs propres licences.
