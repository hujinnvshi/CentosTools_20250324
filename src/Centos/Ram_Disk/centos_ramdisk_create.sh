#!/bin/bash
# 内存盘创建脚本
# 功能：创建8GB内存盘并挂载到/dataram
# 作者：系统优化专家
# 版本：1.2
# 日期：2023-08-20

set -euo pipefail

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 此脚本必须以root权限运行"
    exit 1
fi

# 参数配置
RAMDISK_SIZE="8G"         # 内存盘大小
MOUNT_POINT="/dataram"    # 挂载点
FS_TYPE="ext4"            # 文件系统类型

# 检查系统内存
TOTAL_MEM=$(free -g | awk '/Mem:/ {print $2}')
if [ "$TOTAL_MEM" -lt 16 ]; then
    echo "⚠️ 警告：系统总内存 ${TOTAL_MEM}G，分配8G可能影响性能"
    read -p "是否继续？(y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# 创建挂载点
echo "🛠️ 创建挂载点 ${MOUNT_POINT}"
mkdir -p "${MOUNT_POINT}"
chmod 1777 "${MOUNT_POINT}"  # 设置粘滞位

# 检查是否已挂载
if mount | grep -q "${MOUNT_POINT}"; then
    echo "⚠️ 检测到 ${MOUNT_POINT} 已有挂载"
    read -p "是否卸载重新设置？(y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        umount -l "${MOUNT_POINT}" || true
    else
        exit 0
    fi
fi

# 创建内存盘
echo "💾 创建 ${RAMDISK_SIZE} 内存盘"
mount -t tmpfs -o size=${RAMDISK_SIZE},nr_inodes=1M,mode=1777 tmpfs "${MOUNT_POINT}"

# 可选：格式化为ext4（如果需要持久化特性）
if [ "$FS_TYPE" != "tmpfs" ]; then
    echo "🔄 格式化内存盘为 ${FS_TYPE}"
    dd if=/dev/zero of=/dev/shm/ramdisk.img bs=1M count=8192
    mkfs.${FS_TYPE} /dev/shm/ramdisk.img
    mount -o loop,async,noatime,nodiratime /dev/shm/ramdisk.img "${MOUNT_POINT}"
fi

# 配置开机自动挂载
if ! grep -q "${MOUNT_POINT}" /etc/fstab; then
    echo "⚙️ 配置/etc/fstab自动挂载"
    if [ "$FS_TYPE" == "tmpfs" ]; then
        echo "tmpfs ${MOUNT_POINT} tmpfs defaults,size=${RAMDISK_SIZE},nr_inodes=1M,mode=1777 0 0" >> /etc/fstab
    else
        echo "/dev/shm/ramdisk.img ${MOUNT_POINT} ${FS_TYPE} loop,async,noatime,nodiratime 0 0" >> /etc/fstab
    fi
fi

# 验证挂载
echo "🔍 验证挂载结果"
df -hT "${MOUNT_POINT}"
mount | grep "${MOUNT_POINT}"

# 设置权限
echo "🔒 设置目录权限"
chmod 1777 "${MOUNT_POINT}"
chown nobody:nobody "${MOUNT_POINT}"

# 创建测试文件
echo "📝 创建测试文件"
dd if=/dev/zero of="${MOUNT_POINT}/testfile" bs=1M count=100 status=progress
rm -f "${MOUNT_POINT}/testfile"

# 性能测试
echo "🚀 运行性能测试"
cd "${MOUNT_POINT}"
echo "----- 写入测试 -----"
dd if=/dev/zero of=./speedtest bs=1M count=1024 conv=fdatasync status=progress
echo "----- 读取测试 -----"
dd if=./speedtest of=/dev/null bs=1M status=progress
rm -f ./speedtest

echo "✅ 内存盘配置完成"
echo "挂载点: ${MOUNT_POINT}"
echo "大小: ${RAMDISK_SIZE}"
echo "类型: ${FS_TYPE}"