#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)/easyimages"
mkdir -p "$test_root"
tar --exclude=.git --exclude=admin/logs --exclude=i/cache -cf - -C "$source_root" . | tar -xf - -C "$test_root"

port="$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); $name = stream_socket_get_name($socket, false); echo substr(strrchr($name, ":"), 1); fclose($socket);')"
base_url="http://127.0.0.1:$port"
cookie_jar="$test_root/cookies.txt"
index_page="$test_root/index.html"
manager_page="$test_root/manager.html"
response_page="$test_root/response.json"
password='SVG-Rejection-2026!'
api_token='svgtesttoken2026'

php -r 'require $argv[1] . "/app/function.php"; $config["domain"] = $argv[2]; $config["imgurl"] = $argv[2]; $config["user"] = "admin"; $config["password"] = easyimage_password_hash($argv[3]); $config["file_manage"] = 1; $config["apiStatus"] = 1; $config["extensions"] = "jpg,jpeg,png,svg,SVGZ"; $config["minWidth"] = 1; $config["minHeight"] = 1; $config["thumbnail"] = 0; $config["compress"] = 0; $config["watermark"] = 0; $config["chunks"] = 0; if (!cache_write($argv[1] . "/config/config.php", $config)) { exit(1); }' \
    "$test_root" "$base_url" "$password"
php -r '$tokenList = array($argv[2] => array("id" => 7, "expired" => time() + 3600, "add_time" => time())); $data = "<?php\n\$tokenList=" . var_export($tokenList, true) . ";"; if (file_put_contents($argv[1] . "/config/api_key.php", $data) === false) { exit(1); }' \
    "$test_root" "$api_token"
printf 'installed\n' >"$test_root/config/install.lock"
printf '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><rect width="10" height="10"/></svg>\n' >"$test_root/attack.svg"
cp "$test_root/attack.svg" "$test_root/disguised.jpg"
php -r '$png = base64_decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=", true); if ($png === false || file_put_contents($argv[1], $png) === false) { exit(1); }' \
    "$test_root/normal.png"

php -d opcache.enable_cli=0 -S "127.0.0.1:$port" -t "$test_root" >"$test_root/server.log" 2>&1 &
server_pid=$!

for attempt in $(seq 1 50); do
    if curl --fail --silent "$base_url/" >/dev/null; then
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "PHP development server stopped unexpectedly: $test_root/server.log" >&2
        exit 1
    fi
done

curl --fail --silent --show-error -c "$cookie_jar" "$base_url/" >"$index_page"
grep -Fq "extensions: 'jpg,jpeg,png'" "$index_page"
if grep -Eiq "extensions: '[^']*svg" "$index_page"; then
    echo 'SVG remained in the browser upload allowlist' >&2
    exit 1
fi

curl --fail --silent --show-error -F "sign=$(date +%s)" \
    -F "file=@$test_root/attack.svg;filename=attack.svg;type=image/svg+xml" \
    "$base_url/app/upload.php" >"$response_page"
grep -q '"code":415' "$response_page"
test "$(find "$test_root/i" -type f -iname 'attack.svg' | wc -l)" -eq 0

curl --fail --silent --show-error -F "sign=$(date +%s)" \
    -F "file=@$test_root/disguised.jpg;filename=disguised.jpg;type=image/jpeg" \
    "$base_url/app/upload.php" >"$response_page"
grep -q '"code":415' "$response_page"
test "$(find "$test_root/i" -type f -iname 'disguised.jpg' | wc -l)" -eq 0

curl --fail --silent --show-error -F "sign=$(date +%s)" \
    -F "file=@$test_root/normal.png;filename=normal.png;type=image/png" \
    "$base_url/app/upload.php" >"$response_page"
grep -q '"code":200' "$response_page"
test "$(find "$test_root/i" -type f -iname '*.png' | wc -l)" -eq 1

curl --fail --silent --show-error -F "token=$api_token" \
    -F "image=@$test_root/attack.svg;filename=api-attack.svg;type=image/svg+xml" \
    "$base_url/api/index.php" >"$response_page"
grep -q '"code":415' "$response_page"
test "$(find "$test_root/i" -type f -iname 'api-attack.svg' | wc -l)" -eq 0

curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    --data-urlencode 'user=admin' --data-urlencode "password=$password" \
    "$base_url/admin/index.php" >/dev/null
curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    "$base_url/admin/manager.php?p=" >"$manager_page"
csrf_token="$(sed -n 's/.*name="_csrf" value="\([^"]*\)".*/\1/p' "$manager_page" | head -n 1)"
test -n "$csrf_token"

curl --fail --silent --show-error -b "$cookie_jar" \
    -F 'p=' -F "_csrf=$csrf_token" -F 'fullpath=manager-attack.svg' \
    -F 'dzchunkindex=0' -F 'dztotalchunkcount=1' \
    -F "file=@$test_root/attack.svg;filename=manager-attack.svg;type=image/svg+xml" \
    "$base_url/admin/manager.php?p=" >"$response_page"
grep -q '"status":"error"' "$response_page"
test ! -e "$test_root/i/manager-attack.svg"

curl --fail --silent --show-error -b "$cookie_jar" \
    -F 'p=' -F "_csrf=$csrf_token" -F 'fullpath=manager-disguised.jpg' \
    -F 'dzchunkindex=0' -F 'dztotalchunkcount=1' \
    -F "file=@$test_root/disguised.jpg;filename=manager-disguised.jpg;type=image/jpeg" \
    "$base_url/admin/manager.php?p=" >"$response_page"
grep -q '"status":"error"' "$response_page"
test ! -e "$test_root/i/manager-disguised.jpg"

curl --fail --silent --show-error -b "$cookie_jar" \
    --data-urlencode 'update=1' --data-urlencode 'extensions=jpg,svg,png,SVGZ' \
    --data-urlencode "_csrf=$csrf_token" "$base_url/admin/admin.inc.php" >/dev/null
php -r 'require $argv[1] . "/config/config.php"; if ($config["extensions"] !== "jpg,png") { exit(1); }' "$test_root"

php -r 'require $argv[1] . "/app/function.php"; $config["chunks"] = 1024; if (!cache_write($argv[1] . "/config/config.php", $config)) { exit(1); }' "$test_root"
curl --fail --silent --show-error -F "sign=$(date +%s)" -F 'name=chunk-attack.svg' \
    -F 'chunk=0' -F 'chunks=1' -F "file=@$test_root/attack.svg;type=image/svg+xml" \
    "$base_url/app/upload.php" >"$response_page"
grep -q '"code":415' "$response_page"

curl --fail --silent --show-error -F "token=$api_token" -F 'name=api-chunk-attack.svg' \
    -F 'chunk=0' -F 'chunks=1' -F "image=@$test_root/attack.svg;type=image/svg+xml" \
    "$base_url/api/index.php" >"$response_page"
grep -q '"code":415' "$response_page"

php -r 'require $argv[1] . "/app/function.php"; if (sanitize_upload_extensions("jpg,SVG,png,svgz,png") !== "jpg,png" || !is_forbidden_svg_upload("safe.jpg", "image/svg+xml") || is_forbidden_svg_upload("safe.png", "image/png")) { exit(1); }' "$test_root"

if grep -Eiq 'PHP (Fatal|Parse)' "$test_root/server.log"; then
    cat "$test_root/server.log" >&2
    exit 1
fi

echo "SVG upload rejection passed: $test_root"
