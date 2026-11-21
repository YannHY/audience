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
    echo json_encode(["success" => false, "error" => "Parametres manquants"]);
    exit;
}

$code = trim((string)$input['code']);
$liveActive = isset($input['liveActive']) ? (((int)(bool)$input['liveActive']) ? 1 : 0) : 1;

function normalize_question_time_limit_set_live($value): int {
    $limit = is_numeric($value) ? (int)$value : 30;
    $allowed = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];
    if (!in_array($limit, $allowed, true)) {
        return 30;
    }
    return $limit;
}

try {
    $user = require_login_json();
    $db = app_db();
    $ownerCheck = $db->prepare("SELECT owner_user_id, questions_json, current_index FROM session_batches WHERE session_code = ? AND deleted_at IS NULL LIMIT 1");
    $ownerCheck->execute([$code]);
    $row = $ownerCheck->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        echo json_encode(["success" => false, "error" => "Session introuvable"]);
        exit;
    }
    if ((int)($row['owner_user_id'] ?? 0) !== (int)$user['id']) {
        http_response_code(403);
        echo json_encode(["success" => false, "error" => "Accès refusé"]);
        exit;
    }

    $questionStartedAtMs = null;
    $currentTimeLimitSec = 30;
    $batch = json_decode((string)($row['questions_json'] ?? '[]'), true);
    if (is_array($batch) && count($batch) > 0) {
        $currentIndex = isset($row['current_index']) ? (int)$row['current_index'] : 0;
        if ($currentIndex < 0) {
            $currentIndex = 0;
        }
        if ($currentIndex >= count($batch)) {
            $currentIndex = count($batch) - 1;
        }
        $currentQuestion = isset($batch[$currentIndex]) && is_array($batch[$currentIndex]) ? $batch[$currentIndex] : [];
        $currentTimeLimitSec = normalize_question_time_limit_set_live($currentQuestion['timeLimitSec'] ?? 30);
    }

    if ($liveActive === 1) {
        $startAt = app_compute_question_start_timestamp();
        $questionStartedAtMs = (int)$startAt['ms'];
        $startedAtSql = (string)$startAt['sql'];
        $stmt = $db->prepare("UPDATE session_batches SET live_active = 1, current_question_started_at = ? WHERE session_code = ?");
        $stmt->execute([$startedAtSql, $code]);
    } else {
        $stmt = $db->prepare("UPDATE session_batches SET live_active = 0, current_question_started_at = NULL WHERE session_code = ?");
        $stmt->execute([$code]);
    }

    echo json_encode([
        "success" => true,
        "code" => $code,
        "liveActive" => $liveActive === 1,
        "questionStartedAtMs" => $questionStartedAtMs,
        "timeLimitSec" => $currentTimeLimitSec,
        "serverNowMs" => (int)round(microtime(true) * 1000)
    ]);
} catch (Throwable $e) {
    app_json_error("Erreur interne.", $e);
}
?>
