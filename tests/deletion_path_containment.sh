#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)/easyimages"
mkdir -p "$test_root"
tar --exclude=.git --exclude=admin/logs --exclude=i/cache -cf - -C "$source_root" . | tar -xf - -C "$test_root"

port="$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); $name = stream_socket_get_name($socket, false); echo substr(strrchr($name, ":"), 1); fclose($socket);')"
base_url="http://127.0.0.1:$port"
cookie_jar="$test_root/cookies.txt"
manager_page="$test_root/manager.html"
response_page="$test_root/response.json"
password='Deletion-Path-2026!'
sentinel="$test_root/config/delete-sentinel.txt"

mkdir -p "$test_root/i/2026/08/29" "$test_root/i/recycle" "$test_root/admin/logs/version"
printf 'outside storage\n' >"$sentinel"
printf 'symlink target\n' >"$test_root/config/symlink-target.txt"
ln -s ../config/symlink-target.txt "$test_root/i/outside-link.txt"

php -r 'require $argv[1] . "/app/function.php"; $config["domain"] = $argv[2]; $config["imgurl"] = $argv[2]; $config["user"] = "admin"; $config["password"] = easyimage_password_hash($argv[3]); $config["image_recycl"] = 0; $config["ftp_status"] = 0; if (!cache_write($argv[1] . "/config/config.php", $config)) { exit(1); }' \
    "$test_root" "$base_url" "$password"
printf 'installed\n' >"$test_root/config/install.lock"

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

curl --fail --silent --show-error -c "$cookie_jar" "$base_url/admin/index.php" >/dev/null
curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    --data-urlencode 'user=admin' --data-urlencode "password=$password" \
    "$base_url/admin/index.php" >/dev/null
curl --fail --silent --show-error -b "$cookie_jar" "$base_url/admin/manager.php?p=" >"$manager_page"
csrf_token="$(sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' "$manager_page" | head -n 1)"
test -n "$csrf_token"

curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=delete' --data-urlencode 'url=/i/../../config/delete-sentinel.txt' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":404' "$response_page"
test "$(cat "$sentinel")" = 'outside storage'

curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=delete' --data-urlencode 'url=/i/%2e%2e/%2e%2e/config/delete-sentinel.txt' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":404' "$response_page"
test "$(cat "$sentinel")" = 'outside storage'

curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'del_url_array[]=/i/../../config/delete-sentinel.txt' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >/dev/null
test "$(cat "$sentinel")" = 'outside storage'

curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=recycle' --data-urlencode 'url=/i/../../config/delete-sentinel.txt' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":404' "$response_page"
test "$(cat "$sentinel")" = 'outside storage'

traversal_hash="$(EASYIMAGE_TEST_ROOT="$test_root" php -r 'require getenv("EASYIMAGE_TEST_ROOT") . "/app/function.php"; echo urlHash("/i/../../config/delete-sentinel.txt", 0);')"
curl --fail --silent --show-error --get --data-urlencode "hash=$traversal_hash" \
    "$base_url/app/del.php" >"$response_page"
grep -q '"code":404' "$response_page"
test "$(cat "$sentinel")" = 'outside storage'

curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=delete' --data-urlencode 'url=/i/outside-link.txt' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":404' "$response_page"
test -L "$test_root/i/outside-link.txt"
test "$(cat "$test_root/config/symlink-target.txt")" = 'symlink target'

printf 'delete me\n' >"$test_root/i/2026/08/29/direct-delete.txt"
curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=delete' --data-urlencode "url=$base_url/i/2026/08/29/direct-delete.txt" \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":200' "$response_page"
test ! -e "$test_root/i/2026/08/29/direct-delete.txt"

printf 'hidden path delete\n' >"$test_root/i/2026/08/29/hidden-delete.txt"
php -r 'require $argv[1] . "/app/function.php"; $config["hide_path"] = 1; if (!cache_write($argv[1] . "/config/config.php", $config)) { exit(1); }' "$test_root"
curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode "url_admin_inc=$base_url/2026/08/29/hidden-delete.txt" \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":200' "$response_page"
test ! -e "$test_root/i/2026/08/29/hidden-delete.txt"

printf 'token delete\n' >"$test_root/i/2026/08/29/token-delete.txt"
valid_hash="$(EASYIMAGE_TEST_ROOT="$test_root" php -r 'require getenv("EASYIMAGE_TEST_ROOT") . "/app/function.php"; echo urlHash("/i/2026/08/29/token-delete.txt", 0);')"
curl --fail --silent --show-error --get --data-urlencode "hash=$valid_hash" \
    "$base_url/app/del.php" >"$response_page"
grep -q '"code":200' "$response_page"
test ! -e "$test_root/i/2026/08/29/token-delete.txt"

printf 'recycle me\n' >"$test_root/i/2026/08/29/recycle-test.png"
curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=recycle' --data-urlencode 'url=/i/2026/08/29/recycle-test.png' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":200' "$response_page"
test -f "$test_root/i/recycle/2026_08_29_recycle-test.png"

curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=recycle_reimg' --data-urlencode 'url=2026_08_29_recycle-test.png' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":200' "$response_page"
test -f "$test_root/i/2026/08/29/recycle-test.png"

printf 'attacker replacement\n' >"$test_root/i/recycle/.._.._config_delete-sentinel.txt"
curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=recycle_reimg' --data-urlencode 'url=.._.._config_delete-sentinel.txt' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":404' "$response_page"
test "$(cat "$sentinel")" = 'outside storage'
test -f "$test_root/i/recycle/.._.._config_delete-sentinel.txt"

printf '{}\n' >"$test_root/admin/logs/version/version.json"
curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=del_version_file' --data-urlencode 'url=/config/delete-sentinel.txt' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":404' "$response_page"
test "$(cat "$sentinel")" = 'outside storage'
test -f "$test_root/admin/logs/version/version.json"

curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'mode=del_version_file' --data-urlencode 'url=/admin/logs/version/version.json' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/app/del.php" >"$response_page"
grep -q '"code":200' "$response_page"
test ! -e "$test_root/admin/logs/version/version.json"

echo "Deletion path containment passed: $test_root"
