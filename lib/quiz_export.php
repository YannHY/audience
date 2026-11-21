<?php
declare(strict_types=1);

const AUDIENCE_EXPORT_MAX_VIDEO_BOUNDARY_SEC = 43200;

function audience_export_escape_md($value): string {
    return trim(str_replace(
        ['\\', '|', '`'],
        ['\\\\', '\\|', '\\`'],
        (string)($value ?? '')
    ));
}

function audience_export_extract_question_plain_text($value): string {
    $text = (string)($value ?? '');
    $withBreaks = preg_replace('/<br\s*\/?>/iu', "\n", $text) ?? $text;
    $withBreaks = preg_replace('/<\/(p|div|li|ul|ol)>/iu', "\n", $withBreaks) ?? $withBreaks;
    $withoutTags = strip_tags($withBreaks);
    $decoded = html_entity_decode($withoutTags, ENT_QUOTES | ENT_HTML5, 'UTF-8');
    $decoded = str_replace("\xc2\xa0", ' ', $decoded);
    $decoded = preg_replace("/[ \t]+\n/u", "\n", $decoded) ?? $decoded;
    $decoded = preg_replace("/\n{3,}/u", "\n\n", $decoded) ?? $decoded;
    return trim($decoded);
}

function audience_export_normalize_question_type($type): string {
    $raw = mb_strtolower(trim((string)($type ?? '')), 'UTF-8');
    if ($raw === 'open' || mb_strpos($raw, 'ouverte') !== false || mb_strpos($raw, 'open') !== false) {
        return 'open';
    }
    if ($raw === 'wordcloud' || mb_strpos($raw, 'nuage') !== false) {
        return 'wordcloud';
    }
    if ($raw === 'rating' || mb_strpos($raw, 'notation') !== false || mb_strpos($raw, 'etoile') !== false || mb_strpos($raw, 'étoile') !== false) {
        return 'rating';
    }
    if ($raw === 'cloze' || mb_strpos($raw, 'trou') !== false) {
        return 'cloze';
    }
    if ($raw === 'video' || mb_strpos($raw, 'vidéo') !== false || mb_strpos($raw, 'video') !== false || mb_strpos($raw, 'youtube') !== false) {
        return 'video';
    }
    if ($raw === 'ranking' || $raw === 'rank' || mb_strpos($raw, 'classement') !== false || mb_strpos($raw, 'classer') !== false || mb_strpos($raw, 'ordre') !== false) {
        return 'ranking';
    }
    if ($raw === 'labelimage' || mb_strpos($raw, 'legender') !== false || mb_strpos($raw, 'légender') !== false || mb_strpos($raw, 'étiquette') !== false || mb_strpos($raw, 'etiquette') !== false) {
        return 'labelimage';
    }
    if ($raw === 'checkbox' || mb_strpos($raw, 'checkbox') !== false || mb_strpos($raw, 'cases a cocher') !== false || mb_strpos($raw, 'cases à cocher') !== false || mb_strpos($raw, 'case a cocher') !== false || mb_strpos($raw, 'case à cocher') !== false || mb_strpos($raw, 'cocher') !== false) {
        return 'checkbox';
    }
    return 'multiple';
}

function audience_export_normalize_participant_responses_visibility($value): bool {
    if (is_string($value)) {
        $normalized = mb_strtolower(trim($value), 'UTF-8');
        if (in_array($normalized, ['false', '0', 'non', 'no', 'masquer', 'masquées', 'masquees', 'cacher', 'cachées', 'cachees'], true)) {
            return false;
        }
        if (in_array($normalized, ['true', '1', 'oui', 'yes', 'afficher', 'visibles'], true)) {
            return true;
        }
    }
    return $value !== false;
}

function audience_export_normalize_open_response_format($value): string {
    return mb_strtolower(trim((string)($value ?? '')), 'UTF-8') === 'math' ? 'math' : 'text';
}

function audience_export_normalize_video_boundary_sec($value): ?int {
    if ($value === null || $value === '') {
        return null;
    }
    if (!is_numeric($value)) {
        return null;
    }
    $seconds = (int)round((float)$value);
    return max(0, min(AUDIENCE_EXPORT_MAX_VIDEO_BOUNDARY_SEC, $seconds));
}

function audience_export_normalize_question_image_zoom($value): float {
    if (!is_numeric($value)) {
        return 1.0;
    }
    $zoom = (float)$value;
    return max(0.6, min(2.2, $zoom));
}

function audience_export_is_valid_question_image($value): bool {
    $raw = trim((string)($value ?? ''));
    if ($raw === '') {
        return false;
    }
    if (preg_match('/^data:image\/(?:png|jpeg|webp|gif);base64,/i', $raw) === 1) {
        return true;
    }
    return preg_match('/^https?:\/\//i', $raw) === 1 || str_starts_with($raw, 'uploads/');
}

function audience_export_normalize_legend_labels($rawLabels): array {
    if (!is_array($rawLabels)) {
        return [];
    }
    $out = [];
    foreach ($rawLabels as $index => $entry) {
        if (!is_array($entry)) {
            continue;
        }
        $text = trim((string)($entry['text'] ?? ''));
        $safeId = preg_replace('/[^a-zA-Z0-9_-]/', '', trim((string)($entry['id'] ?? ''))) ?? '';
        if ($safeId === '') {
            $safeId = 'lbl' . ((int)$index + 1);
        }
        $hasX = is_numeric($entry['x'] ?? null);
        $hasY = is_numeric($entry['y'] ?? null);
        $x = $hasX ? max(0, min(100, (float)$entry['x'])) : null;
        $y = $hasY ? max(0, min(100, (float)$entry['y'])) : null;
        if ($x !== null && $y !== null && $x <= 1 && $y <= 1) {
            $x = null;
            $y = null;
        }
        $out[] = [
            'id' => $safeId,
            'text' => $text,
            'x' => $x,
            'y' => $y
        ];
    }
    return $out;
}

function audience_export_resolve_quiz_title(string $quizTitle, array $batch): string {
    $title = trim($quizTitle);
    if ($title !== '') {
        return $title;
    }
    if (isset($batch[0]) && is_array($batch[0])) {
        $fallback = audience_export_extract_question_plain_text($batch[0]['question'] ?? '');
        if ($fallback !== '') {
            return $fallback;
        }
    }
    return 'Questionnaire';
}

function audience_export_slugify_filename(string $value): string {
    $base = trim($value);
    if ($base === '') {
        return 'questionnaire';
    }
    if (function_exists('iconv')) {
        $converted = iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $base);
        if (is_string($converted) && $converted !== '') {
            $base = $converted;
        }
    }
    $base = strtolower($base);
    $base = preg_replace('/[^a-z0-9]+/', '-', $base) ?? '';
    $base = trim($base, '-');
    return $base !== '' ? $base : 'questionnaire';
}

function audience_export_archive_entry_name(int $index, string $quizTitle, string $code, array &$usedNames): string {
    $slug = audience_export_slugify_filename($quizTitle);
    $safeCode = preg_replace('/[^a-zA-Z0-9_-]+/', '-', trim($code)) ?? '';
    $safeCode = trim($safeCode, '-');
    $baseName = sprintf('%02d-%s', $index + 1, $slug);
    if ($safeCode !== '') {
        $baseName .= '-' . $safeCode;
    }
    $baseName = trim($baseName, '-');
    if ($baseName === '') {
        $baseName = sprintf('%02d-questionnaire', $index + 1);
    }
    $candidate = $baseName . '.md';
    $suffix = 2;
    while (isset($usedNames[$candidate])) {
        $candidate = $baseName . '-' . $suffix . '.md';
        $suffix++;
    }
    $usedNames[$candidate] = true;
    return $candidate;
}

function audience_export_build_quiz_markdown(string $quizTitle, string $code, array $batch, bool $participantReportEnabled = false, bool $requireParticipantName = true): string {
    $title = audience_export_resolve_quiz_title($quizTitle, $batch);
    $lines = [];
    $lines[] = '# ' . audience_export_escape_md($title);
    $lines[] = '';
    $lines[] = '- Code: `' . audience_export_escape_md($code) . '`';
    $lines[] = '- Nombre de questions: ' . count($batch);
    $lines[] = '- Rapport participant: ' . ($participantReportEnabled ? 'activé' : 'désactivé');
    $lines[] = '- Nom participant: ' . ($requireParticipantName ? 'requis' : 'optionnel');
    $lines[] = '';

    foreach ($batch as $index => $question) {
        if (!is_array($question)) {
            continue;
        }
        $qType = audience_export_normalize_question_type($question['type'] ?? '');
        $participantResponsesVisible = audience_export_normalize_participant_responses_visibility($question['participantResponsesVisible'] ?? true);

        $lines[] = '## Question ' . ((int)$index + 1);
        $lines[] = '';
        $lines[] = audience_export_escape_md(audience_export_extract_question_plain_text($question['question'] ?? ''));
        $lines[] = '';

        if ($qType === 'multiple') {
            $answers = is_array($question['answers'] ?? null) ? $question['answers'] : [];
            foreach ($answers as $answerIndex => $answer) {
                $isCorrect = (int)($question['correctIndex'] ?? 0) === (int)$answerIndex;
                $lines[] = '- ' . ($isCorrect ? '[x]' : '[ ]') . ' ' . audience_export_escape_md($answer);
            }
            $lines[] = '';
        } elseif ($qType === 'checkbox') {
            $lines[] = '- Type: cases à cocher';
            $answers = is_array($question['answers'] ?? null) ? $question['answers'] : [];
            $correctIndexes = [];
            if (is_array($question['correctIndexes'] ?? null)) {
                foreach ($question['correctIndexes'] as $value) {
                    if (is_numeric($value) && (int)$value >= 0) {
                        $correctIndexes[] = (int)$value;
                    }
                }
            } elseif (is_numeric($question['correctIndex'] ?? null) && (int)$question['correctIndex'] >= 0) {
                $correctIndexes[] = (int)$question['correctIndex'];
            }
            $correctIndexes = array_values(array_unique($correctIndexes));
            foreach ($answers as $answerIndex => $answer) {
                $isCorrect = in_array((int)$answerIndex, $correctIndexes, true);
                $lines[] = '- ' . ($isCorrect ? '[x]' : '[ ]') . ' ' . audience_export_escape_md($answer);
            }
            $lines[] = '';
        } elseif ($qType === 'open') {
            $lines[] = '- Type: question ouverte';
            if (audience_export_normalize_open_response_format($question['responseFormat'] ?? '') === 'math') {
                $lines[] = '- Format de réponse: mathématique';
            }
            $lines[] = '';
        } elseif ($qType === 'cloze') {
            $lines[] = '- Type: texte à trous';
            $lines[] = '- Texte à trous:';
            $lines[] = '```';
            $lines[] = trim((string)($question['clozeText'] ?? ''));
            $lines[] = '```';
            $lines[] = '';
        } elseif ($qType === 'wordcloud') {
            $lines[] = '- Type: nuage de mots';
            $lines[] = '';
        } elseif ($qType === 'rating') {
            $lines[] = '- Type: notation en étoiles (1 à 5)';
            $lines[] = '';
        } elseif ($qType === 'ranking') {
            $lines[] = '- Type: classement';
            $lines[] = '- Éléments à classer:';
            $lines[] = '```';
            $rankingItems = is_array($question['answers'] ?? null) ? $question['answers'] : [];
            foreach ($rankingItems as $item) {
                $lines[] = trim((string)$item);
            }
            $lines[] = '```';
            $lines[] = '';
        } elseif ($qType === 'video') {
            $lines[] = '- Type: vidéo YouTube';
            $lines[] = '- URL vidéo: ' . audience_export_escape_md($question['youtubeUrl'] ?? '');
            $startSec = audience_export_normalize_video_boundary_sec($question['videoStartSec'] ?? null);
            $endSec = audience_export_normalize_video_boundary_sec($question['videoEndSec'] ?? null);
            if ($startSec !== null) {
                $lines[] = '- Début vidéo (s): ' . $startSec;
            }
            if ($endSec !== null) {
                $lines[] = '- Fin vidéo (s): ' . $endSec;
            }
            $lines[] = '';
        } elseif ($qType === 'labelimage') {
            $imageUrl = audience_export_is_valid_question_image($question['questionImage'] ?? '') ? trim((string)($question['questionImage'] ?? '')) : '';
            $zoom = audience_export_normalize_question_image_zoom($question['questionImageZoom'] ?? 1);
            $labels = [];
            foreach (audience_export_normalize_legend_labels($question['legendLabels'] ?? []) as $labelIndex => $label) {
                if (($label['text'] ?? '') === '') {
                    continue;
                }
                $labels[] = [
                    'id' => (string)($label['id'] ?? ('lbl' . ($labelIndex + 1))),
                    'text' => (string)($label['text'] ?? ''),
                    'x' => $label['x'] === null ? null : round((float)$label['x'], 2),
                    'y' => $label['y'] === null ? null : round((float)$label['y'], 2)
                ];
            }
            $lines[] = '- Type: légender une image';
            $lines[] = '- Image: ' . audience_export_escape_md($imageUrl);
            $lines[] = '- Zoom image: ' . number_format($zoom, 2, '.', '');
            $lines[] = '- Étiquettes:';
            $lines[] = '```json';
            $json = json_encode($labels, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            foreach (explode("\n", (string)$json) as $jsonLine) {
                $lines[] = $jsonLine;
            }
            $lines[] = '```';
            $lines[] = '';
        }

        if ($qType !== 'video' && !$participantResponsesVisible) {
            array_splice($lines, count($lines) - 1, 0, '- Réponses des participants: masquées');
        }
    }

    return trim(implode("\n", $lines)) . "\n";
}
