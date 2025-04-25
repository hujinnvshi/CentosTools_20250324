#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    error "请使用 root 用户执行此脚本"
fi

# 检查 ftp 客户端是否已安装
if ! command -v ftp &>/dev/null; then
    log "安装 ftp 客户端..."
    yum install -y ftp || error "安装 ftp 客户端失败"
fi

# 检查 lftp 客户端是否已安装
if ! command -v lftp &>/dev/null; then
    log "安装 lftp 客户端..."
    yum install -y lftp || error "安装 lftp 客户端失败"
fi

# 检查防火墙状态
if systemctl is-active --quiet firewalld; then
    log "配置防火墙..."
    firewall-cmd --permanent --add-service=ftp || error "配置防火墙失败"
    firewall-cmd --reload || error "重新加载防火墙失败"
else
    log "防火墙未启用，跳过配置"
fi

# 安装 vsftpd
log "安装 vsftpd..."
yum install -y vsftpd || error "安装 vsftpd 失败"

# 创建 FTP 用户
log "创建 FTP 用户 ftp_user1..."
if ! id -u ftp_user1 &>/dev/null; then
    useradd -m -s /bin/bash ftp_user1 || error "创建用户 ftp_user1 失败"
    echo "Secsmart#612" | passwd --stdin ftp_user1 || error "设置用户密码失败"
else
    echo "Secsmart#612" | passwd --stdin ftp_user1 || error "设置用户密码失败"
    log "用户 ftp_user1 已存在，跳过创建"
fi

# 检查 PAM 配置
log "检查 PAM 配置..."
if [ ! -f /etc/pam.d/vsftpd ]; then
    log "创建 PAM 配置文件..."
    cat > /etc/pam.d/vsftpd << EOF
auth    required    pam_shells.so
auth    required    pam_listfile.so item=user sense=deny file=/etc/vsftpd/ftpusers onerr=succeed
auth    include     system-auth
account include     system-auth
session include     system-auth
EOF
fi


# 创建 vsftpd 数据目录
log "创建 vsftpd 数据目录..."
mkdir -p /data/vsftpd || error "创建目录失败"
chown -R ftp_user1:ftp_user1 /data/vsftpd || error "设置目录权限失败"
chmod 755 /home/ftp_user1 || error "修复权限失败"

# 配置 vsftpd
log "配置 vsftpd..."
cat > /etc/vsftpd/vsftpd.conf << EOF
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=755
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES
listen=YES
listen_ipv6=NO
pam_service_name=vsftpd
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd/user_list
tcp_wrappers=YES
local_root=/data/vsftpd
EOF


# 允许用户 ftp_user1 访问 FTP
log "允许用户 ftp_user1 访问 FTP..."
echo "ftp_user1" >> /etc/vsftpd/user_list || error "配置用户访问失败"

# 设置正确的权限和所有权
log "设置 /etc/vsftpd/user_list 的权限和所有权..."
chmod 644 /etc/vsftpd/user_list || error "设置权限失败"
chown root:root /etc/vsftpd/user_list || error "设置所有权失败"
ls -l /etc/vsftpd/user_list

# 启动 vsftpd 服务
log "启动 vsftpd 服务..."
systemctl start vsftpd || error "启动 vsftpd 失败"
systemctl enable vsftpd || error "设置 vsftpd 开机自启失败"

# 检查防火墙状态
if systemctl is-active --quiet firewalld; then
    log "配置防火墙..."
    firewall-cmd --permanent --add-service=ftp || error "配置防火墙失败"
    firewall-cmd --reload || error "重新加载防火墙失败"
else
    log "防火墙未启用，跳过配置"
fi

# 测试 FTP 连接
log "测试 FTP 连接..."
echo "测试 FTP 连接..." > /data/vsftpd/test1.txt || error "创建测试文件失败"
chmod 755 /data/vsftpd/test1.txt || error "设置测试文件权限失败"

# 获取主机 IP
get_host_ip() {
    host_ip=$(hostname -I | awk '{print $1}')
    if [ -z "$host_ip" ]; then
        error "无法获取主机 IP"
    fi
    echo "$host_ip"
}

# 使用 lftp 进行测试
log "使用 lftp 测试 FTP 连接..."
host_ip=$(get_host_ip)
lftp_output=$(lftp -u ftp_user1,Secsmart#612 -e "put /data/vsftpd/test1.txt -o test1.txt; quit" $host_ip 2>&1)
lftp_exit_code=$?
if [ $lftp_exit_code -eq 0 ]; then
    log "FTP 连接测试成功！"
else
    error "FTP 连接测试失败：$lftp_output"
fi

if echo "$lftp_output" | grep -q "bytes transferred"; then
    log "FTP 连接测试成功！"
else
    error "FTP 连接测试失败"
fi

log "vsftpd 安装、配置和测试完成！"