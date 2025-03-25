#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志文件
LOG_FILE="/var/log/disk_setup.log"

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

# 检查系统版本
if ! grep -q "CentOS Linux release 7.9.2009" /etc/redhat-release; then
    print_warning "当前系统不是 CentOS 7.9，可能会有兼容性问题"
fi

# 检查必要工具是否安装
for cmd in lvm2 xfsprogs; do
    if ! command -v $cmd &> /dev/null; then
        print_message "正在安装 $cmd..."
        yum install -y $cmd || handle_error "安装 $cmd 失败"
    fi
done

# 备份 fstab
print_message "备份 /etc/fstab..."
cp /etc/fstab /etc/fstab.$(date +%Y%m%d_%H%M%S).bak || print_warning "备份 fstab 失败"

# 查找新添加的磁盘
print_message "查找新磁盘..."
NEW_DISK=$(lsblk -dpn -o NAME,SIZE | grep '200G' | awk '{print $1}')

if [ -z "$NEW_DISK" ]; then
    handle_error "未找到 200GB 的新磁盘"
fi

# 检查磁盘是否已经有分区
if [ $(lsblk -n "${NEW_DISK}" | wc -l) -gt 1 ]; then
    handle_error "磁盘 ${NEW_DISK} 已存在分区，请检查"
fi

print_message "找到新磁盘: $NEW_DISK"

# 检查挂载点
if mountpoint -q /data; then
    handle_error "/data 目录已经被挂载"
fi

# 检查 LVM 是否已存在
VG_NAME="datavg"
LV_NAME="datalv"
if vgs | grep -q "$VG_NAME"; then
    handle_error "卷组 $VG_NAME 已存在"
fi

# 创建物理卷
print_message "正在创建物理卷..."
pvcreate $NEW_DISK || handle_error "创建物理卷失败"

# 创建卷组
print_message "正在创建卷组 $VG_NAME..."
vgcreate $VG_NAME $NEW_DISK || handle_error "创建卷组失败"

# 创建逻辑卷
print_message "正在创建逻辑卷 $LV_NAME..."
lvcreate -l 100%FREE -n $LV_NAME $VG_NAME || handle_error "创建逻辑卷失败"

# 格式化逻辑卷，添加优化参数
print_message "正在格式化逻辑卷..."
mkfs.xfs -f -K -d agcount=$(($(nproc)*4)) /dev/$VG_NAME/$LV_NAME || handle_error "格式化失败"

# 创建挂载点
print_message "正在创建挂载点 /data..."
mkdir -p /data || handle_error "创建挂载点失败"

# 获取逻辑卷的 UUID
UUID=$(blkid -s UUID -o value /dev/$VG_NAME/$LV_NAME)
if [ -z "$UUID" ]; then
    handle_error "获取 UUID 失败"
fi

# 添加到 fstab，使用优化的挂载选项
print_message "正在更新 /etc/fstab..."
echo "UUID=$UUID /data xfs defaults,noatime,nodiratime,logbufs=8 0 0" >> /etc/fstab

# 验证 fstab 语法（修改这部分）
print_message "验证 fstab 配置..."
if ! mount -a -v &>/dev/null; then
    print_error "fstab 配置错误"
    print_message "正在恢复 fstab 备份..."
    cp /etc/fstab.*.bak /etc/fstab
    handle_error "已恢复 fstab 备份"
fi

# 挂载文件系统
print_message "正在挂载文件系统..."
mount -a || handle_error "挂载失败"

# 设置目录权限
chmod 755 /data || print_warning "设置目录权限失败"

# 验证挂载
if ! mountpoint -q /data; then
    handle_error "验证挂载失败"
fi

# 显示结果
print_message "磁盘配置完成！"
print_message "挂载点信息："
df -h /data

print_message "LVM 配置信息："
pvs
vgs
lvs

print_message "XFS 文件系统信息："
xfs_info /data

# 显示 I/O 调度器
print_message "磁盘调度器信息："
cat "/sys/block/${NEW_DISK##*/}/queue/scheduler"

print_message "全部配置已完成，日志保存在 $LOG_FILE"