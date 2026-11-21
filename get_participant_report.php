<?php
declare(strict_types=1);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: GET");

require_once __DIR__ . '/lib/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    echo json_encode(["success" => false, "error" => "Methode non autorisee"]);
    exit;
}

if (!isset($_GET['code'])) {
    echo json_encode(["success" => false, "error" => "Le parametre code est requis"]);
    exit;
}

function participant_report_normalize_flag($value): bool {
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

function participant_report_normalize_question_type($value): string {
    $type = strtolower(trim((string)$value));
    if ($type !== 'open' && $type !== 'wordcloud' && $type !== 'rating' && $type !== 'cloze' && $type !== 'video' && $type !== 'ranking' && $type !== 'labelimage' && $type !== 'checkbox') {
        return 'multiple';
    }
    return $type;
}

function participant_report_normalize_time_limit($value): int {
    $limit = is_numeric($value) ? (int)$value : 30;
    $allowed = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240];
    if (!in_array($limit, $allowed, true)) {
        return 30;
    }
    return $limit;
}

function participant_report_normalize_vote_token($value): string {
    $token = trim((string)$value);
    if ($token === '') {
        return '';
    }
    $token = preg_replace('/[^a-zA-Z0-9_-]/', '', $token) ?? '';
    return substr($token, 0, 120);
}

function participant_report_build_voter_hash(string $voteToken): string {
    $sessionId = trim(session_id());
    if ($sessionId !== '') {
        return hash('sha256', 'sess:' . $sessionId);
    }

    $normalizedToken = participant_report_normalize_vote_token($voteToken);
    if ($normalizedToken !== '') {
        return hash('sha256', 'tok:' . $normalizedToken);
    }

    $userAgent = substr(trim((string)($_SERVER['HTTP_USER_AGENT'] ?? '')), 0, 255);
    return hash('sha256', 'net:' . app_client_ip() . '|' . $userAgent);
}

function participant_report_is_session_completed(array $batch, int $currentIndex, string $startedAtRaw, bool $liveActive): bool {
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
    $questionType = participant_report_normalize_question_type($question['type'] ?? 'multiple');
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

    $timeLimitSec = participant_report_normalize_time_limit($question['timeLimitSec'] ?? 30);
    return time() >= ($startedTs + $timeLimitSec);
}

function participant_report_normalize_payload($value): ?array {
    if (!is_string($value) || trim($value) === '') {
        return null;
    }
    $decoded = json_decode($value, true);
    return is_array($decoded) ? $decoded : null;
}

function participant_report_choice_label(array $answers, int $index): string {
    if (array_key_exists($index, $answers)) {
        $value = trim((string)$answers[$index]);
        if ($value !== '') {
            return $value;
        }
    }
    return 'Choix ' . ($index + 1);
}

function participant_report_normalize_compare_text(string $value): string {
    $normalized = preg_replace('/\s+/u', ' ', trim($value)) ?? '';
    return mb_strtolower($normalized, 'UTF-8');
}

function participant_report_extract_cloze_expected_answers(string $template): array {
    $values = [];
    preg_replace_callback('/\[([^\]]*)\]|\{\{([^}]*)\}\}/u', static function(array $matches) use (&$values): string {
        $values[] = trim((string)($matches[1] ?? $matches[2] ?? ''));
        return $matches[0];
    }, $template);
    return $values;
}

function participant_report_build_cloze_expected_response(string $template): string {
    return preg_replace_callback('/\[([^\]]*)\]|\{\{([^}]*)\}\}/u', static function(array $matches): string {
        return trim((string)($matches[1] ?? $matches[2] ?? ''));
    }, $template) ?? '';
}

function participant_report_grade_cloze(?array $payload, array $question, string $participantResponse): ?bool {
    $template = trim((string)($question['clozeText'] ?? ''));
    if ($template === '') {
        return null;
    }

    if (count(participant_report_extract_cloze_expected_answers($template)) === 0) {
        return null;
    }

    $expectedResponse = participant_report_build_cloze_expected_response($template);
    $recordedResponse = trim((string)($payload['openText'] ?? $participantResponse));
    if ($recordedResponse === '') {
        return null;
    }

    return participant_report_normalize_compare_text($recordedResponse)
        === participant_report_normalize_compare_text($expectedResponse);
}

function participant_report_expected_ranking(array $question): array {
    $raw = is_array($question['answers'] ?? null) ? $question['answers'] : [];
    return array_values(array_filter(array_map(static function($value): string {
        return trim((string)$value);
    }, $raw), static function(string $value): bool {
        return $value !== '';
    }));
}

function participant_report_grade_ranking(?array $payload, array $question): ?bool {
    $expected = participant_report_expected_ranking($question);
    if (count($expected) < 2 || !is_array($payload['rankingOrder'] ?? null)) {
        return null;
    }

    $received = array_values(array_filter(array_map(static function($value): string {
        return trim((string)$value);
    }, $payload['rankingOrder']), static function(string $value): bool {
        return $value !== '';
    }));

    if (count($received) !== count($expected)) {
        return null;
    }

    return $received === $expected;
}

function participant_report_build_label_targets($rawLabels): array {
    if (!is_array($rawLabels)) {
        return [];
    }
    $targets = [];
    foreach ($rawLabels as $index => $entry) {
        if (!is_array($entry)) {
            continue;
        }
        $id = preg_replace('/[^a-zA-Z0-9_-]/', '', (string)($entry['id'] ?? '')) ?? '';
        if ($id === '') {
            $id = 'lbl' . ($index + 1);
        }
        $text = trim((string)($entry['text'] ?? ''));
        $x = isset($entry['x']) && is_numeric($entry['x']) ? (float)$entry['x'] : null;
        $y = isset($entry['y']) && is_numeric($entry['y']) ? (float)$entry['y'] : null;
        if ($text === '' || $x === null || $y === null) {
            continue;
        }
        $targets[$id] = [
            'text' => $text,
            'x' => max(0, min(100, $x)),
            'y' => max(0, min(100, $y))
        ];
    }
    return $targets;
}

function participant_report_grade_labelimage(array $payload, array $targets): ?bool {
    $placementsRaw = is_array($payload['legendPlacements'] ?? null) ? $payload['legendPlacements'] : [];
    if (count($targets) === 0 || count($placementsRaw) === 0) {
        return null;
    }

    $placements = [];
    foreach ($placementsRaw as $entry) {
        if (!is_array($entry)) {
            continue;
        }
        $id = preg_replace('/[^a-zA-Z0-9_-]/', '', (string)($entry['id'] ?? '')) ?? '';
        $x = isset($entry['x']) && is_numeric($entry['x']) ? (float)$entry['x'] : null;
        $y = isset($entry['y']) && is_numeric($entry['y']) ? (float)$entry['y'] : null;
        if ($id === '' || !isset($targets[$id]) || $x === null || $y === null) {
            continue;
        }
        $placements[$id] = [
            'x' => max(0, min(100, $x)),
            'y' => max(0, min(100, $y))
        ];
    }

    if (count($placements) !== count($targets)) {
        return false;
    }

    $tolerance = 8.0;
    foreach ($targets as $id => $target) {
        if (!isset($placements[$id])) {
            return false;
        }
        $deltaX = abs((float)$placements[$id]['x'] - (float)$target['x']);
        $deltaY = abs((float)$placements[$id]['y'] - (float)$target['y']);
        if ($deltaX > $tolerance || $deltaY > $tolerance) {
            return false;
        }
    }

    return true;
}

try {
    $code = trim((string)$_GET['code']);
    $voteToken = trim((string)($_GET['voteToken'] ?? ''));
    if ($code === '') {
        echo json_encode(["success" => false, "error" => "Code invalide"]);
        exit;
    }

    $db = app_db();
    $stmt = $db->prepare("SELECT quiz_title, participant_report_enabled, questions_json, current_index, current_question_started_at, live_active
        FROM session_batches
        WHERE session_code = ? AND deleted_at IS NULL
        LIMIT 1");
    $stmt->execute([$code]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);

    if (!$row) {
        echo json_encode(["success" => false, "error" => "Questionnaire introuvable"]);
        exit;
    }

    $participantReportEnabled = participant_report_normalize_flag($row['participant_report_enabled'] ?? false);
    if (!$participantReportEnabled) {
        echo json_encode(["success" => false, "error" => "Le rapport personnel n'est pas disponible pour ce questionnaire."]);
        exit;
    }

    $batch = json_decode((string)($row['questions_json'] ?? '[]'), true);
    if (!is_array($batch) || count($batch) === 0) {
        echo json_encode(["success" => false, "error" => "Questionnaire invalide"]);
        exit;
    }

    $currentIndex = isset($row['current_index']) ? (int)$row['current_index'] : 0;
    $startedAtRaw = trim((string)($row['current_question_started_at'] ?? ''));
    $liveActive = ((int)($row['live_active'] ?? 0)) === 1;

    if (!participant_report_is_session_completed($batch, $currentIndex, $startedAtRaw, $liveActive)) {
        echo json_encode(["success" => false, "error" => "Le rapport personnel ne sera disponible qu'à la fin du questionnaire."]);
        exit;
    }

    $voterHash = participant_report_build_voter_hash($voteToken);
    $detailStmt = $db->prepare("SELECT question_index, participant_name, response_text, response_payload
        FROM session_response_details
        WHERE session_code = ? AND voter_hash = ?
        ORDER BY question_index ASC");
    $detailStmt->execute([$code, $voterHash]);
    $detailRows = $detailStmt->fetchAll(PDO::FETCH_ASSOC);

    if (!$detailRows) {
        echo json_encode(["success" => false, "error" => "Aucun rapport personnel disponible pour cette session."]);
        exit;
    }

    $detailsByQuestion = [];
    $participantName = '';
    foreach ($detailRows as $detailRow) {
        $questionIndex = (int)($detailRow['question_index'] ?? 0);
        $detailsByQuestion[$questionIndex] = [
            'participantName' => (string)($detailRow['participant_name'] ?? ''),
            'responseText' => (string)($detailRow['response_text'] ?? ''),
            'payload' => participant_report_normalize_payload($detailRow['response_payload'] ?? null)
        ];
        if ($participantName === '') {
            $participantName = trim((string)($detailRow['participant_name'] ?? ''));
        }
    }

    $questions = [];
    $correctCount = 0;
    $incorrectCount = 0;
    $unansweredCount = 0;
    $gradableCount = 0;
    $notGradedCount = 0;

    foreach ($batch as $index => $question) {
        $question = is_array($question) ? $question : [];
        $type = participant_report_normalize_question_type($question['type'] ?? 'multiple');
        $detail = $detailsByQuestion[$index] ?? null;
        $payload = is_array($detail['payload'] ?? null) ? $detail['payload'] : null;
        $participantResponse = trim((string)($detail['responseText'] ?? ''));
        $expectedResponse = '';
        $status = 'not_graded';
        $statusLabel = 'Réponse enregistrée';
        $isCorrect = null;
        $explanation = '';

        $autoGraded = in_array($type, ['multiple', 'checkbox', 'labelimage', 'cloze', 'ranking'], true);
        if ($autoGraded) {
            $gradableCount += 1;
        }

        if ($type === 'video') {
            $status = 'informational';
            $statusLabel = 'Aucune réponse attendue';
            $participantResponse = '';
            $expectedResponse = '';
            $explanation = "Cette question vidéo n'attendait pas de réponse.";
        } elseif ($detail === null) {
            $status = 'unanswered';
            $statusLabel = 'Sans réponse';
            $participantResponse = '';
            $unansweredCount += 1;
            if ($autoGraded) {
                if ($type === 'labelimage') {
                    $expectedResponse = 'Toutes les étiquettes correctement placées';
                } elseif ($type === 'cloze') {
                    $expectedResponse = participant_report_build_cloze_expected_response((string)($question['clozeText'] ?? ''));
                } elseif ($type === 'ranking') {
                    $expectedResponse = implode(' -> ', participant_report_expected_ranking($question));
                }
            }
        } elseif ($type === 'multiple') {
            $answers = is_array($question['answers'] ?? null) ? $question['answers'] : [];
            $correctIndex = isset($question['correctIndex']) ? (int)$question['correctIndex'] : 0;
            if ($correctIndex < 0 || $correctIndex >= count($answers)) {
                $correctIndex = 0;
            }
            $expectedResponse = participant_report_choice_label($answers, $correctIndex);
            if (isset($payload['answerIndex']) && is_numeric($payload['answerIndex'])) {
                $answerIndex = (int)$payload['answerIndex'];
                $isCorrect = $answerIndex === $correctIndex;
            }
            if ($isCorrect === null) {
                $status = 'not_graded';
                $statusLabel = 'Réponse enregistrée';
                $explanation = "Cette réponse a été enregistrée avant l'activation du rapport détaillé.";
                $notGradedCount += 1;
            } elseif ($isCorrect) {
                $status = 'correct';
                $statusLabel = 'Bonne réponse';
                $correctCount += 1;
            } else {
                $status = 'incorrect';
                $statusLabel = 'Réponse incorrecte';
                $incorrectCount += 1;
            }
        } elseif ($type === 'checkbox') {
            $answers = is_array($question['answers'] ?? null) ? $question['answers'] : [];
            $rawCorrectIndexes = is_array($question['correctIndexes'] ?? null) ? $question['correctIndexes'] : [];
            $correctIndexes = [];
            foreach ($rawCorrectIndexes as $value) {
                $correctIndex = (int)$value;
                if ($correctIndex >= 0 && $correctIndex < count($answers)) {
                    $correctIndexes[] = $correctIndex;
                }
            }
            $correctIndexes = array_values(array_unique($correctIndexes));
            $expectedLabels = array_map(static function(int $answerIndex) use ($answers): string {
                return participant_report_choice_label($answers, $answerIndex);
            }, $correctIndexes);
            $expectedResponse = implode(' | ', $expectedLabels);
            if (is_array($payload['answerIndexes'] ?? null)) {
                $selectedIndexes = [];
                foreach ($payload['answerIndexes'] as $value) {
                    if (is_numeric($value)) {
                        $selectedIndexes[] = (int)$value;
                    }
                }
                $selectedIndexes = array_values(array_unique($selectedIndexes));
                sort($selectedIndexes);
                $expectedCompare = $correctIndexes;
                sort($expectedCompare);
                $isCorrect = $selectedIndexes === $expectedCompare;
            }
            if ($isCorrect === null) {
                $status = 'not_graded';
                $statusLabel = 'Réponse enregistrée';
                $explanation = "Cette réponse a été enregistrée avant l'activation du rapport détaillé.";
                $notGradedCount += 1;
            } elseif ($isCorrect) {
                $status = 'correct';
                $statusLabel = 'Bonne réponse';
                $correctCount += 1;
            } else {
                $status = 'incorrect';
                $statusLabel = 'Réponse incorrecte';
                $incorrectCount += 1;
            }
        } elseif ($type === 'labelimage') {
            $expectedTargets = participant_report_build_label_targets($question['legendLabels'] ?? []);
            $expectedResponse = count($expectedTargets) > 0
                ? implode(' | ', array_map(static function(array $target): string {
                    return sprintf('%s (%.1f%%, %.1f%%)', $target['text'], $target['x'], $target['y']);
                }, array_values($expectedTargets)))
                : '';
            $grade = $payload !== null ? participant_report_grade_labelimage($payload, $expectedTargets) : null;
            if ($grade === null) {
                $status = 'not_graded';
                $statusLabel = 'Réponse enregistrée';
                $explanation = "La correction automatique n'est pas disponible pour cette réponse enregistrée.";
                $notGradedCount += 1;
            } elseif ($grade) {
                $status = 'correct';
                $statusLabel = 'Bonne réponse';
                $isCorrect = true;
                $correctCount += 1;
            } else {
                $status = 'incorrect';
                $statusLabel = 'Réponse incorrecte';
                $isCorrect = false;
                $incorrectCount += 1;
            }
        } elseif ($type === 'cloze') {
            $expectedResponse = participant_report_build_cloze_expected_response((string)($question['clozeText'] ?? ''));
            $grade = participant_report_grade_cloze($payload, $question, $participantResponse);
            if ($grade === null) {
                $status = 'not_graded';
                $statusLabel = 'Réponse enregistrée';
                $explanation = "La correction automatique n'est pas disponible pour cette réponse enregistrée.";
                $notGradedCount += 1;
            } elseif ($grade) {
                $status = 'correct';
                $statusLabel = 'Bonne réponse';
                $isCorrect = true;
                $correctCount += 1;
            } else {
                $status = 'incorrect';
                $statusLabel = 'Réponse incorrecte';
                $isCorrect = false;
                $incorrectCount += 1;
            }
        } elseif ($type === 'ranking') {
            $expectedResponse = implode(' -> ', participant_report_expected_ranking($question));
            $grade = participant_report_grade_ranking($payload, $question);
            if ($grade === null) {
                $status = 'not_graded';
                $statusLabel = 'Réponse enregistrée';
                $explanation = "La correction automatique n'est pas disponible pour cette réponse enregistrée.";
                $notGradedCount += 1;
            } elseif ($grade) {
                $status = 'correct';
                $statusLabel = 'Bonne réponse';
                $isCorrect = true;
                $correctCount += 1;
            } else {
                $status = 'incorrect';
                $statusLabel = 'Réponse incorrecte';
                $isCorrect = false;
                $incorrectCount += 1;
            }
        } else {
            $status = 'not_graded';
            $statusLabel = 'Réponse enregistrée';
            $notGradedCount += 1;
            if ($type === 'open' || $type === 'wordcloud') {
                $explanation = "Ce type de question n'est pas corrigé automatiquement dans le rapport personnel.";
            } elseif ($type === 'rating') {
                $explanation = "Cette évaluation n'est pas notée comme juste ou fausse.";
            }
        }

        $questions[] = [
            'questionIndex' => (int)$index,
            'type' => $type,
            'question' => (string)($question['question'] ?? ''),
            'status' => $status,
            'statusLabel' => $statusLabel,
            'isCorrect' => $isCorrect,
            'participantResponse' => $participantResponse,
            'expectedResponse' => $expectedResponse,
            'explanation' => $explanation
        ];
    }

    echo json_encode([
        'success' => true,
        'code' => $code,
        'quizTitle' => trim((string)($row['quiz_title'] ?? '')),
        'participantName' => $participantName,
        'participantReportEnabled' => true,
        'summary' => [
            'correctCount' => $correctCount,
            'incorrectCount' => $incorrectCount,
            'unansweredCount' => $unansweredCount,
            'gradableCount' => $gradableCount,
            'notGradedCount' => $notGradedCount
        ],
        'questions' => $questions,
        'generatedAt' => gmdate('c')
    ]);
} catch (Throwable $e) {
    app_json_error("Erreur interne.", $e);
}
?>
