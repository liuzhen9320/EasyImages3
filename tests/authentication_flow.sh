#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)/easyimages"
mkdir -p "$test_root"
tar --exclude=.git --exclude=admin/logs --exclude=i/cache -cf - -C "$source_root" . | tar -xf - -C "$test_root"
chmod 755 "$test_root/app/upload.php"

port="$(php -r '$socket = stream_socket_server("tcp://127.0.0.1:0"); $name = stream_socket_get_name($socket, false); echo substr(strrchr($name, ":"), 1); fclose($socket);')"
base_url="http://127.0.0.1:$port"
cookie_jar="$test_root/cookies.txt"
legacy_cookie_jar="$test_root/legacy-cookies.txt"
environment_page="$test_root/environment.html"
configuration_page="$test_root/configuration.html"
install_page="$test_root/installed.html"
login_page="$test_root/login.html"
admin_page="$test_root/admin.html"
password='Correct-Horse-2026!'

php -d opcache.enable_cli=0 -S "127.0.0.1:$port" -t "$test_root" >"$test_root/server.log" 2>&1 &
server_pid=$!

for attempt in $(seq 1 50); do
    if curl --fail --silent "$base_url/install/index.php" >/dev/null; then
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "PHP development server stopped unexpectedly: $test_root/server.log" >&2
        exit 1
    fi
done

curl --fail --silent --show-error -c "$cookie_jar" "$base_url/install/index.php" >"$environment_page"
environment_token="$(sed -n 's/.*name="install_token" value="\([^"]*\)".*/\1/p' "$environment_page" | head -n 1)"
test -n "$environment_token"
installer_session="$(awk '$6 == "easyimage_session" { print $7 }' "$cookie_jar")"
test -n "$installer_session"

curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    --data-urlencode 'check=checked' \
    --data-urlencode "install_token=$environment_token" \
    "$base_url/install/install.php" >"$configuration_page"
configuration_token="$(sed -n 's/.*name="install_token" value="\([^"]*\)".*/\1/p' "$configuration_page" | head -n 1)"
test -n "$configuration_token"

curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    --data-urlencode "install_token=$configuration_token" \
    --data-urlencode "domain=$base_url" \
    --data-urlencode "imgurl=$base_url" \
    --data-urlencode 'user=admin' \
    --data-urlencode "password=$password" \
    --data-urlencode "repassword=$password" \
    "$base_url/install/contorl.php" >"$install_page"
grep -q '安装成功' "$install_page"
test -f "$test_root/config/install.lock"
php -r 'require $argv[1]; if ($config["user"] !== "admin" || !password_verify($argv[2], $config["password"])) { exit(1); }' \
    "$test_root/config/config.php" "$password"

curl --fail --silent --show-error -b "$cookie_jar" -c "$cookie_jar" \
    --data-urlencode 'user=admin' \
    --data-urlencode "password=$password" \
    "$base_url/admin/index.php" >"$login_page"
grep -q '管理员登录成功' "$login_page"
authenticated_session="$(awk '$6 == "easyimage_session" { print $7 }' "$cookie_jar")"
test -n "$authenticated_session"
test "$authenticated_session" != "$installer_session"
if awk '$6 == "auth" { found = 1 } END { exit found ? 0 : 1 }' "$cookie_jar"; then
    echo 'Legacy auth cookie was issued' >&2
    exit 1
fi
if grep -Fq 'admin' "$cookie_jar" || grep -Fq "$password" "$cookie_jar"; then
    echo 'Cookie jar contains credential material' >&2
    exit 1
fi
curl --fail --silent --show-error -b "$cookie_jar" "$base_url/admin/admin.inc.php" >"$admin_page"
grep -q '管理员账号' "$admin_page"

php -r 'require $argv[1] . "/app/function.php"; $config["password"] = hash("sha256", $argv[2]); if (!cache_write($argv[1] . "/config/config.php", $config)) { exit(1); }' \
    "$test_root" "$password"
printf '# Netscape HTTP Cookie File\n127.0.0.1\tFALSE\t/\tFALSE\t2147483647\tauth\tlegacy-secret\n' >"$legacy_cookie_jar"
curl --fail --silent --show-error -b "$legacy_cookie_jar" -c "$legacy_cookie_jar" \
    --data-urlencode 'user=admin' \
    --data-urlencode "password=$password" \
    "$base_url/admin/index.php" >"$login_page"
grep -q '管理员登录成功' "$login_page"
if awk '$6 == "auth" { found = 1 } END { exit found ? 0 : 1 }' "$legacy_cookie_jar"; then
    echo 'Legacy auth cookie was not cleared' >&2
    exit 1
fi
php -r 'require $argv[1]; if (preg_match("/\\A[a-f0-9]{64}\\z/i", $config["password"]) || !password_verify($argv[2], $config["password"])) { exit(1); }' \
    "$test_root/config/config.php" "$password"

echo "Authentication flow passed: $test_root"
