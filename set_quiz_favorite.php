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
if (!is_array($input) || !isset($input['code']) || !array_key_exists('favorite', $input)) {
    echo json_encode(["success" => false, "error" => "Parametres invalides"]);
    exit;
}

$code = trim((string)$input['code']);
$favorite = (int)((bool)$input['favorite']);
if ($code === '') {
    echo json_encode(["success" => false, "error" => "Code requis"]);
    exit;
}

$user = require_login_json();
$db = app_db();

$stmt = $db->prepare("UPDATE session_batches
    SET is_favorite = ?
    WHERE session_code = ? AND owner_user_id = ? AND deleted_at IS NULL");
$stmt->execute([$favorite, $code, (int)$user['id']]);

if ($stmt->rowCount() === 0) {
    $check = $db->prepare("SELECT is_favorite FROM session_batches
        WHERE session_code = ? AND owner_user_id = ? AND deleted_at IS NULL");
    $check->execute([$code, (int)$user['id']]);
    $row = $check->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        echo json_encode(["success" => false, "error" => "Questionnaire introuvable"]);
        exit;
    }
    $favorite = ((int)($row['is_favorite'] ?? 0)) === 1 ? 1 : 0;
}

echo json_encode([
    "success" => true,
    "code" => $code,
    "isFavorite" => $favorite === 1
]);
