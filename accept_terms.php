<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
require_once __DIR__ . '/lib/bootstrap.php';

// Records that the signed-in user accepted the terms of use (conditions-utilisation.html).
if (strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET')) !== 'POST') {
    http_response_code(405);
    echo json_encode(["success" => false, "error" => "Méthode non autorisée"]);
    exit;
}
require_same_origin_post(true);
$user = require_login_json();

try {
    $stmt = app_db()->prepare("UPDATE users SET terms_accepted_at = NOW() WHERE id = ? AND terms_accepted_at IS NULL");
    $stmt->execute([(int)$user['id']]);
    echo json_encode(["success" => true]);
} catch (Throwable $e) {
    app_json_error("Impossible d'enregistrer votre acceptation.", $e);
}
