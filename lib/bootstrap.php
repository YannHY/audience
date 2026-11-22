<?php
declare(strict_types=1);

if (session_status() !== PHP_SESSION_ACTIVE) {
    ini_set('session.use_strict_mode', '1');
    $isHttps = !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off';
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/',
        'secure' => $isHttps,
        'httponly' => true,
        'samesite' => 'Lax'
    ]);
    session_start();
}

function app_file_config(): array {
    static $config = null;
    if (is_array($config)) {
        return $config;
    }

    $config = [];
    $serverHome = dirname(dirname(dirname(dirname(__DIR__))));
    $homeFromEnv = trim((string)(getenv('HOME') ?: ''));
    $candidates = [];
    if ($homeFromEnv !== '') {
        $candidates[] = rtrim($homeFromEnv, '/\\') . '/audience-secrets.php';
    }
    if ($serverHome !== '') {
        $candidates[] = rtrim($serverHome, '/\\') . '/audience-secrets.php';
    }
    foreach ($candidates as $path) {
        if (!is_file($path)) {
            continue;
        }
        $loaded = require $path;
        if (is_array($loaded)) {
            $config = array_replace($config, $loaded);
        }
    }

    return $config;
}

function app_env(string $key): ?string {
    $envValue = getenv($key);
    if ($envValue !== false && $envValue !== '') {
        return (string)$envValue;
    }

    if (isset($_SERVER[$key]) && (string)$_SERVER[$key] !== '') {
        return (string)$_SERVER[$key];
    }

    $fileConfig = app_file_config();
    if (array_key_exists($key, $fileConfig) && (string)$fileConfig[$key] !== '') {
        return (string)$fileConfig[$key];
    }

    return null;
}

function app_is_https(): bool {
    return !empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off';
}

function app_normalize_origin(string $origin): string {
    $origin = trim($origin);
    if ($origin === '') {
        return '';
    }
    $parts = parse_url($origin);
    if (!is_array($parts)) {
        return '';
    }
    $scheme = strtolower((string)($parts['scheme'] ?? ''));
    $host = strtolower((string)($parts['host'] ?? ''));
    if (($scheme !== 'http' && $scheme !== 'https') || $host === '') {
        return '';
    }
    $port = isset($parts['port']) ? (int)$parts['port'] : null;
    $defaultPort = $scheme === 'https' ? 443 : 80;
    $portPart = ($port !== null && $port > 0 && $port !== $defaultPort) ? ':' . $port : '';
    return $scheme . '://' . $host . $portPart;
}

function app_request_origin(): string {
    $scheme = app_is_https() ? 'https' : 'http';
    $hostHeader = trim((string)($_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? 'localhost'));
    if ($hostHeader === '' || preg_match('/^[a-z0-9.-]+(?::[0-9]{1,5})?$/i', $hostHeader) !== 1) {
        $hostHeader = 'localhost';
    }
    $normalized = app_normalize_origin($scheme . '://' . $hostHeader);
    return $normalized !== '' ? $normalized : ($scheme . '://localhost');
}

function app_base_url(): string {
    $configured = trim((string)(app_env('APP_BASE_URL') ?? ''));
    if ($configured !== '') {
        return rtrim($configured, '/');
    }

    $scheme = app_is_https() ? 'https' : 'http';
    $host = trim((string)($_SERVER['SERVER_NAME'] ?? 'localhost'));
    $host = preg_replace('/[^a-z0-9.-]/i', '', $host) ?? '';
    if ($host === '') {
        $host = 'localhost';
    }
    $port = isset($_SERVER['SERVER_PORT']) ? (int)$_SERVER['SERVER_PORT'] : 0;
    $portPart = '';
    if (($scheme === 'http' && $port > 0 && $port !== 80) || ($scheme === 'https' && $port > 0 && $port !== 443)) {
        $portPart = ':' . $port;
    }
    $scriptDir = trim((string)dirname((string)($_SERVER['SCRIPT_NAME'] ?? '')));
    $scriptDir = str_replace('\\', '/', $scriptDir);
    if ($scriptDir === '/' || $scriptDir === '.') {
        $scriptDir = '';
    }
    return $scheme . '://' . $host . $portPart . $scriptDir;
}

function app_client_ip(): string {
    $ip = trim((string)($_SERVER['REMOTE_ADDR'] ?? ''));
    if ($ip === '') {
        return '0.0.0.0';
    }
    return substr($ip, 0, 64);
}

function app_rate_limit_subject(string $value): string {
    $normalized = strtolower(trim($value));
    if ($normalized === '') {
        return '';
    }
    $normalized = preg_replace('/\s+/u', ' ', $normalized) ?? '';
    return mb_substr($normalized, 0, 190, 'UTF-8');
}

function app_rate_limit_file(string $scope, string $subject = ''): string {
    $baseDir = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR);
    if ($baseDir === '') {
        $baseDir = __DIR__;
    }
    $key = hash('sha256', $scope . '|' . app_client_ip() . '|' . app_rate_limit_subject($subject));
    return $baseDir . DIRECTORY_SEPARATOR . 'audience-rate-' . $key . '.json';
}

function app_rate_limit_exceeded(string $scope, int $maxAttempts, int $windowSeconds, string $subject = ''): bool {
    $limit = max(1, min(500, $maxAttempts));
    $window = max(1, min(86400, $windowSeconds));
    $path = app_rate_limit_file($scope, $subject);
    $handle = @fopen($path, 'c+');
    if (!is_resource($handle)) {
        return false;
    }

    $blocked = false;
    try {
        if (!flock($handle, LOCK_EX)) {
            return false;
        }

        $raw = stream_get_contents($handle);
        $stored = json_decode(is_string($raw) ? $raw : '', true);
        $now = time();
        $resetAt = $now + $window;
        $count = 0;

        if (is_array($stored)) {
            $storedResetAt = isset($stored['reset_at']) ? (int)$stored['reset_at'] : 0;
            $storedCount = isset($stored['count']) ? (int)$stored['count'] : 0;
            if ($storedResetAt > $now) {
                $resetAt = $storedResetAt;
                $count = max(0, $storedCount);
            }
        }

        $count++;
        $blocked = $count > $limit;

        $payload = json_encode([
            'count' => $count,
            'reset_at' => $resetAt
        ]);
        if (is_string($payload)) {
            rewind($handle);
            ftruncate($handle, 0);
            fwrite($handle, $payload);
            fflush($handle);
        }
    } finally {
        flock($handle, LOCK_UN);
        fclose($handle);
    }

    return $blocked;
}

function app_rate_limit_clear(string $scope, string $subject = ''): void {
    $path = app_rate_limit_file($scope, $subject);
    if (is_file($path)) {
        @unlink($path);
    }
}

function app_mail_host(): string {
    $host = trim((string)($_SERVER['HTTP_HOST'] ?? $_SERVER['SERVER_NAME'] ?? 'localhost'));
    $host = strtolower(preg_replace('/[^a-z0-9.-]/i', '', $host) ?? '');
    return $host !== '' ? $host : 'localhost';
}

function app_default_from_email(): string {
    $configured = trim((string)(
        app_env('CONTACT_FROM_EMAIL')
        ?? app_env('MAIL_FROM_EMAIL')
        ?? app_env('APP_MAIL_FROM_EMAIL')
        ?? ''
    ));
    if ($configured !== '' && filter_var($configured, FILTER_VALIDATE_EMAIL)) {
        return $configured;
    }

    return 'no-reply@' . app_mail_host();
}

function app_send_mail(string $to, string $subject, string $body, array $headers = [], ?string $envelopeFrom = null): bool {
    $recipient = trim($to);
    if ($recipient === '' || !filter_var($recipient, FILTER_VALIDATE_EMAIL)) {
        return false;
    }

    $headerLines = [];
    foreach ($headers as $header) {
        $line = trim((string)$header);
        if ($line === '') {
            continue;
        }
        $headerLines[] = str_replace(["\r", "\n"], '', $line);
    }

    $sender = trim((string)($envelopeFrom ?? ''));
    if ($sender === '' || !filter_var($sender, FILTER_VALIDATE_EMAIL)) {
        $sender = app_default_from_email();
    }

    $params = '-f' . $sender;
    $sent = @mail($recipient, $subject, $body, implode("\r\n", $headerLines), $params);
    if (!$sent) {
        error_log('[audience][mail] Echec envoi mail vers ' . $recipient . ' avec expéditeur ' . $sender);
    }

    return $sent;
}

function require_same_origin_post(bool $jsonResponse = false): void {
    if (strtoupper((string)($_SERVER['REQUEST_METHOD'] ?? 'GET')) !== 'POST') {
        return;
    }

    $expectedOrigin = app_request_origin();
    $origin = app_normalize_origin((string)($_SERVER['HTTP_ORIGIN'] ?? ''));
    if ($origin !== '') {
        if (hash_equals($expectedOrigin, $origin)) {
            return;
        }
    } else {
        $referer = trim((string)($_SERVER['HTTP_REFERER'] ?? ''));
        if ($referer !== '') {
            $refererParts = parse_url($referer);
            if (is_array($refererParts)) {
                $refererScheme = strtolower((string)($refererParts['scheme'] ?? ''));
                $refererHost = strtolower((string)($refererParts['host'] ?? ''));
                $refererPort = isset($refererParts['port']) ? (int)$refererParts['port'] : null;
                $defaultPort = $refererScheme === 'https' ? 443 : 80;
                $refererPortPart = ($refererPort !== null && $refererPort > 0 && $refererPort !== $defaultPort) ? ':' . $refererPort : '';
                $refererOrigin = ($refererScheme === 'http' || $refererScheme === 'https')
                    ? ($refererScheme . '://' . $refererHost . $refererPortPart)
                    : '';
                if ($refererOrigin !== '' && hash_equals($expectedOrigin, $refererOrigin)) {
                    return;
                }
            }
        }
    }

    http_response_code(403);
    if ($jsonResponse) {
        if (!headers_sent()) {
            header("Content-Type: application/json; charset=UTF-8");
        }
        echo json_encode(["success" => false, "error" => "Requête refusée"]);
    } else {
        echo "Requête refusée.";
    }
    exit;
}

function app_json_error(string $publicMessage, ?Throwable $e = null, int $status = 500): void {
    if ($e !== null) {
        try {
            $ref = bin2hex(random_bytes(4));
        } catch (Throwable $_) {
            $ref = substr(sha1(uniqid('', true)), 0, 8);
        }
        error_log('[audience][' . $ref . '] ' . $e->getMessage());
    }
    http_response_code($status);
    echo json_encode([
        "success" => false,
        "error" => $publicMessage,
        "message" => $publicMessage
    ]);
    exit;
}

function app_db(): PDO {
    static $db = null;
    if ($db instanceof PDO) {
        return $db;
    }

    $dsn = trim((string)(app_env('APP_DB_DSN') ?? ''));
    $dbUser = (string)(app_env('APP_DB_USER') ?? '');
    $dbPass = (string)(app_env('APP_DB_PASS') ?? '');
    if ($dsn === '') {
        $dbHost = trim((string)(app_env('APP_DB_HOST') ?? ''));
        $dbName = trim((string)(app_env('APP_DB_NAME') ?? ''));
        if ($dbHost !== '' && $dbName !== '') {
            $dsn = "mysql:host={$dbHost};dbname={$dbName};charset=utf8mb4";
        }
    }
    if ($dsn === '' || $dbUser === '') {
        throw new RuntimeException("Configuration base de données manquante (APP_DB_DSN ou APP_DB_HOST/APP_DB_NAME + APP_DB_USER + APP_DB_PASS).");
    }

    $db = new PDO(
        $dsn,
        $dbUser,
        $dbPass
    );
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    ensure_app_tables($db);
    return $db;
}

function ensure_app_tables(PDO $db): void {
    $db->exec("CREATE TABLE IF NOT EXISTS users (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(80) NOT NULL UNIQUE,
        email VARCHAR(190) NOT NULL UNIQUE,
        password_hash VARCHAR(255) NOT NULL,
        role ENUM('admin','presenter') NOT NULL DEFAULT 'presenter',
        status ENUM('active','disabled') NOT NULL DEFAULT 'active',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $userColumns = [
        "ALTER TABLE users ADD COLUMN username VARCHAR(80) NULL",
        "ALTER TABLE users ADD UNIQUE INDEX idx_users_username (username)",
        "ALTER TABLE users ADD COLUMN last_login_at DATETIME NULL",
        "ALTER TABLE users ADD COLUMN terms_accepted_at DATETIME NULL"
    ];
    foreach ($userColumns as $sql) {
        try {
            $db->exec($sql);
        } catch (PDOException $e) {
            // Ignore: already exists
        }
    }
    $db->exec("UPDATE users
        SET username = LEFT(CONCAT(SUBSTRING_INDEX(email, '@', 1), '_', id), 80)
        WHERE (username IS NULL OR username = '')");
    try {
        $db->exec("ALTER TABLE users MODIFY username VARCHAR(80) NOT NULL");
    } catch (PDOException $e) {
        // Ignore if already in desired state
    }

    $db->exec("CREATE TABLE IF NOT EXISTS session_batches (
        session_code VARCHAR(10) PRIMARY KEY,
        owner_user_id INT UNSIGNED NULL,
        quiz_title VARCHAR(255) NOT NULL DEFAULT '',
        participant_report_enabled TINYINT(1) NOT NULL DEFAULT 0,
        require_participant_name TINYINT(1) NOT NULL DEFAULT 1,
        questions_json LONGTEXT NOT NULL,
        current_index INT NOT NULL DEFAULT 0,
        current_question_started_at DATETIME NULL,
        live_active TINYINT(1) NOT NULL DEFAULT 0,
        is_favorite TINYINT(1) NOT NULL DEFAULT 0,
        deleted_at DATETIME NULL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_owner_user (owner_user_id),
        INDEX idx_deleted_at (deleted_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $columns = [
        "ALTER TABLE session_batches ADD COLUMN owner_user_id INT UNSIGNED NULL",
        "ALTER TABLE session_batches ADD COLUMN quiz_title VARCHAR(255) NOT NULL DEFAULT ''",
        "ALTER TABLE session_batches ADD COLUMN participant_report_enabled TINYINT(1) NOT NULL DEFAULT 0",
        "ALTER TABLE session_batches ADD COLUMN require_participant_name TINYINT(1) NOT NULL DEFAULT 1",
        "ALTER TABLE session_batches ADD COLUMN live_active TINYINT(1) NOT NULL DEFAULT 0",
        "ALTER TABLE session_batches ADD COLUMN is_favorite TINYINT(1) NOT NULL DEFAULT 0",
        "ALTER TABLE session_batches ADD COLUMN current_question_started_at DATETIME NULL",
        "ALTER TABLE session_batches ADD COLUMN deleted_at DATETIME NULL",
        "ALTER TABLE session_batches ADD INDEX idx_owner_user (owner_user_id)",
        "ALTER TABLE session_batches ADD COLUMN folder_id INT UNSIGNED NULL",
        "ALTER TABLE session_batches ADD COLUMN card_color VARCHAR(20) NULL",
        "ALTER TABLE session_batches ADD COLUMN tags_json TEXT NULL",
        "ALTER TABLE session_batches ADD INDEX idx_folder (folder_id)"
    ];
    foreach ($columns as $sql) {
        try {
            $db->exec($sql);
        } catch (PDOException $e) {
            // Ignore: already exists
        }
    }

    $db->exec("CREATE TABLE IF NOT EXISTS quiz_folders (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        owner_user_id INT UNSIGNED NOT NULL,
        name VARCHAR(80) NOT NULL DEFAULT '',
        color VARCHAR(20) NOT NULL DEFAULT 'indigo',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_folder_owner (owner_user_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS session_responses (
        session_code VARCHAR(10) NOT NULL,
        question_index INT NOT NULL,
        answer_index INT NOT NULL,
        count INT NOT NULL DEFAULT 0,
        PRIMARY KEY (session_code, question_index, answer_index)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS session_open_responses (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        session_code VARCHAR(10) NOT NULL,
        question_index INT NOT NULL,
        response_text TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_session_question (session_code, question_index)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS session_response_details (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        session_code VARCHAR(10) NOT NULL,
        question_index INT NOT NULL,
        run_id VARCHAR(80) NOT NULL DEFAULT '',
        voter_hash CHAR(64) NOT NULL,
        participant_name VARCHAR(80) NOT NULL DEFAULT '',
        response_text TEXT NOT NULL,
        response_payload LONGTEXT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE INDEX uniq_response_detail (session_code, question_index, run_id, voter_hash),
        INDEX idx_response_detail_session_question (session_code, question_index),
        INDEX idx_response_detail_session_participant (session_code, participant_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $responseDetailColumns = [
        "ALTER TABLE session_response_details ADD COLUMN run_id VARCHAR(80) NOT NULL DEFAULT ''",
        "ALTER TABLE session_response_details ADD COLUMN participant_name VARCHAR(80) NOT NULL DEFAULT ''",
        "ALTER TABLE session_response_details ADD COLUMN response_payload LONGTEXT NULL",
        "ALTER TABLE session_response_details ADD INDEX idx_response_detail_session_question (session_code, question_index)",
        "ALTER TABLE session_response_details ADD INDEX idx_response_detail_session_participant (session_code, participant_name)"
    ];
    foreach ($responseDetailColumns as $sql) {
        try {
            $db->exec($sql);
        } catch (PDOException $e) {
            // Ignore: already exists
        }
    }
    try {
        $db->exec("ALTER TABLE session_response_details ADD UNIQUE INDEX uniq_response_detail (session_code, question_index, run_id, voter_hash)");
    } catch (PDOException $e) {
        // Ignore if already in desired state
    }

    $db->exec("CREATE TABLE IF NOT EXISTS session_vote_locks (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        session_code VARCHAR(10) NOT NULL,
        question_index INT NOT NULL,
        run_id VARCHAR(80) NOT NULL DEFAULT '',
        voter_hash CHAR(64) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE INDEX uniq_vote_lock (session_code, question_index, run_id, voter_hash),
        INDEX idx_vote_lock_session (session_code),
        INDEX idx_vote_lock_created_at (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $voteLockColumns = [
        "ALTER TABLE session_vote_locks ADD COLUMN run_id VARCHAR(80) NOT NULL DEFAULT ''",
        "ALTER TABLE session_vote_locks ADD INDEX idx_vote_lock_session (session_code)",
        "ALTER TABLE session_vote_locks ADD INDEX idx_vote_lock_created_at (created_at)"
    ];
    foreach ($voteLockColumns as $sql) {
        try {
            $db->exec($sql);
        } catch (PDOException $e) {
            // Ignore: already exists
        }
    }

    $db->exec("CREATE TABLE IF NOT EXISTS session_presence (
        session_code VARCHAR(10) NOT NULL,
        viewer_token VARCHAR(120) NOT NULL,
        last_seen DATETIME NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (session_code, viewer_token),
        INDEX idx_presence_last_seen (last_seen),
        INDEX idx_presence_session_last_seen (session_code, last_seen)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $presenceColumns = [
        "ALTER TABLE session_presence ADD COLUMN last_seen DATETIME NULL",
        "ALTER TABLE session_presence ADD INDEX idx_presence_last_seen (last_seen)",
        "ALTER TABLE session_presence ADD INDEX idx_presence_session_last_seen (session_code, last_seen)"
    ];
    foreach ($presenceColumns as $sql) {
        try {
            $db->exec($sql);
        } catch (PDOException $e) {
            // Ignore: already exists
        }
    }
    try {
        $db->exec("UPDATE session_presence SET last_seen = created_at WHERE last_seen IS NULL");
    } catch (PDOException $e) {
        // Ignore migration issue on legacy schemas.
    }
    try {
        $db->exec("ALTER TABLE session_presence MODIFY last_seen DATETIME NOT NULL");
    } catch (PDOException $e) {
        // Ignore if already in desired state.
    }

    $db->exec("CREATE TABLE IF NOT EXISTS contact_messages (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        user_id INT UNSIGNED NULL,
        name VARCHAR(120) NOT NULL,
        email VARCHAR(190) NOT NULL,
        subject VARCHAR(190) NOT NULL,
        message TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_contact_created_at (created_at),
        INDEX idx_contact_email (email)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $db->exec("CREATE TABLE IF NOT EXISTS password_reset_tokens (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        user_id INT UNSIGNED NOT NULL,
        token_hash CHAR(64) NOT NULL,
        expires_at DATETIME NOT NULL,
        used_at DATETIME NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        UNIQUE INDEX uniq_reset_token_hash (token_hash),
        INDEX idx_reset_user (user_id),
        INDEX idx_reset_expires (expires_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");

    $resetColumns = [
        "ALTER TABLE password_reset_tokens ADD COLUMN used_at DATETIME NULL",
        "ALTER TABLE password_reset_tokens ADD INDEX idx_reset_user (user_id)",
        "ALTER TABLE password_reset_tokens ADD INDEX idx_reset_expires (expires_at)"
    ];
    foreach ($resetColumns as $sql) {
        try {
            $db->exec($sql);
        } catch (PDOException $e) {
            // Ignore: already exists
        }
    }
}

function is_valid_presence_token(string $token): bool {
    return (bool)preg_match('/^[a-zA-Z0-9_-]{16,120}$/', $token);
}

function app_presence_viewer_token(?string $clientToken = null): string {
    $sessionId = trim(session_id());
    if ($sessionId !== '') {
        return 'sess_' . hash('sha256', $sessionId);
    }

    $token = trim((string)$clientToken);
    if (is_valid_presence_token($token)) {
        return 'tok_' . hash('sha256', $token);
    }

    $userAgent = substr(trim((string)($_SERVER['HTTP_USER_AGENT'] ?? '')), 0, 255);
    return 'net_' . hash('sha256', app_client_ip() . '|' . $userAgent);
}

function app_touch_session_presence(PDO $db, string $sessionCode, string $viewerToken): void {
    $code = trim($sessionCode);
    $token = trim($viewerToken);
    if ($code === '' || !is_valid_presence_token($token)) {
        return;
    }

    $stmt = $db->prepare("INSERT INTO session_presence (session_code, viewer_token, last_seen)
        VALUES (?, ?, NOW())
        ON DUPLICATE KEY UPDATE last_seen = NOW()");
    $stmt->execute([$code, $token]);

    if (mt_rand(1, 200) === 1) {
        $cleanup = $db->prepare("DELETE FROM session_presence WHERE last_seen < (NOW() - INTERVAL 2 DAY)");
        $cleanup->execute();
    }
}

function app_count_session_presence(PDO $db, string $sessionCode, int $windowSeconds = 20): int {
    $code = trim($sessionCode);
    if ($code === '') {
        return 0;
    }

    $window = max(6, min(300, $windowSeconds));
    $stmt = $db->prepare("SELECT COUNT(*) FROM session_presence
        WHERE session_code = ?
        AND last_seen >= (NOW() - INTERVAL {$window} SECOND)");
    $stmt->execute([$code]);
    return (int)$stmt->fetchColumn();
}

function app_purge_session_presence(PDO $db, string $sessionCode): void {
    $code = trim($sessionCode);
    if ($code === '') {
        return;
    }
    $stmt = $db->prepare("DELETE FROM session_presence WHERE session_code = ?");
    $stmt->execute([$code]);
}

function app_question_start_buffer_seconds(): int {
    $raw = app_env('APP_QUESTION_START_BUFFER_SEC');
    $seconds = is_numeric($raw) ? (int)$raw : 2;
    return max(0, min(15, $seconds));
}

function app_compute_question_start_timestamp(): array {
    $startSec = (int)ceil(microtime(true) + app_question_start_buffer_seconds());
    return [
        'unix' => $startSec,
        'ms' => $startSec * 1000,
        'sql' => date('Y-m-d H:i:s', $startSec)
    ];
}

function current_user(): ?array {
    if (!isset($_SESSION['user']) || !is_array($_SESSION['user'])) {
        return null;
    }
    return $_SESSION['user'];
}

function ensure_last_login_initialized(array $user): void {
    $userId = (int)($user['id'] ?? 0);
    if ($userId <= 0) {
        return;
    }
    try {
        $db = app_db();
        $stmt = $db->prepare("UPDATE users SET last_login_at = NOW() WHERE id = ? AND last_login_at IS NULL");
        $stmt->execute([$userId]);
    } catch (Throwable $e) {
        // Ne bloque jamais l'authentification sur ce suivi.
    }
}

/**
 * Relit le compte en base : un compte supprimé ou désactivé perd sa session
 * immédiatement, et un changement de rôle s'applique sans reconnexion.
 * En cas d'erreur de base, la session est conservée (on ne bloque pas l'accès).
 */
function refresh_session_user(?array $user): ?array {
    if (!$user) {
        return null;
    }
    $userId = (int)($user['id'] ?? 0);
    if ($userId <= 0) {
        return $user;
    }
    try {
        $stmt = app_db()->prepare("SELECT username, email, role, status FROM users WHERE id = ? LIMIT 1");
        $stmt->execute([$userId]);
        $row = $stmt->fetch(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        return $user;
    }
    if (!$row || (string)$row['status'] !== 'active') {
        $_SESSION = [];
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_regenerate_id(true);
        }
        return null;
    }
    $user['username'] = (string)$row['username'];
    $user['email'] = (string)$row['email'];
    $user['role'] = (string)$row['role'];
    $_SESSION['user'] = $user;
    return $user;
}

/**
 * Supprime un compte et toutes ses données (questionnaires, réponses, dossiers,
 * messages). À appeler dans une transaction.
 */
function app_delete_user_data(PDO $db, int $userId): void {
    $batchCodesStmt = $db->prepare("SELECT session_code FROM session_batches WHERE owner_user_id = ?");
    $batchCodesStmt->execute([$userId]);
    $codes = array_values(array_filter(array_map(function ($r) {
        return (string)($r['session_code'] ?? '');
    }, $batchCodesStmt->fetchAll(PDO::FETCH_ASSOC))));

    if (count($codes) > 0) {
        $placeholders = implode(',', array_fill(0, count($codes), '?'));
        foreach (['session_responses', 'session_open_responses', 'session_response_details', 'session_vote_locks', 'session_presence'] as $table) {
            $db->prepare("DELETE FROM {$table} WHERE session_code IN ($placeholders)")->execute($codes);
        }
    }

    $db->prepare("DELETE FROM session_batches WHERE owner_user_id = ?")->execute([$userId]);
    $db->prepare("DELETE FROM quiz_folders WHERE owner_user_id = ?")->execute([$userId]);
    $db->prepare("DELETE FROM contact_messages WHERE user_id = ?")->execute([$userId]);
    $db->prepare("DELETE FROM password_reset_tokens WHERE user_id = ?")->execute([$userId]);
    $db->prepare("DELETE FROM users WHERE id = ?")->execute([$userId]);
}

function require_login_json(): array {
    $user = refresh_session_user(current_user());
    if (!$user) {
        http_response_code(401);
        echo json_encode(["success" => false, "error" => "Authentification requise"]);
        exit;
    }
    ensure_last_login_initialized($user);
    return $user;
}

function require_login_page(): array {
    $user = refresh_session_user(current_user());
    if (!$user) {
        header('Location: login.php');
        exit;
    }
    ensure_last_login_initialized($user);
    return $user;
}

function require_admin_page(): array {
    $user = require_login_page();
    if (($user['role'] ?? '') !== 'admin') {
        http_response_code(403);
        echo "Accès refusé.";
        exit;
    }
    return $user;
}

function is_admin_seed_needed(PDO $db): bool {
    $stmt = $db->query("SELECT COUNT(*) FROM users WHERE role = 'admin'");
    return ((int)$stmt->fetchColumn()) === 0;
}

function sanitize_username(string $value): string {
    $value = trim($value);
    $value = preg_replace('/\s+/u', '_', $value) ?? '';
    $value = preg_replace('/[^\p{L}\p{N}_.-]/u', '', $value) ?? '';
    return mb_substr($value, 0, 80, 'UTF-8');
}

function sanitize_participant_name(string $value): string {
    $value = str_replace(["\r", "\n", "\t"], ' ', $value);
    $value = preg_replace('/\s+/u', ' ', trim($value)) ?? '';
    return mb_substr($value, 0, 80, 'UTF-8');
}

/**
 * Couleurs autorisées pour les dossiers et les cartes de questionnaires.
 */
function quiz_color_keys(): array {
    return ['indigo', 'blue', 'teal', 'green', 'amber', 'rose', 'slate'];
}

function normalize_quiz_color($value): ?string {
    $key = strtolower(trim((string)$value));
    return in_array($key, quiz_color_keys(), true) ? $key : null;
}

/**
 * Étiquettes libres d'un questionnaire : 12 au plus, 30 caractères chacune,
 * sans doublon (insensible à la casse).
 */
function normalize_quiz_tags($value): array {
    if (is_string($value)) {
        $decoded = json_decode($value, true);
        $value = is_array($decoded) ? $decoded : [];
    }
    if (!is_array($value)) {
        return [];
    }
    $tags = [];
    $seen = [];
    foreach ($value as $tag) {
        $tag = trim(preg_replace('/\s+/u', ' ', (string)$tag) ?? '');
        $tag = ltrim($tag, '#');
        if ($tag === '') {
            continue;
        }
        $tag = mb_substr($tag, 0, 30);
        $key = mb_strtolower($tag);
        if (isset($seen[$key])) {
            continue;
        }
        $seen[$key] = true;
        $tags[] = $tag;
        if (count($tags) >= 12) {
            break;
        }
    }
    return $tags;
}
