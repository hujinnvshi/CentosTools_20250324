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

# 卸载tmpfs
print_message "卸载tmpfs..."
if mountpoint -q ${MOUNT_POINT}; then
    if lsof ${MOUNT_POINT} &>/dev/null; then
        print_error "挂载点 ${MOUNT_POINT} 正在被使用，无法卸载"
    fi
    umount ${MOUNT_POINT} || print_error "卸载tmpfs失败"
else
    print_message "挂载点 ${MOUNT_POINT} 未挂载，跳过卸载"
fi

# 删除挂载点
print_message "删除挂载点：${MOUNT_POINT}..."
if [ -d ${MOUNT_POINT} ]; then
    if [[ "${MOUNT_POINT}" == "/" ]]; then
        print_error "挂载点路径为根目录，禁止删除"
    fi
    rm -rf ${MOUNT_POINT} || print_error "删除挂载点失败"
else
    print_message "挂载点 ${MOUNT_POINT} 不存在，跳过删除"
fi

# 清理fstab配置
print_message "清理fstab配置..."
if [ ! -w /etc/fstab ]; then
    print_error "/etc/fstab 文件不可写"
fi
if grep -q "${MOUNT_POINT}" /etc/fstab; then
    sed -i "\|${MOUNT_POINT}|d" /etc/fstab || print_error "清理fstab配置失败"
else
    print_message "fstab中未找到 ${MOUNT_POINT} 的配置，跳过清理"
fi

# 完成
print_message "内存盘卸载清理完成！"