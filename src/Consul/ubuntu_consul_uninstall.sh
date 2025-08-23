#!/bin/bash
# Consul 清理脚本
# 版本: 1.0
# 作者: 您的名字
# 描述: 完全移除 Consul 安装，包括文件、目录、用户和服务

set -euo pipefail

# 配置参数（与安装脚本保持一致）
CONSUL_USER="consul"
CONSUL_GROUP="consul"
CONSUL_DIR="/data/consul_version"
CONSUL_DATA_DIR="/data/consul_data"
CONSUL_CONFIG_DIR="/etc/consul.d"
CONSUL_SERVICE_FILE="/etc/systemd/system/consul.service"

# 检查是否以 root 用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 此脚本必须以 root 权限运行"
    exit 1
fi

echo "开始清理 Consul 安装..."

# 停止并禁用 Consul 服务
if systemctl is-active --quiet consul; then
    echo "停止 Consul 服务..."
    systemctl stop consul
fi

if systemctl is-enabled --quiet consul; then
    echo "禁用 Consul 服务..."
    systemctl disable consul
fi

# 删除 systemd 服务文件
if [ -f "$CONSUL_SERVICE_FILE" ]; then
    echo "删除服务文件: $CONSUL_SERVICE_FILE"
    rm -f "$CONSUL_SERVICE_FILE"
    systemctl daemon-reload
fi

# 删除安装目录
if [ -d "$CONSUL_DIR" ]; then
    echo "删除安装目录: $CONSUL_DIR"
    rm -rf "$CONSUL_DIR"
fi

# 删除数据目录
if [ -d "$CONSUL_DATA_DIR" ]; then
    echo "删除数据目录: $CONSUL_DATA_DIR"
    rm -rf "$CONSUL_DATA_DIR"
fi

# 删除配置目录
if [ -d "$CONSUL_CONFIG_DIR" ]; then
    echo "删除配置目录: $CONSUL_CONFIG_DIR"
    rm -rf "$CONSUL_CONFIG_DIR"
fi

# 删除符号链接
if [ -L "/usr/local/bin/consul" ]; then
    echo "删除符号链接: /usr/local/bin/consul"
    rm -f /usr/local/bin/consul
fi

# 删除用户和组（如果存在且没有其他进程使用）
if id -u "$CONSUL_USER" >/dev/null 2>&1; then
    echo "删除用户: $CONSUL_USER"
    userdel "$CONSUL_USER"
fi

if grep -q "^$CONSUL_GROUP:" /etc/group; then
    echo "删除组: $CONSUL_GROUP"
    groupdel "$CONSUL_GROUP"
fi

echo "Consul 清理完成!"
echo "所有相关文件、目录、用户和服务已被移除。"