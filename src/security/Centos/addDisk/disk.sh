#!/bin/bash
# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 输出带颜色的信息函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 检查必要工具是否安装
for cmd in lvm2 xfsprogs; do
    if ! command -v $cmd &> /dev/null; then
        print_message "正在安装 $cmd..."
        yum install -y $cmd
    fi
done

# 查找新添加的磁盘
NEW_DISK=$(lsblk -dpn -o NAME,SIZE | grep '200G' | awk '{print $1}')

if [ -z "$NEW_DISK" ]; then
    print_error "未找到 200GB 的新磁盘"
    exit 1
fi

print_message "找到新磁盘: $NEW_DISK"

# 创建物理卷
print_message "正在创建物理卷..."
pvcreate $NEW_DISK
if [ $? -ne 0 ]; then
    print_error "创建物理卷失败"
    exit 1
fi

# 创建卷组
VG_NAME="datavg"
print_message "正在创建卷组 $VG_NAME..."
vgcreate $VG_NAME $NEW_DISK
if [ $? -ne 0 ]; then
    print_error "创建卷组失败"
    exit 1
fi

# 创建逻辑卷
LV_NAME="datalv"
print_message "正在创建逻辑卷 $LV_NAME..."
lvcreate -l 100%FREE -n $LV_NAME $VG_NAME
if [ $? -ne 0 ]; then
    print_error "创建逻辑卷失败"
    exit 1
fi

# 格式化逻辑卷
print_message "正在格式化逻辑卷..."
mkfs.xfs /dev/$VG_NAME/$LV_NAME
if [ $? -ne 0 ]; then
    print_error "格式化失败"
    exit 1
fi

# 创建挂载点
print_message "正在创建挂载点 /data..."
mkdir -p /data

# 获取逻辑卷的 UUID
UUID=$(blkid -s UUID -o value /dev/$VG_NAME/$LV_NAME)

# 添加到 fstab
print_message "正在更新 /etc/fstab..."
echo "UUID=$UUID /data xfs defaults 0 0" >> /etc/fstab

# 挂载文件系统
print_message "正在挂载文件系统..."
mount -a
if [ $? -ne 0 ]; then
    print_error "挂载失败"
    exit 1
fi

# 验证挂载
df -h /data
print_message "磁盘配置完成！"
print_message "挂载点信息："
df -h /data

# 显示 LVM 信息
print_message "LVM 配置信息："
pvs
vgs
lvs