<?php
require_once __DIR__ . '/../app/function.php';
require_once __DIR__ . '/functions.php';

if (file_exists(APP_ROOT . '/config/install.lock')) {
    exit(header('Location:/../index.php'));
}
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    install_error('安装提交只接受 POST 请求。', 405);
}

$installToken = isset($_POST['install_token']) ? $_POST['install_token'] : null;
if (!install_consume_token('configuration', $installToken)) {
    install_error('安装令牌无效或已使用。', 403);
}

$required = array('domain', 'imgurl', 'user', 'password', 'repassword');
foreach ($required as $field) {
    if (!isset($_POST[$field]) || !is_string($_POST[$field]) || $_POST[$field] === '') {
        install_error('安装参数不完整。', 422);
    }
}

$domain = install_normalize_url($_POST['domain']);
$imgurl = install_normalize_url($_POST['imgurl']);
$user = trim($_POST['user']);
$password = $_POST['password'];
if ($domain === false || $imgurl === false) {
    install_error('网站域名和图片域名必须是有效的 HTTP(S) 地址。', 422);
}
if (!preg_match('/\A[A-Za-z0-9_.-]{1,64}\z/D', $user)) {
    install_error('管理员账号格式无效。', 422);
}
if ($password !== $_POST['repassword'] || strlen($password) < 8 || strlen($password) > 128) {
    install_error('两次密码必须一致，长度应为 8 至 128 位。', 422);
}

$passwordHash = easyimage_password_hash($password);
if ($passwordHash === false) {
    install_error('管理员密码散列失败。', 500);
}

$config['domain'] = $domain;
$config['imgurl'] = $imgurl;
$config['user'] = $user;
$config['password'] = $passwordHash;

$configFile = APP_ROOT . '/config/config.php';
$lockFile = APP_ROOT . '/config/install.lock';
$guardFile = APP_ROOT . '/config/.installing.lock';
$guard = install_acquire_lock($guardFile);
if ($guard === false) {
    install_error('无法锁定安装流程，请检查 config 目录权限。', 500);
}

clearstatcache(true, $lockFile);
if (file_exists($lockFile)) {
    install_release_lock($guard, $guardFile);
    install_error('程序已经安装。', 409);
}
if (!install_write_config_and_lock($configFile, $lockFile, $config)) {
    install_release_lock($guard, $guardFile);
    install_error('写入配置或安装锁失败，原配置已保留。', 500);
}
install_release_lock($guard, $guardFile);

if (isset($_POST['del_extra_files']) && $_POST['del_extra_files'] === 'del') {
    @unlink(APP_ROOT . '/LICENSE');
    @unlink(APP_ROOT . '/README.md');
    @deldir(APP_ROOT . '/admin/logs');
    @unlink(APP_ROOT . '/SECURITY.md');
    @unlink(APP_ROOT . '/.whitesource');
    @unlink(APP_ROOT . '/CODE_OF_CONDUCT.md');
    @unlink(APP_ROOT . '/config/EasyIamge.lock');
    @deldir(APP_ROOT . '/.github');
    @deldir(APP_ROOT . '/.git');
    @deldir(APP_ROOT . '/docs');
}

if (isset($_POST['del_install']) && $_POST['del_install'] === 'del') {
    @deldir(APP_ROOT . '/install');
}
?>
<script>
    window.alert("安装成功,即将为您跳转到登陆界面!");
    location.href = "../admin/index.php";
</script>
