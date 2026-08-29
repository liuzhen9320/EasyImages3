# AGENTS.md — EasyImage3 (简单图床)

## Project Overview

EasyImage is a **database-less, single-user image hosting** PHP application. Users upload images, get back multiple link formats (direct URL, Markdown, BBCode, HTML, thumbnail, delete link). Supports optional API access, guest uploaders, image compression, watermarking, thumbnailing, content moderation (NSFW), and FTP offloading.

**Upstream**: [icret/EasyImages2.0](https://github.com/icret/EasyImages2.0) — v2.8.7 (source: `app/base.php:36`). The `admin/version.php` file reads `2.8.8`.

**Demo**: [https://png.cm/](https://png.cm/)

---

## Directory Structure & Entry Points

| Path | Purpose |
|------|---------|
| `index.php` | Home page (uploader UI) — includes `app/header.php` |
| `app/` | Core application logic |
| `app/header.php` | HTML head, navbar, global JS/CSS — includes `function.php` |
| `app/function.php` | **Main function library** — includes `base.php`, `WaterMask.php`, `config.guest.php` |
| `app/base.php` | Bootstrap: sets charset, timezone, memory limit, defines `APP_ROOT` and `APP_VERSION` |
| `app/upload.php` | Web upload handler (`Verot\Upload` namespace) |
| `app/del.php` | Delete/recycle handler — uses `urlHash()` for deletion tokens |
| `app/list.php` | "广场" (public gallery) — lists images by `Y/m/d/` directory |
| `app/history.php` | Upload history page |
| `app/thumb.php` | Thumbnail generation via TimThumb (modified) GET params: `src`, `w`, `h`, `q`, `a`, `zc` |
| `app/hide.php` | Source image protection — decrypts obfuscated paths via `urlHash()` |
| `app/check.php` | Environment check modal (runs on first access, creates `EasyIamge.lock`) |
| `app/class.upload.php` | Verot/Upload library — handles file validation, image processing, upload |
| `app/class.thumb.php` | Thumbnail class by Dejan (QQ: 673008865) — crop modes: `middle`, `top`, `bottom` |
| `app/info.php` | Image EXIF info display page |
| `app/DMCA.php` | Terms/Privacy/DMCA page |
| `app/WaterMask.php` | Watermark (text or image overlay) |
| `app/bing.php` | Bing daily wallpaper for login background |
| `app/captcha.php` | CAPTCHA image generation |
| `app/compress/` | Image compression: Imagick (`class.Imgcompress.php`) and TinyPNG (`TinyImg.php`) |
| `app/ip2region/` | IP geolocation library for upload logs |
| `app/chart.php` | Statistics computation (daily/monthly/yearly counts) |
| `app/total_files.php` | Directory/file counting utilities |
| `app/Ubench.php` | PHP benchmarking library |
| `app/TimThumb.php` | TimThumb derivative with caching |
| `app/Zebra_Image.php` | Alternative image manipulation library |
| `api/index.php` | **API upload endpoint** — expects `$_FILES['image']`, `$_POST['token']` |
| `api/public.php` | Public statistics API — responds to `?show=` param |
| `admin/` | Admin panel |
| `admin/admin.inc.php` | **Settings page** — writes to `config/config.php`, `config/api_key.php`, `config/config.guest.php` |
| `admin/index.php` | Login page |
| `admin/manager.php` | File manager (TinyFileManager v2.4.7) |
| `admin/chart.php` | ECharts statistics dashboard |
| `admin/terms.php` | Terms management |
| `admin/version.php` | Read-only version file (`2.8.8`) |
| `install/` | Installation wizard (`install.php`, `contorl.php`) — creates `install.lock` when done |
| `config/` | **All persistent state lives here** (no database) |
| `config/config.php` | **Main config** — PHP array, `$config`, written via `cache_write()` |
| `config/config.guest.php` | Guest uploader accounts — `$guestConfig` array |
| `config/api_key.php` | API tokens — `$tokenList` array |
| `i/` | Image storage directory (default) — `.htaccess` blocks PHP execution |
| `public/` | Static assets (CSS, JS, fonts, images) |
| `public/static/` | ZUI framework, jQuery, ECharts, NProgress, ViewJS, TinyFileManager assets |
| `docs/` | Documentation site (docsify-based) |

---

## Key Architectural Patterns

### No Database — File-Based Everything

- All configuration is stored as PHP arrays in `config/*.php` files, written via `cache_write()` in `app/function.php`.
- Images stored on filesystem under `i/Y/m/d/filename.ext` (configurable `storage_path`).
- Upload logs written to `admin/logs/` as flat files.
- Statistics cached to `admin/logs/counts/chart-*.php` files.

### Request Flow

```
User -> index.php (or admin/*.php)
         -> app/header.php (HTML shell, navbar)
              -> app/function.php (helpers)
                   -> app/base.php (constants, timezone, memory)
                        -> config/config.php ($config)
```

### Config Storage Gotcha

`admin/admin.inc.php` writes config using `cache_write()`, which serializes arrays as PHP source. This means the config files are **valid PHP** — any syntax error in manually edited values can break the entire site. Passwords are stored with PHP's `password_hash()` format.

### Routing

**No router** — direct file-based routing. Every `.php` file is an entry point. Common pattern:

1. `require_once __DIR__ . '/function.php'` (loads helpers + config)
2. Optionally `require_once APP_ROOT . '/app/header.php'` (HTML shell)
3. Logic + output
4. `require_once APP_ROOT . '/app/footer.php'` (close HTML)

---

## Authentication & Authorization

| Level | Check | Config |
|-------|-------|--------|
| Admin | `is_who_login('admin')` | `$config['user']` + `password_verify()` |
| Logged-in status | `is_who_login('status')` | Server-side PHP session |
| Guest uploader | Array key exists in `$guestConfig` | `config/config.guest.php` |
| API token | `check_api($token)` | `config/api_key.php` — `$tokenList[token]['expired']` |

Auth is checked by `_login()` in `app/function.php`. The browser only receives the random `easyimage_session` identifier; credentials and password hashes remain server-side.

### Important Auth Gotcha

- `mustLogin` forces authentication before upload through the same server-side session.
- The guest uploader accounts in `config.guest.php` have password hashes, expiry timestamps, and `add_time`.
- Legacy 64-character SHA-256 password values are migrated to `password_hash()` after the next successful login.
- There is a bug/gotcha in `admin/index.php:11`: `if ($_GET['login'] = 'logout')` uses **assignment** not comparison (`==`). This is intentional but looks like a bug — it will always evaluate as true.

---

## Upload Pipeline

### Web Upload (`app/upload.php`)

1. Check `mustLogin` flag → reject if not logged in
2. Check `$_FILES['file']` exists
3. Validate `$_POST['sign']` timestamp (must be within 12306 seconds)
4. Check IP allow/deny list
5. Check daily upload limit for guests (`ip_upload_counts`)
6. Optionally handle chunked upload (`$config['chunks']`)
7. Instantiate `new Upload($_FILES['file'], 'zh_CN')` (Verot\Upload namespace)
8. Process: validate MIME type, reject SVG, rename file, apply watermark, compress, thumbnail
9. Return JSON: `{result, code, url, thumb, del, srcName}`

### API Upload (`api/index.php`)

Same pipeline but:
- Uses `$_FILES['image']` (not `file`)
- Authenticates via `$_POST['token']` + `config/api_key.php`
- Cross-origin headers set
- Optional token ID suffix on filenames

### Common Upload Responses

| Code | Meaning |
|------|---------|
| 200 | Success |
| 204 | No file selected |
| 205 | IP blocked, file exists |
| 401 | Login required |
| 403 | Sign expired |
| 406 | File too large |
| 415 | Unsupported format |

---

## JSON Response Convention

All upload endpoints return JSON with `JSON_UNESCAPED_UNICODE` flag. Standard shape:

```php
array("result" => "success|failed", "code" => 200, "message" => "...")
```

Always use `JSON_UNESCAPED_UNICODE` when returning JSON containing Chinese text.

---

## Image Processing Details

### File Naming (`imgName()` in `function.php`)

- `$config['imgName']` controls naming strategy: `default` (original), `dateName` (date-based), `md5` (MD5 hash)
- File extension always preserved
- Token (API) uploads can append token ID suffix (`$config['token_suffix_ID']`)

### Storage Path

- Default: `i/Y/m/d/` (configurable via `$config['storage_path']`)
- Folder path pattern: `Y/m/d/`, `Y-m-d/`, or custom
- Hidden path mode: `config_path()` in `function.php` applies `hide_path` logic — obfuscated via `urlHash()` with `$config['hide_key']`
- Delete and recycle operations must pass through `normalize_storage_web_path()` and `resolve_storage_file()` before local or FTP mutations
- Protected image tokens are authenticated by `urlHash()`, then independently constrained to storage by `resolve_storage_file()`

### Image Validation

- MIME type filtering via `$handle->allowed = array('image/*')`
- Dimension limits: `minWidth`/`minHeight`, `maxWidth`/`maxHeight`
- SVG uploads are rejected by extension, MIME type, and file content
- Animated GIF/WebP detection: `is_Gif_Webp_Animated()` — animated images skip compression and thumbnail operations

### Compression

Two engines:
- **Imgcompress** (Imagick): quality ratio `compress_ratio/100`, skips animated images
- **TinyPNG**: uses TinyPNG API key, also skips animated images

### Watermark

- `WaterMask.php` supports text and image watermarks
- Position: 1-9 (numpad-style, 9 = bottom-right)
- Text watermark supports custom font, color, size

### Thumbnails

- Two implementations: `class.thumb.php` (simple crop) and `TimThumb.php` (feature-rich with caching)
- TimThumb supports: `src`, `w`, `h`, `q` (quality 0-100), `a` (alignment), `zc` (zoom/crop mode 0-3), `f` (filters), `s` (sharpening)
- Cache location: `admin/logs/timthumb/` — cache frequency controlled by `cache_freq` (in hours)

---

## Admin Panel Structure

| URL | Page | Note |
|-----|------|------|
| `/admin/index.php` | Login | Also handles logout via `?login=logout` |
| `/admin/admin.inc.php` | Settings | Writes to `config.php`, `api_key.php`, `config.guest.php` |
| `/admin/chart.php` | Statistics | ECharts + custom chart engine (`zui.chart.php`) |
| `/admin/manager.php` | File manager | TinyFileManager 2.4.7; local uploads only (`file_manage` config to disable) |
| `/admin/terms.php` | Terms management | |
| `/admin/version.php` | Version info | Plain text file, single line `2.8.8` |

### Settings Writing Mechanism

`admin/admin.inc.php` uses `cache_write()`:
```php
function cache_write($file, $data) {
    file_put_contents($file, '<?php' . "\n" . '$config=' . var_export($data, true) . ';');
}
```

This overwrites the entire config file. Any missing keys from the form will be lost. `array_replace($config, $postArr)` merges, but be aware that **checkbox-style settings not present in POST will be reset to default/empty**.

---

## Key Config Options

| Key | Type | Default | Effect |
|-----|------|---------|--------|
| `mustLogin` | bool | 0 | Require login to upload |
| `apiStatus` | bool | 0 | Enable API upload |
| `public` | bool | 0 | Enable public statistics API |
| `compress` | bool | 0 | Enable image compression |
| `watermark` | bool | 0 | Enable watermark |
| `thumbnail` | bool | 1 | Enable auto-thumbnail generation |
| `hide_path` | bool | 0 | Obfuscate storage paths |
| `checkImg` | bool | 0 | Enable NSFW content check |
| `image_recycl` | bool | 1 | Enable recycle bin (images moved to `recycle/` subdirectory) |
| `chunks` | int | 0 | Chunk size for upload (0 = disabled) |
| `storage_path` | string | `Y/m/d/` | Date-based folder structure |
| `extensions` | string | `jpg,jpeg,png,gif,bmp,webp,ico,jfif,tif,tga` | Allowed extensions (SVG is always disabled) |
| `trusted_proxies` | string | empty | Trusted proxies allowed to supply client IP via `CF-Connecting-IP`, `X-Real-IP`, then `X-Forwarded-For` |
| `maxSize` | int | 10485760 | Max file size (bytes) |
| `timezone` | string | `Asia/Shanghai` | PHP timezone |

Complete keys visible in `config/config.php`.

---

## Development & CI

### PHP Version

- Requires **PHP 5.6+**, recommended **PHP 7.0+** (source: `README.md`, `app/check_admin.inc.php`)
- Required PHP extensions: `fileinfo`, `gd`, `openssl`, `iconv`, `mbstring`
- Optional: `imagick` (for Imagick compression)

### CI (GitHub Actions)

| Workflow | Trigger | Action |
|----------|---------|--------|
| `php.yml` | push/PR to master | `composer validate --strict` then `composer install --prefer-dist --no-progress` |
| `codeql-analysis.yml` | push/PR to master | CodeQL analysis |
| `codacy-analysis.yml` | push/PR to master | Codacy analysis |
| `sonarcloud.yml` | push/PR to master | SonarCloud analysis (requires `SONAR_TOKEN` secret) |

**Important**: The `php.yml` workflow expects `composer.json` and `composer.lock`, but **this repository does not contain them** (confirmed: no `composer.*` files found). The validate step may fail, and install will produce a `vendor/` dir with only the root package. The CI is aspirational — the actual app is self-contained with no Composer dependencies.

### No Test Suite

There is no test framework, no test directory, and no test scripts. The `php.yml` workflow has the `Run test suite` step commented out.

### No Build System

No Makefile, no webpack, no build step. This is a traditional PHP application — deploy by copying files to a web server.

---

## Naming Conventions

| Category | Convention | Example |
|----------|-----------|---------|
| PHP functions | camelCase | `is_who_login()`, `imgName()`, `getFile()` |
| Config keys | snake_case | `$config['maxSize']`, `$config['upload_first_show']` |
| Files | lowercase, `.php` | `upload.php`, `function.php`, `admin.inc.php` |
| CSS classes | lowercase, kebab-case in ZUI | `col-md-12`, `uploader-message` |
| JS | camelCase, jQuery-style | `uploadCopy()`, `$('#upShowID').uploader()` |
| Directory structure | `Y/m/d/` (PHP date format) | `i/2026/07/09/photo.jpg` |

---

## Important Gotchas

### 1. Login Assignment Bug
`admin/index.php:11`: `if ($_GET['login'] = 'logout')` uses `=` not `==`. This is intentional and forces the logout branch to always execute when the parameter exists. Don't "fix" it.

### 2. Password Authentication
Login forms submit the password over HTTPS and `_login()` verifies it server-side. Installation, password changes, and recovery hashes must use `easyimage_password_hash()` so stored formats remain consistent.

### 3. Config File Format
Config files are valid PHP written via `var_export()`. Editing them manually requires **valid PHP syntax** — a single broken quote will take down the site.

### 4. namespace Verot\Upload
The `app/upload.php`, `api/index.php`, and `app/class.upload.php` all operate in `namespace Verot\Upload`. This means `$config` and functions from `app/function.php` are accessed as **global** variables (`global $config;` or `\function_name()`). When adding code to these files, pay attention to the namespace scope.

### 5. `static_cdn()` Function
Used throughout templates for asset URLs. Respects `$config['static_cdn']` flag — if enabled, assets load from `$config['static_cdn_url']` (jsDelivr CDN), otherwise from local.

### 6. Chunked Upload
When `$config['chunks']` is non-zero, both `app/upload.php` and `api/index.php` switch to chunked mode via `chunk($_POST['name'])`. The chunked path creates temporary files. This is delicate — the default is 0 (disabled).

### 7. Directory `i/.htaccess`
The `i/` directory has `<Files ~ "\.php">` deny rule to prevent direct PHP execution in the upload directory.

### 8. Language Files
`app/lang/class.upload.zh_CN.php` and variants are loaded by the Verot upload class based on the second constructor parameter (`new Upload($_FILES['file'], 'zh_CN')`).

### 9. Snowflake ID
`app/class.snowflake.php` exists for generating unique IDs, but the filename generation in `function.php` (`imgName()`) primarily uses timestamp + random methods, not Snowflake by default.

### 10. EasyIamge.lock (typo)
The environment check creates `config/EasyIamge.lock` (note the typo: "Iamge" not "Image"). Deleting this file re-shows the environment check modal.

---

## Quick Reference

```bash
# No build, test, or package commands exist.
# Deploy: copy all files to a PHP-enabled web server
# Requirements: PHP 5.6+, extensions: fileinfo, gd, openssl
# Point web root to the repository root
# Visit /install/index.php for first-time setup
# Config files: config/config.php, config/api_key.php, config/config.guest.php
```

### Links
- **Source**: https://github.com/icret/EasyImages2.0
- **Docs**: https://icret.github.io/EasyImages2.0/#/
- **Demo**: https://png.cm/
- **Telegram**: https://t.me/Easy_Image
- **QQ Group**: 954441002
