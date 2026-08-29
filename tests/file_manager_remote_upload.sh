#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)/easyimages"
origin_root="$(mktemp -d)/origin"
mkdir -p "$test_root" "$origin_root"
tar --exclude=.git --exclude=admin/logs --exclude=i/cache -cf - -C "$source_root" . | tar -xf - -C "$test_root"

port="$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); $name = stream_socket_get_name($socket, false); echo substr(strrchr($name, ":"), 1); fclose($socket);')"
origin_port="$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); $name = stream_socket_get_name($socket, false); echo substr(strrchr($name, ":"), 1); fclose($socket);')"
base_url="http://127.0.0.1:$port"
cookie_jar="$test_root/cookies.txt"
manager_page="$test_root/manager.html"
upload_page="$test_root/upload.html"
response_page="$test_root/response.json"
password='Remote-Upload-2026!'

php -r 'require $argv[1] . "/app/function.php"; $config["domain"] = $argv[2]; $config["imgurl"] = $argv[2]; $config["user"] = "admin"; $config["password"] = easyimage_password_hash($argv[3]); $config["file_manage"] = 1; if (!cache_write($argv[1] . "/config/config.php", $config)) { exit(1); }' \
    "$test_root" "$base_url" "$password"
printf 'installed\n' >"$test_root/config/install.lock"
printf 'remote payload\n' >"$origin_root/payload.jpg"

php -d opcache.enable_cli=0 -S "127.0.0.1:$origin_port" -t "$origin_root" >"$origin_root/server.log" 2>&1 &
origin_pid=$!
php -d opcache.enable_cli=0 -S "127.0.0.1:$port" -t "$test_root" >"$test_root/server.log" 2>&1 &
server_pid=$!

for attempt in $(seq 1 50); do
    if curl --fail --silent "$base_url/admin/index.php" >/dev/null; then
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null || ! kill -0 "$origin_pid" 2>/dev/null; then
        echo 'Development server stopped unexpectedly' >&2
        exit 1
    fi
done

curl --fail --silent --show-error -c "$cookie_jar" "$base_url/admin/index.php" >/dev/null
curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    --data-urlencode 'user=admin' --data-urlencode "password=$password" \
    "$base_url/admin/index.php" >/dev/null
curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    "$base_url/admin/manager.php?p=" >"$manager_page"
csrf_token="$(sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' "$manager_page" | head -n 1)"
test -n "$csrf_token"

curl --fail --silent --show-error -b "$cookie_jar" \
    "$base_url/admin/manager.php?p=&upload=1" >"$upload_page"
if grep -Eiq 'Upload from URL|urlUploader|uploadurl' "$upload_page"; then
    echo 'Remote upload controls remain visible' >&2
    exit 1
fi

status="$(curl --silent --output "$response_page" --write-out '%{http_code}' -b "$cookie_jar" \
    --data-urlencode 'p=' --data-urlencode 'ajax=true' --data-urlencode 'type=upload' \
    --data-urlencode "uploadurl=http://2130706433:$origin_port/payload.jpg" \
    --data-urlencode "_csrf=$csrf_token" "$base_url/admin/manager.php?p=")"
test "$status" = '410'
grep -q 'Remote URL uploads are disabled' "$response_page"
test ! -e "$test_root/i/payload.jpg"
if grep -q 'Accepted' "$origin_root/server.log"; then
    echo 'The file manager contacted the remote origin' >&2
    exit 1
fi

echo "File manager remote upload rejection passed: $test_root"
