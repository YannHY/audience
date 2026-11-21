<?php
declare(strict_types=1);

function normalizeQuestionRichText($value): string {
    $raw = str_replace(["\r\n", "\r"], "\n", trim((string)$value));
    if ($raw === '') {
        return '';
    }

    if (strpos($raw, '<') === false) {
        // Questions may already contain HTML entities: keep them intact on every save.
        return nl2br(htmlspecialchars($raw, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8', false), false);
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

