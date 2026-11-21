<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
require_once __DIR__ . '/lib/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(["success" => false, "error" => "Methode non autorisee"]);
    exit;
}

require_same_origin_post(true);

$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input) || !isset($input['code'])) {
    echo json_encode(["success" => false, "error" => "Code requis"]);
    exit;
}

$code = trim((string)$input['code']);
$user = require_login_json();
$db = app_db();

try {
    $db->beginTransaction();

    $ownerStmt = $db->prepare("SELECT owner_user_id, deleted_at FROM session_batches WHERE session_code = ? FOR UPDATE");
    $ownerStmt->execute([$code]);
    $row = $ownerStmt->fetch(PDO::FETCH_ASSOC);
    if (!$row || (int)($row['owner_user_id'] ?? 0) !== (int)$user['id'] || empty($row['deleted_at'])) {
        $db->rollBack();
        echo json_encode(["success" => false, "error" => "Questionnaire introuvable dans la corbeille"]);
        exit;
    }

    $db->prepare("DELETE FROM session_responses WHERE session_code = ?")->execute([$code]);
    $db->prepare("DELETE FROM session_open_responses WHERE session_code = ?")->execute([$code]);
    $db->prepare("DELETE FROM session_response_details WHERE session_code = ?")->execute([$code]);
    $db->prepare("DELETE FROM session_vote_locks WHERE session_code = ?")->execute([$code]);
    app_purge_session_presence($db, $code);
    $db->prepare("DELETE FROM session_batches WHERE session_code = ?")->execute([$code]);

    $db->commit();
    echo json_encode(["success" => true, "code" => $code, "purged" => true]);
} catch (Throwable $e) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    app_json_error("Erreur interne.", $e);
}
