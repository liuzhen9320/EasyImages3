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
response_page="$test_root/response.txt"
password='Manager-CSRF-2026!'
target_name='manager-csrf-test.txt'
upload_name='manager-upload-test.jpg'

php -r 'require $argv[1] . "/app/function.php"; $config["domain"] = $argv[2]; $config["imgurl"] = $argv[2]; $config["user"] = "admin"; $config["password"] = easyimage_password_hash($argv[3]); $config["file_manage"] = 1; if (!cache_write($argv[1] . "/config/config.php", $config)) { exit(1); }' \
    "$test_root" "$base_url" "$password"
printf 'installed\n' >"$test_root/config/install.lock"
printf 'upload fixture\n' >"$test_root/upload-fixture.jpg"

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
    --data-urlencode 'user=admin' \
    --data-urlencode "password=$password" \
    "$base_url/admin/index.php" >/dev/null
curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    "$base_url/admin/manager.php?p=" >"$manager_page"
csrf_token="$(sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' "$manager_page" | head -n 1)"
test -n "$csrf_token"

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    "$base_url/admin/manager.php?p=&type=file&new=$target_name")"
test "$status" = '405'
test ! -e "$test_root/i/$target_name"

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    --data-urlencode 'p=' --data-urlencode 'type=file' --data-urlencode "new=$target_name" \
    "$base_url/admin/manager.php")"
test "$status" = '403'
test ! -e "$test_root/i/$target_name"

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    --data-urlencode 'p=' --data-urlencode 'type=file' --data-urlencode "new=$target_name" \
    --data-urlencode "_csrf=$csrf_token" "$base_url/admin/manager.php")"
test "$status" = '302'
test -f "$test_root/i/$target_name"

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    --data-urlencode 'ajax=true' --data-urlencode 'type=backup' --data-urlencode 'path=' \
    --data-urlencode "file=$target_name" "$base_url/admin/manager.php?p=")"
test "$status" = '403'
test "$(find "$test_root/i" -maxdepth 1 -name "$target_name-*.bak" | wc -l)" -eq 0

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    --data-urlencode 'ajax=true' --data-urlencode 'type=backup' --data-urlencode 'path=' \
    --data-urlencode "file=$target_name" --data-urlencode "_csrf=$csrf_token" \
    "$base_url/admin/manager.php?p=")"
test "$status" = '200'
test "$(find "$test_root/i" -maxdepth 1 -name "$target_name-*.bak" | wc -l)" -eq 1

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    -F 'p=' -F "fullpath=$upload_name" -F 'dzchunkindex=0' -F 'dztotalchunkcount=1' \
    -F "file=@$test_root/upload-fixture.jpg;filename=$upload_name" \
    "$base_url/admin/manager.php?p=")"
test "$status" = '403'
test ! -e "$test_root/i/$upload_name"

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    -F 'p=' -F "_csrf=$csrf_token" -F "fullpath=$upload_name" -F 'dzchunkindex=0' \
    -F 'dztotalchunkcount=1' -F "file=@$test_root/upload-fixture.jpg;filename=$upload_name" \
    "$base_url/admin/manager.php?p=")"
test "$status" = '200'
grep -q 'success' "$response_page"
test -f "$test_root/i/$upload_name"

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    "$base_url/admin/manager.php?p=&del=$target_name")"
test "$status" = '405'
test -f "$test_root/i/$target_name"

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    --data-urlencode 'p=' --data-urlencode "del=$target_name" --data-urlencode "_csrf=$csrf_token" \
    "$base_url/admin/manager.php")"
test "$status" = '302'
test ! -e "$test_root/i/$target_name"

echo "File manager CSRF flow passed: $test_root"
