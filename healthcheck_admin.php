<?php
declare(strict_types=1);

header("Content-Type: application/json; charset=UTF-8");
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Pragma: no-cache");

require_once __DIR__ . '/lib/bootstrap.php';

$user = require_login_json();
if (($user['role'] ?? '') !== 'admin') {
    http_response_code(403);
    echo json_encode(["success" => false, "error" => "Accès refusé"]);
    exit;
}

$checks = [];
$status = 'ok';

try {
    $db = app_db();

    $db->query("SELECT 1");
    $checks['db_connection'] = 'ok';

    $checks['users_count'] = (int)$db->query("SELECT COUNT(*) FROM users")->fetchColumn();
    $checks['quizzes_total_count'] = (int)$db->query("SELECT COUNT(*) FROM session_batches")->fetchColumn();
    $checks['active_sessions_count'] = (int)$db->query("SELECT COUNT(*) FROM session_batches WHERE deleted_at IS NULL")->fetchColumn();
    $checks['quizzes_deleted_count'] = (int)$db->query("SELECT COUNT(*) FROM session_batches WHERE deleted_at IS NOT NULL")->fetchColumn();
    $checks['quizzes_owned_count'] = (int)$db->query("SELECT COUNT(*)
        FROM session_batches sb
        INNER JOIN users u ON u.id = sb.owner_user_id")->fetchColumn();
    $checks['quizzes_orphan_count'] = (int)$db->query("SELECT COUNT(*)
        FROM session_batches sb
        LEFT JOIN users u ON u.id = sb.owner_user_id
        WHERE sb.owner_user_id IS NULL OR u.id IS NULL")->fetchColumn();
    $checks['vote_locks_count'] = (int)$db->query("SELECT COUNT(*) FROM session_vote_locks")->fetchColumn();
    $checks['open_responses_count'] = (int)$db->query("SELECT COUNT(*) FROM session_open_responses")->fetchColumn();

    $uploadDir = __DIR__ . '/uploads/questions';
    $checks['uploads_dir_exists'] = is_dir($uploadDir);
    $checks['uploads_dir_writable'] = is_dir($uploadDir) ? is_writable($uploadDir) : false;
} catch (Throwable $e) {
    $status = 'error';
    $checks['db_connection'] = 'error';
    error_log('[audience][healthcheck_admin] ' . $e->getMessage());
}

echo json_encode([
    'success' => $status === 'ok',
    'status' => $status,
    'timestamp' => gmdate('c'),
    'checks' => $checks
], JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
