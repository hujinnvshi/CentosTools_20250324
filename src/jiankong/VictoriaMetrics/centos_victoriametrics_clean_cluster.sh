#!/bin/bash
# VictoriaMetrics 清理脚本
# 用于清理安装失败的伪分布式集群部署
# Author: Your Name
# Date: $(date +%Y-%m-%d)
# Version: 1.0

# 配置参数 - 必须与部署脚本一致
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

echo "开始清理VictoriaMetrics伪分布式集群环境..."

# 停止并禁用服务
echo "停止并禁用服务..."
services=(
    vmstorage1 vmstorage2 vmstorage3
    vminsert1 vminsert2
    vmselect1 vmselect2
)

for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "停止 $service 服务..."
        systemctl stop $service
    fi
    
    if systemctl is-enabled --quiet $service; then
        echo "禁用 $service 服务..."
        systemctl disable $service
    fi
done

# 删除systemd服务文件
echo "删除systemd服务文件..."
for i in {1..3}; do
    service_file="/etc/systemd/system/vmstorage$i.service"
    if [ -f "$service_file" ]; then
        echo "删除 $service_file"
        rm -f "$service_file"
    fi
done

for i in {1..2}; do
    service_file="/etc/systemd/system/vminsert$i.service"
    if [ -f "$service_file" ]; then
        echo "删除 $service_file"
        rm -f "$service_file"
    fi
    
    service_file="/etc/systemd/system/vmselect$i.service"
    if [ -f "$service_file" ]; then
        echo "删除 $service_file"
        rm -f "$service_file"
    fi
done

# 重新加载systemd
systemctl daemon-reload

# 删除目录结构
echo "删除目录结构..."
[ -d "$BASE_DIR" ] && echo "删除 $BASE_DIR" && rm -rf "$BASE_DIR"
[ -d "$CONFIG_DIR" ] && echo "删除 $CONFIG_DIR" && rm -rf "$CONFIG_DIR"
[ -d "$LOG_DIR" ] && echo "删除 $LOG_DIR" && rm -rf "$LOG_DIR"

# 删除用户和组（如果存在且没有其他进程使用）
echo "检查并删除用户和组..."
if id -u $VM_USER >/dev/null 2>&1; then
    # 检查是否有进程使用该用户
    if ! pgrep -u $VM_USER >/dev/null; then
        echo "删除用户: $VM_USER"
        userdel $VM_USER
    else
        echo "警告：用户 $VM_USER 仍有进程运行，跳过删除"
    fi
fi

if getent group $VM_GROUP >/dev/null; then
    # 检查是否有其他用户在该组
    if [ $(getent group $VM_GROUP | cut -d: -f4 | wc -w) -eq 0 ]; then
        echo "删除组: $VM_GROUP"
        groupdel $VM_GROUP
    else
        echo "警告：组 $VM_GROUP 仍有其他成员，跳过删除"
    fi
fi

# 删除README文件
readme_file="/root/victoriametrics-README.md"
[ -f "$readme_file" ] && echo "删除 $readme_file" && rm -f "$readme_file"

echo "清理完成！"
echo "注意：安装包 $LOCAL_PACKAGE 已被保留，可用于重新部署"