<?php

/**
 * Program: EasyImage2.0
 * Author: Icret
 * Date: 2022/3/13 20:11
 * For: 源图保护解密
 */

require_once __DIR__ . '/function.php';

$real_path = false;
if (isset($_GET['key']) && is_string($_GET['key'])) {
    $hidden_path = urlHash($_GET['key'], 1, $config['hide_key']);
    $real_path = resolve_storage_file($hidden_path);
}

if ($real_path === false) {
    http_response_code(404);
    $real_path = APP_ROOT . '/public/images/404.png';
}

// 获取文件后缀
$ex = pathinfo($real_path, PATHINFO_EXTENSION);

// 设置头
header('Content-Type: image/' . $ex);

//输出文件
echo file_get_contents($real_path);

exit;
