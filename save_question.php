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

function extractYouTubeVideoId(string $value): string {
    $value = trim($value);
    if ($value === '') {
        return '';
    }

    if (preg_match('/^[a-zA-Z0-9_-]{11}$/', $value) === 1) {
        return $value;
    }

    $parts = parse_url($value);
    if (!is_array($parts) || !isset($parts['host'])) {
        $parts = parse_url('https://' . ltrim($value, '/'));
    }
    if (!is_array($parts)) {
        return '';
    }

    $host = strtolower((string)($parts['host'] ?? ''));
    $host = preg_replace('/^www\./i', '', $host) ?? $host;
    $path = (string)($parts['path'] ?? '');
    $query = (string)($parts['query'] ?? '');

    $isYouTubeHost = $host === 'youtube.com'
        || $host === 'm.youtube.com'
        || $host === 'music.youtube.com'
        || $host === 'youtube-nocookie.com'
        || str_ends_with($host, '.youtube.com')
        || str_ends_with($host, '.youtube-nocookie.com');

    if ($isYouTubeHost) {
        parse_str($query, $params);
        $fromQuery = (string)($params['v'] ?? '');
        if (preg_match('/^[a-zA-Z0-9_-]{11}$/', $fromQuery) === 1) {
            return $fromQuery;
        }
        if (preg_match('~^/(?:embed|shorts|live)/([a-zA-Z0-9_-]{11})~', $path, $m) === 1) {
            return $m[1];
        }
    }

    if ($host === 'youtu.be' && preg_match('~^/([a-zA-Z0-9_-]{11})~', $path, $m) === 1) {
        return $m[1];
    }

    return '';
}

function persistQuestionImage(string $rawValue, string $code): string {
    $raw = trim($rawValue);
    if ($raw === '') {
        return '';
    }
    if (preg_match('~^https?://~i', $raw) === 1) {
        return $raw;
    }
    if (strpos($raw, 'uploads/questions/') === 0) {
        return $raw;
    }
    if (preg_match('~^data:image/(png|jpeg|webp|gif);base64,([a-zA-Z0-9+/=\r\n]+)$~', $raw, $m) !== 1) {
        return '';
    }
    $decoded = base64_decode($m[2], true);
    if ($decoded === false) {
        return '';
    }
    if (strlen($decoded) > (2 * 1024 * 1024)) {
        return '';
    }

    $ext = strtolower((string)$m[1]);
    if ($ext === 'jpeg') {
        $ext = 'jpg';
    }

    $safeCode = preg_replace('/[^a-zA-Z0-9_-]/', '', $code);
    if ($safeCode === '') {
        $safeCode = 'default';
    }
    $baseDir = __DIR__ . '/uploads/questions/' . $safeCode;
    if (!is_dir($baseDir) && !mkdir($baseDir, 0755, true) && !is_dir($baseDir)) {
        return '';
    }

    $hash = sha1($decoded);
    $fileName = $hash . '.' . $ext;
    $targetPath = $baseDir . '/' . $fileName;
    if (!is_file($targetPath)) {
        if (file_put_contents($targetPath, $decoded) === false) {
            return '';
        }
    }

    return 'uploads/questions/' . $safeCode . '/' . $fileName;
}

function normalizeQuestionImage($value, string $code): string {
    $raw = trim((string)$value);
    if ($raw === '') {
        return '';
    }
    if (preg_match('~^https?://~i', $raw) === 1 || strpos($raw, 'uploads/questions/') === 0) {
        return $raw;
    }
    $persisted = persistQuestionImage($raw, $code);
    if ($persisted !== '') {
        return $persisted;
    }
    return '';
}

function normalizeQuestionImageZoom($value): float {
    $zoom = is_numeric($value) ? (float)$value : 1.0;
    if (!is_finite($zoom)) {
        $zoom = 1.0;
    }
    if ($zoom < 0.6) {
        $zoom = 0.6;
    }
    if ($zoom > 2.2) {
        $zoom = 2.2;
    }
    return round($zoom, 2);
}

function normalizeQuestionTimeLimit($value): int {
    $limit = is_numeric($value) ? (int)$value : 30;
    $allowed = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];
    if (!in_array($limit, $allowed, true)) {
        return 30;
    }
    return $limit;
}

function normalizeVideoBoundarySec($value): ?int {
    if ($value === null) {
        return null;
    }
    if (is_string($value) && trim($value) === '') {
        return null;
    }
    if (!is_numeric($value)) {
        return null;
    }
    $seconds = (int)$value;
    if ($seconds < 0) {
        return null;
    }
    if ($seconds > 43200) {
        $seconds = 43200;
    }
    if ($seconds <= 0) {
        return null;
    }
    return $seconds;
}

function normalizeQuestionRichText($value): string {
    $raw = str_replace(["\r\n", "\r"], "\n", trim((string)$value));
    if ($raw === '') {
        return '';
    }

    if (strpos($raw, '<') === false) {
        return nl2br(htmlspecialchars($raw, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'), false);
    }

    $withoutScripts = preg_replace('~<(script|style)\b[^>]*>.*?</\1>~is', '', $raw);
    $allowed = strip_tags((string)$withoutScripts, '<strong><b><em><i><u><ol><ul><li><p><br>');
    $normalized = preg_replace_callback(
        '~<(\/?)(strong|b|em|i|u|ol|ul|li|p|br)\b[^>]*>~i',
        static function (array $matches): string {
            $closing = $matches[1] === '/' ? '/' : '';
            $tag = strtolower($matches[2]);
            if ($tag === 'b') {
                $tag = 'strong';
            } elseif ($tag === 'i') {
                $tag = 'em';
            }
            if ($tag === 'br') {
                return '<br>';
            }
            return sprintf('<%s%s>', $closing, $tag);
        },
        (string)$allowed
    );

    $clean = preg_replace('~<(?!/?(?:strong|em|u|ol|ul|li|p|br)\b)[^>]+>~i', '', (string)$normalized);
    $clean = preg_replace('~(?:<br>\s*){3,}~i', '<br><br>', (string)$clean);
    return trim((string)$clean);
}

function extractQuestionPlainText(string $value): string {
    $withBreaks = preg_replace('~<br\s*/?>~i', "\n", $value);
    $withoutTags = strip_tags((string)$withBreaks);
    $decoded = html_entity_decode($withoutTags, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    $normalizedWhitespace = preg_replace('/[ \t\x{00A0}]+/u', ' ', $decoded);
    $normalizedLines = preg_replace("/\n{3,}/", "\n\n", (string)$normalizedWhitespace);
    return trim((string)$normalizedLines);
}

function normalizeOpenResponseFormat($value): string {
    return strtolower(trim((string)$value)) === 'math' ? 'math' : 'text';
}

function normalizeParticipantResponsesVisibility($value): bool {
    if (is_string($value)) {
        $normalized = strtolower(trim($value));
        if (in_array($normalized, ['false', '0', 'non', 'no', 'masquer', 'masquées', 'masquees', 'cacher', 'cachées', 'cachees'], true)) {
            return false;
        }
        if (in_array($normalized, ['true', '1', 'oui', 'yes', 'afficher', 'visibles'], true)) {
            return true;
        }
    }
    return $value !== false;
}

function normalizeParticipantReportEnabled($value): bool {
    if (is_string($value)) {
        $normalized = strtolower(trim($value));
        if (in_array($normalized, ['false', '0', 'non', 'no', 'off', 'disabled', 'desactive', 'desactivee', 'désactivé', 'désactivée'], true)) {
            return false;
        }
        if (in_array($normalized, ['true', '1', 'oui', 'yes', 'on', 'active', 'activee', 'activé', 'activée'], true)) {
            return true;
        }
    }
    return $value === true || $value === 1 || $value === '1';
}

function normalizeLegendLabels($raw): array {
    if (!is_array($raw)) {
        return [];
    }
    $labels = [];
    foreach ($raw as $index => $entry) {
        if (!is_array($entry)) {
            continue;
        }
        $text = trim((string)($entry['text'] ?? ''));
        if ($text === '') {
            continue;
        }
        $id = preg_replace('/[^a-zA-Z0-9_-]/', '', (string)($entry['id'] ?? ''));
        if ($id === '') {
            $id = 'lbl' . ($index + 1);
        }
        $x = isset($entry['x']) && is_numeric($entry['x']) ? (float)$entry['x'] : null;
        $y = isset($entry['y']) && is_numeric($entry['y']) ? (float)$entry['y'] : null;
        if ($x === null || $y === null) {
            continue;
        }
        $labels[] = [
            'id' => $id,
            'text' => $text,
            'x' => max(0, min(100, $x)),
            'y' => max(0, min(100, $y))
        ];
    }
    return $labels;
}

function normalizeBatch(array $input, string $code): array {
    $rawBatch = [];

    if (isset($input['batch']) && is_array($input['batch'])) {
        $rawBatch = $input['batch'];
    } elseif (isset($input['questions']) && is_array($input['questions'])) {
        $rawBatch = $input['questions'];
    } elseif (isset($input['question']) && isset($input['answers']) && is_array($input['answers'])) {
        $rawBatch = [[
            'question' => $input['question'],
            'answers' => $input['answers'],
            'correctIndex' => $input['correctIndex'] ?? 0,
            'questionImage' => $input['questionImage'] ?? ''
        ]];
    }

    $batch = [];
    foreach ($rawBatch as $item) {
        if (!is_array($item)) {
            continue;
        }

        $questionType = strtolower(trim((string)($item['type'] ?? 'multiple')));
        if ($questionType !== 'open' && $questionType !== 'wordcloud' && $questionType !== 'rating' && $questionType !== 'cloze' && $questionType !== 'video' && $questionType !== 'ranking' && $questionType !== 'labelimage' && $questionType !== 'checkbox') {
            $questionType = 'multiple';
        }
        $timeLimitSec = normalizeQuestionTimeLimit($item['timeLimitSec'] ?? 30);

        $question = normalizeQuestionRichText($item['question'] ?? '');
        $responseFormat = normalizeOpenResponseFormat($item['responseFormat'] ?? 'text');
        $participantResponsesVisible = normalizeParticipantResponsesVisibility($item['participantResponsesVisible'] ?? true);
        $runId = trim((string)($item['runId'] ?? ''));
        if ($runId !== '') {
            $runId = preg_replace('/[^a-zA-Z0-9_-]/', '', $runId) ?? '';
        }
        $questionImage = normalizeQuestionImage($item['questionImage'] ?? '', $code);
        $questionImageZoom = normalizeQuestionImageZoom($item['questionImageZoom'] ?? 1);
        if (extractQuestionPlainText($question) === '') {
            continue;
        }

        if ($questionType === 'open' || $questionType === 'wordcloud' || $questionType === 'cloze') {
            $clozeText = trim((string)($item['clozeText'] ?? ''));
            if ($questionType === 'cloze' && $clozeText === '') {
                continue;
            }
            $batch[] = [
                'type' => $questionType,
                'question' => $question,
                'answers' => [],
                'correctIndex' => null,
                'clozeText' => $questionType === 'cloze' ? $clozeText : '',
                'responseFormat' => $questionType === 'open' ? $responseFormat : 'text',
                'participantResponsesVisible' => $participantResponsesVisible,
                'questionImage' => ($questionType === 'open' || $questionType === 'cloze') ? $questionImage : '',
                'questionImageZoom' => ($questionType === 'open' || $questionType === 'cloze') ? $questionImageZoom : 1,
                'timeLimitSec' => $timeLimitSec,
                'runId' => $runId
            ];
            continue;
        }

        if ($questionType === 'video') {
            $youtubeUrl = trim((string)($item['youtubeUrl'] ?? ''));
            if (extractYouTubeVideoId($youtubeUrl) === '') {
                continue;
            }
            $videoStartSec = normalizeVideoBoundarySec($item['videoStartSec'] ?? null);
            $videoEndSec = normalizeVideoBoundarySec($item['videoEndSec'] ?? null);
            if ($videoStartSec !== null && $videoEndSec !== null && $videoEndSec <= $videoStartSec) {
                $videoEndSec = null;
            }
            $batch[] = [
                'type' => 'video',
                'question' => $question,
                'answers' => [],
                'correctIndex' => null,
                'youtubeUrl' => $youtubeUrl,
                'videoStartSec' => $videoStartSec,
                'videoEndSec' => $videoEndSec,
                'participantResponsesVisible' => true,
                'timeLimitSec' => $timeLimitSec,
                'runId' => $runId
            ];
            continue;
        }

        if ($questionType === 'rating') {
            $batch[] = [
                'type' => 'rating',
                'question' => $question,
                'answers' => [],
                'correctIndex' => null,
                'maxRating' => 5,
                'participantResponsesVisible' => $participantResponsesVisible,
                'timeLimitSec' => $timeLimitSec,
                'runId' => $runId
            ];
            continue;
        }

        if ($questionType === 'ranking') {
            $answers = is_array($item['answers'] ?? null) ? $item['answers'] : [];
            $normalized = [];
            foreach ($answers as $answer) {
                $value = trim((string)$answer);
                if ($value !== '') {
                    $normalized[] = $value;
                }
            }
            $normalized = array_values(array_unique($normalized));
            if (count($normalized) < 2) {
                continue;
            }
            $batch[] = [
                'type' => 'ranking',
                'question' => $question,
                'answers' => $normalized,
                'correctIndex' => null,
                'participantResponsesVisible' => $participantResponsesVisible,
                'timeLimitSec' => $timeLimitSec,
                'runId' => $runId
            ];
            continue;
        }

        if ($questionType === 'labelimage') {
            $legendLabels = normalizeLegendLabels($item['legendLabels'] ?? []);
            if ($questionImage === '' || count($legendLabels) < 1) {
                continue;
            }
            $batch[] = [
                'type' => 'labelimage',
                'question' => $question,
                'answers' => [],
                'correctIndex' => null,
                'questionImage' => $questionImage,
                'questionImageZoom' => 1,
                'legendLabels' => $legendLabels,
                'participantResponsesVisible' => $participantResponsesVisible,
                'timeLimitSec' => $timeLimitSec,
                'runId' => $runId
            ];
            continue;
        }

        $answers = is_array($item['answers'] ?? null) ? $item['answers'] : [];
        $normalizedAnswers = [];
        foreach ($answers as $answer) {
            $value = trim((string)$answer);
            if ($value !== '') {
                $normalizedAnswers[] = $value;
            }
        }
        if (count($normalizedAnswers) < 2) {
            continue;
        }

        if ($questionType === 'checkbox') {
            $rawCorrectIndexes = is_array($item['correctIndexes'] ?? null) ? $item['correctIndexes'] : [];
            $correctIndexes = [];
            foreach ($rawCorrectIndexes as $value) {
                $index = (int)$value;
                if ($index < 0 || $index >= count($normalizedAnswers)) {
                    continue;
                }
                $correctIndexes[] = $index;
            }
            $correctIndexes = array_values(array_unique($correctIndexes));
            if (count($correctIndexes) === 0 && isset($item['correctIndex']) && is_numeric($item['correctIndex'])) {
                $fallbackIndex = (int)$item['correctIndex'];
                if ($fallbackIndex >= 0 && $fallbackIndex < count($normalizedAnswers)) {
                    $correctIndexes = [$fallbackIndex];
                }
            }
            $batch[] = [
                'type' => 'checkbox',
                'question' => $question,
                'answers' => $normalizedAnswers,
                'correctIndex' => null,
                'correctIndexes' => $correctIndexes,
                'participantResponsesVisible' => $participantResponsesVisible,
                'questionImage' => $questionImage,
                'questionImageZoom' => $questionImageZoom,
                'timeLimitSec' => $timeLimitSec,
                'runId' => $runId
            ];
            continue;
        }

        $isPollMode = !empty($item['isPollMode']);
        if ($isPollMode) {
            $correct = null;
        } else {
            $correct = (int)($item['correctIndex'] ?? 0);
            if ($correct < 0 || $correct >= count($normalizedAnswers)) {
                $correct = 0;
            }
        }

        $batch[] = [
            'type' => 'multiple',
            'question' => $question,
            'answers' => $normalizedAnswers,
            'isPollMode' => $isPollMode,
            'correctIndex' => $correct,
            'participantResponsesVisible' => $participantResponsesVisible,
            'questionImage' => $questionImage,
            'questionImageZoom' => $questionImageZoom,
            'timeLimitSec' => $timeLimitSec,
            'runId' => $runId
        ];
    }

    return $batch;
}

try {
    $user = require_login_json();
    $userId = (int)$user['id'];
    $db = app_db();

    $code = trim((string)$input['code']);
    if ($code === '') {
        echo json_encode(["success" => false, "error" => "Code de session manquant"]);
        exit;
    }
    $draftMode = isset($input['draftMode']) ? (bool)$input['draftMode'] : false;
    $batch = normalizeBatch($input, $code);
    if (count($batch) === 0 && !$draftMode) {
        echo json_encode(["success" => false, "error" => "Aucune question valide"]);
        exit;
    }

    $quizTitle = trim((string)($input['quizTitle'] ?? ''));
    $participantReportEnabledProvided = array_key_exists('participantReportEnabled', $input);
    $participantReportEnabled = normalizeParticipantReportEnabled($input['participantReportEnabled'] ?? false);
    $requireParticipantNameProvided = array_key_exists('requireParticipantName', $input);
    $requireParticipantName = isset($input['requireParticipantName']) ? (bool)$input['requireParticipantName'] : true;
    $requestedIndex = isset($input['currentIndex']) ? (int)$input['currentIndex'] : 0;
    $liveActive = isset($input['liveActive']) ? (((int)(bool)$input['liveActive']) ? 1 : 0) : 1;
    $resetAllResponses = isset($input['resetAllResponses']) ? (bool)$input['resetAllResponses'] : false;
    if ($quizTitle === '') {
        $quizTitle = 'Questionnaire sans titre';
    }
    if ($requestedIndex < 0) {
        $requestedIndex = 0;
    }
    if (count($batch) === 0) {
        $requestedIndex = 0;
    } elseif ($requestedIndex >= count($batch)) {
        $requestedIndex = count($batch) - 1;
    }

    $db->beginTransaction();

    $existingStmt = $db->prepare("SELECT owner_user_id, deleted_at, participant_report_enabled, require_participant_name, questions_json, current_index, live_active, current_question_started_at FROM session_batches WHERE session_code = ? FOR UPDATE");
    $existingStmt->execute([$code]);
    $existing = $existingStmt->fetch(PDO::FETCH_ASSOC);
    if ($existing && (int)($existing['owner_user_id'] ?? 0) !== $userId) {
        throw new RuntimeException("Ce code est déjà utilisé par un autre utilisateur.");
    }
    if (!$participantReportEnabledProvided && $existing) {
        $participantReportEnabled = normalizeParticipantReportEnabled($existing['participant_report_enabled'] ?? false);
    }
    if (!$requireParticipantNameProvided && $existing) {
        $requireParticipantName = ((int)($existing['require_participant_name'] ?? 1)) !== 0;
    }

    $persistedBatch = $batch;
    $persistedIndex = $requestedIndex;
    $persistedLiveActive = $liveActive;
    $persistedQuestionStartedAt = null;
    $questionStartedAtMs = null;

    if ($draftMode && count($batch) === 0 && $existing) {
        $existingBatch = json_decode((string)($existing['questions_json'] ?? '[]'), true);
        if (!is_array($existingBatch)) {
            $existingBatch = [];
        }
        $persistedBatch = $existingBatch;
        $persistedIndex = isset($existing['current_index']) ? (int)$existing['current_index'] : 0;
        $persistedLiveActive = isset($existing['live_active']) ? (int)$existing['live_active'] : 0;
        $persistedQuestionStartedAt = isset($existing['current_question_started_at']) && (string)$existing['current_question_started_at'] !== ''
            ? (string)$existing['current_question_started_at']
            : null;
    } elseif ($draftMode && $existing) {
        $persistedQuestionStartedAt = isset($existing['current_question_started_at']) && (string)$existing['current_question_started_at'] !== ''
            ? (string)$existing['current_question_started_at']
            : null;
    } elseif (!$draftMode && count($batch) > 0 && $persistedLiveActive === 1) {
        $startAt = app_compute_question_start_timestamp();
        $questionStartedAtMs = (int)$startAt['ms'];
        $persistedQuestionStartedAt = (string)$startAt['sql'];
    }

    if ($existing) {
        $updateBatch = $db->prepare("UPDATE session_batches
            SET quiz_title = ?, participant_report_enabled = ?, require_participant_name = ?, questions_json = ?, current_index = ?, current_question_started_at = ?, live_active = ?, owner_user_id = ?, deleted_at = NULL
            WHERE session_code = ?");
        $updateBatch->execute([$quizTitle, $participantReportEnabled ? 1 : 0, $requireParticipantName ? 1 : 0, json_encode($persistedBatch, JSON_UNESCAPED_UNICODE), $persistedIndex, $persistedQuestionStartedAt, $persistedLiveActive, $userId, $code]);
    } else {
        $insertBatch = $db->prepare("INSERT INTO session_batches (session_code, owner_user_id, quiz_title, participant_report_enabled, require_participant_name, questions_json, current_index, current_question_started_at, live_active)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $insertBatch->execute([$code, $userId, $quizTitle, $participantReportEnabled ? 1 : 0, $requireParticipantName ? 1 : 0, json_encode($persistedBatch, JSON_UNESCAPED_UNICODE), $persistedIndex, $persistedQuestionStartedAt, $persistedLiveActive]);
    }

    if (!$draftMode && count($batch) > 0 && $resetAllResponses) {
        $resetAll = $db->prepare("DELETE FROM session_responses WHERE session_code = ?");
        $resetAll->execute([$code]);
        $resetOpenAll = $db->prepare("DELETE FROM session_open_responses WHERE session_code = ?");
        $resetOpenAll->execute([$code]);
        $resetDetailsAll = $db->prepare("DELETE FROM session_response_details WHERE session_code = ?");
        $resetDetailsAll->execute([$code]);
        $resetLocksAll = $db->prepare("DELETE FROM session_vote_locks WHERE session_code = ?");
        $resetLocksAll->execute([$code]);
    }

    $db->commit();

    if ($questionStartedAtMs === null && $persistedQuestionStartedAt !== null && $persistedQuestionStartedAt !== '') {
        $startedTs = strtotime($persistedQuestionStartedAt);
        if ($startedTs !== false) {
            $questionStartedAtMs = ((int)$startedTs) * 1000;
        }
    }
    $currentTimeLimitSec = 30;
    if (count($persistedBatch) > 0 && isset($persistedBatch[$persistedIndex]) && is_array($persistedBatch[$persistedIndex])) {
        $currentTimeLimitSec = normalizeQuestionTimeLimit($persistedBatch[$persistedIndex]['timeLimitSec'] ?? 30);
    }

    echo json_encode([
        "success" => true,
        "quizTitle" => $quizTitle,
        "participantReportEnabled" => $participantReportEnabled,
        "requireParticipantName" => $requireParticipantName,
        "questionIndex" => $persistedIndex,
        "totalQuestions" => count($persistedBatch),
        "timeLimitSec" => $currentTimeLimitSec,
        "questionStartedAtMs" => $questionStartedAtMs,
        "serverNowMs" => (int)round(microtime(true) * 1000)
    ]);
} catch (Throwable $e) {
    if (isset($db) && $db->inTransaction()) {
        $db->rollBack();
    }
    if ($e instanceof RuntimeException) {
        echo json_encode(["success" => false, "error" => $e->getMessage()]);
        exit;
    }
    app_json_error("Erreur interne.", $e);
}
?>
