#!/bin/bash
# VictoriaMetrics Cleanup Script for CentOS 7.9
# Author: Your Name
# Date: $(date +%Y-%m-%d)
# Version: 1.0

# 配置参数 - 必须与安装脚本一致
VM_USER="victoriametrics"          # 运行用户
VM_GROUP="victoriametrics"         # 运行组
DATA_DIR="/var/lib/victoriametrics" # 数据存储目录
CONFIG_DIR="/etc/victoriametrics"  # 配置文件目录
LOG_DIR="/var/log/victoriametrics" # 日志目录

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本必须以root权限运行"
    exit 1
fi

echo "开始清理 VictoriaMetrics 安装..."

# 1. 停止并禁用服务
echo "停止并禁用 VictoriaMetrics 服务..."
systemctl stop victoriametrics 2>/dev/null
systemctl disable victoriametrics 2>/dev/null

# 2. 删除服务文件
echo "删除 systemd 服务文件..."
rm -f /etc/systemd/system/victoriametrics.service
systemctl daemon-reload

# 3. 删除二进制文件
echo "删除 VictoriaMetrics 二进制文件..."
rm -f /usr/local/bin/victoria-metrics

# 4. 删除配置文件
echo "删除配置文件..."
rm -rf $CONFIG_DIR

# 5. 删除日志文件
echo "删除日志文件..."
rm -rf $LOG_DIR

# 6. 删除日志轮转配置
echo "删除日志轮转配置..."
rm -f /etc/logrotate.d/victoriametrics

# 7. 删除 README 文件
echo "删除 README 文件..."
rm -f /root/victoriametrics-README.md

# 8. 删除临时安装包
echo "删除临时安装包..."
# rm -f /tmp/victoria-metrics-linux-amd64-*.tar.gz

# 9. 删除数据目录（可选）
read -p "是否删除数据目录 $DATA_DIR？这将永久删除所有监控数据！(y/N): " delete_data
if [[ "$delete_data" =~ ^[Yy]$ ]]; then
    echo "删除数据目录 $DATA_DIR..."
    rm -rf $DATA_DIR
else
    echo "保留数据目录 $DATA_DIR"
fi

# 10. 删除用户和组（可选）
read -p "是否删除用户和组 ($VM_USER:$VM_GROUP)？(y/N): " delete_user
if [[ "$delete_user" =~ ^[Yy]$ ]]; then
    echo "删除用户 $VM_USER 和组 $VM_GROUP..."
    userdel $VM_USER 2>/dev/null
    groupdel $VM_GROUP 2>/dev/null
else
    echo "保留用户 $VM_USER 和组 $VM_GROUP"
fi

echo "清理完成！"
echo "VictoriaMetrics 已完全移除"