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

$code = trim((string)$_GET['code']);

try {
    $user = require_login_json();
    $db = app_db();

    $batchStmt = $db->prepare("SELECT questions_json, current_index, owner_user_id FROM session_batches WHERE session_code = ? AND deleted_at IS NULL");
    $batchStmt->execute([$code]);
    $batchRow = $batchStmt->fetch(PDO::FETCH_ASSOC);

    if (!$batchRow) {
        echo json_encode(["success" => false, "error" => "Aucun lot trouve pour ce code"]);
        exit;
    }
    if ((int)($batchRow['owner_user_id'] ?? 0) !== (int)$user['id']) {
        http_response_code(403);
        echo json_encode(["success" => false, "error" => "Accès refusé"]);
        exit;
    }

    $batch = json_decode($batchRow['questions_json'], true);
    if (!is_array($batch) || count($batch) === 0) {
        echo json_encode(["success" => false, "error" => "Lot invalide"]);
        exit;
    }

    $resStmt = $db->prepare("SELECT question_index, answer_index, count FROM session_responses WHERE session_code = ?");
    $resStmt->execute([$code]);
    $rows = $resStmt->fetchAll(PDO::FETCH_ASSOC);

    $counts = [];
    foreach ($rows as $row) {
        $qi = (int)$row['question_index'];
        $ai = (int)$row['answer_index'];
        $ct = (int)$row['count'];
        if (!isset($counts[$qi])) {
            $counts[$qi] = [];
        }
        if ($ai >= 0) {
            $counts[$qi][$ai] = $ct;
        }
    }

    $openStmt = $db->prepare("SELECT question_index, response_text FROM session_open_responses WHERE session_code = ? ORDER BY id ASC");
    $openStmt->execute([$code]);
    $openRows = $openStmt->fetchAll(PDO::FETCH_ASSOC);
    $openByQuestion = [];
    foreach ($openRows as $row) {
        $qi = (int)$row['question_index'];
        if (!isset($openByQuestion[$qi])) {
            $openByQuestion[$qi] = [];
        }
        $openByQuestion[$qi][] = (string)$row['response_text'];
    }

    $detailStmt = $db->prepare("SELECT question_index, voter_hash, participant_name, response_text
        FROM session_response_details
        WHERE session_code = ?
        ORDER BY id ASC");
    $detailStmt->execute([$code]);
    $detailRows = $detailStmt->fetchAll(PDO::FETCH_ASSOC);
    $detailByQuestion = [];
    foreach ($detailRows as $row) {
        $qi = (int)$row['question_index'];
        if (!isset($detailByQuestion[$qi])) {
            $detailByQuestion[$qi] = [];
        }
        $detailByQuestion[$qi][] = [
            'participantKey' => (string)($row['voter_hash'] ?? ''),
            'participantName' => (string)($row['participant_name'] ?? ''),
            'responseText' => (string)($row['response_text'] ?? '')
        ];
    }

    $questionsOut = [];
    foreach ($batch as $index => $q) {
        $questionType = strtolower(trim((string)($q['type'] ?? 'multiple')));
        if ($questionType !== 'open' && $questionType !== 'wordcloud' && $questionType !== 'rating' && $questionType !== 'cloze' && $questionType !== 'video' && $questionType !== 'ranking' && $questionType !== 'labelimage' && $questionType !== 'checkbox') {
            $questionType = 'multiple';
        }

        if ($questionType === 'video') {
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
            $questionsOut[] = [
                "questionIndex" => $index,
                "type" => "video",
                "question" => (string)($q['question'] ?? ''),
                "questionImage" => '',
                "youtubeUrl" => (string)($q['youtubeUrl'] ?? ''),
                "videoStartSec" => $videoStartSec,
                "videoEndSec" => $videoEndSec,
                "answers" => [],
                "correctIndex" => null,
                "results" => new stdClass(),
                "openResponses" => [],
                "participantResponses" => [],
                "total" => 0
            ];
            continue;
        }

        if ($questionType === 'open' || $questionType === 'wordcloud' || $questionType === 'cloze') {
            $openResponses = $openByQuestion[$index] ?? [];
            $questionsOut[] = [
                "questionIndex" => $index,
                "type" => $questionType,
                "question" => (string)($q['question'] ?? ''),
                "questionImage" => ($questionType === 'open' || $questionType === 'cloze') ? (string)($q['questionImage'] ?? '') : '',
                "clozeText" => (string)($q['clozeText'] ?? ''),
                "responseFormat" => $questionType === 'open' && strtolower(trim((string)($q['responseFormat'] ?? 'text'))) === 'math' ? 'math' : 'text',
                "answers" => [],
                "correctIndex" => null,
                "results" => new stdClass(),
                "openResponses" => $openResponses,
                "participantResponses" => $detailByQuestion[$index] ?? [],
                "total" => count($openResponses)
            ];
            continue;
        }

        if ($questionType === 'labelimage') {
            $rawResponses = $openByQuestion[$index] ?? [];
            $formattedResponses = [];
            foreach ($rawResponses as $raw) {
                $payload = trim((string)$raw);
                if ($payload === '') {
                    continue;
                }
                $parsed = json_decode($payload, true);
                if (!is_array($parsed)) {
                    continue;
                }
                $placements = is_array($parsed['legendPlacements'] ?? null) ? $parsed['legendPlacements'] : [];
                if (count($placements) > 0) {
                    $formattedResponses[] = 'Placement complété';
                }
            }

            $questionsOut[] = [
                "questionIndex" => $index,
                "type" => "labelimage",
                "question" => (string)($q['question'] ?? ''),
                "questionImage" => (string)($q['questionImage'] ?? ''),
                "legendLabels" => is_array($q['legendLabels'] ?? null) ? $q['legendLabels'] : [],
                "answers" => [],
                "correctIndex" => null,
                "results" => new stdClass(),
                "openResponses" => $formattedResponses,
                "participantResponses" => $detailByQuestion[$index] ?? [],
                "total" => count($formattedResponses)
            ];
            continue;
        }

        if ($questionType === 'ranking') {
            $rawResponses = $openByQuestion[$index] ?? [];
            $rankingCounts = [];
            $formattedResponses = [];
            foreach ($rawResponses as $raw) {
                $payload = trim((string)$raw);
                if ($payload === '') {
                    continue;
                }
                $parsed = json_decode($payload, true);
                if (!is_array($parsed)) {
                    $parsed = [];
                    foreach (explode('|', $payload) as $piece) {
                        $value = trim((string)$piece);
                        if ($value !== '') {
                            $parsed[] = $value;
                        }
                    }
                }
                $order = array_values(array_filter(array_map(function($value) {
                    return trim((string)$value);
                }, $parsed), function($value) {
                    return $value !== '';
                }));
                if (count($order) < 2) {
                    continue;
                }
                $label = implode(' -> ', $order);
                $formattedResponses[] = $label;
                if (!isset($rankingCounts[$label])) {
                    $rankingCounts[$label] = 0;
                }
                $rankingCounts[$label] += 1;
            }

            $questionsOut[] = [
                "questionIndex" => $index,
                "type" => "ranking",
                "question" => (string)($q['question'] ?? ''),
                "questionImage" => '',
                "answers" => is_array($q['answers'] ?? null) ? $q['answers'] : [],
                "correctIndex" => null,
                "results" => new stdClass(),
                "rankingCounts" => $rankingCounts,
                "openResponses" => $formattedResponses,
                "participantResponses" => $detailByQuestion[$index] ?? [],
                "total" => count($formattedResponses)
            ];
            continue;
        }

        if ($questionType === 'rating') {
            $maxRating = isset($q['maxRating']) ? (int)$q['maxRating'] : 5;
            if ($maxRating < 2 || $maxRating > 10) {
                $maxRating = 5;
            }

            $countsForQuestion = [];
            $sumRatings = 0;
            $totalRatings = 0;
            for ($rating = 1; $rating <= $maxRating; $rating++) {
                $count = (int)($counts[$index][$rating] ?? 0);
                $countsForQuestion[(string)$rating] = $count;
                $sumRatings += ($rating * $count);
                $totalRatings += $count;
            }

            $avgRating = $totalRatings > 0 ? round($sumRatings / $totalRatings, 2) : 0;

            $questionsOut[] = [
                "questionIndex" => $index,
                "type" => "rating",
                "question" => (string)($q['question'] ?? ''),
                "questionImage" => '',
                "answers" => [],
                "correctIndex" => null,
                "results" => $countsForQuestion,
                "openResponses" => [],
                "participantResponses" => $detailByQuestion[$index] ?? [],
                "maxRating" => $maxRating,
                "avgRating" => $avgRating,
                "total" => $totalRatings
            ];
            continue;
        }

        $answers = is_array($q['answers'] ?? null) ? $q['answers'] : ['', ''];
        if (count($answers) < 2) {
            $answers = array_pad($answers, 2, '');
        }
        $correctIndex = null;
        $correctIndexes = [];
        if ($questionType === 'multiple') {
            $correctIndex = isset($q['correctIndex']) ? (int)$q['correctIndex'] : 0;
            if ($correctIndex < 0 || $correctIndex >= count($answers)) {
                $correctIndex = 0;
            }
        } elseif ($questionType === 'checkbox') {
            $rawCorrectIndexes = is_array($q['correctIndexes'] ?? null) ? $q['correctIndexes'] : [];
            foreach ($rawCorrectIndexes as $value) {
                $correctValue = (int)$value;
                if ($correctValue < 0 || $correctValue >= count($answers)) {
                    continue;
                }
                $correctIndexes[] = $correctValue;
            }
            $correctIndexes = array_values(array_unique($correctIndexes));
        }

        $results = $counts[$index] ?? [];
        $formattedResults = [];
        foreach ($answers as $answerIndex => $_answerText) {
            $formattedResults[(string)$answerIndex] = (int)($results[$answerIndex] ?? 0);
        }
        $total = array_sum($formattedResults);

        $questionsOut[] = [
            "questionIndex" => $index,
            "type" => $questionType,
            "question" => (string)($q['question'] ?? ''),
            "questionImage" => (string)($q['questionImage'] ?? ''),
            "answers" => $answers,
            "correctIndex" => $correctIndex,
            "correctIndexes" => $correctIndexes,
            "results" => $formattedResults,
            "openResponses" => [],
            "participantResponses" => $detailByQuestion[$index] ?? [],
            "total" => (int)$total
        ];
    }

    echo json_encode([
        "success" => true,
        "code" => $code,
        "currentIndex" => (int)$batchRow['current_index'],
        "totalQuestions" => count($questionsOut),
        "questions" => $questionsOut
    ]);
} catch(Throwable $e) {
    app_json_error("Erreur interne.", $e);
}
?>
