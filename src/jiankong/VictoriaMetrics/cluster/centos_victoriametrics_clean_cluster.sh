#!/bin/bash
# VictoriaMetrics 集群清理脚本
# 用于完全卸载之前部署的VictoriaMetrics集群
# 注意：此脚本会删除所有数据和配置文件，操作不可逆！

# 配置参数 - 与安装脚本保持一致
VM_USER="victoriametrics"          # 运行用户
VM_GROUP="victoriametrics"         # 运行组
BASE_DIR="/data/victoriametrics"   # 基础目录
CONFIG_DIR="/etc/victoriametrics"  # 配置文件目录
LOG_DIR="/var/log/victoriametrics" # 日志目录

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本必须以root权限运行"
    exit 1
fi

# 警告信息
echo "======================================================"
echo "警告：此脚本将完全删除VictoriaMetrics集群及其所有数据！"
echo "======================================================"
echo "将删除以下内容："
echo "1. 所有VictoriaMetrics服务 (vmstorage/vminsert/vmselect)"
echo "2. 所有配置文件和数据目录"
echo "3. 所有日志文件"
echo "4. 系统用户和组"
echo "5. README文档"
echo "======================================================"

# 确认操作
read -p "确定要完全清理VictoriaMetrics集群吗？(y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "操作已取消"
    exit 0
fi

# 停止并禁用所有服务
echo "停止并禁用服务..."
services=(
    vmstorage1 vmstorage2 vmstorage3
    vminsert1 vminsert2
    vmselect1 vmselect2
)

for service in "${services[@]}"; do
    # 检查服务是否存在
    if systemctl list-unit-files | grep -q "^$service.service"; then
        echo "停止 $service..."
        systemctl stop $service >/dev/null 2>&1
        
        echo "禁用 $service..."
        systemctl disable $service >/dev/null 2>&1
        
        echo "删除服务文件 /etc/systemd/system/$service.service"
        rm -f "/etc/systemd/system/$service.service"
    else
        echo "跳过 $service - 服务不存在"
    fi
done

# 重新加载systemd
systemctl daemon-reload

# 删除配置文件
echo "删除配置文件..."
[ -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR"

# 删除数据目录
echo "删除数据目录..."
[ -d "$BASE_DIR" ] && rm -rf "$BASE_DIR"

# 删除日志目录
echo "删除日志目录..."
[ -d "$LOG_DIR" ] && rm -rf "$LOG_DIR"

# 删除用户和组（如果存在）
echo "删除用户和组..."
if id -u "$VM_USER" >/dev/null 2>&1; then
    userdel "$VM_USER" >/dev/null 2>&1
    echo "已删除用户 $VM_USER"
else
    echo "用户 $VM_USER 不存在，跳过删除"
fi

if getent group "$VM_GROUP" >/dev/null; then
    groupdel "$VM_GROUP" >/dev/null 2>&1
    echo "已删除组 $VM_GROUP"
else
    echo "组 $VM_GROUP 不存在，跳过删除"
fi

# 删除README文件
echo "删除README文件..."
rm -f /root/victoriametrics-README.md

# 清理journal日志中VictoriaMetrics相关条目
echo "清理系统日志..."
journalctl --vacuum-size=100M >/dev/null 2>&1
journalctl --flush >/dev/null 2>&1

echo "======================================================"
echo "VictoriaMetrics集群已完全清理"
echo "======================================================"