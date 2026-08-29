#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d)/easyimages"
mkdir -p "$test_root"
tar --exclude=.git --exclude=admin/logs --exclude=i/cache -cf - -C "$source_root" . | tar -xf - -C "$test_root"

EASYIMAGE_TEST_ROOT="$test_root" php <<'PHP'
<?php
$testRoot = getenv('EASYIMAGE_TEST_ROOT');
require $testRoot . '/app/function.php';

function assert_same($expected, $actual, $message)
{
    if ($expected !== $actual) {
        fwrite(STDERR, $message . ': expected ' . var_export($expected, true)
            . ', got ' . var_export($actual, true) . PHP_EOL);
        exit(1);
    }
}

function set_request_addresses($remote, $xRealIp = null, $cfConnectingIp = null, $forwarded = null, $clientIp = null)
{
    $_SERVER['REMOTE_ADDR'] = $remote;
    if ($xRealIp === null) {
        unset($_SERVER['HTTP_X_REAL_IP']);
    } else {
        $_SERVER['HTTP_X_REAL_IP'] = $xRealIp;
    }
    if ($cfConnectingIp === null) {
        unset($_SERVER['HTTP_CF_CONNECTING_IP']);
    } else {
        $_SERVER['HTTP_CF_CONNECTING_IP'] = $cfConnectingIp;
    }
    if ($forwarded === null) {
        unset($_SERVER['HTTP_X_FORWARDED_FOR']);
    } else {
        $_SERVER['HTTP_X_FORWARDED_FOR'] = $forwarded;
    }
    if ($clientIp === null) {
        unset($_SERVER['HTTP_CLIENT_IP']);
    } else {
        $_SERVER['HTTP_CLIENT_IP'] = $clientIp;
    }
}

$config['trusted_proxies'] = '';
set_request_addresses('198.51.100.20', '192.0.2.10', '192.0.2.11', '192.0.2.12', '192.0.2.13');
assert_same('198.51.100.20', real_ip(), 'Direct clients must not control forwarding headers');

$config['trusted_proxies'] = '10.0.0.0/8';
set_request_addresses('198.51.100.20', '192.0.2.10', '192.0.2.11');
assert_same('198.51.100.20', real_ip(), 'Untrusted direct clients must not control single-value headers');

set_request_addresses('10.2.3.4', '198.51.100.42');
assert_same('198.51.100.42', real_ip(), 'Trusted proxy should supply X-Real-IP');

set_request_addresses('10.2.3.4', null, '203.0.113.42');
assert_same('203.0.113.42', real_ip(), 'Trusted proxy should supply CF-Connecting-IP');

set_request_addresses('10.2.3.4', '198.51.100.42', '203.0.113.42');
assert_same('203.0.113.42', real_ip(), 'CF-Connecting-IP should take precedence when both headers exist');

set_request_addresses('10.0.0.5', '198.51.100.99, 203.0.113.7');
assert_same('10.0.0.5', real_ip(), 'Comma-separated X-Real-IP must be rejected');

set_request_addresses('10.0.0.5', null, 'unknown');
assert_same('10.0.0.5', real_ip(), 'Malformed CF-Connecting-IP must be rejected');

set_request_addresses('10.0.0.5', null, null, '198.51.100.99', '203.0.113.42');
assert_same('198.51.100.99', real_ip(), 'X-Forwarded-For should remain a trusted-proxy fallback');

$config['trusted_proxies'] = '10.0.0.0/8,192.168.0.0/16';
set_request_addresses('10.0.0.5', null, null, '198.51.100.99, 203.0.113.7, 192.168.1.2');
assert_same('203.0.113.7', real_ip(), 'X-Forwarded-For chains must stop at the first untrusted hop');

set_request_addresses('10.0.0.5', null, null, null, '203.0.113.42');
assert_same('10.0.0.5', real_ip(), 'Client-IP must remain ignored');

$config['trusted_proxies'] = '2001:db8:ffff::/48';
set_request_addresses('2001:db8:ffff::1', '2001:db8:abcd::99');
assert_same('2001:db8:abcd::99', real_ip(), 'IPv6 proxy and client addresses must be supported');

$config['trusted_proxies'] = '';
set_request_addresses('2001:db8::20', '2001:db8::99');
assert_same('2001:db8::20', real_ip(), 'Direct IPv6 clients must ignore forwarding headers');

assert_same(true, ip_in_network('10.255.1.2', '10.0.0.0/8'), 'IPv4 CIDR match failed');
assert_same(false, ip_in_network('11.0.0.1', '10.0.0.0/8'), 'IPv4 CIDR mismatch failed');
assert_same(true, ip_in_network('2001:db8:1::1', '2001:db8::/32'), 'IPv6 CIDR match failed');
assert_same('127.0.0.1,10.0.0.1/8,2001:db8::1/32',
    sanitize_trusted_proxies("127.0.0.1, 10.0.0.1/8\n2001:0db8::1/32,invalid"),
    'Trusted proxy normalization failed');

assert_same(true, checkIP('2001:db8::2', '2001:db8::/32', false), 'IPv6 blacklist CIDR failed');
assert_same(false, checkIP('193.134.22.5', '193.134.*.*', true), 'Matching wildcard whitelist failed');
assert_same(true, checkIP('192.0.2.5', '193.134.*.*', true), 'Nonmatching wildcard whitelist failed');
assert_same(true, checkIP('203.0.113.8', '203.0.113.8', false), 'Explicit blacklist address failed');

$resolvedClient = '203.0.113.77';
$config['trusted_proxies'] = '10.0.0.0/8';
$config['password'] = 'trusted-proxy-test-secret';
$config['user'] = 'admin';
set_request_addresses('10.0.0.9', $resolvedClient);

$apiToken = 'trusted-proxy-api-test';
assert_same(0, api_rate_limit($apiToken), 'API rate limit request failed');
$apiBucket = hash_hmac('sha256', $apiToken . "\0" . $resolvedClient, $config['password']);
assert_same(true, is_file(APP_ROOT . '/admin/logs/security/api-rate/' . $apiBucket . '.php'),
    'API rate limit did not use the resolved client address');

assert_same(0, login_rate_limit('unknown-user', 'failure'), 'Login rate limit request failed');
$loginBucket = hash_hmac('sha256', 'ip:' . $resolvedClient, $config['password']);
assert_same(true, is_file(APP_ROOT . '/admin/logs/security/login-rate/' . $loginBucket . '.php'),
    'Login rate limit did not use the resolved client address');

$config['ip_upload_counts'] = 5;
write_ip_upload_count_logs();
$countFile = APP_ROOT . '/admin/logs/ipcounts/' . date('Y-m-d') . '.php';
require $countFile;
assert_same(1, isset($ipcounts[$resolvedClient]) ? $ipcounts[$resolvedClient] : null,
    'Guest upload quota did not use the resolved client address');

$_SERVER['REMOTE_PORT'] = '54321';
$_SERVER['HTTP_USER_AGENT'] = 'trusted-proxy-test';
$fixture = APP_ROOT . '/i/trusted-proxy-test.jpg';
file_put_contents($fixture, 'fixture');
$config['upload_logs'] = 1;
$config['checkImg'] = 0;
write_upload_logs('/i/trusted-proxy-test.jpg', 'fixture.jpg', $fixture, filesize($fixture));
$uploadLog = APP_ROOT . '/admin/logs/upload/' . date('Y-m') . '.php';
require $uploadLog;
assert_same($resolvedClient, $logs['trusted-proxy-test.jpg']['ip'],
    'Upload log did not use the resolved client address');

write_login_log('test-user', 'test-message');
$loginLog = APP_ROOT . '/admin/logs/login/' . date('/Y-m-') . 'logs.php';
assert_same(true, strpos(file_get_contents($loginLog), 'IP: ' . $resolvedClient) !== false,
    'Login log did not use the resolved client address');

echo 'Trusted proxy IP handling passed: ' . APP_ROOT . PHP_EOL;
PHP
