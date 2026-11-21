<?php
declare(strict_types=1);
require_once __DIR__ . '/lib/bootstrap.php';

$db = app_db();
if (is_admin_seed_needed($db)) {
    header('Location: setup_admin.php');
    exit;
}

if (current_user()) {
    header('Location: index.html');
    exit;
}

$error = '';
$info = '';
if (isset($_GET['account_deleted']) && (string)$_GET['account_deleted'] === '1') {
    $info = "Votre compte a été supprimé avec succès.";
}
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_same_origin_post();
    $email = trim((string)($_POST['email'] ?? ''));
    $password = (string)($_POST['password'] ?? '');

    if ($email === '' || $password === '') {
        $error = "Merci de renseigner l'email et le mot de passe.";
    } elseif (
        app_rate_limit_exceeded('login-ip', 12, 900)
        || app_rate_limit_exceeded('login-email', 6, 900, $email)
    ) {
        http_response_code(429);
        $error = "Trop de tentatives de connexion. Réessayez dans quelques minutes.";
    } else {
        $stmt = $db->prepare("SELECT id, username, email, password_hash, role, status FROM users WHERE email = ? LIMIT 1");
        $stmt->execute([$email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if (!$user || $user['status'] !== 'active' || !password_verify($password, (string)$user['password_hash'])) {
            $error = "Identifiants invalides.";
        } else {
            app_rate_limit_clear('login-ip');
            app_rate_limit_clear('login-email', $email);
            $touch = $db->prepare("UPDATE users SET last_login_at = NOW() WHERE id = ?");
            $touch->execute([(int)$user['id']]);
            session_regenerate_id(true);
            $_SESSION['user'] = [
                'id' => (int)$user['id'],
                'username' => (string)$user['username'],
                'email' => (string)$user['email'],
                'role' => (string)$user['role']
            ];
            header('Location: index.html');
            exit;
        }
    }
}
?>
<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Audience</title>
    <meta name="description" content="Créez vos questions et affichez les réponses en direct avec Audience.">
    <link rel="canonical" href="https://www.ralentirtravaux.com/apps/audience/login.php">
    <meta property="og:locale" content="fr_FR">
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="Audience">
    <meta property="og:title" content="Audience">
    <meta property="og:description" content="Créez vos questions et affichez les réponses en direct.">
    <meta property="og:url" content="https://www.ralentirtravaux.com/apps/audience/login.php">
    <meta property="og:image" content="https://www.ralentirtravaux.com/apps/audience/audience-social-preview.png">
    <meta property="og:image:secure_url" content="https://www.ralentirtravaux.com/apps/audience/audience-social-preview.png">
    <meta property="og:image:type" content="image/png">
    <meta property="og:image:width" content="1200">
    <meta property="og:image:height" content="627">
    <meta property="og:image:alt" content="Audience — Créez vos questions et affichez les réponses en direct.">
    <meta name="twitter:card" content="summary_large_image">
    <meta name="twitter:title" content="Audience">
    <meta name="twitter:description" content="Créez vos questions et affichez les réponses en direct.">
    <meta name="twitter:image" content="https://www.ralentirtravaux.com/apps/audience/audience-social-preview.png">
    <meta name="twitter:image:alt" content="Audience — Créez vos questions et affichez les réponses en direct.">
    <link rel="icon" type="image/png" sizes="32x32" href="favicon-32.png?v=2">
    <link rel="icon" type="image/png" sizes="16x16" href="favicon-16.png?v=2">
    <link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png?v=2">
    <script>
        try {
            const savedTheme = localStorage.getItem('audience-theme');
            if (savedTheme === 'dark') {
                document.documentElement.classList.add('theme-dark');
            } else if (savedTheme === 'light') {
                document.documentElement.classList.add('theme-light');
            } else if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
                document.documentElement.classList.add('theme-dark');
            }
        } catch (_) {}
    </script>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Pacifico&display=swap" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.2/css/all.min.css" referrerpolicy="no-referrer">
    <link rel="stylesheet" href="styles.css?v=20261121u">
</head>
<body class="page-login">
    <button type="button" id="themeToggle" class="theme-toggle" aria-label="Activer le mode sombre" title="Activer le mode sombre"><i class="fa-solid fa-moon" aria-hidden="true"></i></button>
    <div class="wrap">
        <div class="hero">
            <h1 class="title">Audience</h1>
            <p class="subtitle">Créez vos questions et affichez les réponses en direct</p>
        </div>
        <div class="login-main">
            <div class="card">
                <div class="split">
                    <div class="logo-pane">
                        <a href="index.html" aria-label="Retour à l'accueil Audience">
                            <img src="logo.png" alt="Logo Audience">
                        </a>
                    </div>
                    <div class="divider" aria-hidden="true"></div>
                    <div class="form-pane">
                        <h2>Connexion</h2>
                        <form method="post" autocomplete="on">
                            <label for="email">Email</label>
                            <input id="email" name="email" type="email" required>
                            <label for="password">Mot de passe</label>
                            <input id="password" name="password" type="password" required>
                            <button type="submit">Se connecter</button>
                        </form>
                        <?php if ($error !== ''): ?>
                            <div class="error"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
                        <?php endif; ?>
                        <?php if ($info !== ''): ?>
                            <div class="info"><?= htmlspecialchars($info, ENT_QUOTES, 'UTF-8') ?></div>
                        <?php endif; ?>
                        <div class="hint"><a href="forgot_password.php"><i class="fa-solid fa-circle-question" aria-hidden="true"></i> Mot de passe oublié</a></div>
                    </div>
                </div>
            </div>
            <div class="beta-notice">
                <p class="beta-notice-title"><i class="fa-solid fa-bug" aria-hidden="true"></i> Le site est actuellement en version bêta.</p>
                <p>Vous pouvez faire une demande pour l'essayer via la page <a href="contact.html">Contact</a> | <a href="https://github.com/YannHY/audience" target="_blank" rel="noopener noreferrer">Code source</a>.</p>
            </div>
        </div>

        <footer class="footer" data-animate="fade-up" data-delay="700">
            <div class="footer-content">
                <p class="made-with">
                    Créé avec <i class="fas fa-heart" aria-hidden="true"></i> par
                    <a href="https://www.linkedin.com/in/yann-houry-a2350651/" target="_blank" rel="noopener noreferrer">Yann Houry</a>
                </p>
                <p class="footer-legal">
                    <a href="conditions-utilisation.html">Conditions d'utilisation</a> | <a href="aide.html">Aide</a> | <a href="contact.html">Contact</a>
                </p>
                <div class="license">
                    <p><i class="fa-brands fa-creative-commons" aria-hidden="true"></i> Logiciel libre : code sous <a href="https://www.gnu.org/licenses/gpl-3.0.fr.html" target="_blank" rel="noopener noreferrer">GPL v3</a>, contenus sous <a href="https://creativecommons.org/licenses/by-sa/4.0/deed.fr" target="_blank" rel="noopener noreferrer">CC BY-SA 4.0</a></p>
                </div>
                <p class="year"><span id="current-year"></span></p>
            </div>
        </footer>
    </div>
    <script src="theme.js"></script>
    <script>
        const footerYear = document.getElementById('current-year');
        if (footerYear) {
            footerYear.textContent = String(new Date().getFullYear());
        }
    </script>
</body>
</html>
