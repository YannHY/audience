<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
require_once __DIR__ . '/lib/bootstrap.php';

/*
 * Organisation de l'accueil : dossiers et couleurs des questionnaires.
 * Actions (POST JSON, champ "action") :
 *   create_folder  { name, color?, codes? }  crée un dossier et y range les codes fournis
 *   update_folder  { id, name?, color? }
 *   delete_folder  { id }                     les questionnaires reviennent hors dossier
 *   move           { code, folderId|null }
 *   set_color      { code, color|null }        couleur propre à la carte (null = celle du dossier)
 *   set_tags       { code, tags: [] }          étiquettes libres du questionnaire
 * Aucune de ces actions ne modifie la date de modification des questionnaires.
 */

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(["success" => false, "error" => "Méthode non autorisée"]);
    exit;
}

require_same_origin_post(true);

$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) {
    echo json_encode(["success" => false, "error" => "Paramètres invalides"]);
    exit;
}

$user = require_login_json();
$userId = (int)$user['id'];
$db = app_db();
$action = (string)($input['action'] ?? '');

function organize_fail(string $message): void {
    echo json_encode(["success" => false, "error" => $message]);
    exit;
}

function organize_folder_name($value): string {
    $name = trim(preg_replace('/\s+/u', ' ', (string)$value) ?? '');
    if ($name === '') {
        $name = 'Nouveau dossier';
    }
    return mb_substr($name, 0, 80);
}

function organize_owned_folder(PDO $db, int $userId, $id): ?array {
    $folderId = (int)$id;
    if ($folderId <= 0) {
        return null;
    }
    $stmt = $db->prepare("SELECT id, name, color FROM quiz_folders WHERE id = ? AND owner_user_id = ?");
    $stmt->execute([$folderId, $userId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return null;
    }
    return [
        'id' => (int)$row['id'],
        'name' => (string)$row['name'],
        'color' => normalize_quiz_color($row['color']) ?? 'indigo'
    ];
}

function organize_owned_codes(PDO $db, int $userId, array $codes): array {
    $codes = array_values(array_unique(array_filter(array_map(function ($code) {
        return trim((string)$code);
    }, $codes), function ($code) {
        return $code !== '';
    })));
    if (count($codes) === 0) {
        return [];
    }
    $placeholders = implode(',', array_fill(0, count($codes), '?'));
    $stmt = $db->prepare("SELECT session_code FROM session_batches
        WHERE owner_user_id = ? AND deleted_at IS NULL AND session_code IN ($placeholders)");
    $stmt->execute(array_merge([$userId], $codes));
    return array_map(function ($row) {
        return (string)$row['session_code'];
    }, $stmt->fetchAll(PDO::FETCH_ASSOC));
}

if ($action === 'create_folder') {
    $name = organize_folder_name($input['name'] ?? '');
    $color = normalize_quiz_color($input['color'] ?? '') ?? 'indigo';
    $codes = organize_owned_codes($db, $userId, is_array($input['codes'] ?? null) ? $input['codes'] : []);

    $db->beginTransaction();
    $db->prepare("INSERT INTO quiz_folders (owner_user_id, name, color) VALUES (?, ?, ?)")
        ->execute([$userId, $name, $color]);
    $folderId = (int)$db->lastInsertId();
    if (count($codes) > 0) {
        $placeholders = implode(',', array_fill(0, count($codes), '?'));
        $db->prepare("UPDATE session_batches SET folder_id = ?, updated_at = updated_at
            WHERE owner_user_id = ? AND session_code IN ($placeholders)")
            ->execute(array_merge([$folderId, $userId], $codes));
    }
    $db->commit();

    echo json_encode(["success" => true, "folder" => ['id' => $folderId, 'name' => $name, 'color' => $color]]);
    exit;
}

if ($action === 'update_folder') {
    $folder = organize_owned_folder($db, $userId, $input['id'] ?? 0);
    if (!$folder) {
        organize_fail("Dossier introuvable");
    }
    if (array_key_exists('name', $input)) {
        $folder['name'] = organize_folder_name($input['name']);
    }
    if (array_key_exists('color', $input)) {
        $folder['color'] = normalize_quiz_color($input['color']) ?? 'indigo';
    }
    $db->prepare("UPDATE quiz_folders SET name = ?, color = ? WHERE id = ? AND owner_user_id = ?")
        ->execute([$folder['name'], $folder['color'], $folder['id'], $userId]);
    echo json_encode(["success" => true, "folder" => $folder]);
    exit;
}

if ($action === 'delete_folder') {
    $folder = organize_owned_folder($db, $userId, $input['id'] ?? 0);
    if (!$folder) {
        organize_fail("Dossier introuvable");
    }
    $db->beginTransaction();
    $db->prepare("UPDATE session_batches SET folder_id = NULL, updated_at = updated_at
        WHERE owner_user_id = ? AND folder_id = ?")->execute([$userId, $folder['id']]);
    $db->prepare("DELETE FROM quiz_folders WHERE id = ? AND owner_user_id = ?")->execute([$folder['id'], $userId]);
    $db->commit();
    echo json_encode(["success" => true, "id" => $folder['id']]);
    exit;
}

if ($action === 'move') {
    $codes = organize_owned_codes($db, $userId, [$input['code'] ?? '']);
    if (count($codes) === 0) {
        organize_fail("Questionnaire introuvable");
    }
    $folderId = null;
    if (($input['folderId'] ?? null) !== null) {
        $folder = organize_owned_folder($db, $userId, $input['folderId']);
        if (!$folder) {
            organize_fail("Dossier introuvable");
        }
        $folderId = $folder['id'];
    }
    $db->prepare("UPDATE session_batches SET folder_id = ?, updated_at = updated_at
        WHERE owner_user_id = ? AND session_code = ?")->execute([$folderId, $userId, $codes[0]]);
    echo json_encode(["success" => true, "code" => $codes[0], "folderId" => $folderId]);
    exit;
}

if ($action === 'set_color') {
    $codes = organize_owned_codes($db, $userId, [$input['code'] ?? '']);
    if (count($codes) === 0) {
        organize_fail("Questionnaire introuvable");
    }
    $color = normalize_quiz_color($input['color'] ?? '');
    $db->prepare("UPDATE session_batches SET card_color = ?, updated_at = updated_at
        WHERE owner_user_id = ? AND session_code = ?")->execute([$color, $userId, $codes[0]]);
    echo json_encode(["success" => true, "code" => $codes[0], "color" => $color]);
    exit;
}

if ($action === 'set_tags') {
    $codes = organize_owned_codes($db, $userId, [$input['code'] ?? '']);
    if (count($codes) === 0) {
        organize_fail("Questionnaire introuvable");
    }
    $tags = normalize_quiz_tags($input['tags'] ?? []);
    $db->prepare("UPDATE session_batches SET tags_json = ?, updated_at = updated_at
        WHERE owner_user_id = ? AND session_code = ?")
        ->execute([count($tags) > 0 ? json_encode($tags, JSON_UNESCAPED_UNICODE) : null, $userId, $codes[0]]);
    echo json_encode(["success" => true, "code" => $codes[0], "tags" => $tags]);
    exit;
}

organize_fail("Action inconnue");
