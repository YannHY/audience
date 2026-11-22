<?php
declare(strict_types=1);

require_once __DIR__ . '/lib/bootstrap.php';
require_once __DIR__ . '/lib/participant_report_pdf.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode(['success' => false, 'error' => 'Methode non autorisee']);
    exit;
}

require_same_origin_post(true);

$inputJson = file_get_contents('php://input');
$input = json_decode($inputJson ?: '', true);
if (!is_array($input) || !is_array($input['report'] ?? null)) {
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode(['success' => false, 'error' => 'Rapport invalide']);
    exit;
}

try {
    $report = participant_report_pdf_prepare_report($input['report']);
    $pdf = participant_report_pdf_build($report, __DIR__ . '/img/logo/logo.png');
    $filename = participant_report_pdf_filename($report);

    header('Content-Type: application/pdf');
    header('Content-Disposition: attachment; filename="' . $filename . '"');
    header('Content-Length: ' . strlen($pdf));
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    echo $pdf;
} catch (Throwable $error) {
    http_response_code(400);
    header('Content-Type: application/json; charset=UTF-8');
    echo json_encode([
        'success' => false,
        'error' => $error->getMessage() !== '' ? $error->getMessage() : 'Impossible de generer le PDF'
    ]);
}
