<?php

/**
 * 下载文件
 * https://www.php.cn/php-weizijiaocheng-394566.html
 */
//获取要下载的文件名
require_once __DIR__ . '/function.php';

if (!isset($_GET['dw']) && !isset($_GET['history'])) {
    exit('No file path');
}

$requestedPath = isset($_GET['dw']) ? $_GET['dw'] : $_GET['history'];
$requestedPath = str_replace('\\', '/', $requestedPath);
$storagePath = '/' . trim(str_replace('\\', '/', $config['path']), '/') . '/';
$normalizedPath = '/' . ltrim($requestedPath, '/');

// 历史上传记录的路径
if (strpos($normalizedPath, $storagePath) !== 0) {
    $normalizedPath = $storagePath . ltrim($normalizedPath, '/');
}

$storageRoot = realpath(APP_ROOT . $storagePath);
$dw = strpos($normalizedPath, "\0") === false ? realpath(APP_ROOT . $normalizedPath) : false;
$storagePrefix = $storageRoot === false ? false : rtrim($storageRoot, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR;

// 仅允许下载图片存储目录内的普通文件
if ($dw === false || $storagePrefix === false || strpos($dw, $storagePrefix) !== 0 || !is_file($dw)) {
    exit('No File');
}

// 过滤下载非指定上传文件格式
$dw_extension = strtolower(pathinfo($dw, PATHINFO_EXTENSION));
$filter_extensions = array_map('strtolower', array_map('trim', explode(',', $config['extensions'])));

// 过滤下载其他格式
$filter_other = array('php', 'php3', 'php4', 'php5', 'php7', 'php8', 'phtml', 'pht', 'phar', 'phps', 'json', 'log', 'lock');

// 先过滤后下载
if (in_array($dw_extension, $filter_extensions) && !in_array($dw_extension, $filter_other)) {
    //设置头信息
    header('Content-Disposition:attachment;filename=' . basename($dw));
    header('Content-Length:' . filesize($dw));
    //读取文件并写入到输出缓冲
    readfile($dw);
    exit;
} else {
    exit('Downfile Type Error');
}
