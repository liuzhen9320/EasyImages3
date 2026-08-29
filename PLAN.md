# Security Audit — EasyImage3

> 审计日期: 2026-07-09
> 代码版本: 2.8.7 (master `42b4711`)

## 第二轮复审（2026-08-29，基于 `04025cc`）

> 状态说明：以下为第一轮 19 项修复完成后新确认的问题，均待修复。按“确认一项、立即记录一项”的方式持续补充。

### 20. 严重 — `admin/filer.php` 可越出站点根目录且写操作无 CSRF

**文件**: `admin/filer.php:22`, `admin/filer.php:83-90`, `admin/filer.php:627-634`, `admin/filer.php:678-884`, `admin/filer.php:955-958`

旧版 web-indexr 文件管理器把根目录设为 `$_SERVER['DOCUMENT_ROOT']`，但相对路径转换仅做字符串拼接：

```php
RexHelper::$root = $_SERVER['DOCUMENT_ROOT'];

static function path_rtoa($path)
{
    $path = self::$root . DIRECTORY_SEPARATOR . trim($path, '/\\');
    return $path;
}
```

`path` 来自 `$_REQUEST`，没有 `realpath()`、`..` 拒绝或根目录前缀校验。登录文件管理器后，攻击者可提交 `path=/../../tmp`，通过 `newfile`、`edit`、`upload`、`rename`、`chmod`、`zip`、`unzip`、`delete` 等操作读写或删除站点根目录外、PHP 进程权限可及的文件。

同时，所有动作仅检查文件管理器 Session，不校验 CSRF Token；删除、注销和清空 OPcache 等动作可由 GET 触发。实测使用 `POST ?action=newfile&path=/../../tmp` 成功创建 `/tmp/easyimages-filer-audit-20260829.txt`，再用不含 Token 的 `GET ?action=delete&path=/../../tmp/easyimages-filer-audit-20260829.txt` 成功删除。

**修复要求**：将文件管理根目录固定到配置的图片存储根；对每个源/目标路径做规范化和目录边界校验，拒绝 `..`、NUL 与符号链接逃逸；所有状态变更仅接受 POST 并统一校验 CSRF Token；移除 GET 写操作。考虑该文件管理器长期无人维护，优先评估删除 `admin/filer.php`，只保留已受限的 `admin/manager.php`。

### 21. 严重 — 安装控制器可被无参数 GET 触发并锁定为公开默认凭据

**文件**: `install/contorl.php:4-31`, `config/config.php:13-16`, `app/function.php:289-297`

发行包不包含 `config/install.lock`。安装控制器虽然按字段读取 POST，但不要求请求方法为 POST，也不要求任何安装流程状态；无论请求是否带参数，都会执行：

```php
$config_file = APP_ROOT . '/config/config.php';
cache_write($config_file, $config);
file_put_contents(APP_ROOT . '/config/install.lock', '安装程序锁定文件。');
```

因此，攻击者只需在站点完成安装前访问一次 `/install/contorl.php`，就能跳过环境检查和设置表单，使用发行包配置创建安装锁。发行包中的账号为 `admin`，密码值是公开默认密码 `admin@123` 的 SHA-256；登录页正好提交 SHA-256，`_login()` 又直接比较该值，攻击者随后可以默认凭据取得管理员权限。

在临时检出的干净副本中实测，无参数 GET 返回 HTTP 200，`config/install.lock` 从不存在变为存在，响应显示“安装成功”，最终配置满足 `user=admin` 且 `password=sha256('admin@123')`。

**修复要求**：安装提交只接受 POST；通过服务端 Session 保存并验证上一步产生的一次性安装 Token；拒绝空请求和缺失必填字段；发行包不得包含可登录的固定凭据；写配置与创建锁应使用原子、失败即回滚的流程。部署层应在安装完成后移除或禁止访问整个 `install/` 目录。

### 22. 高危 — 正常安装写入 bcrypt，但登录协议仍比较 SHA-256，管理员必然无法登录（已修复）

**文件**: `install/contorl.php:8-12`, `admin/index.php:146-150`, `admin/index.php:182-191`, `app/function.php:289-297`

安装表单直接提交明文密码，控制器用 `password_hash()` 保存 bcrypt：

```php
$config['password'] = password_hash($_POST['password'], PASSWORD_DEFAULT);
```

但管理员登录页仍在浏览器中执行 `SHA256(password.value)`，服务端 `_login()` 没有调用 `password_verify()`，而是把收到的 64 位 SHA-256 与配置中的 bcrypt 字符串直接全等比较：

```php
if ($user === $config['user'] && $password === $config['password']) {
```

两种格式永远不可能相等，导致通过正常安装流程设置的管理员凭据不可用。临时副本实测：POST 安装后密码以 `$2y$` 开头且能由 `password_verify()` 验证明文；随后按登录页协议提交该密码的 SHA-256，页面返回“密码错误”。

**修复要求**：统一密码协议。推荐在 HTTPS 下提交明文密码并在服务端使用 `password_verify()`；认证 Cookie 改为随机服务端 Session 标识，不再保存任何密码或密码哈希。对现有 64 位 SHA-256 配置提供一次成功登录后的渐进迁移，管理员修改密码、安装和登录必须共用同一套散列与验证函数，并增加从安装到首次登录的端到端测试。

**修复状态**：登录、安装、管理员改密和上传者账号统一使用服务端密码散列函数；浏览器只保存随机 PHP Session ID，旧 SHA-256 配置会在成功登录后自动迁移。CI 已覆盖两阶段安装、首次登录、Session 轮换、旧 Cookie 清除与旧散列迁移。

### 23. 高危 — `admin/manager.php` 的文件写操作仍无 CSRF，且创建/删除/改名使用 GET（已修复）

**文件**: `config/config.manager.php:22`, `admin/manager.php:311-392`, `admin/manager.php:443-653`, `admin/manager.php:656-870`

EasyImage 的管理器配置把 TinyFileManager 自带认证关闭，因此通过入口处的全站管理员 Cookie 校验后即可执行全部文件操作。管理器没有接入项目的 `csrf_validate()`；保存、上传、复制等 POST 动作不校验 Token，创建、删除、复制、移动、改名等动作甚至由 GET 参数直接触发：

```php
if (isset($_GET['del']) && !FM_READONLY) { /* 删除 */ }
if (isset($_GET['new'], $_GET['type']) && !FM_READONLY) { /* 创建 */ }
if (isset($_GET['ren'], $_GET['to']) && !FM_READONLY) { /* 改名 */ }
```

认证 Cookie 的 `SameSite=Lax` 不能防住顶层导航发起的跨站 GET。攻击者可诱导已登录管理员打开特制链接，在配置的图片根目录内创建、删除、改名或移动文件；这会造成图片批量破坏，还可能把已有文件改成可由 Web 服务器主动解释的扩展名。

临时副本实测：仅携带合法管理员 Cookie、完全不提交 CSRF Token，访问 `?p=&type=file&new=manager-csrf-audit-20260829.txt` 成功在 `i/` 创建文件；随后访问 `?p=&del=manager-csrf-audit-20260829.txt` 成功删除，两次响应均为 302。

**修复要求**：所有状态变更统一限制为 POST，并在动作分发前校验项目 CSRF Token；GET 只允许查看和下载。表单、AJAX、分片上传均应使用同一 Token 机制。增加请求方法与 CSRF 的回归测试，并升级长期停留在 2.4.7 的 TinyFileManager，或以项目内受维护的最小文件管理功能替代。

**修复状态**：项目入口对所有文件管理器 POST 请求统一校验 CSRF Token，旧 GET 写操作返回 405；创建、删除、重命名、复制移动、解压、编辑、设置、AJAX 和分片上传均已接入同一 Token。回归测试覆盖普通请求、AJAX 与分片上传的拒绝和成功路径。本项目继续维护现有深度定制文件管理器，避免直接替换上游 2.6 导致认证、存储根目录和静态资源集成回归。

### 24. 高危 — BootCSS/BootCDN 投毒事件引发全球开发者供应链信任危机（已修复）

**文件**: `docs/index.html:15`, `docs/index.html:83-93`

文档站的 docsify 主题、主脚本和三个插件共 5 个资源原先由 `cdn.bootcdn.net` 加载。BootCSS/BootCDN 投毒事件使其成为前端供应链风险源，并引发全球开发者对该 CDN 资源完整性与运营可信度的信任危机；继续引用会让文档访问者执行无法再被项目方信任的第三方内容。现已按要求全部替换为相同 docsify 4.13.0 版本的 `cdnjs.cloudflare.com` HTTPS 地址，资源顺序和版本保持不变。

验证结果：全仓已无 `bootcss`、`bootcdn` 或 `cdn.bootcdn.net` 引用；5 个 cdnjs 目标均返回 HTTP 200 且 Content-Type 正确，本地 `/docs/` 返回 HTTP 200。

### 25. 高危 — `admin/manager.php` 远程上传的 SSRF 过滤可被整数 IP 和私网地址绕过

**文件**: `admin/manager.php:566-640`

TinyFileManager 的“从 URL 上传”功能由服务器主动请求用户提供的 HTTP(S) 地址。现有防护只按原始主机字符串拦截 `localhost`、`127.*`、`::1`，并只禁止 4 个端口：

```php
$domain = parse_url($url, PHP_URL_HOST);
if (preg_match('/^localhost$|^127...$|...::1$/i', $domain) || in_array($port, $knownPorts)) {
    exit();
}
copy($url, $temp_file, $ctx);
```

代码没有解析 DNS 后的全部 A/AAAA 地址，也没有拒绝 RFC1918 私网、链路本地、云元数据、保留地址和非标准形式的回环地址；PHP HTTP 包装器还可能跟随未经重新校验的重定向。拥有管理器请求能力的攻击者可借此探测或读取 PHP 进程可访问的内网 HTTP 服务，并把响应保存到公开图片目录。

实测将回环地址 `127.0.0.1` 写成整数 `2130706433` 后，`http://2130706433:28773/public/images/404.png` 未被过滤，接口返回 `{"done":{"name":"404.png"}}`；落盘文件与本机 28773 服务返回的原文件逐字节一致。

**修复要求**：若业务不必需，禁用 URL 上传。否则只允许 HTTP/HTTPS，解析并固定连接目标，对每个 IPv4/IPv6 地址使用 `FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE` 等完整策略校验；拒绝解析结果变化、用户信息、异常端口和非规范 IP；每次重定向都重新解析与校验，限制跳转次数、响应体大小和超时，并避免把响应直接保存到可公开访问目录。

### 26. 高危 — 无条件信任 `X-Forwarded-For`，上传 IP 黑白名单和游客配额可绕过

**文件**: `app/function.php:1462-1536`, `app/function.php:1915-1958`, `app/upload.php:49-76`, `api/index.php:30-40`

`real_ip()` 无论直连来源是否为可信反向代理，都优先采用客户端提供的 `X-Forwarded-For` 或 `Client-IP`，并从中提取第一个看似 IPv4 的片段。上传 IP 黑白名单、网页游客每日上传次数和上传审计日志都依赖这个结果。

任意远程客户端都可以自行设置请求头来轮换 IP、绕过黑名单与每日配额，或冒充白名单地址；日志中的攻击来源也会被污染。该函数还不支持 IPv6，合法 IPv6 地址会归并为 `0.0.0.0`，造成不同用户共享配额和误封。

函数级实测：连接地址固定为 `127.0.0.1` 时，黑名单 `127.0.0.1` 正常阻止；加入 `X-Forwarded-For: 203.0.113.77` 后 `real_ip()` 返回伪造值，黑名单判定变为放行。连接地址为 `198.51.100.20` 时，伪造 `X-Forwarded-For: 192.0.2.10` 也能通过仅允许 `192.0.2.10` 的白名单。

**修复要求**：默认只使用经过 `FILTER_VALIDATE_IP` 验证的 `REMOTE_ADDR`。新增显式可信代理网段配置；仅当直连地址属于可信代理时，才按代理约定从右向左解析转发链，并完整支持 IPv4/IPv6。黑白名单、游客配额、API/登录限流和日志必须统一使用同一个可信客户端地址函数，并增加伪造头、代理链和 IPv6 测试。

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

### 9. SVG 上传 XSS 过滤不完整（已修复）

**文件**: `app/upload.php:96`, `api/index.php:66`

```php
preg_match('/<script[\s\S]*?<\/script>/', $svg) || stripos($svg, 'href=')
```

仅检测 `<script>` 标签和 `href=`。事件处理器如 `<svg onload="alert(1)">`、`<foreignObject>` 内部 HTML/JS 可绕过。

**修复状态**：不再尝试净化 SVG。默认配置、浏览器允许列表、普通上传、API、分片上传和后台文件管理器均禁用 SVG；服务端同时检查扩展名、MIME 与文件内容，避免大小写、旧配置和伪装扩展名绕过。回归测试覆盖上游 issue #260 的 `onload` 样例、伪装 JPEG、配置持久化与正常 PNG 上传。

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
