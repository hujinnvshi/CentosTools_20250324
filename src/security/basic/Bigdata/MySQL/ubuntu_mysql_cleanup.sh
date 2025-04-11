#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

MYSQL_BASE="/data/mysql"
SERVICE_FILE="/etc/systemd/system/mysqld.service"

print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用root权限运行此脚本"
    exit 1
fi

# 停止并禁用服务
if systemctl is-active --quiet mysqld; then
    print_message "停止MySQL服务..."
    systemctl stop mysqld
    systemctl disable mysqld
fi

# 删除服务文件
if [ -f "$SERVICE_FILE" ]; then
    print_message "删除服务文件..."
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
fi

# 删除安装目录
if [ -d "$MYSQL_BASE" ]; then
    print_message "清理安装目录..."
    rm -rf "$MYSQL_BASE"
fi

# 删除环境变量配置
if [ -f "/etc/profile.d/mysql.sh" ]; then
    print_message "移除环境变量配置..."
    rm -f /etc/profile.d/mysql.sh
fi

# 删除MySQL用户
if id mysql &>/dev/null; then
    print_message "删除mysql用户..."
    userdel -r mysql 2>/dev/null
fi

print_message "清理完成！可重新执行安装脚本进行全新安装"