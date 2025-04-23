#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 输出函数
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" && exit 1; }

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用root用户执行此脚本"
fi

# 设置变量
INSTALL_DIR="/data/dm8"
SOFT_DIR="/media/dm8"

# 停止DM8服务
print_message "停止DM8服务..."
if systemctl is-active --quiet DmServiceDMSERVER; then
    systemctl stop DmServiceDMSERVER || print_error "停止DM8服务失败"
fi

# 禁用DM8服务
print_message "禁用DM8服务..."
if systemctl is-enabled --quiet DmServiceDMSERVER; then
    systemctl disable DmServiceDMSERVER || print_error "禁用DM8服务失败"
fi

# 删除DM8服务文件
print_message "删除DM8服务文件..."
rm -f /usr/lib/systemd/system/DmServiceDMSERVER.service

# 删除安装目录
print_message "删除安装目录..."
if [ -d "${INSTALL_DIR}" ]; then
    rm -rf ${INSTALL_DIR} || print_error "删除安装目录失败"
fi

# 卸载挂载点
print_message "卸载挂载点..."
if mountpoint -q ${SOFT_DIR}; then
    umount ${SOFT_DIR} || print_error "卸载挂载点失败"
fi

# 删除挂载目录
print_message "删除挂载目录..."
if [ -d "${SOFT_DIR}" ]; then
    rm -rf ${SOFT_DIR} || print_error "删除挂载目录失败"
fi

# 删除环境变量配置
print_message "删除环境变量配置..."
rm -f /etc/profile.d/dm8.sh

# 完成
print_message "DM8卸载清理完成！"