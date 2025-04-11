#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用root用户执行此脚本"
    fi
}


# 创建挂载目录
create_mount_point() {
    print_message "创建挂载目录..."
    mkdir -p /media/cdrom
    chmod 755 /media/cdrom
}

# 检查CDROM设备
check_cdrom() {
    print_message "检查CDROM设备..."
    if ! blkid | grep -q "iso9660"; then
        print_error "未检测到CentOS 7.9安装光盘，请插入后重试"
    fi
    
    CDROM_DEV=$(blkid | grep "iso9660" | cut -d: -f1)
    print_message "检测到CDROM设备: $CDROM_DEV"
}

# 配置开机自动挂载
configure_fstab() {
    print_message "配置开机自动挂载..."
    
    # 检查是否已配置
    if grep -q "/media/cdrom" /etc/fstab; then
        print_message "CDROM已配置自动挂载"
        return
    fi
    
    # 备份fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # 添加挂载配置
    echo "${CDROM_DEV} /media/cdrom iso9660 defaults 0 0" >> /etc/fstab
    
    # 测试挂载
    mount -a || print_error "挂载测试失败，请检查/etc/fstab配置"
}

# 配置本地YUM源
configure_local_yum() {
    print_message "配置本地YUM源..."
    
    # 检查LocalYum是否已存在
    if [ -f /etc/yum.repos.d/LocalYum.repo ]; then
        print_message "LocalYum源已存在，跳过配置"
        return
    fi
    
    # 创建YUM源配置
    cat > /etc/yum.repos.d/LocalYum.repo << 'EOF'
[LocalYum]
name=CentOS-7.9 Local Media
baseurl=file:///media/cdrom
gpgcheck=0
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF

    # 清理YUM缓存并重建
    yum clean all
    yum makecache
}

# 验证配置
verify_config() {
    print_message "验证配置..."
    
    # 验证挂载
    if ! mount | grep -q "/media/cdrom"; then
        print_error "CDROM挂载失败"
    fi
    
    # 验证YUM源
    if ! yum repolist | grep -q "LocalYum"; then
        print_error "LocalYum源配置失败"
    fi
    
    print_message "验证成功！"
}

# 主函数
main() {
    print_message "开始配置CDROM本地YUM源..."    
    check_root
    create_mount_point
    check_cdrom
    configure_fstab
    configure_local_yum
    verify_config    
    print_message "配置完成！"
    print_message "CDROM已挂载到 /media/cdrom"
    print_message "本地YUM源已配置为 LocalYum"
}

# 执行主函数
main


# 业已核验之次数： 
# - ⭐️ 172.16.48.171 时间：2025-04-11 16:21:50
