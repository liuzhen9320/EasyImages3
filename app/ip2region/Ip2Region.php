<?php

/**
 * class Ip2Region
 * 为兼容老版本调度而创建，封装 ip2region v3.17.0 的 Searcher 类
 * @author Anyon<zoujingli@qq.com>
 * @datetime 2022/07/18
 */
class Ip2Region
{
    /**
     * 查询实例对象
     * @var \ip2region\xdb\Searcher
     */
    private $searcher;

    /**
     * 初始化构造方法
     * @throws Exception
     */
    public function __construct()
    {
        class_exists('ip2region\xdb\Searcher') or include __DIR__ . '/Searcher.class.php';
        $this->searcher = \ip2region\xdb\Searcher::newWithFileOnly(
            \ip2region\xdb\IPv4::default(),
            __DIR__ . '/ip2region.xdb'
        );
    }

    /**
     * 兼容原 memorySearch 查询
     * @param string $ip
     * @return array
     * @throws Exception
     */
    public function memorySearch($ip)
    {
        return ['city_id' => 0, 'region' => $this->searcher->search($ip)];
    }

    /**
     * 兼容原 binarySearch 查询
     * @param string $ip
     * @return array
     * @throws Exception
     */
    public function binarySearch($ip)
    {
        return $this->memorySearch($ip);
    }

    /**
     * 兼容原 btreeSearch 查询
     * @param string $ip
     * @return array
     * @throws Exception
     */
    public function btreeSearch($ip)
    {
        return $this->memorySearch($ip);
    }

    /**
     * 直接查询并返回名称
     * @param string $ip
     * @return string
     * @throws \Exception
     */
    public function simple($ip)
    {
        $geo = $this->memorySearch($ip);
        $arr = explode('|', str_replace(['0|'], '|', isset($geo['region']) ? $geo['region'] : ''));
        if (($last = array_pop($arr)) === '内网IP') $last = '';
        return join('', $arr) . (empty($last) ? '' : "【{$last}】");
    }

    /**
     * destruct method
     * resource destroy
     */
    public function __destruct()
    {
        $this->searcher->close();
        unset($this->searcher);
    }
}
