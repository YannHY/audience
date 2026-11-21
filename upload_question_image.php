<?php
declare(strict_types=1);
header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST, OPTIONS");
require_once __DIR__ . '/lib/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(["success" => false, "error" => "Methode non autorisee"]);
    exit;
}

require_same_origin_post(true);

try {
    $user = require_login_json();
    if (!isset($_FILES['image']) || !is_array($_FILES['image'])) {
        echo json_encode(["success" => false, "error" => "Fichier image manquant"]);
        exit;
    }

    $file = $_FILES['image'];
    $error = (int)($file['error'] ?? UPLOAD_ERR_NO_FILE);
    if ($error !== UPLOAD_ERR_OK) {
        echo json_encode(["success" => false, "error" => "Erreur d'upload (code $error)"]);
        exit;
    }

    $tmpName = (string)($file['tmp_name'] ?? '');
    if ($tmpName === '' || !is_uploaded_file($tmpName)) {
        echo json_encode(["success" => false, "error" => "Fichier temporaire invalide"]);
        exit;
    }

    $size = (int)($file['size'] ?? 0);
    if ($size <= 0 || $size > (2 * 1024 * 1024)) {
        echo json_encode(["success" => false, "error" => "Image trop volumineuse (2 Mo maximum)"]);
        exit;
    }

    $finfo = finfo_open(FILEINFO_MIME_TYPE);
    $mime = $finfo ? (string)finfo_file($finfo, $tmpName) : '';
    if ($finfo) {
        finfo_close($finfo);
    }

    $allowed = [
        'image/png' => 'png',
        'image/jpeg' => 'jpg',
        'image/webp' => 'webp',
        'image/gif' => 'gif'
    ];
    if (!isset($allowed[$mime])) {
        echo json_encode(["success" => false, "error" => "Format non supporte"]);
        exit;
    }

    $code = trim((string)($_POST['code'] ?? ''));
    if ($code === '') {
        $code = 'draft_' . (string)((int)$user['id']);
    }
    $safeCode = preg_replace('/[^a-zA-Z0-9_-]/', '', $code);
    if ($safeCode === '') {
        $safeCode = 'default';
    }

    $dir = __DIR__ . '/uploads/questions/' . $safeCode;
    if (!is_dir($dir) && !mkdir($dir, 0755, true) && !is_dir($dir)) {
        throw new RuntimeException("Impossible de creer le dossier d'upload");
    }

    $payload = file_get_contents($tmpName);
    if ($payload === false || $payload === '') {
        throw new RuntimeException("Fichier image vide");
    }
    $hash = sha1($payload);
    $ext = $allowed[$mime];
    $fileName = $hash . '.' . $ext;
    $target = $dir . '/' . $fileName;

    if (!is_file($target)) {
        if (!move_uploaded_file($tmpName, $target)) {
            if (file_put_contents($target, $payload) === false) {
                throw new RuntimeException("Impossible d'enregistrer l'image");
            }
        }
    }

    echo json_encode([
        "success" => true,
        "imageUrl" => 'uploads/questions/' . $safeCode . '/' . $fileName
    ]);
} catch (Throwable $e) {
    app_json_error("Erreur interne.", $e);
}
?>
