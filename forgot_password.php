<?php
declare(strict_types=1);
require_once __DIR__ . '/lib/bootstrap.php';

if (current_user()) {
    header('Location: index.html');
    exit;
}

$db = app_db();
$error = '';
$info = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_same_origin_post();
    $email = trim((string)($_POST['email'] ?? ''));
    if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $error = "Merci de renseigner une adresse email valide.";
    } elseif (
        app_rate_limit_exceeded('forgot-password-ip', 8, 3600)
        || app_rate_limit_exceeded('forgot-password-email', 3, 3600, $email)
    ) {
        http_response_code(429);
        $info = "Si un compte existe avec cette adresse, un lien de réinitialisation a été envoyé.";
    } else {
        $info = "Si un compte existe avec cette adresse, un lien de réinitialisation a été envoyé.";

        $stmt = $db->prepare("SELECT id, email, username FROM users WHERE email = ? AND status = 'active' LIMIT 1");
        $stmt->execute([$email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);

        if ($user) {
            try {
                $rawToken = bin2hex(random_bytes(32));
                $tokenHash = hash('sha256', $rawToken);
                $expiresAt = date('Y-m-d H:i:s', time() + 3600);

                $db->beginTransaction();
                $invalidate = $db->prepare("UPDATE password_reset_tokens SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL");
                $invalidate->execute([(int)$user['id']]);
                $insert = $db->prepare("INSERT INTO password_reset_tokens (user_id, token_hash, expires_at) VALUES (?, ?, ?)");
                $insert->execute([(int)$user['id'], $tokenHash, $expiresAt]);
                $db->commit();

                $resetLink = app_base_url() . '/reset_password.php?token=' . urlencode($rawToken) . '&email=' . urlencode((string)$user['email']);
                $host = preg_replace('/[^a-z0-9.-]/i', '', trim((string)($_SERVER['SERVER_NAME'] ?? 'localhost'))) ?: 'localhost';
                $from = trim((string)(getenv('CONTACT_FROM_EMAIL') ?: ''));
                if ($from === '' || !filter_var($from, FILTER_VALIDATE_EMAIL)) {
                    $from = 'no-reply@' . $host;
                }
                $safeUsername = trim((string)($user['username'] ?? ''));
                $displayName = $safeUsername !== '' ? $safeUsername : (string)$user['email'];
                $subject = mb_encode_mimeheader('Réinitialisation du mot de passe - Audience', 'UTF-8');
                $body = "Bonjour " . $displayName . ",\r\n\r\n"
                    . "Vous avez demandé la réinitialisation de votre mot de passe.\r\n"
                    . "Cliquez sur ce lien (valable 1 heure) :\r\n"
                    . $resetLink . "\r\n\r\n"
                    . "Si vous n'êtes pas à l'origine de cette demande, ignorez ce message.\r\n";
                $headers = [
                    'MIME-Version: 1.0',
                    'Content-Type: text/plain; charset=UTF-8',
                    'Content-Transfer-Encoding: 8bit',
                    'From: Audience <' . $from . '>',
                    'Reply-To: ' . $from
                ];
                $sent = @mail((string)$user['email'], $subject, $body, implode("\r\n", $headers));
                if (!$sent) {
                    $error = "Impossible d'envoyer l'email pour le moment. Vérifiez la configuration mail du serveur.";
                    $info = '';
                }
            } catch (Throwable $e) {
                if ($db->inTransaction()) {
                    $db->rollBack();
                }
                $error = "La demande n'a pas pu être traitée pour le moment.";
                $info = '';
            }
        }
    }
}
?>
<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Mot de passe oublié - Audience</title>
    <link rel="icon" type="image/png" sizes="32x32" href="img/icones/favicon-32.png?v=2">
    <link rel="icon" type="image/png" sizes="16x16" href="img/icones/favicon-16.png?v=2">
    <link rel="apple-touch-icon" sizes="180x180" href="img/icones/apple-touch-icon.png?v=2">
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
    <link rel="stylesheet" href="styles.css?v=20261121y">
</head>
<body class="page-login">
    <div id="accountBar" class="account-bar"></div>
    <div class="wrap">
        <div class="hero">
            <h1 class="title">Audience</h1>
            <p class="subtitle">Réinitialiser votre mot de passe</p>
        </div>
        <div class="card">
            <div class="form-pane">
                <h2>Mot de passe oublié</h2>
                <form method="post" autocomplete="on">
                    <label for="email">Email</label>
                    <input id="email" name="email" type="email" required>
                    <button type="submit">Envoyer le lien</button>
                </form>
                <?php if ($error !== ''): ?>
                    <div class="error"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
                <?php endif; ?>
                <?php if ($info !== ''): ?>
                    <div class="info"><?= htmlspecialchars($info, ENT_QUOTES, 'UTF-8') ?></div>
                <?php endif; ?>
                <div class="hint"><a href="login.php">Retour à la connexion</a></div>
            </div>
        </div>

        <footer class="footer" data-animate="fade-up" data-delay="700" data-site-footer></footer>
    </div>
    <script src="site-nav.js?v=20261121v"></script>
    <script src="site-footer.js?v=20261121b"></script>
    <script src="theme.js?v=20261122a"></script>
    <script>
        const footerYear = document.getElementById('current-year');
        if (footerYear) {
            footerYear.textContent = String(new Date().getFullYear());
        }
    </script>
</body>
</html>
