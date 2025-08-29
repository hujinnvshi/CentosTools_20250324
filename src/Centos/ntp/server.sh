#!/bin/bash
# NTP服务器配置脚本

# 安装NTP服务
if [ -f /etc/redhat-release ]; then
    yum install -y ntp
    systemctl enable ntpd
    systemctl start ntpd
elif [ -f /etc/debian_version ]; then
    apt-get update
    apt-get install -y ntp
    systemctl enable ntp
    systemctl start ntp
else
    echo "Unsupported OS"
    exit 1
fi

# 配置NTP服务器
cat > /etc/ntp.conf <<EOF
# 使用本地时钟作为时间源
server 127.127.1.0
fudge 127.127.1.0 stratum 10

# 允许内网客户端访问
restrict 192.168.20.0 mask 255.255.255.0 nomodify notrap

# 日志配置
logfile /var/log/ntp.log
logconfig =syncall +clockall

# 时间同步精度设置
tinker panic 0
EOF

# 重启NTP服务
systemctl restart ntpd

# 设置硬件时钟同步
hwclock --systohc

echo "NTP服务器配置完成"