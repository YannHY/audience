<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
require_once __DIR__ . '/lib/bootstrap.php';

$user = require_login_json();
$db = app_db();

$stmt = $db->prepare("SELECT session_code, quiz_title, questions_json, deleted_at
    FROM session_batches
    WHERE owner_user_id = ? AND deleted_at IS NOT NULL
    ORDER BY deleted_at DESC
    LIMIT 100");
$stmt->execute([(int)$user['id']]);
$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

$items = [];
foreach ($rows as $row) {
    $batch = json_decode((string)$row['questions_json'], true);
    if (!is_array($batch)) {
        $batch = [];
    }
    $title = trim((string)($row['quiz_title'] ?? ''));
    if ($title === '') {
        $title = count($batch) > 0 ? (string)($batch[0]['question'] ?? '') : '(sans titre)';
    }
    $items[] = [
        'code' => (string)$row['session_code'],
        'title' => $title,
        'questionCount' => count($batch),
        'deletedAt' => (string)$row['deleted_at']
    ];
}

echo json_encode(['success' => true, 'items' => $items]);

