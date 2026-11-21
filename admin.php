<?php
declare(strict_types=1);
require_once __DIR__ . '/lib/bootstrap.php';

$admin = require_admin_page();
$db = app_db();

$error = '';
$ok = '';
$adminId = (int)($admin['id'] ?? 0);

/** Nombre d'administrateurs actifs, en excluant éventuellement un compte. */
function admin_active_admin_count(PDO $db, int $excludeId = 0): int {
    $stmt = $db->prepare("SELECT COUNT(*) FROM users WHERE role = 'admin' AND status = 'active' AND id <> ?");
    $stmt->execute([$excludeId]);
    return (int)$stmt->fetchColumn();
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    require_same_origin_post();
    $action = (string)($_POST['action'] ?? 'create');

    if ($action === 'create') {
        $username = sanitize_username((string)($_POST['username'] ?? ''));
        $email = trim((string)($_POST['email'] ?? ''));
        $password = (string)($_POST['password'] ?? '');
        $role = (string)($_POST['role'] ?? 'presenter');
        if ($role !== 'admin' && $role !== 'presenter') {
            $role = 'presenter';
        }

        if ($username === '' || $email === '' || $password === '') {
            $error = "Nom d'utilisateur, email et mot de passe requis.";
        } elseif (strlen($password) < 8) {
            $error = "Mot de passe trop court (8 caractères minimum).";
        } else {
            try {
                $stmt = $db->prepare("INSERT INTO users (username, email, password_hash, role, status) VALUES (?, ?, ?, ?, 'active')");
                $stmt->execute([$username, $email, password_hash($password, PASSWORD_DEFAULT), $role]);
                $ok = "Compte créé pour @" . $username;
            } catch (PDOException $e) {
                $error = "Impossible de créer ce compte (email ou nom d'utilisateur déjà utilisé ?).";
            }
        }
    } else {
        $targetId = (int)($_POST['user_id'] ?? 0);
        $targetStmt = $db->prepare("SELECT id, username, role, status FROM users WHERE id = ? LIMIT 1");
        $targetStmt->execute([$targetId]);
        $target = $targetStmt->fetch(PDO::FETCH_ASSOC);

        if (!$target) {
            $error = "Compte introuvable.";
        } elseif ((int)$target['id'] === $adminId) {
            $error = "Vous ne pouvez pas modifier votre propre compte ici : passez par votre profil.";
        } elseif ($action === 'set_role') {
            $role = (string)($_POST['role'] ?? '');
            if ($role !== 'admin' && $role !== 'presenter') {
                $error = "Rôle invalide.";
            } elseif ($role === 'presenter' && $target['role'] === 'admin' && admin_active_admin_count($db, (int)$target['id']) === 0) {
                $error = "Impossible de retirer le dernier administrateur actif.";
            } else {
                $db->prepare("UPDATE users SET role = ? WHERE id = ?")->execute([$role, (int)$target['id']]);
                $ok = $role === 'admin'
                    ? "@" . $target['username'] . " est maintenant administrateur."
                    : "@" . $target['username'] . " est maintenant présentateur.";
            }
        } elseif ($action === 'set_status') {
            $status = (string)($_POST['status'] ?? '');
            if ($status !== 'active' && $status !== 'disabled') {
                $error = "Statut invalide.";
            } elseif ($status === 'disabled' && $target['role'] === 'admin' && admin_active_admin_count($db, (int)$target['id']) === 0) {
                $error = "Impossible de désactiver le dernier administrateur actif.";
            } else {
                $db->prepare("UPDATE users SET status = ? WHERE id = ?")->execute([$status, (int)$target['id']]);
                $ok = $status === 'active'
                    ? "Le compte @" . $target['username'] . " est réactivé."
                    : "Le compte @" . $target['username'] . " est désactivé : il ne peut plus se connecter.";
            }
        } elseif ($action === 'delete_user') {
            if ($target['role'] === 'admin' && admin_active_admin_count($db, (int)$target['id']) === 0) {
                $error = "Impossible de supprimer le dernier administrateur actif.";
            } else {
                try {
                    $db->beginTransaction();
                    app_delete_user_data($db, (int)$target['id']);
                    $db->commit();
                    $ok = "Le compte @" . $target['username'] . " et toutes ses données ont été supprimés.";
                } catch (Throwable $e) {
                    if ($db->inTransaction()) {
                        $db->rollBack();
                    }
                    $error = "La suppression du compte a échoué.";
                }
            }
        } else {
            $error = "Action inconnue.";
        }
    }
}

/* ---------- Statistiques ---------- */
function admin_scalar(PDO $db, string $sql): ?int {
    try {
        $value = $db->query($sql)->fetchColumn();
        return $value === false || $value === null ? 0 : (int)$value;
    } catch (Throwable $e) {
        return null;
    }
}

$stats = [
    'users' => admin_scalar($db, "SELECT COUNT(*) FROM users"),
    'usersActive30' => admin_scalar($db, "SELECT COUNT(*) FROM users WHERE last_login_at >= (NOW() - INTERVAL 30 DAY)"),
    'usersNew30' => admin_scalar($db, "SELECT COUNT(*) FROM users WHERE created_at >= (NOW() - INTERVAL 30 DAY)"),
    'usersNever' => admin_scalar($db, "SELECT COUNT(*) FROM users WHERE last_login_at IS NULL"),
    'admins' => admin_scalar($db, "SELECT COUNT(*) FROM users WHERE role = 'admin'"),
    'disabled' => admin_scalar($db, "SELECT COUNT(*) FROM users WHERE status = 'disabled'"),
    'quizzes' => admin_scalar($db, "SELECT COUNT(*) FROM session_batches WHERE deleted_at IS NULL"),
    'quizzesTrash' => admin_scalar($db, "SELECT COUNT(*) FROM session_batches WHERE deleted_at IS NOT NULL"),
    'questions' => admin_scalar($db, "SELECT COALESCE(SUM(JSON_LENGTH(questions_json)), 0) FROM session_batches WHERE deleted_at IS NULL AND JSON_VALID(questions_json)"),
    'live' => admin_scalar($db, "SELECT COUNT(*) FROM session_batches WHERE live_active = 1 AND deleted_at IS NULL"),
    'folders' => admin_scalar($db, "SELECT COUNT(*) FROM quiz_folders"),
    'responses' => admin_scalar($db, "SELECT COUNT(*) FROM session_response_details"),
    'responses7' => admin_scalar($db, "SELECT COUNT(*) FROM session_response_details WHERE created_at >= (NOW() - INTERVAL 7 DAY)"),
    'participants30' => admin_scalar($db, "SELECT COUNT(DISTINCT voter_hash) FROM session_response_details WHERE created_at >= (NOW() - INTERVAL 30 DAY)"),
];

// Réponses par jour sur les 14 derniers jours (jours sans réponse inclus).
$activityDays = [];
for ($i = 13; $i >= 0; $i -= 1) {
    $activityDays[date('Y-m-d', strtotime("-{$i} day"))] = 0;
}
try {
    $activityStmt = $db->query("SELECT DATE(created_at) AS d, COUNT(*) AS c
        FROM session_response_details
        WHERE created_at >= (CURDATE() - INTERVAL 13 DAY)
        GROUP BY DATE(created_at)");
    foreach ($activityStmt->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $day = (string)$row['d'];
        if (array_key_exists($day, $activityDays)) {
            $activityDays[$day] = (int)$row['c'];
        }
    }
} catch (Throwable $e) {
    // Statistique facultative.
}
$activityMax = max(1, max($activityDays));
$activityTotal = array_sum($activityDays);

function admin_number(?int $value): string {
    return $value === null ? '—' : number_format($value, 0, ',', "\u{202F}");
}

function admin_date(?string $value, bool $withTime = false): string {
    $value = trim((string)$value);
    if ($value === '') {
        return '';
    }
    $ts = strtotime($value);
    if ($ts === false) {
        return $value;
    }
    $months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    $label = (int)date('j', $ts) . ' ' . $months[(int)date('n', $ts) - 1] . ' ' . date('Y', $ts);
    return $withTime ? $label . ' à ' . date('H:i', $ts) : $label;
}

/* ---------- Comptes ---------- */
$usersStmt = $db->query("SELECT
        u.id,
        u.username,
        u.email,
        u.role,
        u.status,
        u.created_at,
        u.last_login_at,
        COALESCE(q.quiz_count, 0) AS quiz_count
    FROM users u
    LEFT JOIN (
        SELECT owner_user_id, COUNT(*) AS quiz_count
        FROM session_batches
        WHERE deleted_at IS NULL
        GROUP BY owner_user_id
    ) q ON q.owner_user_id = u.id
    ORDER BY u.created_at DESC");
$users = $usersStmt->fetchAll(PDO::FETCH_ASSOC);

$searchQuery = trim((string)($_GET['q'] ?? ''));
$roleFilter = (string)($_GET['role'] ?? '');
if (!in_array($roleFilter, ['', 'admin', 'presenter', 'disabled'], true)) {
    $roleFilter = '';
}
if ($searchQuery !== '' || $roleFilter !== '') {
    $needle = mb_strtolower($searchQuery);
    $users = array_values(array_filter($users, function ($u) use ($needle, $roleFilter) {
        if ($roleFilter === 'disabled' && (string)$u['status'] !== 'disabled') {
            return false;
        }
        if (($roleFilter === 'admin' || $roleFilter === 'presenter') && (string)$u['role'] !== $roleFilter) {
            return false;
        }
        if ($needle === '') {
            return true;
        }
        return mb_strpos(mb_strtolower((string)$u['username'] . ' ' . (string)$u['email']), $needle) !== false;
    }));
}

$allowedUsersPerPage = [10, 20, 50, 100];
$requestedPerPage = isset($_GET['per_page']) ? (int)$_GET['per_page'] : 10;
$usersPerPage = in_array($requestedPerPage, $allowedUsersPerPage, true) ? $requestedPerPage : 10;
$totalUsers = count($users);
$totalPages = max(1, (int)ceil($totalUsers / $usersPerPage));
$requestedPage = isset($_GET['page']) ? (int)$_GET['page'] : 1;
$currentPage = max(1, min($totalPages, $requestedPage));
if ($ok !== '' && (string)($_POST['action'] ?? 'create') === 'create') {
    $currentPage = 1;
}
$usersPage = array_slice($users, ($currentPage - 1) * $usersPerPage, $usersPerPage);

/** Paramètres de la liste à conserver dans les liens et formulaires. */
function admin_list_query(array $overrides = []): string {
    global $currentPage, $usersPerPage, $searchQuery, $roleFilter;
    $params = array_merge([
        'page' => $currentPage,
        'per_page' => $usersPerPage,
        'q' => $searchQuery,
        'role' => $roleFilter,
    ], $overrides);
    $params = array_filter($params, function ($v) {
        return $v !== '' && $v !== null;
    });
    return htmlspecialchars('?' . http_build_query($params), ENT_QUOTES, 'UTF-8');
}
?>
<!doctype html>
<html lang="fr">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Admin - Audience</title>
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
<body class="page-admin">
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

    <?php if ($ok !== ''): ?><p class="msg-ok admin-flash"><?= htmlspecialchars($ok, ENT_QUOTES, 'UTF-8') ?></p><?php endif; ?>
    <?php if ($error !== ''): ?><p class="msg-err admin-flash"><?= htmlspecialchars($error, ENT_QUOTES, 'UTF-8') ?></p><?php endif; ?>
    <div class="card admin-overview">
        <h2><i class="fa-solid fa-chart-simple" aria-hidden="true"></i>Vue d'ensemble</h2>
        <div class="admin-stats">
            <div class="admin-stat">
                <span class="admin-stat-label"><i class="fa-solid fa-users" aria-hidden="true"></i>Utilisateurs</span>
                <strong class="admin-stat-value"><?= admin_number($stats['users']) ?></strong>
                <span class="admin-stat-sub"><?= admin_number($stats['usersActive30']) ?> actifs sur 30 jours · <?= admin_number($stats['usersNew30']) ?> nouveaux</span>
            </div>
            <div class="admin-stat">
                <span class="admin-stat-label"><i class="fa-solid fa-user-shield" aria-hidden="true"></i>Administrateurs</span>
                <strong class="admin-stat-value"><?= admin_number($stats['admins']) ?></strong>
                <span class="admin-stat-sub"><?= admin_number($stats['disabled']) ?> compte(s) désactivé(s) · <?= admin_number($stats['usersNever']) ?> jamais connecté(s)</span>
            </div>
            <div class="admin-stat">
                <span class="admin-stat-label"><i class="fa-solid fa-layer-group" aria-hidden="true"></i>Questionnaires</span>
                <strong class="admin-stat-value"><?= admin_number($stats['quizzes']) ?></strong>
                <span class="admin-stat-sub"><?= admin_number($stats['questions']) ?> questions · <?= admin_number($stats['folders']) ?> dossiers · <?= admin_number($stats['quizzesTrash']) ?> en corbeille</span>
            </div>
            <div class="admin-stat">
                <span class="admin-stat-label"><i class="fa-solid fa-tower-broadcast" aria-hidden="true"></i>En direct</span>
                <strong class="admin-stat-value"><?= admin_number($stats['live']) ?></strong>
                <span class="admin-stat-sub">session(s) lancée(s) en ce moment</span>
            </div>
            <div class="admin-stat">
                <span class="admin-stat-label"><i class="fa-solid fa-reply-all" aria-hidden="true"></i>Réponses</span>
                <strong class="admin-stat-value"><?= admin_number($stats['responses']) ?></strong>
                <span class="admin-stat-sub">+<?= admin_number($stats['responses7']) ?> ces 7 derniers jours</span>
            </div>
            <div class="admin-stat">
                <span class="admin-stat-label"><i class="fa-solid fa-user-group" aria-hidden="true"></i>Participants</span>
                <strong class="admin-stat-value"><?= admin_number($stats['participants30']) ?></strong>
                <span class="admin-stat-sub">appareils distincts sur 30 jours</span>
            </div>
        </div>
        <div class="admin-activity">
            <div class="admin-activity-head">
                <span class="admin-stat-label"><i class="fa-solid fa-chart-column" aria-hidden="true"></i>Réponses par jour</span>
                <span class="admin-activity-total"><?= admin_number($activityTotal) ?> sur 14 jours</span>
            </div>
            <div class="admin-activity-chart" role="img" aria-label="Réponses par jour sur les 14 derniers jours">
                <?php foreach ($activityDays as $day => $count): ?>
                    <?php $ratio = $count / $activityMax; $dayTs = strtotime($day); ?>
                    <div class="admin-activity-col" title="<?= htmlspecialchars(admin_date($day) . ' : ' . admin_number($count) . ' réponse(s)', ENT_QUOTES, 'UTF-8') ?>">
                        <span class="admin-activity-bar<?= $count === 0 ? ' is-empty' : '' ?>" style="--h: <?= number_format(max($ratio, $count > 0 ? 0.04 : 0), 3, '.', '') ?>"></span>
                        <span class="admin-activity-day"><?= (int)date('j', $dayTs) ?></span>
                    </div>
                <?php endforeach; ?>
            </div>
        </div>
    </div>
    <div class="card">
        <h2><i class="fa-solid fa-user-plus" aria-hidden="true"></i>Créer un utilisateur</h2>
        <form method="post" action="<?= admin_list_query(['page' => 1]) ?>" autocomplete="off">
            <input type="hidden" name="action" value="create">
            <div class="row">
                <div>
                    <label for="username">Nom d'utilisateur</label>
                    <input id="username" type="text" name="username" required autocomplete="off" autocapitalize="none" autocorrect="off" spellcheck="false">
                </div>
                <div>
                    <label for="email">Email</label>
                    <input id="email" type="email" name="email" required autocomplete="off" autocapitalize="none" autocorrect="off" spellcheck="false">
                </div>
                <div>
                    <label for="password">Mot de passe</label>
                    <input id="password" type="password" name="password" minlength="8" required autocomplete="new-password">
                </div>
                <div>
                    <label for="role">Rôle</label>
                    <select id="role" name="role">
                        <option value="presenter">Présentateur</option>
                        <option value="admin">Admin</option>
                    </select>
                </div>
            </div>
            <div class="form-actions">
                <button type="submit">Créer le compte</button>
            </div>
        </form>
    </div>

    <div class="card" id="accountsSection">
        <h2><i class="fa-solid fa-users" aria-hidden="true"></i>Comptes existants <span class="admin-count"><?= admin_number($totalUsers) ?></span></h2>
        <form method="get" action="#accountsSection" class="admin-filters" role="search">
            <input type="hidden" name="per_page" value="<?= $usersPerPage ?>">
            <label class="admin-search">
                <i class="fa-solid fa-magnifying-glass" aria-hidden="true"></i>
                <input type="search" name="q" value="<?= htmlspecialchars($searchQuery, ENT_QUOTES, 'UTF-8') ?>" placeholder="Rechercher un nom ou un email" aria-label="Rechercher un compte">
            </label>
            <select name="role" aria-label="Filtrer les comptes" onchange="this.form.submit()">
                <option value=""<?= $roleFilter === '' ? ' selected' : '' ?>>Tous les comptes</option>
                <option value="admin"<?= $roleFilter === 'admin' ? ' selected' : '' ?>>Administrateurs</option>
                <option value="presenter"<?= $roleFilter === 'presenter' ? ' selected' : '' ?>>Présentateurs</option>
                <option value="disabled"<?= $roleFilter === 'disabled' ? ' selected' : '' ?>>Désactivés</option>
            </select>
            <button type="submit" class="secondary-btn">Rechercher</button>
            <?php if ($searchQuery !== '' || $roleFilter !== ''): ?>
                <a class="admin-clear-filters" href="?per_page=<?= $usersPerPage ?>#accountsSection"><i class="fa-solid fa-xmark" aria-hidden="true"></i>Effacer</a>
            <?php endif; ?>
        </form>
        <div class="accounts-table-scroll">
            <table>
                <thead>
                    <tr><th>Compte</th><th>Rôle</th><th>Statut</th><th>Questionnaires</th><th>Créé le</th><th>Dernière connexion</th><th class="admin-actions-col"><span class="sr-only">Actions</span></th></tr>
                </thead>
                <tbody>
                <?php if (count($usersPage) === 0): ?>
                    <tr><td colspan="7" class="admin-empty">Aucun compte ne correspond.</td></tr>
                <?php endif; ?>
                <?php foreach ($usersPage as $u): ?>
                    <?php
                        $uid = (int)$u['id'];
                        $isSelf = $uid === $adminId;
                        $isAdminRole = (string)$u['role'] === 'admin';
                        $isActive = (string)$u['status'] === 'active';
                        $uname = (string)$u['username'];
                        $quizCount = (int)($u['quiz_count'] ?? 0);
                        $lastLoginAt = trim((string)($u['last_login_at'] ?? ''));
                    ?>
                    <tr class="<?= $isActive ? '' : 'is-disabled' ?>">
                        <td>
                            <div class="admin-user">
                                <span class="admin-avatar" aria-hidden="true"><?= htmlspecialchars(mb_strtoupper(mb_substr($uname !== '' ? $uname : '?', 0, 1)), ENT_QUOTES, 'UTF-8') ?></span>
                                <span class="admin-user-text">
                                    <strong><?= htmlspecialchars($uname, ENT_QUOTES, 'UTF-8') ?><?php if ($isSelf): ?> <span class="admin-chip is-self">Vous</span><?php endif; ?></strong>
                                    <small><?= htmlspecialchars((string)$u['email'], ENT_QUOTES, 'UTF-8') ?></small>
                                </span>
                            </div>
                        </td>
                        <td><span class="admin-chip <?= $isAdminRole ? 'is-admin' : '' ?>"><?= $isAdminRole ? 'Admin' : 'Présentateur' ?></span></td>
                        <td><span class="admin-status <?= $isActive ? 'is-active' : 'is-disabled' ?>"><?= $isActive ? 'Actif' : 'Désactivé' ?></span></td>
                        <td class="is-num"><?= number_format($quizCount, 0, ',', ' ') ?></td>
                        <td><?= htmlspecialchars(admin_date((string)$u['created_at']), ENT_QUOTES, 'UTF-8') ?></td>
                        <td><?= $lastLoginAt !== '' ? htmlspecialchars(admin_date($lastLoginAt, true), ENT_QUOTES, 'UTF-8') : '<span class="admin-muted">Jamais</span>' ?></td>
                        <td class="admin-actions-col">
                            <?php if (!$isSelf): ?>
                            <div class="admin-row-actions">
                                <form method="post" action="<?= admin_list_query() ?>#accountsSection">
                                    <input type="hidden" name="action" value="set_role">
                                    <input type="hidden" name="user_id" value="<?= $uid ?>">
                                    <input type="hidden" name="role" value="<?= $isAdminRole ? 'presenter' : 'admin' ?>">
                                    <button type="submit" class="admin-icon-btn" title="<?= $isAdminRole ? 'Rendre présentateur' : 'Rendre administrateur' ?>" aria-label="<?= $isAdminRole ? 'Rendre présentateur' : 'Rendre administrateur' ?> : <?= htmlspecialchars($uname, ENT_QUOTES, 'UTF-8') ?>">
                                        <i class="fa-solid <?= $isAdminRole ? 'fa-user-minus' : 'fa-user-shield' ?>" aria-hidden="true"></i>
                                    </button>
                                </form>
                                <form method="post" action="<?= admin_list_query() ?>#accountsSection"<?php if ($isActive): ?> data-confirm-title="Désactiver @<?= htmlspecialchars($uname, ENT_QUOTES, 'UTF-8') ?> ?" data-confirm-message="Ce compte ne pourra plus se connecter et sera déconnecté immédiatement. Ses questionnaires sont conservés ; vous pourrez le réactiver à tout moment." data-confirm-label="Désactiver" data-confirm-icon="fa-ban"<?php endif; ?>>
                                    <input type="hidden" name="action" value="set_status">
                                    <input type="hidden" name="user_id" value="<?= $uid ?>">
                                    <input type="hidden" name="status" value="<?= $isActive ? 'disabled' : 'active' ?>">
                                    <button type="submit" class="admin-icon-btn" title="<?= $isActive ? 'Désactiver le compte' : 'Réactiver le compte' ?>" aria-label="<?= $isActive ? 'Désactiver' : 'Réactiver' ?> : <?= htmlspecialchars($uname, ENT_QUOTES, 'UTF-8') ?>">
                                        <i class="fa-solid <?= $isActive ? 'fa-ban' : 'fa-circle-check' ?>" aria-hidden="true"></i>
                                    </button>
                                </form>
                                <form method="post" action="<?= admin_list_query() ?>#accountsSection" data-confirm-title="Supprimer @<?= htmlspecialchars($uname, ENT_QUOTES, 'UTF-8') ?> ?" data-confirm-message="Le compte et ses <?= $quizCount ?> questionnaire(s), avec toutes leurs réponses et ses dossiers, seront effacés définitivement. Cette action est irréversible." data-confirm-label="Supprimer le compte" data-confirm-icon="fa-trash">
                                    <input type="hidden" name="action" value="delete_user">
                                    <input type="hidden" name="user_id" value="<?= $uid ?>">
                                    <button type="submit" class="admin-icon-btn is-danger" title="Supprimer le compte" aria-label="Supprimer le compte : <?= htmlspecialchars($uname, ENT_QUOTES, 'UTF-8') ?>">
                                        <i class="fa-solid fa-trash" aria-hidden="true"></i>
                                    </button>
                                </form>
                            </div>
                            <?php endif; ?>
                        </td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <div class="accounts-pagination-row">
            <?php if ($totalPages > 1): ?>
                <nav class="accounts-pagination" aria-label="Pagination des comptes utilisateurs">
                    <?php for ($page = 1; $page <= $totalPages; $page += 1): ?>
                        <?php if ($page === $currentPage): ?>
                            <span class="accounts-page-link is-current" aria-current="page"><?= $page ?></span>
                        <?php else: ?>
                            <a class="accounts-page-link" href="<?= admin_list_query(['page' => $page]) ?>#accountsSection"><?= $page ?></a>
                        <?php endif; ?>
                    <?php endfor; ?>
                </nav>
            <?php endif; ?>
            <form method="get" action="" class="accounts-page-size-form">
                <input type="hidden" name="page" value="1">
                <?php if ($searchQuery !== ''): ?><input type="hidden" name="q" value="<?= htmlspecialchars($searchQuery, ENT_QUOTES, 'UTF-8') ?>"><?php endif; ?>
                <?php if ($roleFilter !== ''): ?><input type="hidden" name="role" value="<?= htmlspecialchars($roleFilter, ENT_QUOTES, 'UTF-8') ?>"><?php endif; ?>
                <label for="accountsPerPage">Utilisateurs par page</label>
                <select id="accountsPerPage" name="per_page" onchange="this.form.submit()">
                    <?php foreach ($allowedUsersPerPage as $perPageOption): ?>
                        <option value="<?= $perPageOption ?>"<?= $perPageOption === $usersPerPage ? ' selected' : '' ?>><?= $perPageOption ?></option>
                    <?php endforeach; ?>
                </select>
            </form>
        </div>
    </div>

    <div class="card">
        <h2><i class="fa-solid fa-stethoscope" aria-hidden="true"></i>Diagnostic système</h2>
        <p>Vérifie la base de données et les dossiers critiques. Réservé aux administrateurs connectés.</p>
        <div class="form-actions healthcheck-actions">
            <button type="button" id="runHealthcheckBtn" class="secondary-btn">
                <i class="fa-solid fa-heart-pulse" aria-hidden="true"></i>Lancer
            </button>
            <button type="button" id="purgeOrphansBtn" class="danger-btn">
                <i class="fa-solid fa-trash-can" aria-hidden="true"></i>Purger les orphelins
            </button>
        </div>
        <div id="healthcheckPanel" class="healthcheck-panel hidden" aria-live="polite">
            <div class="healthcheck-summary-row">
                <span id="healthcheckBadge" class="healthcheck-badge">Diagnostic en attente</span>
                <span id="healthcheckTimestamp" class="healthcheck-timestamp"></span>
            </div>
            <div id="healthcheckCards" class="healthcheck-cards"></div>
            <details class="healthcheck-raw">
                <summary>Voir le JSON brut</summary>
                <pre id="healthcheckOutput"></pre>
            </details>
        </div>
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
<script src="client-common.js?v=20261121s"></script>
<script>
    document.addEventListener('submit', async function(event) {
        const form = event.target.closest('form[data-confirm-title]');
        if (!form || form.dataset.confirmed === '1') {
            return;
        }
        event.preventDefault();
        const confirmed = window.AudienceDialog
            ? await window.AudienceDialog.confirm({
                title: form.dataset.confirmTitle,
                message: form.dataset.confirmMessage || '',
                confirmLabel: form.dataset.confirmLabel || 'Confirmer',
                tone: 'danger',
                icon: form.dataset.confirmIcon || 'fa-triangle-exclamation'
            })
            : window.confirm(form.dataset.confirmTitle);
        if (confirmed) {
            form.dataset.confirmed = '1';
            form.submit();
        }
    });
</script>
<script>
    const footerYear = document.getElementById('current-year');
    if (footerYear) {
        footerYear.textContent = String(new Date().getFullYear());
    }
    // Ne pas placer le curseur automatiquement dans le formulaire à l'ouverture de la page.
    window.requestAnimationFrame(() => {
        const active = document.activeElement;
        if (active instanceof HTMLElement && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.tagName === 'SELECT')) {
            active.blur();
        }
    });

    const runHealthcheckBtn = document.getElementById('runHealthcheckBtn');
    const purgeOrphansBtn = document.getElementById('purgeOrphansBtn');
    const healthcheckPanel = document.getElementById('healthcheckPanel');
    const healthcheckOutput = document.getElementById('healthcheckOutput');
    const healthcheckCards = document.getElementById('healthcheckCards');
    const healthcheckBadge = document.getElementById('healthcheckBadge');
    const healthcheckTimestamp = document.getElementById('healthcheckTimestamp');
    const metricLabels = {
        db_connection: 'Connexion base',
        users_count: 'Utilisateurs',
        quizzes_total_count: 'Questionnaires créés',
        active_sessions_count: 'Sessions actives',
        quizzes_deleted_count: 'Questionnaires en corbeille',
        quizzes_owned_count: 'Questionnaires liés à un compte',
        quizzes_orphan_count: 'Questionnaires orphelins',
        vote_locks_count: 'Verrous anti-vote',
        open_responses_count: 'Réponses ouvertes',
        uploads_dir_exists: 'Dossier uploads',
        uploads_dir_writable: 'Uploads inscriptible'
    };

    function formatMetricValue(key, value) {
        if (key === 'db_connection') {
            return value === 'ok' ? 'OK' : 'Erreur';
        }
        if (typeof value === 'boolean') {
            return value ? 'Oui' : 'Non';
        }
        if (typeof value === 'number') {
            return new Intl.NumberFormat('fr-FR').format(value);
        }
        if (value === null || value === undefined || value === '') {
            return '—';
        }
        return String(value);
    }

    function metricStateClass(key, value) {
        if (key === 'db_connection') {
            return value === 'ok' ? 'is-ok' : 'is-error';
        }
        if (typeof value === 'boolean') {
            return value ? 'is-ok' : 'is-warn';
        }
        return 'is-neutral';
    }

    function renderHealthcheck(data) {
        const checks = data && typeof data.checks === 'object' && data.checks ? data.checks : {};
        const success = !!(data && data.success);
        const statusText = success ? 'Système opérationnel' : 'Incident détecté';

        healthcheckBadge.textContent = statusText;
        healthcheckBadge.classList.remove('is-ok', 'is-error', 'is-pending');
        healthcheckBadge.classList.add(success ? 'is-ok' : 'is-error');

        const stamp = data && data.timestamp ? new Date(data.timestamp) : null;
        healthcheckTimestamp.textContent = stamp && !Number.isNaN(stamp.getTime())
            ? 'Mis à jour: ' + stamp.toLocaleString('fr-FR')
            : '';

        healthcheckCards.innerHTML = '';
        const entries = Object.entries(checks);
        if (entries.length === 0) {
            const empty = document.createElement('p');
            empty.className = 'healthcheck-empty';
            empty.textContent = 'Aucun indicateur disponible.';
            healthcheckCards.appendChild(empty);
            return;
        }

        entries.forEach(([key, value]) => {
            const item = document.createElement('article');
            item.className = 'healthcheck-item';
            const stateClass = metricStateClass(key, value);
            item.classList.add(stateClass);

            const label = document.createElement('p');
            label.className = 'healthcheck-item-label';
            label.textContent = metricLabels[key] || key;

            const metricValue = document.createElement('p');
            metricValue.className = 'healthcheck-item-value ' + stateClass;
            metricValue.textContent = formatMetricValue(key, value);

            item.appendChild(label);
            item.appendChild(metricValue);
            healthcheckCards.appendChild(item);
        });
    }

    async function runHealthcheck() {
        if (!runHealthcheckBtn || !healthcheckPanel || !healthcheckOutput || !healthcheckCards || !healthcheckBadge || !healthcheckTimestamp) {
            return;
        }

        const originalText = runHealthcheckBtn.innerHTML;
        runHealthcheckBtn.disabled = true;
        runHealthcheckBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i>Diagnostic...';
        healthcheckPanel.classList.remove('hidden');
        healthcheckBadge.textContent = 'Diagnostic en cours...';
        healthcheckBadge.classList.remove('is-ok', 'is-error', 'is-pending');
        healthcheckBadge.classList.add('is-pending');
        healthcheckTimestamp.textContent = '';
        healthcheckCards.innerHTML = '<p class="healthcheck-empty">Chargement...</p>';
        healthcheckOutput.textContent = '';
        try {
            const response = await fetch('healthcheck_admin.php', {
                credentials: 'same-origin',
                headers: { 'Accept': 'application/json' }
            });
            const data = await response.json();
            renderHealthcheck(data);
            healthcheckOutput.textContent = JSON.stringify(data, null, 2);
        } catch (error) {
            const fallback = {
                success: false,
                error: 'Impossible de lancer le diagnostic.'
            };
            renderHealthcheck(fallback);
            healthcheckOutput.textContent = JSON.stringify(fallback, null, 2);
        } finally {
            runHealthcheckBtn.disabled = false;
            runHealthcheckBtn.innerHTML = originalText;
        }
    }

    runHealthcheckBtn?.addEventListener('click', () => {
        runHealthcheck();
    });

    purgeOrphansBtn?.addEventListener('click', async () => {
        const confirmed = await window.AudienceDialog.confirm({
            title: 'Purger les questionnaires orphelins ?',
            message: 'Tous les questionnaires sans propriétaire valide seront supprimés définitivement. Cette action est irréversible.',
            confirmLabel: 'Purger',
            tone: 'danger',
            icon: 'fa-triangle-exclamation'
        });
        if (!confirmed) {
            return;
        }

        const originalText = purgeOrphansBtn.innerHTML;
        purgeOrphansBtn.disabled = true;
        purgeOrphansBtn.innerHTML = '<i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i>Purge...';
        try {
            const response = await fetch('purge_orphan_quizzes.php', {
                method: 'POST',
                credentials: 'same-origin',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({})
            });
            const data = await response.json();
            if (!data.success) {
                throw new Error(data.error || 'Purge impossible.');
            }

            alert(`Purge terminée. Questionnaires supprimés: ${new Intl.NumberFormat('fr-FR').format(Number(data.purgedBatches || 0))}.`);
            await runHealthcheck();
        } catch (error) {
            alert(error.message || 'Purge impossible.');
        } finally {
            purgeOrphansBtn.disabled = false;
            purgeOrphansBtn.innerHTML = originalText;
        }
    });
</script>
</body>
</html>
