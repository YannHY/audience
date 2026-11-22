<?php
// Modèle sans identifiants réels, non chargé par l’application.
// En production, copier ce fichier sous le nom audience-secrets.php dans
// le dossier HOME du compte serveur, hors du répertoire public, puis le remplir.
// Le même emplacement peut être utilisé en développement.
return [
    'APP_DB_DSN' => 'mysql:host=localhost;dbname=audience;charset=utf8mb4',
    'APP_DB_USER' => 'audience_user',
    'APP_DB_PASS' => 'a_remplacer',
    'APP_BASE_URL' => 'https://example.com/audience'
];
