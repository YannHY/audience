<?php
require_once __DIR__ . '/lib/bootstrap.php';

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");

if (!isset($_GET['code'])) {
    echo json_encode(["success" => false, "error" => "Le parametre code est requis"]);
    exit;
}

$code = trim((string)$_GET['code']);
$requestedIndex = isset($_GET['questionIndex']) ? (int)$_GET['questionIndex'] : null;
$clientSignature = isset($_GET['signature']) ? trim((string)$_GET['signature']) : '';
$presenceToken = isset($_GET['presenceToken']) ? trim((string)$_GET['presenceToken']) : '';
$participantView = isset($_GET['participantView']) ? trim((string)$_GET['participantView']) : '';
$user = current_user();
$userId = is_array($user) && isset($user['id']) ? (int)$user['id'] : 0;

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

function normalizeParticipantViewFlag($value): bool {
    if (is_string($value)) {
        $normalized = strtolower(trim($value));
        return in_array($normalized, ['1', 'true', 'oui', 'yes', 'participant', 'answer', 'repondant'], true);
    }
    return $value === true || $value === 1;
}

function normalizeQuestionTimeLimit($value): int {
    $limit = is_numeric($value) ? (int)$value : 30;
    $allowed = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];
    if (!in_array($limit, $allowed, true)) {
        return 30;
    }
    return $limit;
}

function isSessionCompleted(array $batch, int $currentIndex, string $startedAtRaw, bool $liveActive): bool {
    if (count($batch) === 0) {
        return false;
    }
    $lastIndex = count($batch) - 1;
    if ($currentIndex < 0) {
        $currentIndex = 0;
    }
    if ($currentIndex > $lastIndex) {
        $currentIndex = $lastIndex;
    }
    if ($currentIndex < $lastIndex) {
        return false;
    }
    if ($startedAtRaw === '') {
        return false;
    }
    $question = isset($batch[$currentIndex]) && is_array($batch[$currentIndex]) ? $batch[$currentIndex] : [];
    $questionType = strtolower(trim((string)($question['type'] ?? 'multiple')));
    if (!$liveActive) {
        return true;
    }
    if ($questionType === 'video') {
        return true;
    }
    $startedTs = strtotime($startedAtRaw);
    if ($startedTs === false) {
        return false;
    }
    return time() >= ($startedTs + normalizeQuestionTimeLimit($question['timeLimitSec'] ?? 30));
}

try {
    $db = app_db();

    $batchStmt = $db->prepare("SELECT questions_json, current_index, current_question_started_at, live_active, owner_user_id, participant_report_enabled, require_participant_name, quiz_title FROM session_batches WHERE session_code = ? AND deleted_at IS NULL");
    $batchStmt->execute([$code]);
    $batchRow = $batchStmt->fetch(PDO::FETCH_ASSOC);

    if ($batchRow) {
        $isOwner = $userId > 0 && (int)($batchRow['owner_user_id'] ?? 0) === $userId;
        $isParticipantView = normalizeParticipantViewFlag($participantView);
        if (!$isOwner) {
            app_touch_session_presence($db, $code, app_presence_viewer_token($presenceToken));
        }
        $batch = json_decode($batchRow['questions_json'], true);
        if (!is_array($batch) || count($batch) === 0) {
            echo json_encode(["success" => false, "error" => "Lot invalide"]);
            exit;
        }

        $currentIndex = (int)$batchRow['current_index'];
        $liveActive = isset($batchRow['live_active']) ? ((int)$batchRow['live_active'] === 1) : false;
        $participantReportEnabled = normalizeParticipantReportEnabled($batchRow['participant_report_enabled'] ?? false);
        $requireParticipantName = ((int)($batchRow['require_participant_name'] ?? 1)) !== 0;
        if ($requestedIndex !== null && $isOwner) {
            $currentIndex = $requestedIndex;
        }
        if ($currentIndex < 0) {
            $currentIndex = 0;
        }
        if ($currentIndex >= count($batch)) {
            $currentIndex = count($batch) - 1;
        }

        $startedAtRaw = trim((string)($batchRow['current_question_started_at'] ?? ''));
        $sessionCompleted = $isParticipantView && $participantReportEnabled && isSessionCompleted($batch, $currentIndex, $startedAtRaw, $liveActive);

        if (!$liveActive) {
            if ($sessionCompleted) {
                echo json_encode([
                    "success" => true,
                    "completed" => true,
                    "participantReportAvailable" => true,
                    "participantReportEnabled" => true,
                    "requireParticipantName" => $requireParticipantName,
                    "quizTitle" => (string)($batchRow['quiz_title'] ?? ''),
                    "questionIndex" => $currentIndex,
                    "totalQuestions" => count($batch)
                ]);
                exit;
            }
            echo json_encode([
                "success" => true,
                "waiting" => true,
                "message" => "Le présentateur n'a pas encore affiché la question. Merci de patienter",
                "participantReportEnabled" => $participantReportEnabled,
                "requireParticipantName" => $requireParticipantName,
                "questionIndex" => $currentIndex,
                "totalQuestions" => count($batch)
            ]);
            exit;
        }

        if ($startedAtRaw === '' && !$isOwner) {
            echo json_encode([
                "success" => true,
                "waiting" => true,
                "message" => "Le vote n'a pas encore commencé. Merci de patienter",
                "participantReportEnabled" => $participantReportEnabled,
                "requireParticipantName" => $requireParticipantName,
                "questionIndex" => $currentIndex,
                "totalQuestions" => count($batch)
            ]);
            exit;
        }

        if ($startedAtRaw === '' && $isOwner) {
            $startAt = app_compute_question_start_timestamp();
            $startedAtRaw = (string)$startAt['sql'];
            $touchStartStmt = $db->prepare("UPDATE session_batches SET current_question_started_at = ? WHERE session_code = ?");
            $touchStartStmt->execute([$startedAtRaw, $code]);
        }
        $questionStartedAtMs = null;
        $startedAtTs = strtotime($startedAtRaw);
        if ($startedAtTs !== false) {
            $questionStartedAtMs = ((int)$startedAtTs) * 1000;
        }
        $serverNowMs = (int)round(microtime(true) * 1000);

        $q = $batch[$currentIndex];
        $questionType = strtolower(trim((string)($q['type'] ?? 'multiple')));
        if ($questionType !== 'open' && $questionType !== 'wordcloud' && $questionType !== 'rating' && $questionType !== 'cloze' && $questionType !== 'video' && $questionType !== 'ranking' && $questionType !== 'labelimage' && $questionType !== 'checkbox') {
            $questionType = 'multiple';
        }
        $timeLimitSec = is_numeric($q['timeLimitSec'] ?? null) ? (int)$q['timeLimitSec'] : 30;
        $allowedTimeLimits = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];
        if (!in_array($timeLimitSec, $allowedTimeLimits, true)) {
            $timeLimitSec = 30;
        }
        $question = (string)($q['question'] ?? '');
        $runId = (string)($q['runId'] ?? '');
        $answers = [];
        $correctIndex = null;
        $correctIndexes = [];
        $maxRating = 5;
        $clozeText = '';
        $youtubeUrl = '';
        $videoStartSec = null;
        $videoEndSec = null;
        $questionImage = '';
        $questionImageZoom = 1.0;
        $legendLabels = [];
        $responseFormat = 'text';
        $participantResponsesVisible = normalizeParticipantResponsesVisibility($q['participantResponsesVisible'] ?? true);

        if ($questionType === 'multiple' || $questionType === 'checkbox') {
            $answers = is_array($q['answers'] ?? null) ? $q['answers'] : ['', ''];
            if (count($answers) < 2) {
                $answers = array_pad($answers, 2, '');
            }
            if ($questionType === 'multiple') {
                $isPollMode = !empty($q['isPollMode']);
                if ($isPollMode || (array_key_exists('correctIndex', $q) && $q['correctIndex'] === null)) {
                    $correctIndex = null;
                } else {
                    $correctIndex = array_key_exists('correctIndex', $q) ? (int)$q['correctIndex'] : 0;
                    if ($correctIndex < 0 || $correctIndex >= count($answers)) {
                        $correctIndex = 0;
                    }
                }
            } else {
                $rawCorrectIndexes = is_array($q['correctIndexes'] ?? null) ? $q['correctIndexes'] : [];
                foreach ($rawCorrectIndexes as $value) {
                    $index = (int)$value;
                    if ($index < 0 || $index >= count($answers)) {
                        continue;
                    }
                    $correctIndexes[] = $index;
                }
                $correctIndexes = array_values(array_unique($correctIndexes));
            }
            $questionImage = (string)($q['questionImage'] ?? '');
            $questionImageZoom = isset($q['questionImageZoom']) && is_numeric($q['questionImageZoom']) ? (float)$q['questionImageZoom'] : 1.0;
        } elseif ($questionType === 'ranking') {
            $answers = is_array($q['answers'] ?? null) ? $q['answers'] : [];
            $normalized = [];
            foreach ($answers as $answer) {
                $value = trim((string)$answer);
                if ($value !== '') {
                    $normalized[] = $value;
                }
            }
            $answers = $normalized;
            if (count($answers) < 2) {
                $answers = [];
            }
        } elseif ($questionType === 'rating') {
            $maxRating = isset($q['maxRating']) ? (int)$q['maxRating'] : 5;
            if ($maxRating < 2 || $maxRating > 10) {
                $maxRating = 5;
            }
        } elseif ($questionType === 'cloze') {
            $clozeText = (string)($q['clozeText'] ?? '');
            $questionImage = (string)($q['questionImage'] ?? '');
            $questionImageZoom = isset($q['questionImageZoom']) && is_numeric($q['questionImageZoom']) ? (float)$q['questionImageZoom'] : 1.0;
        } elseif ($questionType === 'video') {
            $youtubeUrl = (string)($q['youtubeUrl'] ?? '');
            $videoStartSec = is_numeric($q['videoStartSec'] ?? null) ? (int)$q['videoStartSec'] : null;
            $videoEndSec = is_numeric($q['videoEndSec'] ?? null) ? (int)$q['videoEndSec'] : null;
            if ($videoStartSec !== null && $videoStartSec > 43200) {
                $videoStartSec = 43200;
            }
            if ($videoEndSec !== null && $videoEndSec > 43200) {
                $videoEndSec = 43200;
            }
            if ($videoStartSec !== null && $videoStartSec <= 0) {
                $videoStartSec = null;
            }
            if ($videoEndSec !== null && $videoEndSec <= 0) {
                $videoEndSec = null;
            }
            if ($videoStartSec !== null && $videoEndSec !== null && $videoEndSec <= $videoStartSec) {
                $videoEndSec = null;
            }
        } elseif ($questionType === 'labelimage') {
            $questionImage = (string)($q['questionImage'] ?? '');
            $legendLabels = is_array($q['legendLabels'] ?? null) ? $q['legendLabels'] : [];
        } elseif ($questionType === 'open') {
            $questionImage = (string)($q['questionImage'] ?? '');
            $questionImageZoom = isset($q['questionImageZoom']) && is_numeric($q['questionImageZoom']) ? (float)$q['questionImageZoom'] : 1.0;
            $responseFormat = strtolower(trim((string)($q['responseFormat'] ?? 'text'))) === 'math' ? 'math' : 'text';
        }

        if (!is_finite($questionImageZoom) || $questionImageZoom <= 0) {
            $questionImageZoom = 1.0;
        }
        $questionImageZoom = max(0.6, min(2.2, $questionImageZoom));

        $signature = md5($questionType . '|' . $question . '|' . implode('|', $answers) . '|' . (string)($correctIndex ?? '') . '|' . implode(',', $correctIndexes) . '|' . $clozeText . '|' . $youtubeUrl . '|' . (string)($videoStartSec ?? '') . '|' . (string)($videoEndSec ?? '') . '|' . $questionImage . '|' . $questionImageZoom . '|' . json_encode($legendLabels, JSON_UNESCAPED_UNICODE) . '|' . $responseFormat . '|' . ($participantResponsesVisible ? '1' : '0') . '|' . $runId . '|' . $currentIndex . '|' . $timeLimitSec . '|' . $startedAtRaw);

        if ($sessionCompleted) {
            echo json_encode([
                "success" => true,
                "completed" => true,
                "participantReportAvailable" => true,
                "participantReportEnabled" => true,
                "requireParticipantName" => $requireParticipantName,
                "quizTitle" => (string)($batchRow['quiz_title'] ?? ''),
                "questionIndex" => $currentIndex,
                "totalQuestions" => count($batch),
                "signature" => $signature
            ]);
            exit;
        }

        if ($clientSignature !== '' && hash_equals($signature, $clientSignature)) {
            echo json_encode([
                "success" => true,
                "unchanged" => true,
                "questionIndex" => $currentIndex,
                "totalQuestions" => count($batch),
                "participantReportEnabled" => $participantReportEnabled,
                "requireParticipantName" => $requireParticipantName,
                "signature" => $signature,
                "timeLimitSec" => $timeLimitSec,
                "questionStartedAtMs" => $questionStartedAtMs,
                "serverNowMs" => $serverNowMs
            ]);
            exit;
        }

        echo json_encode([
            "success" => true,
            "type" => $questionType,
            "question" => $question,
            "answers" => $answers,
            "correctIndex" => $isOwner ? $correctIndex : null,
            "correctIndexes" => $isOwner ? $correctIndexes : [],
            "maxRating" => $maxRating,
            "clozeText" => $clozeText,
            "youtubeUrl" => $youtubeUrl,
            "videoStartSec" => $videoStartSec,
            "videoEndSec" => $videoEndSec,
            "questionImage" => $questionImage,
            "questionImageZoom" => $questionImageZoom,
            "responseFormat" => $responseFormat,
            "participantResponsesVisible" => $participantResponsesVisible,
            "participantReportEnabled" => $participantReportEnabled,
            "requireParticipantName" => $requireParticipantName,
            "legendLabels" => $legendLabels,
            "timeLimitSec" => $timeLimitSec,
            "questionStartedAtMs" => $questionStartedAtMs,
            "serverNowMs" => $serverNowMs,
            "runId" => $runId,
            "questionIndex" => $currentIndex,
            "totalQuestions" => count($batch),
            "signature" => $signature
        ]);
        exit;
    }

    echo json_encode(["success" => false, "error" => "Question non trouvee"]);
} catch (Throwable $e) {
    app_json_error("Erreur interne.", $e);
}
?>
