<?php
declare(strict_types=1);
require_once __DIR__ . '/lib/bootstrap.php';

$user = require_login_page();
$db = app_db();

$msgOk = (string)($_SESSION['profile_msg_ok'] ?? '');
$msgErr = (string)($_SESSION['profile_msg_err'] ?? '');
unset($_SESSION['profile_msg_ok'], $_SESSION['profile_msg_err']);

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_same_origin_post();
    $action = (string)($_POST['action'] ?? '');

    if ($action === 'identity') {
        $username = sanitize_username((string)($_POST['username'] ?? ''));
        $email = trim((string)($_POST['email'] ?? ''));

        if ($username === '' || $email === '') {
            $msgErr = "Nom d'utilisateur et email requis.";
        } elseif (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
            $msgErr = "Adresse email invalide.";
        } else {
            try {
                $stmt = $db->prepare("UPDATE users SET username = ?, email = ? WHERE id = ?");
                $stmt->execute([$username, $email, (int)$user['id']]);
                $_SESSION['user']['username'] = $username;
                $_SESSION['user']['email'] = $email;
                $msgOk = "Informations mises à jour.";
            } catch (PDOException $e) {
                $msgErr = "Nom d'utilisateur ou email déjà utilisé.";
            }
        }
    } elseif ($action === 'password') {
        $current = (string)($_POST['current_password'] ?? '');
        $next = (string)($_POST['new_password'] ?? '');
        $confirm = (string)($_POST['confirm_password'] ?? '');

        if ($current === '' || $next === '' || $confirm === '') {
            $msgErr = "Tous les champs mot de passe sont requis.";
        } elseif (strlen($next) < 8) {
            $msgErr = "Le nouveau mot de passe doit faire au moins 8 caractères.";
        } elseif ($next !== $confirm) {
            $msgErr = "La confirmation du nouveau mot de passe ne correspond pas.";
        } else {
            $stmt = $db->prepare("SELECT password_hash FROM users WHERE id = ? LIMIT 1");
            $stmt->execute([(int)$user['id']]);
            $row = $stmt->fetch(PDO::FETCH_ASSOC);
            if (!$row || !password_verify($current, (string)$row['password_hash'])) {
                $msgErr = "Mot de passe actuel incorrect.";
            } else {
                $upd = $db->prepare("UPDATE users SET password_hash = ? WHERE id = ?");
                $upd->execute([password_hash($next, PASSWORD_DEFAULT), (int)$user['id']]);
                $msgOk = "Mot de passe mis à jour.";
            }
        }
    } elseif ($action === 'delete_account') {
        $currentPassword = (string)($_POST['delete_current_password'] ?? '');

        if ($currentPassword === '') {
            $msgErr = "Veuillez saisir votre mot de passe pour confirmer la suppression.";
        } else {
            $userId = (int)$user['id'];
            try {
                $db->beginTransaction();

                $roleStmt = $db->prepare("SELECT role, password_hash FROM users WHERE id = ? LIMIT 1");
                $roleStmt->execute([$userId]);
                $row = $roleStmt->fetch(PDO::FETCH_ASSOC);
                if (!$row || !password_verify($currentPassword, (string)$row['password_hash'])) {
                    $db->rollBack();
                    $msgErr = "Mot de passe incorrect. Suppression annulée.";
                } else {
                    if ((string)$row['role'] === 'admin') {
                        $adminCountStmt = $db->prepare("SELECT COUNT(*) FROM users WHERE role = 'admin' AND status = 'active' AND id <> ?");
                        $adminCountStmt->execute([$userId]);
                        $otherActiveAdmins = (int)$adminCountStmt->fetchColumn();
                        if ($otherActiveAdmins === 0) {
                            $db->rollBack();
                            $msgErr = "Impossible de supprimer le dernier compte administrateur actif.";
                        } else {
                            $batchCodesStmt = $db->prepare("SELECT session_code FROM session_batches WHERE owner_user_id = ?");
                            $batchCodesStmt->execute([$userId]);
                            $codes = array_values(array_filter(array_map(function($r) {
                                return (string)($r['session_code'] ?? '');
                            }, $batchCodesStmt->fetchAll(PDO::FETCH_ASSOC))));

                            if (count($codes) > 0) {
                                $placeholders = implode(',', array_fill(0, count($codes), '?'));
                                $db->prepare("DELETE FROM session_responses WHERE session_code IN ($placeholders)")->execute($codes);
                                $db->prepare("DELETE FROM session_open_responses WHERE session_code IN ($placeholders)")->execute($codes);
                                $db->prepare("DELETE FROM session_response_details WHERE session_code IN ($placeholders)")->execute($codes);
                                $db->prepare("DELETE FROM session_vote_locks WHERE session_code IN ($placeholders)")->execute($codes);
                                $db->prepare("DELETE FROM session_presence WHERE session_code IN ($placeholders)")->execute($codes);
                            }

                            $db->prepare("DELETE FROM session_batches WHERE owner_user_id = ?")->execute([$userId]);
                            $db->prepare("DELETE FROM quiz_folders WHERE owner_user_id = ?")->execute([$userId]);
                            $db->prepare("DELETE FROM contact_messages WHERE user_id = ?")->execute([$userId]);
                            $db->prepare("DELETE FROM users WHERE id = ?")->execute([$userId]);

                            $db->commit();

                            $_SESSION = [];
                            if (session_status() === PHP_SESSION_ACTIVE) {
                                session_destroy();
                            }
                            header('Location: login.php?account_deleted=1');
                            exit;
                        }
                    } else {
                        $batchCodesStmt = $db->prepare("SELECT session_code FROM session_batches WHERE owner_user_id = ?");
                        $batchCodesStmt->execute([$userId]);
                        $codes = array_values(array_filter(array_map(function($r) {
                            return (string)($r['session_code'] ?? '');
                        }, $batchCodesStmt->fetchAll(PDO::FETCH_ASSOC))));

                        if (count($codes) > 0) {
                            $placeholders = implode(',', array_fill(0, count($codes), '?'));
                            $db->prepare("DELETE FROM session_responses WHERE session_code IN ($placeholders)")->execute($codes);
                            $db->prepare("DELETE FROM session_open_responses WHERE session_code IN ($placeholders)")->execute($codes);
                            $db->prepare("DELETE FROM session_response_details WHERE session_code IN ($placeholders)")->execute($codes);
                            $db->prepare("DELETE FROM session_vote_locks WHERE session_code IN ($placeholders)")->execute($codes);
                            $db->prepare("DELETE FROM session_presence WHERE session_code IN ($placeholders)")->execute($codes);
                        }

                        $db->prepare("DELETE FROM session_batches WHERE owner_user_id = ?")->execute([$userId]);
                            $db->prepare("DELETE FROM quiz_folders WHERE owner_user_id = ?")->execute([$userId]);
                        $db->prepare("DELETE FROM contact_messages WHERE user_id = ?")->execute([$userId]);
                        $db->prepare("DELETE FROM users WHERE id = ?")->execute([$userId]);
                        $db->commit();

                        $_SESSION = [];
                        if (session_status() === PHP_SESSION_ACTIVE) {
                            session_destroy();
                        }
                        header('Location: login.php?account_deleted=1');
                        exit;
                    }
                }
            } catch (Throwable $e) {
                if ($db->inTransaction()) {
                    $db->rollBack();
                }
                $msgErr = "Suppression impossible pour le moment.";
            }
        }
    }
}

$stmt = $db->prepare("SELECT username, email, role FROM users WHERE id = ? LIMIT 1");
$stmt->execute([(int)$user['id']]);
$me = $stmt->fetch(PDO::FETCH_ASSOC) ?: ['username' => '', 'email' => '', 'role' => 'presenter'];
$_SESSION['user']['username'] = (string)$me['username'];
$_SESSION['user']['email'] = (string)$me['email'];
?>
<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Mon profil - Audience</title>
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
<body class="page-profile">
<div id="accountBar" class="account-bar"></div>
<div class="wrap">
    <div class="top">
        <div class="page-top-brand">
            <div class="page-brand-line">
                <a href="index.html" aria-label="Retour à l'accueil Audience">
                    <img src="logo.png" alt="Logo Audience" class="page-brand-logo">
                </a>
                <h1 class="page-title">Audience</h1>
            </div>
            <p class="page-site-tagline">Créez vos questions et affichez les réponses en direct</p>
        </div>
    </div>

    <?php if ($msgOk !== ''): ?><p class="msg-ok"><?= htmlspecialchars($msgOk, ENT_QUOTES, 'UTF-8') ?></p><?php endif; ?>
    <?php if ($msgErr !== ''): ?><p class="msg-err"><?= htmlspecialchars($msgErr, ENT_QUOTES, 'UTF-8') ?></p><?php endif; ?>

    <div class="card">
        <h2><i class="fa-solid fa-user" aria-hidden="true"></i>Informations du compte</h2>
        <form method="post">
            <input type="hidden" name="action" value="identity">
            <div class="row">
                <div>
                    <label for="username">Nom d'utilisateur</label>
                    <input id="username" name="username" type="text" value="<?= htmlspecialchars((string)$me['username'], ENT_QUOTES, 'UTF-8') ?>" required>
                </div>
                <div>
                    <label for="email">Email</label>
                    <input id="email" name="email" type="email" value="<?= htmlspecialchars((string)$me['email'], ENT_QUOTES, 'UTF-8') ?>" required>
                </div>
            </div>
            <div class="form-actions">
                <button type="submit">Enregistrer</button>
            </div>
        </form>
    </div>

    <div class="card">
        <h2><i class="fa-solid fa-key" aria-hidden="true"></i>Changer le mot de passe</h2>
        <form method="post">
            <input type="hidden" name="action" value="password">
            <label for="current_password">Mot de passe actuel</label>
            <input id="current_password" name="current_password" type="password" required>
            <label for="new_password">Nouveau mot de passe</label>
            <input id="new_password" name="new_password" type="password" minlength="8" required>
            <label for="confirm_password">Confirmer le nouveau mot de passe</label>
            <input id="confirm_password" name="confirm_password" type="password" minlength="8" required>
            <div class="form-actions">
                <button type="submit">Mettre à jour le mot de passe</button>
            </div>
        </form>
    </div>

    <div class="card export-zone">
        <h2><i class="fa-solid fa-file-zipper" aria-hidden="true"></i>Exporter mes questionnaires</h2>
        <p class="export-text">Téléchargez une archive ZIP contenant un fichier Markdown par questionnaire</p>
        <form method="post" action="export_quizzes.php">
            <div class="form-actions">
                <button type="submit" class="export-btn"><i class="fa-solid fa-download" aria-hidden="true"></i>Exporter</button>
            </div>
        </form>
    </div>

    <div class="card danger-zone">
        <h2 class="danger-title"><i class="fa-solid fa-triangle-exclamation" aria-hidden="true"></i>Supprimer mon compte</h2>
        <p class="danger-text">Cette action est définitive. Toutes vos sessions et réponses associées seront supprimées.</p>
        <form method="post" id="deleteAccountForm">
            <input type="hidden" name="action" value="delete_account">
            <label for="delete_current_password">Mot de passe actuel</label>
            <input id="delete_current_password" name="delete_current_password" type="password" required>
            <div class="form-actions">
                <button type="submit" class="danger-btn"><i class="fa-solid fa-trash-can" aria-hidden="true"></i>Supprimer mon compte</button>
            </div>
        </form>
    </div>

    <footer class="footer" data-animate="fade-up" data-delay="700" data-site-footer></footer>
</div>
<script src="site-nav.js?v=20261121v"></script>
<script src="site-footer.js?v=20261121b"></script>
<script src="theme.js?v=20261122a"></script>
<script src="client-common.js?v=20261121s"></script>
<script>
    const deleteAccountForm = document.getElementById('deleteAccountForm');
    deleteAccountForm?.addEventListener('submit', async function(event) {
        if (deleteAccountForm.dataset.confirmed === '1') {
            return;
        }
        event.preventDefault();
        if (!deleteAccountForm.reportValidity()) {
            return;
        }
        const confirmed = window.AudienceDialog
            ? await window.AudienceDialog.confirm({
                title: 'Supprimer votre compte ?',
                message: 'Votre compte, tous vos questionnaires, leurs réponses et vos dossiers seront effacés définitivement. Cette action est irréversible.',
                confirmLabel: 'Supprimer mon compte',
                tone: 'danger',
                icon: 'fa-triangle-exclamation'
            })
            : window.confirm('Confirmer la suppression définitive de votre compte ?');
        if (confirmed) {
            deleteAccountForm.dataset.confirmed = '1';
            deleteAccountForm.submit();
        }
    });

    const footerYear = document.getElementById('current-year');
    if (footerYear) {
        footerYear.textContent = String(new Date().getFullYear());
    }
</script>
</body>
</html>
