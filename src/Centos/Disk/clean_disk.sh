#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志文件
LOG_FILE="/var/log/disk_cleanup.log"

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $1" >> $LOG_FILE
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> $LOG_FILE
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> $LOG_FILE
}

# 错误处理函数
handle_error() {
    print_error "$1"
    exit 1
}

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    handle_error "请使用 root 用户执行此脚本"
fi

# 设置默认值
VG_NAME="datavg"
MOUNT_POINT="/data"

# 清理函数
cleanup_disk() {
    print_message "开始清理磁盘配置..."
    
    # 备份 fstab
    cp /etc/fstab /etc/fstab.$(date +%Y%m%d_%H%M%S).bak || print_warning "备份 fstab 失败"
    
    # 卸载文件系统
    if mountpoint -q $MOUNT_POINT; then
        print_message "正在卸载 $MOUNT_POINT..."
        umount -f $MOUNT_POINT || handle_error "卸载 $MOUNT_POINT 失败"
    fi
    
    # 删除 fstab 中的相关条目
    print_message "清理 fstab 配置..."
    sed -i "\@ $MOUNT_POINT @d" /etc/fstab
    
    # 删除逻辑卷和卷组
    if vgs | grep -q "$VG_NAME"; then
        print_message "清理 LVM 配置..."
        lvs | grep "$VG_NAME" | awk '{print $1}' | while read lv; do
            lvremove -f $VG_NAME/$lv || print_warning "删除逻辑卷 $lv 失败"
        done
        vgremove -f $VG_NAME || print_warning "删除卷组 $VG_NAME 失败"
    fi
    
    # 清理所有相关的物理卷
    print_message "清理物理卷..."
    pvs | grep "$VG_NAME" | awk '{print $1}' | while read pv; do
        pvremove -f $pv || print_warning "清理物理卷 $pv 失败"
    done
    
    # 删除挂载点目录（如果为空）
    if [ -d "$MOUNT_POINT" ] && [ -z "$(ls -A $MOUNT_POINT)" ]; then
        print_message "删除空的挂载点目录..."
        rmdir $MOUNT_POINT || print_warning "删除挂载点目录失败"
    elif [ -d "$MOUNT_POINT" ]; then
        print_warning "挂载点目录不为空，保留目录"
    fi
    
    print_message "清理完成"
}

# 执行清理
cleanup_disk

# 显示清理结果
print_message "验证清理结果："
echo "挂载点状态："
df -h | grep $MOUNT_POINT || echo "挂载点已清理"
echo "LVM 状态："
vgs | grep $VG_NAME || echo "卷组已清理"
echo "fstab 配置："
grep $MOUNT_POINT /etc/fstab || echo "fstab 已清理"

print_message "清理日志保存在 $LOG_FILE"