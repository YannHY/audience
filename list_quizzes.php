<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
require_once __DIR__ . '/lib/bootstrap.php';

$user = require_login_json();
$db = app_db();
$userId = (int)$user['id'];

$stmt = $db->prepare("SELECT session_code, quiz_title, questions_json, current_index, live_active, is_favorite, folder_id, card_color, tags_json, updated_at
    FROM session_batches
    WHERE owner_user_id = ? AND deleted_at IS NULL
    ORDER BY updated_at DESC
    LIMIT 300");
$stmt->execute([$userId]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

$folderStmt = $db->prepare("SELECT id, name, color FROM quiz_folders WHERE owner_user_id = ? ORDER BY name ASC, id ASC");
$folderStmt->execute([$userId]);
$folders = [];
$folderIds = [];
foreach ($folderStmt->fetchAll(PDO::FETCH_ASSOC) as $folder) {
    $id = (int)$folder['id'];
    $folderIds[$id] = true;
    $folders[] = [
        'id' => $id,
        'name' => (string)$folder['name'],
        'color' => normalize_quiz_color($folder['color']) ?? 'indigo'
    ];
}

$items = [];
foreach ($rows as $row) {
    $batch = json_decode((string)$row['questions_json'], true);
    if (!is_array($batch)) {
        $batch = [];
    }
    $count = count($batch);
    $title = trim((string)($row['quiz_title'] ?? ''));
    if ($title === '') {
        $title = $count > 0 ? (string)($batch[0]['question'] ?? '') : '';
    }
    $folderId = $row['folder_id'] !== null ? (int)$row['folder_id'] : null;
    if ($folderId !== null && !isset($folderIds[$folderId])) {
        $folderId = null;
    }
    $items[] = [
        'code' => (string)$row['session_code'],
        'title' => $title,
        'questionCount' => $count,
        'currentIndex' => (int)$row['current_index'],
        'liveActive' => ((int)$row['live_active']) === 1,
        'isFavorite' => ((int)($row['is_favorite'] ?? 0)) === 1,
        'folderId' => $folderId,
        'color' => normalize_quiz_color($row['card_color'] ?? ''),
        'tags' => normalize_quiz_tags($row['tags_json'] ?? ''),
        'updatedAt' => (string)$row['updated_at']
    ];
}

echo json_encode(['success' => true, 'items' => $items, 'folders' => $folders]);
