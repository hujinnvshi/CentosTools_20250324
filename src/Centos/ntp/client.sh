#!/bin/bash
# NTP客户端配置脚本

SERVER_IP="192.168.20.199"  # NTP服务器IP

# 安装NTP客户端
if [ -f /etc/redhat-release ]; then
    yum install -y ntp
    SERVICE="ntpd"
elif [ -f /etc/debian_version ]; then
    apt-get update
    apt-get install -y ntp
    SERVICE="ntp"
else
    echo "Unsupported OS"
    exit 1
fi

# 配置NTP客户端
cat > /etc/ntp.conf <<EOF
# 使用内网NTP服务器
server $SERVER_IP iburst

# 禁止修改NTP配置
restrict default nomodify notrap nopeer noquery

# 允许本地访问
restrict 127.0.0.1
restrict ::1

# 时间同步精度设置
tinker panic 0
EOF

# 启动NTP服务
systemctl enable $SERVICE
systemctl restart $SERVICE

# 强制立即同步时间
ntpdate -u $SERVER_IP
hwclock --systohc

echo "NTP客户端配置完成"