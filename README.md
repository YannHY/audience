# Audience

Audience permet de créer des questionnaires et de recueillir en direct les réponses d’un public. Le projet comprend :

- le **site web** (PHP, HTML, CSS, JavaScript), à la racine du dépôt ;
- les **applications macOS et iPad** natives (SwiftUI), dans le dossier [`app`](app/README.md).

## Installer le site

1. Copiez les fichiers sur un serveur PHP avec MySQL.
2. Copiez [`config.local.example.php`](config.local.example.php) sous le nom `audience-secrets.php` dans le dossier `HOME` du compte serveur, **hors du répertoire public**, puis renseignez la connexion à la base et l’adresse publique du site. Par exemple : `/home/mon-compte/audience-secrets.php` si les fichiers publics sont dans `/home/mon-compte/www/apps/audience/`. Le modèle peut rester dans le dépôt ; la copie remplie doit rester privée.
3. Ouvrez `setup_admin.php` pour créer le premier compte administrateur.

En développement, utilisez également `audience-secrets.php` dans votre dossier `HOME`, hors du répertoire public, ou les variables d’environnement.

Vous pouvez aussi définir les variables d’environnement listées dans [`.env.example`](.env.example) : elles sont prioritaires sur les fichiers PHP. L’application ne charge pas automatiquement de fichier `.env`.

`APP_BASE_URL` fixe l’URL publique de l’installation, notamment pour les liens de réinitialisation de mot de passe. Renseignez-la dans `audience-secrets.php` ou dans l’environnement ; à défaut, l’application la déduit de la requête.

## Licence

Audience est un logiciel libre, créé par Yann Houry.

- **Code source** (PHP, JavaScript, CSS, Swift, scripts) : [GNU GPL version 3](LICENSE) ou toute version ultérieure. Vous pouvez l’utiliser, l’étudier, le modifier et le redistribuer, à condition de diffuser vos versions modifiées sous la même licence, avec leur code source.
- **Contenus** (textes des pages et de l’aide, documentation, logos, illustrations, captures d’écran) : [Creative Commons Attribution – Partage dans les mêmes conditions 4.0](LICENSE-CONTENT.txt) (CC BY-SA 4.0), la licence de Wikipédia. Vous pouvez les réutiliser en citant l’auteur et en partageant vos adaptations sous la même licence.

Les bibliothèques et polices chargées depuis des services externes (Font Awesome, Google Fonts, etc.) restent sous leurs propres licences.
