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

$stmt = $db->prepare("UPDATE session_batches
    SET deleted_at = NULL
    WHERE session_code = ? AND owner_user_id = ? AND deleted_at IS NOT NULL");
$stmt->execute([$code, (int)$user['id']]);

if ($stmt->rowCount() === 0) {
    echo json_encode(["success" => false, "error" => "Questionnaire introuvable dans la corbeille"]);
    exit;
}

echo json_encode(["success" => true, "code" => $code, "restored" => true]);
