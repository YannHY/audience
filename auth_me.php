<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
require_once __DIR__ . '/lib/bootstrap.php';

$user = refresh_session_user(current_user());
if (!$user) {
    http_response_code(401);
    echo json_encode(["success" => false, "error" => "Non connecté"]);
    exit;
}

// Acceptance of the terms of use, asked once per account (see accept_terms.php).
$termsAccepted = true;
try {
    $stmt = app_db()->prepare("SELECT terms_accepted_at FROM users WHERE id = ? LIMIT 1");
    $stmt->execute([(int)$user['id']]);
    $termsAccepted = !empty($stmt->fetchColumn());
} catch (Throwable $e) {
    // If the column cannot be read, do not block the user.
}

echo json_encode([
    "success" => true,
    "user" => [
        "id" => (int)$user['id'],
        "username" => (string)($user['username'] ?? ''),
        "email" => (string)$user['email'],
        "role" => (string)$user['role'],
        "termsAccepted" => $termsAccepted
    ]
]);
