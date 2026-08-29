#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)/easyimages"
mkdir -p "$test_root"
tar --exclude=.git --exclude=admin/logs --exclude=i/cache -cf - -C "$source_root" . | tar -xf - -C "$test_root"

port="$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); $name = stream_socket_get_name($socket, false); echo substr(strrchr($name, ":"), 1); fclose($socket);')"
base_url="http://127.0.0.1:$port"
response_file="$test_root/response.bin"
header_file="$test_root/headers.txt"

mkdir -p "$test_root/i/2026/08/29"
printf 'protected image fixture\n' >"$test_root/i/2026/08/29/protected.jpg"
printf 'outside storage secret\n' >"$test_root/config/protected-sentinel.txt"
ln -s ../config/protected-sentinel.txt "$test_root/i/protected-link.jpg"
php -r 'require $argv[1] . "/app/function.php"; $config["hide_key"] = "protected-image-test-key"; if (!cache_write($argv[1] . "/config/config.php", $config)) { exit(1); }' "$test_root"
printf 'installed\n' >"$test_root/config/install.lock"

php -d opcache.enable_cli=0 -S "127.0.0.1:$port" -t "$test_root" >"$test_root/server.log" 2>&1 &
server_pid=$!

for attempt in $(seq 1 50); do
    if curl --fail --silent "$base_url/public/images/404.png" >/dev/null; then
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "PHP development server stopped unexpectedly: $test_root/server.log" >&2
        exit 1
    fi
done

make_token() {
    EASYIMAGE_TEST_ROOT="$test_root" php -r 'require getenv("EASYIMAGE_TEST_ROOT") . "/app/function.php"; echo urlHash($argv[1], 0, $config["hide_key"]);' "$1"
}

valid_token="$(make_token '/i/2026/08/29/protected.jpg')"
status="$(curl --silent --output "$response_file" --dump-header "$header_file" --write-out '%{http_code}' \
    --get --data-urlencode "key=$valid_token" "$base_url/app/hide.php")"
test "$status" = '200'
test "$(cat "$response_file")" = 'protected image fixture'
grep -qi '^Content-Type: image/jpg' "$header_file"

traversal_token="$(make_token '/i/../../config/protected-sentinel.txt')"
status="$(curl --silent --output "$response_file" --write-out '%{http_code}' \
    --get --data-urlencode "key=$traversal_token" "$base_url/app/hide.php")"
test "$status" = '404'
if grep -q 'outside storage secret' "$response_file"; then
    echo 'Protected image endpoint disclosed a file outside storage' >&2
    exit 1
fi

link_token="$(make_token '/i/protected-link.jpg')"
status="$(curl --silent --output "$response_file" --write-out '%{http_code}' \
    --get --data-urlencode "key=$link_token" "$base_url/app/hide.php")"
test "$status" = '404'
if grep -q 'outside storage secret' "$response_file"; then
    echo 'Protected image endpoint followed an escaping symbolic link' >&2
    exit 1
fi

status="$(curl --silent --output "$response_file" --write-out '%{http_code}' \
    --get --data-urlencode "key=${valid_token}tampered" "$base_url/app/hide.php")"
test "$status" = '404'

echo "Protected image path containment passed: $test_root"
