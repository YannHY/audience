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

$user = require_login_json();
if (($user['role'] ?? '') !== 'admin') {
    http_response_code(403);
    echo json_encode(["success" => false, "error" => "Accès refusé"]);
    exit;
}

$db = app_db();

try {
    $db->beginTransaction();

    $orphanCount = (int)$db->query("SELECT COUNT(*)
        FROM session_batches sb
        LEFT JOIN users u ON u.id = sb.owner_user_id
        WHERE sb.owner_user_id IS NULL OR u.id IS NULL")->fetchColumn();

    if ($orphanCount === 0) {
        $db->commit();
        echo json_encode([
            "success" => true,
            "purgedBatches" => 0,
            "purgedResponses" => 0,
            "purgedOpenResponses" => 0,
            "purgedResponseDetails" => 0,
            "purgedVoteLocks" => 0,
            "purgedPresence" => 0
        ]);
        exit;
    }

    $deleteResponses = $db->exec("DELETE sr
        FROM session_responses sr
        INNER JOIN session_batches sb ON sb.session_code = sr.session_code
        LEFT JOIN users u ON u.id = sb.owner_user_id
        WHERE sb.owner_user_id IS NULL OR u.id IS NULL");

    $deleteOpenResponses = $db->exec("DELETE sor
        FROM session_open_responses sor
        INNER JOIN session_batches sb ON sb.session_code = sor.session_code
        LEFT JOIN users u ON u.id = sb.owner_user_id
        WHERE sb.owner_user_id IS NULL OR u.id IS NULL");

    $deleteResponseDetails = $db->exec("DELETE srd
        FROM session_response_details srd
        INNER JOIN session_batches sb ON sb.session_code = srd.session_code
        LEFT JOIN users u ON u.id = sb.owner_user_id
        WHERE sb.owner_user_id IS NULL OR u.id IS NULL");

    $deleteVoteLocks = $db->exec("DELETE svl
        FROM session_vote_locks svl
        INNER JOIN session_batches sb ON sb.session_code = svl.session_code
        LEFT JOIN users u ON u.id = sb.owner_user_id
        WHERE sb.owner_user_id IS NULL OR u.id IS NULL");

    $deletePresence = $db->exec("DELETE sp
        FROM session_presence sp
        INNER JOIN session_batches sb ON sb.session_code = sp.session_code
        LEFT JOIN users u ON u.id = sb.owner_user_id
        WHERE sb.owner_user_id IS NULL OR u.id IS NULL");

    $deleteBatches = $db->exec("DELETE sb
        FROM session_batches sb
        LEFT JOIN users u ON u.id = sb.owner_user_id
        WHERE sb.owner_user_id IS NULL OR u.id IS NULL");

    $db->commit();

    echo json_encode([
        "success" => true,
        "purgedBatches" => (int)$deleteBatches,
        "purgedResponses" => (int)$deleteResponses,
        "purgedOpenResponses" => (int)$deleteOpenResponses,
        "purgedResponseDetails" => (int)$deleteResponseDetails,
        "purgedVoteLocks" => (int)$deleteVoteLocks,
        "purgedPresence" => (int)$deletePresence
    ]);
} catch (Throwable $e) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    app_json_error("Erreur interne.", $e);
}
