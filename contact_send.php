<?php
declare(strict_types=1);

header("Content-Type: application/json; charset=UTF-8");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

require_once __DIR__ . '/lib/bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(["success" => false, "error" => "Methode non autorisee"]);
    exit;
}

require_same_origin_post(true);

$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) {
    http_response_code(400);
    echo json_encode(["success" => false, "error" => "JSON invalide"]);
    exit;
}

$name = trim((string)($input['name'] ?? ''));
$email = trim((string)($input['email'] ?? ''));
$subject = trim((string)($input['subject'] ?? ''));
$message = trim((string)($input['message'] ?? ''));

if ($name === '' || $email === '' || $subject === '' || $message === '') {
    http_response_code(400);
    echo json_encode(["success" => false, "error" => "Tous les champs sont obligatoires"]);
    exit;
}

if (mb_strlen($name) > 120 || mb_strlen($email) > 190 || mb_strlen($subject) > 190 || mb_strlen($message) > 4000) {
    http_response_code(400);
    echo json_encode(["success" => false, "error" => "Un ou plusieurs champs depassent la longueur autorisee"]);
    exit;
}

if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
    http_response_code(400);
    echo json_encode(["success" => false, "error" => "Adresse email invalide"]);
    exit;
}

if (
    app_rate_limit_exceeded('contact-ip', 6, 3600)
    || app_rate_limit_exceeded('contact-email', 3, 3600, $email)
) {
    http_response_code(429);
    echo json_encode([
        "success" => false,
        "error" => "Trop de messages envoyés récemment. Merci de réessayer plus tard."
    ]);
    exit;
}

$contactTo = trim((string)(
    app_env('CONTACT_TO_EMAIL')
    ?? app_env('CONTACT_RECIPIENT_EMAIL')
    ?? 'yannhoury@ralentirtravaux.com'
));
$contactFrom = app_default_from_email();

try {
    $db = app_db();
    $user = current_user();
    $userId = is_array($user) && isset($user['id']) ? (int)$user['id'] : null;

    if ($contactTo === '' || !filter_var($contactTo, FILTER_VALIDATE_EMAIL)) {
        $adminEmailStmt = $db->query("SELECT email FROM users WHERE role = 'admin' AND status = 'active' ORDER BY id ASC LIMIT 1");
        $adminEmail = (string)($adminEmailStmt->fetchColumn() ?: '');
        if (filter_var($adminEmail, FILTER_VALIDATE_EMAIL)) {
            $contactTo = $adminEmail;
        }
    }

    if ($contactTo === '' || !filter_var($contactTo, FILTER_VALIDATE_EMAIL)) {
        http_response_code(500);
        echo json_encode([
            "success" => false,
            "error" => "Aucune destination email configuree. Ajoutez CONTACT_TO_EMAIL ou un compte admin actif avec un email valide."
        ]);
        exit;
    }

    $stmt = $db->prepare("INSERT INTO contact_messages (user_id, name, email, subject, message)
        VALUES (:user_id, :name, :email, :subject, :message)");
    $stmt->bindValue(':user_id', $userId, $userId === null ? PDO::PARAM_NULL : PDO::PARAM_INT);
    $stmt->bindValue(':name', $name, PDO::PARAM_STR);
    $stmt->bindValue(':email', $email, PDO::PARAM_STR);
    $stmt->bindValue(':subject', $subject, PDO::PARAM_STR);
    $stmt->bindValue(':message', $message, PDO::PARAM_STR);
    $stmt->execute();

    $cleanSubject = preg_replace('/[\r\n]+/', ' ', $subject) ?? $subject;
    $cleanName = str_replace(["\r", "\n"], ' ', $name);
    $mailRef = strtoupper(substr(hash('sha256', uniqid('', true)), 0, 10));
    $mailSubject = '[Audience][' . $mailRef . '] ' . $cleanSubject;
    $mailSubject = mb_encode_mimeheader($mailSubject, 'UTF-8');
    $mailBody = "Nouveau message depuis le formulaire de contact Audience\n\n"
        . $message . "\n\n"
        . "-----\n"
        . "Nom: " . $cleanName . "\n"
        . "Email: " . $email . "\n"
        . "Sujet: " . $cleanSubject . "\n"
        . "Réf.: " . $mailRef . "\n"
        . "Date: " . gmdate('Y-m-d H:i:s') . " UTC\n";
    $mailBody = str_replace("\n", "\r\n", $mailBody);
    $messageIdHost = preg_replace('/[^a-z0-9.-]/i', '', (string)($_SERVER['HTTP_HOST'] ?? 'localhost')) ?: 'localhost';
    $messageId = sprintf('<%s@%s>', str_replace('.', '', uniqid('', true)), $messageIdHost);
    $headers = [
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset=UTF-8',
        'Content-Transfer-Encoding: 8bit',
        'Date: ' . gmdate('D, d M Y H:i:s') . ' +0000',
        'Message-ID: ' . $messageId,
        'X-Entity-Ref-ID: ' . $mailRef,
        'X-Mailer: Audience Contact Form',
        'From: Audience Contact <' . $contactFrom . '>',
        'Sender: ' . $contactFrom,
        'Reply-To: ' . $cleanName . ' <' . $email . '>'
    ];
    $mailSent = app_send_mail($contactTo, $mailSubject, $mailBody, $headers, $contactFrom);
    if (!$mailSent) {
        http_response_code(500);
        echo json_encode([
            "success" => false,
            "error" => "Message enregistre, mais l'envoi email a echoue. Verifiez la configuration mail du serveur."
        ]);
        exit;
    }

    $ackSubject = mb_encode_mimeheader('Nous avons bien reçu votre message - Audience', 'UTF-8');
    $ackBody = "Bonjour " . $cleanName . ",\r\n\r\n"
        . "Votre message a bien été reçu.\r\n"
        . "Référence : " . $mailRef . "\r\n"
        . "Sujet : " . $cleanSubject . "\r\n\r\n"
        . "Nous reviendrons vers vous dès que possible.\r\n\r\n"
        . "Audience\r\n";
    $ackHeaders = [
        'MIME-Version: 1.0',
        'Content-Type: text/plain; charset=UTF-8',
        'Content-Transfer-Encoding: 8bit',
        'From: Audience <' . $contactFrom . '>',
        'Sender: ' . $contactFrom,
        'Reply-To: ' . $contactFrom
    ];
    app_send_mail($email, $ackSubject, $ackBody, $ackHeaders, $contactFrom);

    echo json_encode(["success" => true, "message" => "Message envoyé avec succès."]);
} catch (PDOException $e) {
    app_json_error("Erreur interne.", $e);
}
