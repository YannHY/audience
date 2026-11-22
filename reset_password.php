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
$email = trim((string)($_GET['email'] ?? $_POST['email'] ?? ''));
$token = trim((string)($_GET['token'] ?? $_POST['token'] ?? ''));

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_same_origin_post();
    $password = (string)($_POST['password'] ?? '');
    $confirm = (string)($_POST['confirm_password'] ?? '');

    if ($email === '' || !filter_var($email, FILTER_VALIDATE_EMAIL) || $token === '') {
        $error = "Lien invalide ou incomplet.";
    } elseif (
        app_rate_limit_exceeded('reset-password-ip', 10, 3600)
        || app_rate_limit_exceeded('reset-password-email', 5, 3600, $email)
    ) {
        http_response_code(429);
        $error = "Trop de tentatives de réinitialisation. Réessayez dans quelques minutes.";
    } elseif (strlen($password) < 8) {
        $error = "Mot de passe trop court (8 caractères minimum).";
    } elseif ($password !== $confirm) {
        $error = "Les mots de passe ne correspondent pas.";
    } else {
        try {
            $db->beginTransaction();

            $userStmt = $db->prepare("SELECT id FROM users WHERE email = ? AND status = 'active' LIMIT 1");
            $userStmt->execute([$email]);
            $user = $userStmt->fetch(PDO::FETCH_ASSOC);

            if (!$user) {
                throw new RuntimeException('Lien invalide ou expiré.');
            }

            $tokenHash = hash('sha256', $token);
            $tokenStmt = $db->prepare("SELECT id, expires_at, used_at
                FROM password_reset_tokens
                WHERE user_id = ? AND token_hash = ?
                ORDER BY id DESC
                LIMIT 1");
            $tokenStmt->execute([(int)$user['id'], $tokenHash]);
            $tokenRow = $tokenStmt->fetch(PDO::FETCH_ASSOC);

            if (!$tokenRow) {
                throw new RuntimeException('Lien invalide ou expiré.');
            }
            if (!empty($tokenRow['used_at'])) {
                throw new RuntimeException('Ce lien a déjà été utilisé.');
            }
            if (strtotime((string)$tokenRow['expires_at']) < time()) {
                throw new RuntimeException('Ce lien a expiré.');
            }

            $updatePwd = $db->prepare("UPDATE users SET password_hash = ? WHERE id = ?");
            $updatePwd->execute([password_hash($password, PASSWORD_DEFAULT), (int)$user['id']]);

            $markUsed = $db->prepare("UPDATE password_reset_tokens SET used_at = NOW() WHERE id = ?");
            $markUsed->execute([(int)$tokenRow['id']]);

            $invalidateOthers = $db->prepare("UPDATE password_reset_tokens SET used_at = NOW() WHERE user_id = ? AND used_at IS NULL");
            $invalidateOthers->execute([(int)$user['id']]);

            $db->commit();
            app_rate_limit_clear('reset-password-ip');
            app_rate_limit_clear('reset-password-email', $email);
            $info = "Mot de passe mis à jour. Vous pouvez maintenant vous connecter.";
            $token = '';
        } catch (Throwable $e) {
            if ($db->inTransaction()) {
                $db->rollBack();
            }
            if ($e instanceof RuntimeException) {
                $error = $e->getMessage();
            } else {
                error_log('[audience][reset_password] ' . $e->getMessage());
                $error = "La mise à jour du mot de passe a échoué. Merci de réessayer.";
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
    <title>Nouveau mot de passe - Audience</title>
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
    <link rel="stylesheet" href="styles.css?v=20261121y">
</head>
<body class="page-login">
    <div id="accountBar" class="account-bar"></div>
    <div class="wrap">
        <div class="hero">
            <h1 class="title">Audience</h1>
            <p class="subtitle">Choisir un nouveau mot de passe</p>
        </div>
        <div class="card">
            <div class="form-pane">
                <h2>Réinitialisation</h2>
                <?php if ($token === '' && $info === ''): ?>
                    <div class="error">Lien invalide ou expiré.</div>
                <?php else: ?>
                    <?php if ($token !== ''): ?>
                        <form method="post" autocomplete="on">
                            <input type="hidden" name="email" value="<?= htmlspecialchars($email, ENT_QUOTES, 'UTF-8') ?>">
                            <input type="hidden" name="token" value="<?= htmlspecialchars($token, ENT_QUOTES, 'UTF-8') ?>">
                            <label for="password">Nouveau mot de passe</label>
                            <input id="password" name="password" type="password" minlength="8" required autocomplete="new-password">
                            <label for="confirm_password">Confirmer le mot de passe</label>
                            <input id="confirm_password" name="confirm_password" type="password" minlength="8" required autocomplete="new-password">
                            <button type="submit">Mettre à jour le mot de passe</button>
                        </form>
                    <?php endif; ?>
                <?php endif; ?>
                <?php if ($error !== ''): ?>
                    <div class="error"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></div>
                <?php endif; ?>
                <?php if ($info !== ''): ?>
                    <div class="info"><?= htmlspecialchars($info, ENT_QUOTES, 'UTF-8') ?></div>
                <?php endif; ?>
                <div class="hint"><a href="login.php">Retour à la connexion</a></div>
            </div>
        </div>
    </div>
    <footer class="footer" data-site-footer></footer>
    <script src="site-nav.js?v=20261121v"></script>
    <script src="site-footer.js?v=20261121b"></script>
    <script src="theme.js?v=20261122a"></script>
</body>
</html>
