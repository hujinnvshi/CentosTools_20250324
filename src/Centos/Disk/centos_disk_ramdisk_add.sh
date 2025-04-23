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
MOUNT_POINT="/mnt/ramdisk"
SIZE="50G"

# 创建挂载点
print_message "创建挂载点：${MOUNT_POINT}..."
mkdir -p ${MOUNT_POINT} || print_error "创建挂载点失败"

# 挂载tmpfs
print_message "挂载tmpfs，大小：${SIZE}..."
if mountpoint -q ${MOUNT_POINT}; then
    print_error "挂载点 ${MOUNT_POINT} 已被占用"
fi
mount -t tmpfs -o size=${SIZE} tmpfs ${MOUNT_POINT} || print_error "挂载tmpfs失败"

# 验证挂载
print_message "验证挂载..."
if ! mountpoint -q ${MOUNT_POINT}; then
    print_error "挂载验证失败"
fi

# 配置开机自动挂载
print_message "配置开机自动挂载..."
if [ ! -w /etc/fstab ]; then
    print_error "/etc/fstab 文件不可写"
fi
echo "tmpfs ${MOUNT_POINT} tmpfs defaults,size=${SIZE} 0 0" >> /etc/fstab || print_error "写入fstab失败"

# 完成
print_message "内存盘配置完成！"
print_message "挂载点：${MOUNT_POINT}"
print_message "大小：${SIZE}"