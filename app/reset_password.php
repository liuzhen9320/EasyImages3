<?php
include_once __DIR__ . "/header.php";

$value = '';
if (isset($_POST['password']) && is_string($_POST['password'])
    && strlen($_POST['password']) >= 8 && strlen($_POST['password']) <= 128) {
    $value = easyimage_password_hash($_POST['password']);
}

?>
<div class="row">
    <div class="col-md-12">
        <p class="text-primary">忘记账号可以打开<code>/config/config.php</code>文件找到<code data-toggle="tooltip" title="'user'=><strong>admin</strong>'">user</code>对应的键值->填入</p>
        <p class="text-success">生成新密码散列后，打开<code>/config/config.php</code>文件并替换<code>password</code>对应的键值。</p>
        <h4 class="text-danger">更改后会立即生效并重新登录,请务必牢记账号和密码! </h4>
        <?php if ($value !== '') : ?>
            <pre><?php echo htmlspecialchars($value, ENT_QUOTES, 'UTF-8'); ?></pre>
        <?php endif; ?>
    </div>
    <div class="col-md-12">
        <form action="<?php echo $_SERVER['SCRIPT_NAME']; ?>" method="post" class="form-horizontal">
            <div class="form-group">
                <label for="password" class="col-sm-2">新密码</label>
                <div class="col-md-6 col-sm-10">
                    <input type="password" class="form-control" id="password" name="password" required minlength="8" maxlength="128" autocomplete="new-password" placeholder="输入 8 至 128 位新密码">
                </div>
            </div>
            <div class="form-group">
                <div class="col-sm-offset-2 col-sm-10">
                    <button type="submit" class="btn btn-primary">获取新的密码</button>
                </div>
            </div>
        </form>
    </div>
</div>
<script>
    // 更改网页标题
    document.title = "获取新的密码 - <?php echo $config['title']; ?>"
</script>
<?php

include_once __DIR__ . "/footer.php";
