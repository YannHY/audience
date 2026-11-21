<?php
declare(strict_types=1);
require_once __DIR__ . '/lib/bootstrap.php';

header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(["success" => false, "message" => "Methode non autorisee"]);
    exit;
}

require_same_origin_post(true);

$inputJSON = file_get_contents('php://input');
$input = json_decode($inputJSON, true);

if (json_last_error() !== JSON_ERROR_NONE) {
    echo json_encode(["success" => false, "message" => "JSON invalide"]);
    exit;
}

if (!isset($input['code'])) {
    echo json_encode(["success" => false, "message" => "Parametres manquants"]);
    exit;
}

$code = trim((string)$input['code']);
$participantName = sanitize_participant_name((string)($input['participantName'] ?? ''));

function normalized_question_run_id(array $question): string {
    $runId = trim((string)($question['runId'] ?? ''));
    if ($runId === '') {
        return '';
    }
    $runId = preg_replace('/[^a-zA-Z0-9_-]/', '', $runId) ?? '';
    return substr($runId, 0, 80);
}

function normalized_vote_token(array $input): string {
    $token = trim((string)($input['voteToken'] ?? ''));
    if ($token === '') {
        return '';
    }
    $token = preg_replace('/[^a-zA-Z0-9_-]/', '', $token) ?? '';
    return substr($token, 0, 120);
}

function build_voter_hash(array $input): string {
    $sessionId = trim(session_id());
    if ($sessionId !== '') {
        return hash('sha256', 'sess:' . $sessionId);
    }

    $voteToken = normalized_vote_token($input);
    if ($voteToken !== '') {
        return hash('sha256', 'tok:' . $voteToken);
    }

    $userAgent = substr(trim((string)($_SERVER['HTTP_USER_AGENT'] ?? '')), 0, 255);
    return hash('sha256', 'net:' . app_client_ip() . '|' . $userAgent);
}

function normalize_response_time_limit($value): int {
    $limit = is_numeric($value) ? (int)$value : 30;
    $allowed = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];
    if (!in_array($limit, $allowed, true)) {
        return 30;
    }
    return $limit;
}

function normalize_open_response_format($value): string {
    return strtolower(trim((string)$value)) === 'math' ? 'math' : 'text';
}

function normalize_response_export_text(string $value): string {
    $normalized = str_ireplace(['<br>', '<br/>', '<br />'], "\n", $value);
    $normalized = strip_tags($normalized);
    $normalized = html_entity_decode($normalized, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    $normalized = preg_replace('/\s+/u', ' ', trim($normalized)) ?? '';
    return mb_substr($normalized, 0, 4000, 'UTF-8');
}

function response_choice_label(array $answers, int $index): string {
    $label = '';
    if (array_key_exists($index, $answers)) {
        $label = normalize_response_export_text((string)$answers[$index]);
    }
    if ($label !== '') {
        return $label;
    }
    return 'Choix ' . ($index + 1);
}

function format_response_percent(float $value): string {
    $formatted = number_format($value, 1, '.', '');
    return rtrim(rtrim($formatted, '0'), '.');
}

function save_response_detail(PDO $db, string $code, int $questionIndex, string $runId, string $voterHash, string $participantName, string $responseText, $responsePayload = null): void {
    $payloadJson = null;
    if (is_array($responsePayload)) {
        $encoded = json_encode($responsePayload, JSON_UNESCAPED_UNICODE);
        if (is_string($encoded) && $encoded !== '') {
            $payloadJson = $encoded;
        }
    } elseif (is_string($responsePayload) && trim($responsePayload) !== '') {
        $payloadJson = trim($responsePayload);
    }

    $stmt = $db->prepare("INSERT INTO session_response_details (session_code, question_index, run_id, voter_hash, participant_name, response_text, response_payload)
        VALUES (?, ?, ?, ?, ?, ?, ?)");
    $stmt->execute([$code, $questionIndex, $runId, $voterHash, $participantName, $responseText, $payloadJson]);
}

function acquire_vote_lock(PDO $db, string $code, int $questionIndex, string $runId, string $voterHash): bool {
    $stmt = $db->prepare("INSERT INTO session_vote_locks (session_code, question_index, run_id, voter_hash) VALUES (?, ?, ?, ?)");
    try {
        $stmt->execute([$code, $questionIndex, $runId, $voterHash]);
        return true;
    } catch (PDOException $e) {
        $errorInfo = $e->errorInfo;
        if (is_array($errorInfo) && (int)($errorInfo[1] ?? 0) === 1062) {
            return false;
        }
        throw $e;
    }
}

function with_vote_lock(PDO $db, string $code, int $questionIndex, string $runId, string $voterHash, string $questionType, callable $writer): void {
    $db->beginTransaction();
    try {
        if (!acquire_vote_lock($db, $code, $questionIndex, $runId, $voterHash)) {
            $db->rollBack();
            echo json_encode([
                "success" => true,
                "duplicate" => true,
                "message" => "Réponse déjà enregistrée pour cette question.",
                "questionIndex" => $questionIndex,
                "questionType" => $questionType
            ]);
            exit;
        }
        $writer();
        $db->commit();
    } catch (Throwable $e) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        throw $e;
    }
}

try {
    $db = app_db();

    $batchStmt = $db->prepare("SELECT questions_json, current_index, current_question_started_at, live_active, require_participant_name FROM session_batches WHERE session_code = ? AND deleted_at IS NULL");
    $batchStmt->execute([$code]);
    $batchRow = $batchStmt->fetch(PDO::FETCH_ASSOC);

    if ($batchRow) {
        $requireParticipantName = ((int)($batchRow['require_participant_name'] ?? 1)) !== 0;
        if ($participantName === '' && $requireParticipantName) {
            echo json_encode(["success" => false, "message" => "Nom du participant manquant"]);
            exit;
        }

        if ((int)($batchRow['live_active'] ?? 0) !== 1) {
            echo json_encode(["success" => false, "message" => "La session n'est pas encore ouverte. Merci de patienter"]);
            exit;
        }

        $batch = json_decode($batchRow['questions_json'], true);
        if (!is_array($batch) || count($batch) === 0) {
            echo json_encode(["success" => false, "message" => "Lot invalide"]);
            exit;
        }

        $questionIndex = (int)$batchRow['current_index'];
        if ($questionIndex < 0) { $questionIndex = 0; }
        if ($questionIndex >= count($batch)) { $questionIndex = count($batch) - 1; }

        $question = $batch[$questionIndex] ?? [];
        $questionType = strtolower(trim((string)($question['type'] ?? 'multiple')));
        if ($questionType !== 'open' && $questionType !== 'wordcloud' && $questionType !== 'rating' && $questionType !== 'cloze' && $questionType !== 'video' && $questionType !== 'ranking' && $questionType !== 'labelimage' && $questionType !== 'checkbox') {
            $questionType = 'multiple';
        }
        $timeLimitSec = normalize_response_time_limit($question['timeLimitSec'] ?? 30);
        $startedAtRaw = trim((string)($batchRow['current_question_started_at'] ?? ''));
        $isTimeExpired = false;
        $isQuestionNotStarted = false;
        if ($startedAtRaw === '') {
            $isQuestionNotStarted = true;
        } else {
            $startedTs = strtotime($startedAtRaw);
            if ($startedTs !== false) {
                $nowTs = time();
                $isQuestionNotStarted = $nowTs < $startedTs;
                $isTimeExpired = $nowTs >= ($startedTs + $timeLimitSec);
            }
        }
        $runId = normalized_question_run_id($question);
        $voterHash = build_voter_hash($input);

        if ($questionType === 'video') {
            echo json_encode([
                "success" => false,
                "message" => "Cette question vidéo ne demande pas de réponse.",
                "questionIndex" => $questionIndex,
                "questionType" => "video"
            ]);
            exit;
        }

        if ($isTimeExpired) {
            echo json_encode([
                "success" => false,
                "timeExpired" => true,
                "message" => "Temps écoulé pour cette question.",
                "questionIndex" => $questionIndex,
                "questionType" => $questionType
            ]);
            exit;
        }

        if ($isQuestionNotStarted) {
            echo json_encode([
                "success" => false,
                "timeNotStarted" => true,
                "message" => "Le vote n'a pas encore commencé.",
                "questionIndex" => $questionIndex,
                "questionType" => $questionType
            ]);
            exit;
        }

        if ($questionType === 'open' || $questionType === 'wordcloud' || $questionType === 'cloze') {
            $responseFormat = $questionType === 'open'
                ? normalize_open_response_format($question['responseFormat'] ?? 'text')
                : 'text';
            $openText = $responseFormat === 'math'
                ? trim((string)($input['openMathLatex'] ?? ''))
                : trim((string)($input['openText'] ?? ''));
            if ($openText === '') {
                echo json_encode(["success" => false, "message" => "Reponse ouverte manquante"]);
                exit;
            }
            if ($responseFormat === 'math') {
                $openText = '\\(' . $openText . '\\)';
            }

            $detailText = normalize_response_export_text($openText);

            with_vote_lock($db, $code, $questionIndex, $runId, $voterHash, $questionType, function() use ($db, $code, $questionIndex, $openText, $questionType, $responseFormat, $runId, $voterHash, $participantName, $detailText): void {
                $stmt = $db->prepare("INSERT INTO session_open_responses (session_code, question_index, response_text) VALUES (?, ?, ?)");
                $stmt->execute([$code, $questionIndex, $openText]);
                save_response_detail($db, $code, $questionIndex, $runId, $voterHash, $participantName, $detailText, [
                    'type' => $questionType,
                    'openText' => $detailText,
                    'responseFormat' => $responseFormat
                ]);
            });

            echo json_encode([
                "success" => true,
                "message" => "Reponse ouverte enregistree",
                "questionIndex" => $questionIndex,
                "questionType" => $questionType
            ]);
            exit;
        }

        if ($questionType === 'ranking') {
            $rankingOrder = $input['rankingOrder'] ?? null;
            if (!is_array($rankingOrder)) {
                echo json_encode(["success" => false, "message" => "Classement manquant"]);
                exit;
            }

            $expected = is_array($question['answers'] ?? null) ? $question['answers'] : [];
            $expected = array_values(array_filter(array_map(function($value) {
                return trim((string)$value);
            }, $expected), function($value) {
                return $value !== '';
            }));
            $received = array_values(array_filter(array_map(function($value) {
                return trim((string)$value);
            }, $rankingOrder), function($value) {
                return $value !== '';
            }));

            if (count($expected) < 2 || count($received) !== count($expected)) {
                echo json_encode(["success" => false, "message" => "Classement invalide"]);
                exit;
            }

            $expectedSorted = $expected;
            $receivedSorted = $received;
            sort($expectedSorted);
            sort($receivedSorted);
            if ($expectedSorted !== $receivedSorted) {
                echo json_encode(["success" => false, "message" => "Classement invalide"]);
                exit;
            }

            $encoded = json_encode($received, JSON_UNESCAPED_UNICODE);
            if (!is_string($encoded) || $encoded === '') {
                echo json_encode(["success" => false, "message" => "Classement invalide"]);
                exit;
            }

            $detailText = normalize_response_export_text(implode(' -> ', $received));

            with_vote_lock($db, $code, $questionIndex, $runId, $voterHash, 'ranking', function() use ($db, $code, $questionIndex, $encoded, $received, $runId, $voterHash, $participantName, $detailText): void {
                $stmt = $db->prepare("INSERT INTO session_open_responses (session_code, question_index, response_text) VALUES (?, ?, ?)");
                $stmt->execute([$code, $questionIndex, $encoded]);
                save_response_detail($db, $code, $questionIndex, $runId, $voterHash, $participantName, $detailText, [
                    'type' => 'ranking',
                    'rankingOrder' => array_values($received)
                ]);
            });

            echo json_encode([
                "success" => true,
                "message" => "Classement enregistre",
                "questionIndex" => $questionIndex,
                "questionType" => "ranking"
            ]);
            exit;
        }

        if ($questionType === 'labelimage') {
            $legendPlacements = $input['legendPlacements'] ?? null;
            if (!is_array($legendPlacements)) {
                echo json_encode(["success" => false, "message" => "Placements manquants"]);
                exit;
            }

            $expectedRaw = is_array($question['legendLabels'] ?? null) ? $question['legendLabels'] : [];
            $expected = [];
            foreach ($expectedRaw as $entry) {
                if (!is_array($entry)) {
                    continue;
                }
                $id = preg_replace('/[^a-zA-Z0-9_-]/', '', (string)($entry['id'] ?? ''));
                $text = trim((string)($entry['text'] ?? ''));
                if ($id === '' || $text === '') {
                    continue;
                }
                $expected[$id] = $text;
            }
            if (count($expected) < 1) {
                echo json_encode(["success" => false, "message" => "Question invalide"]);
                exit;
            }

            $normalized = [];
            foreach ($legendPlacements as $entry) {
                if (!is_array($entry)) {
                    continue;
                }
                $id = preg_replace('/[^a-zA-Z0-9_-]/', '', (string)($entry['id'] ?? ''));
                if ($id === '' || !array_key_exists($id, $expected)) {
                    continue;
                }
                $x = isset($entry['x']) && is_numeric($entry['x']) ? (float)$entry['x'] : null;
                $y = isset($entry['y']) && is_numeric($entry['y']) ? (float)$entry['y'] : null;
                if ($x === null || $y === null) {
                    continue;
                }
                $normalized[$id] = [
                    'id' => $id,
                    'x' => max(0, min(100, $x)),
                    'y' => max(0, min(100, $y))
                ];
            }

            if (count($normalized) !== count($expected)) {
                echo json_encode(["success" => false, "message" => "Placements incomplets"]);
                exit;
            }

            $payloadText = json_encode([
                'legendPlacements' => array_values($normalized)
            ], JSON_UNESCAPED_UNICODE);
            if (!is_string($payloadText) || $payloadText === '') {
                echo json_encode(["success" => false, "message" => "Placements invalides"]);
                exit;
            }

            $detailParts = [];
            foreach (array_values($normalized) as $placement) {
                $labelText = normalize_response_export_text((string)($expected[$placement['id']] ?? $placement['id']));
                $detailParts[] = sprintf(
                    '%s (%s%%, %s%%)',
                    $labelText !== '' ? $labelText : (string)$placement['id'],
                    format_response_percent((float)$placement['x']),
                    format_response_percent((float)$placement['y'])
                );
            }
            $detailText = implode(' | ', $detailParts);

            with_vote_lock($db, $code, $questionIndex, $runId, $voterHash, 'labelimage', function() use ($db, $code, $questionIndex, $payloadText, $normalized, $runId, $voterHash, $participantName, $detailText): void {
                $stmt = $db->prepare("INSERT INTO session_open_responses (session_code, question_index, response_text) VALUES (?, ?, ?)");
                $stmt->execute([$code, $questionIndex, $payloadText]);
                save_response_detail($db, $code, $questionIndex, $runId, $voterHash, $participantName, $detailText, [
                    'type' => 'labelimage',
                    'legendPlacements' => array_values($normalized)
                ]);
            });

            echo json_encode([
                "success" => true,
                "message" => "Réponse enregistrée",
                "questionIndex" => $questionIndex,
                "questionType" => "labelimage"
            ]);
            exit;
        }

        if ($questionType === 'rating') {
            $ratingValue = isset($input['ratingValue']) ? (int)$input['ratingValue'] : 0;
            $maxRating = isset($question['maxRating']) ? (int)$question['maxRating'] : 5;
            if ($maxRating < 2 || $maxRating > 10) {
                $maxRating = 5;
            }
            if ($ratingValue < 1 || $ratingValue > $maxRating) {
                echo json_encode(["success" => false, "message" => "Note invalide"]);
                exit;
            }

            $detailText = $ratingValue . '/' . $maxRating;

            with_vote_lock($db, $code, $questionIndex, $runId, $voterHash, 'rating', function() use ($db, $code, $questionIndex, $ratingValue, $maxRating, $runId, $voterHash, $participantName, $detailText): void {
                $stmt = $db->prepare("INSERT INTO session_responses (session_code, question_index, answer_index, count)
                    VALUES (?, ?, ?, 1)
                    ON DUPLICATE KEY UPDATE count = count + 1");
                $stmt->execute([$code, $questionIndex, $ratingValue]);
                save_response_detail($db, $code, $questionIndex, $runId, $voterHash, $participantName, $detailText, [
                    'type' => 'rating',
                    'ratingValue' => $ratingValue,
                    'maxRating' => $maxRating
                ]);
            });

            echo json_encode([
                "success" => true,
                "message" => "Note enregistree",
                "questionIndex" => $questionIndex,
                "questionType" => "rating"
            ]);
            exit;
        }

        if ($questionType === 'checkbox') {
            $answerIndexes = $input['answerIndexes'] ?? null;
            if (!is_array($answerIndexes)) {
                echo json_encode(["success" => false, "message" => "Réponses manquantes"]);
                exit;
            }

            $answers = is_array($question['answers'] ?? null) ? $question['answers'] : [];
            $normalized = [];
            foreach ($answerIndexes as $value) {
                $index = (int)$value;
                if ($index < 0 || $index >= count($answers)) {
                    echo json_encode(["success" => false, "message" => "Réponse invalide"]);
                    exit;
                }
                $normalized[] = $index;
            }
            $normalized = array_values(array_unique($normalized));
            if (count($normalized) < 1) {
                echo json_encode(["success" => false, "message" => "Réponse invalide"]);
                exit;
            }

            $detailLabels = array_map(function($answerIndex) use ($answers) {
                return response_choice_label($answers, (int)$answerIndex);
            }, $normalized);
            $detailText = implode(' | ', $detailLabels);

            with_vote_lock($db, $code, $questionIndex, $runId, $voterHash, 'checkbox', function() use ($db, $code, $questionIndex, $normalized, $runId, $voterHash, $participantName, $detailText): void {
                $stmt = $db->prepare("INSERT INTO session_responses (session_code, question_index, answer_index, count)
                    VALUES (?, ?, ?, 1)
                    ON DUPLICATE KEY UPDATE count = count + 1");
                foreach ($normalized as $answerIndex) {
                    $stmt->execute([$code, $questionIndex, $answerIndex]);
                }
                save_response_detail($db, $code, $questionIndex, $runId, $voterHash, $participantName, $detailText, [
                    'type' => 'checkbox',
                    'answerIndexes' => array_values($normalized)
                ]);
            });

            echo json_encode([
                "success" => true,
                "message" => "Réponse enregistrée",
                "questionIndex" => $questionIndex,
                "questionType" => "checkbox"
            ]);
            exit;
        }

        if (!isset($input['answerIndex'])) {
            echo json_encode(["success" => false, "message" => "Reponse manquante"]);
            exit;
        }

        $answerIndex = (int)$input['answerIndex'];
        $answers = is_array($question['answers'] ?? null) ? $question['answers'] : [];
        if ($answerIndex < 0 || $answerIndex >= count($answers)) {
            echo json_encode(["success" => false, "message" => "Reponse invalide"]);
            exit;
        }

        $detailText = response_choice_label($answers, $answerIndex);

        with_vote_lock($db, $code, $questionIndex, $runId, $voterHash, 'multiple', function() use ($db, $code, $questionIndex, $answerIndex, $runId, $voterHash, $participantName, $detailText): void {
            $stmt = $db->prepare("INSERT INTO session_responses (session_code, question_index, answer_index, count)
                VALUES (?, ?, ?, 1)
                ON DUPLICATE KEY UPDATE count = count + 1");
            $stmt->execute([$code, $questionIndex, $answerIndex]);
            save_response_detail($db, $code, $questionIndex, $runId, $voterHash, $participantName, $detailText, [
                'type' => 'multiple',
                'answerIndex' => $answerIndex
            ]);
        });

        echo json_encode([
            "success" => true,
            "message" => "Reponse enregistree",
            "questionIndex" => $questionIndex,
            "questionType" => "multiple"
        ]);
        exit;
    }

    echo json_encode(["success" => false, "message" => "Question introuvable ou inactive"]);
} catch (Throwable $e) {
    app_json_error("Erreur interne.", $e);
}
?>
