# 安装
chmod +x centos_bywave_download.sh
sudo ./centos_bywave_download.sh "https://sub.bbwwvip.org/subscribe/435800/la8WuuCKoHfT"


# 手动重启
ps -ef | grep ss-local
pkill -f ss-local
ss-local -c /etc/shadowsocks-libev/configs/node3.json -u -v > /dev/null 2>&1 &
netstat -tunlp | grep 1080


# 测试连通性
# 返回HTTP头信息
curl -k -x socks5h://127.0.0.1:1080 https://www.google.com -I -v
# 测试响应时间
curl -x socks5h://127.0.0.1:1080 https://www.google.com --max-time 5 -o /dev/null -s -w "%{time_total}\n"
# 测试下载速度
wget -e use_proxy=yes -e http_proxy=socks5h://127.0.0.1:1080 https://www.google.com -O /dev/null