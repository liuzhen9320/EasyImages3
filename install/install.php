<?php
require_once __DIR__ . '/../app/function.php';
require_once __DIR__ . '/functions.php';
// 存在程序锁则跳转主页
if (file_exists(APP_ROOT . '/config/install.lock')) {
    exit(header("Location:/../index.php"));
}

// 验证上一步环境检测
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    install_error('安装配置页只接受 POST 请求。', 405);
}
$state = isset($_POST['check']) ? $_POST['check'] : null;
$environmentToken = isset($_POST['install_token']) ? $_POST['install_token'] : null;
if ($state !== 'checked' || !install_consume_token('environment', $environmentToken)) {
    install_error('安装步骤已失效，请重新执行环境检查。', 403);
}
$installToken = install_issue_token('configuration');
if ($installToken === false) {
    install_error('无法创建安全安装会话。', 500);
}

?>
<!DOCTYPE html>
<html lang="zh-cn">

<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <title>EasyIamge 2.0 即将完成安装!</title>
    <meta http-equiv="X-UA-Compatible" content="IE=edge">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="keywords" content="EasyIamge 2.0 即将完成安装!" />
    <meta name="description" content="EasyIamge 2.0 即将完成安装!" />
    <link rel="shortcut icon" href="./../favicon.ico" type="image/x-icon" />
    <link rel="stylesheet" href="./../public/static/zui/css/zui.min.css?v1.10.0">
    <link rel="stylesheet" href="./../public/static/nprogress/nprogress.min.css?v1.10.0">
    <script type="application/javascript" src="./../public/static/zui/lib/jquery/jquery-3.6.4.min.js?v3.6.4"></script>
    <script type="application/javascript" src="./../public/static/zui/js/zui.min.js?v1.10.0"></script>
    <script type="application/javascript" src="./../public/static/qrcode/qrcode.min.js?v2.0"></script>
    <script type="application/javascript" src="./../public/static/nprogress/nprogress.min.js"></script>
    <style>
        .message {
            font-size: 12px;
            font-weight: bold;
            color: #999;
        }

        .wrong {
            color: red;
        }

        .right {
            color: green;
        }
    </style>
</head>

<body class="container">
    <!-- install header html end -->
    <h1 class="header-dividing" style="text-align:center">EasyIamge 2.0 网站基础配置</h1>
    <div class="col-md-10 col-md-offset-2" style="text-align: center;">
        <form class="form-horizontal" action="./contorl.php" method="post">
            <input type="hidden" name="install_token" value="<?php echo htmlspecialchars($installToken, ENT_QUOTES, 'UTF-8'); ?>">
            <div class="form-group">
                <label class="col-sm-2">网站域名,末尾不加"/"</label>
                <div class="col-md-6 col-sm-10">
                    <input type="url" class="form-control" name="domain" value="<?php echo htmlspecialchars(get_whole_url('/install/install.php'), ENT_QUOTES, 'UTF-8'); ?>" required="required" onkeyup="this.value=this.value.replace(/\s/g,'')" placeholder="网站域名与图片链接域名可以不同，比如A域名上传，可以返回B域名图片链接，如果不变的话，下边2个填写成一样的!" title="网站域名与图片链接域名可以不同，比如A域名上传，可以返回B域名图片链接，如果不变的话，下边2个填写成一样的!">
                </div>
            </div>
            <div class="form-group">
                <label class="col-sm-2">图片链接域名,末尾不加"/"</label>
                <div class="col-md-6 col-sm-10">
                    <input type="url" class="form-control" name="imgurl" value="<?php echo htmlspecialchars(get_whole_url('/install/install.php'), ENT_QUOTES, 'UTF-8'); ?>" required="required" placeholder="给图片的域名，末尾不加/，如果没有请填写和上边的一样即可" onkeyup="this.value=this.value.replace(/\s/g,'')">
                </div>
            </div>
            <div class="form-group">
                <label class="col-sm-2 ">管理账号</label>
                <div class="col-md-6 col-sm-10">
                    <input type="text" class="form-control" name="user" value="admin" required="required" maxlength="64" pattern="[A-Za-z0-9_.-]+" placeholder="请以大小写英文或数字输入管理员账号" onkeyup="this.value=this.value.replace(/[^A-Za-z0-9_.-]/g,'')">
                </div>
            </div>
            <div class="form-group">
                <label class="col-sm-2 ">管理密码</label>
                <span class="message">请输入8~128位密码</span>
                <div class="col-md-6 col-sm-10 register">
                    <input type="password" class="form-control inp" name="password" required="required" minlength="8" maxlength="128" autocomplete="new-password" placeholder="请使用英文输入法输入密码并不小于8位数">
                </div>
            </div>
            <div class="form-group">
                <label class="col-sm-2 ">确认密码</label>
                <div class="col-md-6 col-sm-10">
                    <input type="password" class="form-control" name="repassword" required="required" minlength="8" maxlength="128" autocomplete="new-password" placeholder="确认密码">
                </div>
            </div>
            <div class="form-group">
                <div class="col-sm-offset-2 col-sm-10">
                    <div class="checkbox">
                        <label>
                            <input type="checkbox" name="del_extra_files" value="del" checked><span style="font-weight: bold;color:green;" title="删除Github|Gitee下载的多余文件">删除多余文件</span>
                        </label>
                        <label>
                            <input type="checkbox" name="del_install" value="del"><span style="font-weight: bold;color:red;">删除安装目录</span>
                        </label>
                    </div>
                </div>
            </div>
            <div class="form-group">
                <div class="col-sm-offset-2 col-sm-10">
                    <a class="btn btn" href="index.php">上一步</a>
                    <button type="submit" class="btn btn-success">开始安装</button>
                </div>
            </div>
        </form>
    </div>
    <!-- install bottom HTML start -->
    <div class="modal fade" id="myModal">
        <div class="modal-dialog modal-sm">
            <div class="modal-content">
                <div class="modal-header">
                    <button type="button" class="close" data-dismiss="modal">
                        <span aria-hidden="true">x</span>
                        <span class="sr-only">关闭</span></button>
                    <h4 class="modal-title icon icon-mobile" style="text-align: center">扫描二维码使用手机上传</h4>
                </div>
                <div class="modal-body" align="center">
                    <input id="text" type="hidden" value="" />
                    <p id="qrcode"></p>
                </div>
                <div class="modal-footer">
                    <a class="btn btn-danger btn-sm" href="" target="_blank">访问</a>
                    <button type="button" class="btn btn-primary btn-sm" data-dismiss="modal">关闭</button>
                </div>
            </div>
        </div>
    </div>
    <script>
        // 双重验证密码
        var password = document.querySelector('.inp');
        var message = document.querySelector('.message');

        password.onblur = function() {
            if (this.value.length < 8 || this.value.length > 128) {
                message.innerHTML = '密码长度错误,应为8~128位';
                message.className = 'message wrong';
            } else {
                message.innerHTML = '密码长度正确';
                message.className = 'message right';
            }
        }

        // NProgress
        NProgress.configure({
            showSpinner: false
        });
        NProgress.set(0.5);
        NProgress.set(0.9);

        // js二维码 获取当前网址并赋值给id=text的value
        document.getElementById("text").value = window.location.href;
        var qrcode = new QRCode(document.getElementById("qrcode"), {
            width: 200,
            height: 200,
        });

        function makeCode() {
            var elText = document.getElementById("text");
            if (!elText.value) {
                alert("Input a text");
                elText.focus();
                return;
            }
            qrcode.makeCode(elText.value);
        }
        makeCode();
        $("#text").on("blur",
            function() {
                makeCode();
            }).on("keydown",
            function(e) {
                if (e.keyCode == 13) {
                    makeCode();
                }
            });
    </script>
    <footer class="text-muted small col-md-12" style="text-align: center;margin-bottom: 10px">
        <hr>
        <div>
            <!-- 对话框触发按钮 -->
            <a href="#" data-position="center" data-moveable="inside" data-moveable="true" data-toggle="modal" data-target="#myModal"><i class="icon icon-qrcode"></i>二维码 </a>
        </div>
        <?php echo 'Copyright © 2018' . date('-Y'); ?> <a href="https://png.cm" target="_blank">EasyImage</a> By Icret Version:<a href="https://github.com/icret/EasyImages2.0" target="_blank"> <?php echo APP_VERSION; ?></a>
    </footer>
</body>

</html>
