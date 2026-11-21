<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
require_once __DIR__ . '/lib/bootstrap.php';

$user = require_login_json();
if (!isset($_GET['code'])) {
    echo json_encode(["success" => false, "error" => "Code requis"]);
    exit;
}

$code = trim((string)$_GET['code']);
$db = app_db();

$stmt = $db->prepare("SELECT quiz_title, participant_report_enabled, require_participant_name, questions_json, current_index, current_question_started_at, live_active, owner_user_id
    FROM session_batches WHERE session_code = ? AND deleted_at IS NULL LIMIT 1");
$stmt->execute([$code]);
$row = $stmt->fetch(PDO::FETCH_ASSOC);

if (!$row) {
    echo json_encode(["success" => false, "error" => "Questionnaire introuvable"]);
    exit;
}

if ((int)($row['owner_user_id'] ?? 0) !== (int)$user['id']) {
    http_response_code(403);
    echo json_encode(["success" => false, "error" => "Accès refusé"]);
    exit;
}

$batch = json_decode((string)$row['questions_json'], true);
if (!is_array($batch)) {
    $batch = [];
}

$currentIndex = (int)($row['current_index'] ?? 0);
if ($currentIndex < 0) {
    $currentIndex = 0;
}
if ($currentIndex >= count($batch) && count($batch) > 0) {
    $currentIndex = count($batch) - 1;
}
$startedAtRaw = trim((string)($row['current_question_started_at'] ?? ''));
$currentQuestionStartedAtMs = null;
if ($startedAtRaw !== '') {
    $startedTs = strtotime($startedAtRaw);
    if ($startedTs !== false) {
        $currentQuestionStartedAtMs = ((int)$startedTs) * 1000;
    }
}
$currentTimeLimitSec = 30;
if (count($batch) > 0 && isset($batch[$currentIndex]) && is_array($batch[$currentIndex])) {
    $limit = is_numeric($batch[$currentIndex]['timeLimitSec'] ?? null) ? (int)$batch[$currentIndex]['timeLimitSec'] : 30;
    $allowed = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];
    if (in_array($limit, $allowed, true)) {
        $currentTimeLimitSec = $limit;
    }
}

echo json_encode([
    "success" => true,
    "code" => $code,
    "quizTitle" => (string)($row['quiz_title'] ?? ''),
    "participantReportEnabled" => ((int)($row['participant_report_enabled'] ?? 0)) === 1,
    "requireParticipantName" => ((int)($row['require_participant_name'] ?? 1)) !== 0,
    "batch" => $batch,
    "currentIndex" => $currentIndex,
    "liveActive" => ((int)$row['live_active']) === 1,
    "currentQuestionStartedAtMs" => $currentQuestionStartedAtMs,
    "currentTimeLimitSec" => $currentTimeLimitSec,
    "serverNowMs" => (int)round(microtime(true) * 1000)
]);
