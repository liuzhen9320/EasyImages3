#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)/easyimages"
mkdir -p "$test_root"
tar --exclude=.git --exclude=admin/logs --exclude=i/cache -cf - -C "$source_root" . | tar -xf - -C "$test_root"

port="$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); $name = stream_socket_get_name($socket, false); echo substr(strrchr($name, ":"), 1); fclose($socket);')"
base_url="http://127.0.0.1:$port"
cookie_jar="$test_root/cookies.txt"
response_page="$test_root/response.html"
admin_page="$test_root/admin.html"
password='Log-Viewer-2026!'
log_month="$(date '+%Y-%m')"

mkdir -p "$test_root/admin/logs/upload" "$test_root/admin/logs/login"
php -r 'require $argv[1] . "/app/function.php"; $config["domain"] = $argv[2]; $config["imgurl"] = $argv[2]; $config["user"] = "admin"; $config["password"] = easyimage_password_hash($argv[3]); if (!cache_write($argv[1] . "/config/config.php", $config)) { exit(1); }' \
    "$test_root" "$base_url" "$password"
printf 'installed\n' >"$test_root/config/install.lock"
printf '%s\n' '<?php $logs=array();' >"$test_root/admin/logs/upload/$log_month.php"
printf '%s\n' '<?php file_put_contents(__DIR__ . "/viewlog-executed.txt", "executed"); $logs=array();' \
    >"$test_root/config/viewlog-sentinel.php"
printf '%s\n' '<?php exit; ?>login log fixture' >"$test_root/admin/logs/login/$(date '+%Y-%m-')logs.php"

php -d opcache.enable_cli=0 -S "127.0.0.1:$port" -t "$test_root" >"$test_root/server.log" 2>&1 &
server_pid=$!

for attempt in $(seq 1 50); do
    if curl --fail --silent "$base_url/admin/index.php" >/dev/null; then
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "PHP development server stopped unexpectedly: $test_root/server.log" >&2
        exit 1
    fi
done

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' \
    --data-urlencode "logDate=$log_month" "$base_url/app/viewlog.php")"
test "$status" = '200'
grep -q 'Permission denied' "$response_page"

curl --fail --silent --show-error -c "$cookie_jar" "$base_url/admin/index.php" >/dev/null
curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    --data-urlencode 'user=admin' --data-urlencode "password=$password" \
    "$base_url/admin/index.php" >/dev/null

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    --data-urlencode 'logDate=../../../config/viewlog-sentinel' "$base_url/app/viewlog.php")"
test "$status" = '400'
grep -q 'Invalid log date' "$response_page"
test ! -e "$test_root/config/viewlog-executed.txt"

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    --data-urlencode 'logDate=2026-13' "$base_url/app/viewlog.php")"
test "$status" = '400'
test ! -e "$test_root/config/viewlog-executed.txt"

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    --data-urlencode "logDate=$log_month" "$base_url/app/viewlog.php")"
test "$status" = '200'
test ! -e "$test_root/config/viewlog-executed.txt"

curl --fail --silent --show-error -b "$cookie_jar" \
    "$base_url/app/viewlog.php?login_log=1" >"$response_page"
grep -q 'login log fixture' "$response_page"

curl --fail --silent --show-error -b "$cookie_jar" "$base_url/admin/admin.inc.php" >"$admin_page"
if grep -Eq 'viewlog\.php[^" ]*sign=|name="sign"[^>]*日志访问' "$admin_page"; then
    echo 'Admin page still exposes a password-derived log signature' >&2
    exit 1
fi

echo "Log viewer path containment passed: $test_root"
