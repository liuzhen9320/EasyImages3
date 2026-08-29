<?php

function install_random_token()
{
    if (function_exists('random_bytes')) {
        $random = random_bytes(32);
    } elseif (function_exists('openssl_random_pseudo_bytes')) {
        $random = openssl_random_pseudo_bytes(32);
    } else {
        return false;
    }

    return $random === false ? false : bin2hex($random);
}

function install_issue_token($step)
{
    if (!is_string($step) || !preg_match('/\A[a-z_]+\z/', $step) || !csrf_session_start()) {
        return false;
    }

    $token = install_random_token();
    if ($token === false) {
        return false;
    }

    if (!isset($_SESSION['_install_tokens']) || !is_array($_SESSION['_install_tokens'])) {
        $_SESSION['_install_tokens'] = array();
    }
    $_SESSION['_install_tokens'][$step] = array(
        'token' => $token,
        'expires' => time() + 900
    );

    return $token;
}

function install_consume_token($step, $token)
{
    if (!is_string($token) || !csrf_session_start()
        || empty($_SESSION['_install_tokens'][$step])
        || !is_array($_SESSION['_install_tokens'][$step])) {
        return false;
    }

    $entry = $_SESSION['_install_tokens'][$step];
    unset($_SESSION['_install_tokens'][$step]);
    if (empty($entry['token']) || !is_string($entry['token'])
        || empty($entry['expires']) || $entry['expires'] < time()) {
        return false;
    }

    return hash_equals($entry['token'], $token);
}

function install_normalize_url($url)
{
    if (!is_string($url)) {
        return false;
    }

    $url = rtrim(trim($url), '/');
    $parts = parse_url($url);
    if ($url === '' || filter_var($url, FILTER_VALIDATE_URL) === false || !is_array($parts)
        || empty($parts['scheme']) || empty($parts['host'])
        || !in_array(strtolower($parts['scheme']), array('http', 'https'), true)
        || isset($parts['user']) || isset($parts['pass']) || isset($parts['query']) || isset($parts['fragment'])) {
        return false;
    }

    return $url;
}

function install_acquire_lock($filename)
{
    $handle = @fopen($filename, 'c');
    if ($handle === false || !flock($handle, LOCK_EX)) {
        if (is_resource($handle)) {
            fclose($handle);
        }
        return false;
    }

    return $handle;
}

function install_release_lock($handle, $filename)
{
    if (is_resource($handle)) {
        flock($handle, LOCK_UN);
        fclose($handle);
    }
}

function install_write_config_and_lock($configFile, $lockFile, array $values)
{
    $directory = dirname($configFile);
    if ($directory !== dirname($lockFile) || !is_dir($directory) || !is_writable($directory)) {
        return false;
    }

    $original = is_file($configFile) ? file_get_contents($configFile) : null;
    if ($original === false) {
        return false;
    }

    $configTemp = tempnam($directory, '.config-');
    $lockTemp = tempnam($directory, '.lock-');
    $backupTemp = $original === null ? null : tempnam($directory, '.backup-');
    $temporaryFiles = array($configTemp, $lockTemp, $backupTemp);
    if ($configTemp === false || $lockTemp === false || ($original !== null && $backupTemp === false)) {
        foreach ($temporaryFiles as $temporaryFile) {
            if (is_string($temporaryFile)) {
                @unlink($temporaryFile);
            }
        }
        return false;
    }

    $configText = "<?php\r\n" . '$config=' . arrayeval($values) . ';';
    $lockText = '安装程序锁定文件。';
    $prepared = file_put_contents($configTemp, $configText, LOCK_EX) === strlen($configText)
        && file_put_contents($lockTemp, $lockText, LOCK_EX) === strlen($lockText)
        && ($original === null || file_put_contents($backupTemp, $original, LOCK_EX) === strlen($original));
    if (!$prepared || !@rename($configTemp, $configFile)) {
        foreach ($temporaryFiles as $temporaryFile) {
            if (is_string($temporaryFile)) {
                @unlink($temporaryFile);
            }
        }
        return false;
    }

    if (!@rename($lockTemp, $lockFile)) {
        $restored = $original === null
            ? @unlink($configFile)
            : @rename($backupTemp, $configFile);
        if (!$restored && $original !== null) {
            $restored = file_put_contents($configFile, $original, LOCK_EX) === strlen($original);
        }
        @unlink($configTemp);
        @unlink($lockTemp);
        @unlink($backupTemp);
        return false;
    }

    @unlink($backupTemp);
    if (function_exists('opcache_invalidate')) {
        opcache_invalidate($configFile, true);
    }

    return true;
}

function install_error($message, $status)
{
    http_response_code($status);
    header('Content-Type: text/plain; charset=UTF-8');
    exit($message);
}
