# Security Audit — EasyImage3

> 审计日期: 2026-07-09
> 代码版本: 2.8.7 (master `42b4711`)

---

## 🔴 严重 (3)

### 1. CSRF — 管理面板无防护

**文件**: `admin/admin.inc.php`

所有写操作（配置修改、Token 管理、用户管理、目录删除）仅靠 `is_who_login('admin')` cookie 校验，**无 CSRF Token**。登录管理员访问任意外部页面即可在不知情下触发操作。更有部分操作用 GET 即可触发（`?stop_token=`、`?delete_token=`、`?stop_guest=`、`?delete_guest=`、`?delDir=`）。

```php
// admin/admin.inc.php:51 — POST 全量覆盖配置
$new_config = array_replace($config, $postArr);
// admin/admin.inc.php:92 — GET 禁用 Token
if (isset($_GET['stop_token'])) { ... cache_write($api_key_file, ...); }
// admin/admin.inc.php:233 — GET 删除目录
if (isset($_REQUEST['delDir'])) { deldir($delDir); }
```

### 2. 密码明文记录到登录日志

**文件**: `app/function.php:1705`

```php
$log = htmlentities(date('Y-m-d H:i:s') . ' IP: ' . real_ip() . ' 账号: ' . $user . ' 密码: ' .  $pass . ' 提示: ' . $msg);
file_put_contents($log_file, $log . PHP_EOL, FILE_APPEND | LOCK_EX);
```

登录日志存储在 `admin/logs/login/Y-m-logs.php`，密码以明文写入（SHA-256 哈希值）。日志可通过 `app/viewlog.php` 读取，其鉴权仅靠 `md5($password . date('ymdh'))` — 单小时内可暴力破解。

### 3. `urlHash()` 使用 CRC32（32 位）作为加密密钥

**文件**: `app/function.php:565`

```php
$key = crc32($config['password']);   // 32-bit checksum, NOT a crypto key
$iv = 'sciCuBC7orQtDhTO';            // 固定 IV
return openssl_encrypt($data, "AES-128-XTS", $key, 0, $iv);
```

CRC32 是 32 位校验和，密钥空间可在秒级暴力破解。这导致：
- `app/del.php` 的删除链接 hash 可被伪造
- `app/hide.php` 的源图保护可被解密

---

## 🟠 高危 (6)

### 4. Auth Cookie 无 httponly / secure / samesite

**文件**: `app/function.php:124`, `admin/index.php:14`

```php
setcookie('auth', $browser_cookie, time() + 3600 * 24 * 14, '/');
```

无任何安全标志。cookie 中直接存储密码哈希（明文等价物），可被 XSS 窃取。登录后不轮换。

### 5. 路径穿越 — `app/thumb.php`

**文件**: `app/thumb.php:94`

```php
$src = APP_ROOT . $_GET['img'];
```

用户输入直接拼入文件路径。唯一保护是检查是否包含 `$config['path']`（如 `/i/`），可绕过：

```
?img=/i/../../config/config.php
```

### 6. 路径穿越 — `app/down.php`

**文件**: `app/down.php:17`

```php
$dw = '../' . $_GET['dw'];
```

扩展名过滤依赖管理员配置，若管理员将 `php` 加入允许扩展名则可下载任意 PHP 文件。

### 7. POST 全量覆盖 Config

**文件**: `admin/admin.inc.php:51`

```php
$new_config = array_replace($config, $postArr);   // $_POST 所有字段
```

任何 POST 字段可覆盖 `password`、`user` 等关键配置。同样问题在 line 184 的管理员表单。

### 8. 目录删除可遍历

**文件**: `admin/admin.inc.php:234`

```php
$delDir = APP_ROOT . $config['path'] . $_REQUEST['delDir'];
```

`delDir` 无任何路径校验，可删除 `i/` 目录下的任意子目录。

### 9. SVG 上传 XSS 过滤不完整

**文件**: `app/upload.php:96`, `api/index.php:66`

```php
preg_match('/<script[\s\S]*?<\/script>/', $svg) || stripos($svg, 'href=')
```

仅检测 `<script>` 标签和 `href=`。事件处理器如 `<svg onload="alert(1)">`、`<foreignObject>` 内部 HTML/JS 可绕过。

---

## 🟡 中危 (7)

### 10. 无安全响应头

全局缺失 `X-Content-Type-Options: nosniff`、`X-Frame-Options`、`Content-Security-Policy`、`Referrer-Policy`。

### 11. 登录无速率限制

`admin/index.php` 无登录失败次数限制，可暴力破解。

### 12. User-Agent 存储型 XSS

**文件**: `app/function.php:1531` → `app/viewlog.php:121-175`

```php
'user_agent' => $_SERVER['HTTP_USER_AGENT'],   // 未转义写入日志
```

User-Agent 未经 HTML 转义写入日志文件。日志在 viewlog.php 中以 `html: true` 渲染，恶意 User-Agent 可在管理页面执行 JS。

### 13. `check_api()` 逻辑缺陷

**文件**: `app/function.php:1342`

```php
if (!in_array($tokenList[$token], $tokenList))
```

若 `$token` 为空/不存在（`$_POST['token']` 未设置时），访问 `$tokenList[$token]` 触发 PHP 警告。

### 14. 无 Session 固定防护

**文件**: `admin/index.php:57`

登录成功后不调用 `session_regenerate_id()`。

### 15. API 无调用频率限制

**文件**: `api/index.php`

无每分钟/每小时调用次数限制。

### 16. 分片上传临时文件

**文件**: `app/upload.php:80`

分片上传临时文件命名可能可预测。

---

## 🔵 低危 (3)

### 17. `.htaccess` 仅封禁 `.php`

**文件**: `i/.htaccess`

仅阻止 `.php` 执行。`.shtml`、`.phtml`、`.php5`、`.pht` 可绕过。

### 18. `header()` 含用户可控值

多处 `header("refresh:2;url=" . $config['domain'])`，若域名被篡改可做响应头注入。

### 19. cURL 跟随重定向无协议限制

**文件**: `app/TimThumb.php:1349`, `app/function.php:830`

```php
CURLOPT_FOLLOWLOCATION = true
```

无白名单协议限制（如仅限于 `http`/`https`），SSRF 场景中可利用。

---

## 优先修复顺序

| 优先级 | # | 漏洞 | 影响 |
|--------|---|------|------|
| P0 | 1 | CSRF | 账户完全接管 |
| P0 | 2 | 密码明文日志 | 凭据泄露 |
| P0 | 3 | CRC32 加密 | 删除链接/隐藏路径保护失效 |
| P1 | 4 | Cookie 安全标志 | 凭据被 XSS 窃取 |
| P1 | 5-6 | 路径穿越 | 任意文件读取 |
| P1 | 7 | Config 注入 | 账户/password 覆盖 |
| P2 | 9 | SVG XSS 过滤不完整 | XSS 攻击 |
| P2 | 12 | User-Agent XSS | 存储型 XSS |
| P3 | 10-11,14-16 | 其他中危 | 视场景而定 |
