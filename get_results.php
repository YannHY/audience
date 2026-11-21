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
$requestedIndex = isset($_GET['questionIndex']) ? (int)$_GET['questionIndex'] : null;

try {
    $user = require_login_json();
    $db = app_db();

    $batchStmt = $db->prepare("SELECT questions_json, current_index, owner_user_id FROM session_batches WHERE session_code = ? AND deleted_at IS NULL");
    $batchStmt->execute([$code]);
    $batchRow = $batchStmt->fetch(PDO::FETCH_ASSOC);

    if ($batchRow) {
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

        $questionIndex = (int)$batchRow['current_index'];
        if ($requestedIndex !== null) {
            $questionIndex = $requestedIndex;
        }
        if ($questionIndex < 0) {
            $questionIndex = 0;
        }
        if ($questionIndex >= count($batch)) {
            $questionIndex = count($batch) - 1;
        }

        $q = $batch[$questionIndex];
        $questionType = strtolower(trim((string)($q['type'] ?? 'multiple')));
        if ($questionType !== 'open' && $questionType !== 'wordcloud' && $questionType !== 'rating' && $questionType !== 'cloze' && $questionType !== 'video' && $questionType !== 'ranking' && $questionType !== 'labelimage' && $questionType !== 'checkbox') {
            $questionType = 'multiple';
        }

        if ($questionType === 'video') {
            echo json_encode([
                "success" => true,
                "questionType" => "video",
                "results" => new stdClass(),
                "total" => 0,
                "questionIndex" => $questionIndex,
                "totalQuestions" => count($batch),
                "correctIndex" => null
            ]);
            exit;
        }

        if ($questionType === 'open' || $questionType === 'wordcloud' || $questionType === 'cloze') {
            $openStmt = $db->prepare("SELECT response_text FROM session_open_responses WHERE session_code = ? AND question_index = ? ORDER BY id ASC");
            $openStmt->execute([$code, $questionIndex]);
            $rows = $openStmt->fetchAll(PDO::FETCH_ASSOC);
            $responses = [];
            foreach ($rows as $row) {
                $responses[] = (string)$row['response_text'];
            }

            echo json_encode([
                "success" => true,
                "questionType" => $questionType,
                "openResponses" => $responses,
                "totalOpenResponses" => count($responses),
                "questionIndex" => $questionIndex,
                "totalQuestions" => count($batch),
                "correctIndex" => null
            ]);
            exit;
        }

        if ($questionType === 'labelimage') {
            $openStmt = $db->prepare("SELECT response_text FROM session_open_responses WHERE session_code = ? AND question_index = ? ORDER BY id ASC");
            $openStmt->execute([$code, $questionIndex]);
            $rows = $openStmt->fetchAll(PDO::FETCH_ASSOC);
            $responses = [];
            foreach ($rows as $row) {
                $raw = trim((string)($row['response_text'] ?? ''));
                if ($raw === '') {
                    continue;
                }
                $parsed = json_decode($raw, true);
                if (!is_array($parsed)) {
                    continue;
                }
                $placements = is_array($parsed['legendPlacements'] ?? null) ? $parsed['legendPlacements'] : [];
                if (count($placements) > 0) {
                    $responses[] = $placements;
                }
            }

            echo json_encode([
                "success" => true,
                "questionType" => "labelimage",
                "labelImageResponses" => $responses,
                "totalLabelImageResponses" => count($responses),
                "questionIndex" => $questionIndex,
                "totalQuestions" => count($batch),
                "correctIndex" => null
            ]);
            exit;
        }

        if ($questionType === 'ranking') {
            $openStmt = $db->prepare("SELECT response_text FROM session_open_responses WHERE session_code = ? AND question_index = ? ORDER BY id ASC");
            $openStmt->execute([$code, $questionIndex]);
            $rows = $openStmt->fetchAll(PDO::FETCH_ASSOC);

            $rankingCounts = [];
            $rankingResponses = [];
            foreach ($rows as $row) {
                $raw = trim((string)($row['response_text'] ?? ''));
                if ($raw === '') {
                    continue;
                }

                $parsed = json_decode($raw, true);
                if (!is_array($parsed)) {
                    $parts = [];
                    foreach (explode('|', $raw) as $piece) {
                        $value = trim((string)$piece);
                        if ($value !== '') {
                            $parts[] = $value;
                        }
                    }
                    $parsed = $parts;
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
                $rankingResponses[] = $label;
                if (!isset($rankingCounts[$label])) {
                    $rankingCounts[$label] = 0;
                }
                $rankingCounts[$label] += 1;
            }

            echo json_encode([
                "success" => true,
                "questionType" => "ranking",
                "rankingCounts" => $rankingCounts,
                "rankingResponses" => $rankingResponses,
                "totalRankingResponses" => count($rankingResponses),
                "questionIndex" => $questionIndex,
                "totalQuestions" => count($batch),
                "correctIndex" => null
            ]);
            exit;
        }

        if ($questionType === 'rating') {
            $maxRating = isset($q['maxRating']) ? (int)$q['maxRating'] : 5;
            if ($maxRating < 2 || $maxRating > 10) {
                $maxRating = 5;
            }

            $resStmt = $db->prepare("SELECT answer_index, count FROM session_responses WHERE session_code = ? AND question_index = ?");
            $resStmt->execute([$code, $questionIndex]);
            $rows = $resStmt->fetchAll(PDO::FETCH_ASSOC);

            $ratingCounts = [];
            for ($i = 1; $i <= $maxRating; $i++) {
                $ratingCounts[(string)$i] = 0;
            }

            $sumRatings = 0;
            $totalRatings = 0;
            foreach ($rows as $row) {
                $rating = (int)$row['answer_index'];
                $count = (int)$row['count'];
                if ($rating < 1 || $rating > $maxRating) {
                    continue;
                }
                $ratingCounts[(string)$rating] = $count;
                $sumRatings += ($rating * $count);
                $totalRatings += $count;
            }

            $avgRating = $totalRatings > 0 ? round($sumRatings / $totalRatings, 2) : 0;

            echo json_encode([
                "success" => true,
                "questionType" => "rating",
                "ratingCounts" => $ratingCounts,
                "totalRatings" => $totalRatings,
                "avgRating" => $avgRating,
                "maxRating" => $maxRating,
                "questionIndex" => $questionIndex,
                "totalQuestions" => count($batch),
                "correctIndex" => null
            ]);
            exit;
        }

        $answers = is_array($q['answers'] ?? null) ? $q['answers'] : ['', ''];
        if (count($answers) < 2) {
            $answers = array_pad($answers, 2, '');
        }
        $correctIndex = null;
        $correctIndexes = [];
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
        } elseif ($questionType === 'checkbox') {
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

        $resStmt = $db->prepare("SELECT answer_index, count FROM session_responses WHERE session_code = ? AND question_index = ?");
        $resStmt->execute([$code, $questionIndex]);
        $rows = $resStmt->fetchAll(PDO::FETCH_ASSOC);

        $formatted = [];
        foreach ($rows as $row) {
            $formatted[$row['answer_index']] = (int)$row['count'];
        }

        echo json_encode([
            "success" => true,
            "questionType" => $questionType,
            "results" => $formatted,
            "questionIndex" => $questionIndex,
            "totalQuestions" => count($batch),
            "correctIndex" => $correctIndex,
            "correctIndexes" => $correctIndexes
        ]);
        exit;
    }

    echo json_encode(["success" => false, "error" => "Session introuvable"]);
} catch(Throwable $e) {
    app_json_error("Erreur interne.", $e);
}
?>
