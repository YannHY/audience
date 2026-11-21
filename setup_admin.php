<?php
declare(strict_types=1);
require_once __DIR__ . '/lib/bootstrap.php';

$db = app_db();
if (!is_admin_seed_needed($db)) {
    header('Location: login.php');
    exit;
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_same_origin_post();
    $username = sanitize_username((string)($_POST['username'] ?? ''));
    $email = trim((string)($_POST['email'] ?? ''));
    $password = (string)($_POST['password'] ?? '');

    if ($username === '' || $email === '' || $password === '') {
        $error = "Nom d'utilisateur, email et mot de passe requis.";
    } elseif (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $error = "Adresse email invalide.";
    } elseif (strlen($password) < 8) {
        $error = "Mot de passe trop court (8 caractères minimum).";
    } else {
        $stmt = $db->prepare("INSERT INTO users (username, email, password_hash, role, status) VALUES (?, ?, ?, 'admin', 'active')");
        $stmt->execute([$username, $email, password_hash($password, PASSWORD_DEFAULT)]);
        header('Location: login.php');
        exit;
    }
}
?>
<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Configuration admin - Audience</title>
    <link rel="icon" type="image/png" sizes="32x32" href="favicon-32.png?v=2">
    <link rel="icon" type="image/png" sizes="16x16" href="favicon-16.png?v=2">
    <link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png?v=2">
    <script>
        try {
            if (localStorage.getItem('audience-theme') === 'dark') {
                document.documentElement.classList.add('theme-dark');
            }
        } catch (_) {}
    </script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css" referrerpolicy="no-referrer">
    <link rel="stylesheet" href="styles.css?v=20261121u">
</head>
<body class="page-setup-admin">
    <div id="accountBar" class="account-bar"></div>
    <div class="wrap">
        <div class="card">
            <h1 class="brand-heading"><a href="index.html" aria-label="Retour à l'accueil Audience"><img src="logo.png" alt="Logo Audience"></a><span>Créer le premier compte admin</span></h1>
            <p>Cette page n'est disponible que tant qu'aucun administrateur n'existe.</p>
            <form method="post">
                <label for="username">Nom d'utilisateur</label>
                <input id="username" name="username" type="text" required>
                <label for="email">Email admin</label>
                <input id="email" name="email" type="email" required>
                <label for="password">Mot de passe</label>
                <input id="password" name="password" type="password" minlength="8" required>
                <button type="submit">Créer l'administrateur</button>
            </form>
            <?php if ($error !== ''): ?>
                <div class="error"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
            <?php endif; ?>
        </div>

        <footer class="footer" data-animate="fade-up" data-delay="700">
            <div class="footer-content">
                <p class="made-with">
                    Créé avec <i class="fas fa-heart" aria-hidden="true"></i> par
                    <a href="https://www.linkedin.com/in/yann-houry-a2350651/" target="_blank" rel="noopener noreferrer">Yann Houry</a>
                </p>
                <p class="footer-legal">
                    <a href="conditions-utilisation.html">Conditions d'utilisation</a> | <a href="aide.html">Aide</a> | <a href="app.html">Applications</a> | <a href="contact.html">Contact</a> | <a href="https://github.com/YannHY/audience" target="_blank" rel="noopener noreferrer">Code source</a>
                </p>
                <div class="license">
                    <p><i class="fa-brands fa-creative-commons" aria-hidden="true"></i> Logiciel libre : code sous <a href="https://www.gnu.org/licenses/gpl-3.0.fr.html" target="_blank" rel="noopener noreferrer">GPL v3</a>, contenus sous <a href="https://creativecommons.org/licenses/by-sa/4.0/deed.fr" target="_blank" rel="noopener noreferrer">CC BY-SA 4.0</a></p>
                </div>
                <p class="year"><span id="current-year"></span></p>
            </div>
        </footer>
    </div>
    <script src="site-nav.js?v=20261121u"></script>
    <script src="theme.js"></script>
    <script>
        const footerYear = document.getElementById('current-year');
        if (footerYear) {
            footerYear.textContent = String(new Date().getFullYear());
        }
    </script>
</body>
</html>
