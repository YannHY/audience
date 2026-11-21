<?php
declare(strict_types=1);

require_once __DIR__ . '/lib/bootstrap.php';
require_once __DIR__ . '/lib/quiz_export.php';

function export_quizzes_redirect_with_error(string $message): void {
    $_SESSION['profile_msg_err'] = $message;
    header('Location: profile.php');
    exit;
}

$user = require_login_page();

if (strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET')) !== 'POST') {
    header('Location: profile.php');
    exit;
}

require_same_origin_post();

if (!class_exists('ZipArchive')) {
    export_quizzes_redirect_with_error("L'export ZIP n'est pas disponible sur ce serveur pour le moment.");
}

$db = app_db();
$stmt = $db->prepare("SELECT session_code, quiz_title, participant_report_enabled, require_participant_name, questions_json
    FROM session_batches
    WHERE owner_user_id = ? AND deleted_at IS NULL
    ORDER BY updated_at DESC");
$stmt->execute([(int)$user['id']]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

if (!$rows) {
    export_quizzes_redirect_with_error("Aucun questionnaire actif à exporter pour le moment.");
}

$zipPath = tempnam(sys_get_temp_dir(), 'audience-export-');
if ($zipPath === false) {
    export_quizzes_redirect_with_error("Impossible de préparer l'archive d'export.");
}

$zip = new ZipArchive();
$openResult = $zip->open($zipPath, ZipArchive::OVERWRITE);
if ($openResult !== true) {
    @unlink($zipPath);
    export_quizzes_redirect_with_error("Impossible de créer l'archive ZIP pour le moment.");
}

$usedNames = [];
$readmeLines = [
    "Export des questionnaires Audience",
    '',
    'Cette archive ZIP contient un fichier Markdown (.md) par questionnaire actif.',
    'Chaque fichier reprend le titre du questionnaire, son code et l\'ensemble de ses questions.'
];
$zip->addFromString('README.txt', implode("\r\n", $readmeLines) . "\r\n");

foreach ($rows as $index => $row) {
    $code = trim((string)($row['session_code'] ?? ''));
    if ($code === '') {
        continue;
    }
    $batch = json_decode((string)($row['questions_json'] ?? '[]'), true);
    if (!is_array($batch)) {
        $batch = [];
    }
    $title = audience_export_resolve_quiz_title((string)($row['quiz_title'] ?? ''), $batch);
    $entryName = audience_export_archive_entry_name((int)$index, $title, $code, $usedNames);
    $markdown = audience_export_build_quiz_markdown($title, $code, $batch, ((int)($row['participant_report_enabled'] ?? 0)) === 1, ((int)($row['require_participant_name'] ?? 1)) !== 0);
    $zip->addFromString($entryName, $markdown);
}

$zip->close();

$archiveFilename = 'audience-questionnaires-' . date('Ymd-His') . '.zip';
$filesize = filesize($zipPath);

while (ob_get_level() > 0) {
    ob_end_clean();
}

header('Content-Type: application/zip');
header('Content-Disposition: attachment; filename="' . $archiveFilename . '"');
if (is_int($filesize) && $filesize > 0) {
    header('Content-Length: ' . $filesize);
}
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');

readfile($zipPath);
@unlink($zipPath);
exit;
