#!/bin/bash
# Consul 清理脚本
# 版本: 1.0
# 描述: 清理通过安装脚本安装的 Consul 服务

set -euo pipefail

# 配置参数 - 必须与安装脚本一致
CONSUL_VERSION="1.14.10"             # 清理的 Consul 版本
CONSUL_USER="consul_$CONSUL_VERSION"
CONSUL_GROUP="consul_$CONSUL_VERSION"
CONSUL_DIR="/data/consul/base_$CONSUL_VERSION"
CONSUL_DATA_DIR="/data/consul/data_$CONSUL_VERSION"
CONSUL_CONFIG_DIR="/etc/consul.d/conf_$CONSUL_VERSION"
CONSUL_LOG_DIR="/var/log/consul_$CONSUL_VERSION"
CONSUL_SERVICE_NAME="consul_$CONSUL_VERSION"
CONSUL_SERVICE_FILE="/etc/systemd/system/${CONSUL_SERVICE_NAME}.service"
BIN_LINK="/usr/local/bin/consul-$CONSUL_VERSION"

# 清理说明
echo "=================================================="
echo "Consul 清理脚本"
echo "当前清理版本: $CONSUL_VERSION"
echo "警告: 此操作将永久删除 Consul 服务及其所有数据!"
echo "=================================================="

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 此脚本必须以 root 权限运行" >&2
    exit 1
fi

# 确认操作
read -p "您确定要完全删除 Consul $CONSUL_VERSION 吗? (y/n) " choice
if [ "$choice" != "y" ] && [ "$choice" != "Y" ]; then
    echo "操作已取消"
    exit 0
fi

# 停止并禁用服务
echo "停止 Consul 服务..."
systemctl stop "$CONSUL_SERVICE_NAME" || true
systemctl disable "$CONSUL_SERVICE_NAME" || true

# 删除服务文件
echo "删除 systemd 服务文件..."
rm -f "$CONSUL_SERVICE_FILE"
systemctl daemon-reload

# 删除日志轮转配置
echo "删除日志轮转配置..."
rm -f "/etc/logrotate.d/consul_$CONSUL_VERSION"

# 删除符号链接
echo "删除符号链接..."
rm -f "$BIN_LINK"
rm -f "/usr/local/bin/consul"

# 删除安装目录
echo "删除安装目录..."
rm -rf "$CONSUL_DIR"

# 删除数据目录
echo "删除数据目录..."
rm -rf "$CONSUL_DATA_DIR"

# 删除配置目录
echo "删除配置目录..."
rm -rf "$CONSUL_CONFIG_DIR"

# 删除日志目录
echo "删除日志目录..."
rm -rf "$CONSUL_LOG_DIR"

# 删除用户和组
echo "删除用户和组..."
if id -u "$CONSUL_USER" >/dev/null 2>&1; then
    userdel "$CONSUL_USER" || true
fi

if getent group "$CONSUL_GROUP" >/dev/null; then
    groupdel "$CONSUL_GROUP" || true
fi

# 输出摘要信息
echo -e "\n=================================================="
echo "Consul $CONSUL_VERSION 已完全清理!"
echo "=================================================="
echo "已删除:"
echo "  服务文件: $CONSUL_SERVICE_FILE"
echo "  安装目录: $CONSUL_DIR"
echo "  数据目录: $CONSUL_DATA_DIR"
echo "  配置目录: $CONSUL_CONFIG_DIR"
echo "  日志目录: $CONSUL_LOG_DIR"
echo "  用户: $CONSUL_USER"
echo "  用户组: $CONSUL_GROUP"
echo "  符号链接: $BIN_LINK"
echo "  日志轮转配置: /etc/logrotate.d/consul_$CONSUL_VERSION"
echo "=================================================="