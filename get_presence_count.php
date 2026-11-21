<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
require_once __DIR__ . '/lib/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    echo json_encode(["success" => false, "error" => "Methode non autorisee"]);
    exit;
}

if (!isset($_GET['code'])) {
    echo json_encode(["success" => false, "error" => "Code requis"]);
    exit;
}

$code = trim((string)$_GET['code']);
$activeWindowSeconds = 20;

try {
    $user = require_login_json();
    $db = app_db();

    $ownerStmt = $db->prepare("SELECT owner_user_id, live_active
        FROM session_batches
        WHERE session_code = ? AND deleted_at IS NULL
        LIMIT 1");
    $ownerStmt->execute([$code]);
    $row = $ownerStmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        echo json_encode(["success" => false, "error" => "Session introuvable"]);
        exit;
    }
    if ((int)($row['owner_user_id'] ?? 0) !== (int)$user['id']) {
        http_response_code(403);
        echo json_encode(["success" => false, "error" => "Accès refusé"]);
        exit;
    }

    $connectedCount = app_count_session_presence($db, $code, $activeWindowSeconds);
    echo json_encode([
        "success" => true,
        "code" => $code,
        "connectedCount" => $connectedCount,
        "activeWindowSeconds" => $activeWindowSeconds,
        "liveActive" => ((int)($row['live_active'] ?? 0)) === 1
    ]);
} catch (Throwable $e) {
    app_json_error("Erreur interne.", $e);
}
?>
