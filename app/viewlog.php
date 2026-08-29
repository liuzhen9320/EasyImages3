<?php

/**
 * 读取上传日志
 */

require_once __DIR__ . '/function.php';

// 非管理员不可访问!
if (!is_who_login('admin')) exit('Permission denied');

// 登录日志
if (isset($_GET['login_log'])) {
    $file = APP_ROOT . '/admin/logs/login/' . date('/Y-m-') . 'logs.php';
    echo '<pre class="pre-scrollable" style="background-color: rgba(0, 0, 0, 0);border-color:rgba(0, 0, 0, 0);">';
    if (is_file($file)) {
        echo file_get_contents($file);
    } else {
        echo '并未生成登录日志,请检查文件权限!';
    }
    exit('</pre>');
}

// 上传日志
require_once APP_ROOT . '/app/header.php';

if (isset($_POST['logDate'])) {
    if (!is_string($_POST['logDate']) || !preg_match('/\A\d{4}-(0[1-9]|1[0-2])\z/D', $_POST['logDate'])) {
        http_response_code(400);
        exit('Invalid log date');
    }
    $logFile = APP_ROOT . '/admin/logs/upload/' . $_POST['logDate'] . '.php';
} else {
    $logFile = APP_ROOT . '/admin/logs/upload/' . date('Y-m') . '.php';
}

try {
    if (is_file($logFile)) {
        require_once $logFile;
    } else {
        throw new Exception('<h3 class="alert alert-danger">日志文件不存在, 请在图床安全中开启上传日志!</h3>');
    }
    if (empty($logs)) {
        throw new Exception('<div class="alert alert-info">没有上传日志!<div>');
    }
} catch (Exception $e) {
    require_once APP_ROOT . '/app/footer.php';
    exit;
}

$escapeLogValue = function ($value) {
    return htmlspecialchars((string) $value, ENT_QUOTES, 'UTF-8');
};
$logRows = array();
foreach ($logs as $name => $values) {
    $source = isset($values['source']) ? $values['source'] : '';
    $date = isset($values['date']) ? $values['date'] : '';
    $ip = isset($values['ip']) && filter_var($values['ip'], FILTER_VALIDATE_IP) ? $values['ip'] : '0.0.0.0';
    $port = isset($values['port']) ? $values['port'] : '';
    $userAgent = isset($values['user_agent']) ? $values['user_agent'] : '';
    $path = isset($values['path']) ? $values['path'] : '';
    $md5 = isset($values['md5']) ? $values['md5'] : '';
    $size = isset($values['size']) ? $values['size'] : '';
    $checkImg = isset($values['checkImg']) ? $values['checkImg'] : 'OFF';
    $from = isset($values['from']) ? $values['from'] : 'web';
    $safePath = $escapeLogValue($path);
    $viewUrl = $escapeLogValue(rand_imgurl() . $path);
    $infoUrl = '/app/info.php?img=' . rawurlencode($path);

    $logRows[] = array(
        'orgin' => $escapeLogValue($name),
        'source' => '<input class="form-control input-sm" type="text" value="' . $escapeLogValue($source) . '" readonly>',
        'date' => $escapeLogValue($date),
        'ip' => '<a href="http://freeapi.ipip.net/' . rawurlencode($ip) . '" target="_blank">' . $escapeLogValue($ip . ':' . $port) . '</a>',
        'ip2region' => ip2region($ip),
        'user_agent' => '<input class="form-control input-sm" type="text" value="' . $escapeLogValue($userAgent) . '" readonly>',
        'path' => '<input class="form-control input-sm" type="text" value="' . $safePath . '" readonly>',
        'md5' => '<input class="form-control input-sm" type="text" value="' . $escapeLogValue($md5) . '" readonly>',
        'size' => $escapeLogValue($size),
        'checkImg' => strstr('OFF', $checkImg) ? '否' : '是',
        'from' => is_string($from) ? '网页' : 'API: ' . $escapeLogValue($from),
        'manage' => '<div class="btn-group"><a href="' . $viewUrl . '" target="_blank" class="btn btn-mini btn-success">查看</a> '
            . '<a href="' . $infoUrl . '" target="_blank" class="btn btn-mini">信息</a>'
            . '<a href="#" data-path="' . $safePath . '" onclick="ajax_post(this.getAttribute(\'data-path\'),\'recycle\')" class="btn btn-mini btn-info">回收</a> '
            . '<a href="#" data-path="' . $safePath . '" onclick="ajax_post(this.getAttribute(\'data-path\'),\'delete\')" class="btn btn-mini btn-danger">删除</a></div>',
    );
}
?>
<div class="col-md-12">
    <div id="logs" class="datagrid table-bordered">
        <div class="input-control search-box search-box-circle has-icon-left has-icon-right" id="searchboxExample2" style="margin-bottom: 10px;">
            <input id="inputSearchExample2" type="search" class="form-control search-input input-sm" placeholder="日志搜索...">
            <label for="inputSearchExample2" class="input-control-icon-left search-icon"><i class="icon icon-search"></i></label>
            <a href="#" class="input-control-icon-right search-clear-btn"><i class="icon icon-remove"></i></a>
        </div>
        <div class="datagrid-container"></div>
    </div>
    <p class="text-muted" style="font-size:10px;"><i class="modal-icon icon-info"></i> 建议使用分辨率 ≥ 1366*768px; 当前日志文件: <?php echo $logFile; ?></p>
</div>
<link rel="stylesheet" href="<?php static_cdn(); ?>/public/static/zui/lib/datagrid/zui.datagrid.min.css">
<script type="application/javascript" src="<?php static_cdn(); ?>/public/static/zui/lib/datagrid/zui.datagrid.min.js"></script>
<script>
    // 更改页面布局
    $(document).ready(function() {
        $("body").removeClass("container").addClass("container-fixed-lg");
    });

    // POST 删除提交
    function ajax_post(url, mode = 'delete') {
        $.post("del.php", {
                url: url,
                mode: mode,
                _csrf: <?php echo json_encode(csrf_token()); ?>
            },
            function(data, status) {
                console.log(data)
                let res = JSON.parse(data);
                new $.zui.Messager(res.msg, {
                    type: res.type,
                    icon: res.icon
                }).show();
                // 延时2秒刷新
                window.setTimeout(function() {
                    window.location.reload();
                }, 2000)
            });
    }

    // logs 数据表格
    $('#logs').datagrid({
        dataSource: {
            height: 800,
            cols: [{
                    label: '当前名称',
                    name: 'orgin',
                    width: 0.07
                },
                {
                    label: '源文件名',
                    name: 'source',
                    html: true,
                    width: 0.08
                },
                {
                    label: '上传时间',
                    name: 'date',
                    html: true,
                    width: 0.09
                },
                {
                    label: '上传IP及端口',
                    name: 'ip',
                    html: true,
                    width: 0.08
                },
                {
                    label: '上传地址',
                    name: 'ip2region',
                    html: true,
                    width: 0.1
                },
                {
                    label: 'User-Agent',
                    name: 'user_agent',
                    html: true,
                    width: 0.11
                },
                {
                    label: 'FILE-MD5',
                    name: 'md5',
                    html: true,
                    width: 0.1
                },
                {
                    label: '文件路径',
                    name: 'path',
                    html: true,
                    width: 0.11
                },
                {
                    label: '文件大小',
                    name: 'size',
                    html: true,
                    width: 0.06
                },
                {
                    label: '鉴黄?',
                    name: 'checkImg',
                    html: true,
                    width: 0.05
                },
                {
                    label: '来源',
                    name: 'from',
                    html: true,
                    width: 0.05
                },
                {
                    label: '管理',
                    name: 'manage',
                    html: true,
                    width: 0.1
                },
            ],
            array: <?php echo json_encode($logRows, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_HEX_TAG | JSON_HEX_AMP | JSON_HEX_APOS | JSON_HEX_QUOT); ?>
        },
        sortable: true,
        hoverCell: true,
        showRowIndex: true,
        responsive: true,
        height: 666,
        // ... 其他初始化选项
        configs: {
            R1: {
                style: {
                    color: '#00b8d4',
                    backgroundColor: '#e0f7fa'
                }
            },
        }
    });

    // 获取数据表格实例
    var logMyDataGrid = $('#logs').data('zui.datagrid');

    var myDate = new Date();
    logMyDataGrid.showMessage('已获取 <?php echo pathinfo($logFile, PATHINFO_FILENAME); ?> 月上传日志...... ', 'primary', 2000);

    // logMyDataGrid.showMessage('上传日志已加载完毕...... ', 'primary', 2500);

    // 按照 `name` 列降序排序
    logMyDataGrid.sortBy('date', 'desc');

    // 更改网页标题
    document.title = "<?php echo pathinfo($logFile, PATHINFO_FILENAME); ?>月上传日志 - <?php echo $config['title']; ?>"
</script>
<?php
require_once APP_ROOT . '/app/footer.php';
