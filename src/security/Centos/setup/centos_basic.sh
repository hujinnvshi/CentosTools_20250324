#!/bin/bash

# 建议添加在脚本开头
set -o errexit   # 遇到错误立即退出
set -o nounset   # 使用未定义变量时退出
set -o pipefail  # 管道命令中任意失败则整体失败

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 检查系统版本
if ! grep -q "CentOS Linux release 7.9.2009" /etc/redhat-release; then
    print_warning "当前系统不是 CentOS 7.9，可能会有兼容性问题"
fi

# 关闭防火墙
print_message "正在关闭防火墙..."
systemctl stop firewalld
systemctl disable firewalld
if [ $? -eq 0 ]; then
    print_message "防火墙已关闭并禁止开机自启"
else
    print_error "防火墙操作失败"
fi

# 获取系统信息
CPU_CORES=$(nproc)
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
fs.file-max = $((TOTAL_MEM_KB * 1024))  # 更精确的内存字节计算

print_message "系统信息："
echo "CPU 核心数：$CPU_CORES"
echo "内存大小：${TOTAL_MEM}GB"

# 优化系统参数
print_message "正在优化系统参数..."
cat > /etc/sysctl.conf << EOF
# 系统级别的最大文件句柄数
fs.file-max = $(($TOTAL_MEM * 10048576))

# 进程级别的最大文件句柄数
fs.nr_open = $(($TOTAL_MEM * 10048576))

# 内核参数优化
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_tw_recycle = 0
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# 虚拟内存优化
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# 网络优化
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_orphans = 262144
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_synack_retries = 1
net.ipv4.tcp_syn_retries = 1
EOF

sysctl -p
if [ $? -eq 0 ]; then
    print_message "系统参数优化完成"
else
    print_error "系统参数优化失败"
fi

# 设置进程最大文件句柄数
cat > /etc/security/limits.conf << EOF
* soft nofile $(($TOTAL_MEM * 524288))
* hard nofile $(($TOTAL_MEM * 524288))
* soft nproc  $(($CPU_CORES * 204800))
* hard nproc  $(($CPU_CORES * 204800))
* soft stack  163840
* hard stack  163840
EOF

# 关闭 SELinux
print_message "正在关闭 SELinux..."
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
if [ $? -eq 0 ]; then
    print_message "SELinux 已设置为 disabled"
else
    print_error "SELinux 配置修改失败"
fi

# 设置 PS1 环境变量（更美观的配色）
print_message "正在设置 PS1 环境变量..."
PS1_CONFIG='export PS1="\[\e[38;5;39m\][\t]\[\e[m\] \[\e[38;5;82m\]\u\[\e[m\]@\[\e[38;5;198m\]\h\[\e[m\] \[\e[38;5;226m\]\w\[\e[m\]\n\[\e[38;5;198m\]➜\[\e[m\] "'

# 为当前用户和 root 用户设置 PS1
echo "$PS1_CONFIG" > /etc/profile.d/custom_ps1.sh
chmod +x /etc/profile.d/custom_ps1.sh

if [ $? -eq 0 ]; then
    print_message "PS1 环境变量设置完成"
else
    print_error "PS1 环境变量设置失败"
fi

# 显示最终配置状态
print_message "配置完成，当前状态："
echo "防火墙状态：$(systemctl status firewalld | grep Active)"
echo "SELinux 状态：$(getenforce)"
echo "主机名：$(hostname)"
echo "最大文件句柄数：$(cat /proc/sys/fs/file-max)"
echo "当前系统限制："
ulimit -a

print_message "系统配置已完成，请执行以下命令使 PS1 设置生效："
echo "source ~/.bashrc"
print_message "建议重启系统以使所有更改生效"

# 创建备份目录（移到最前面）
BACKUP_DIR="/data/backup/system_$(date +%Y%m%d_%H%M%S)"
mkdir -p ${BACKUP_DIR} || {
    print_error "创建备份目录失败"
    exit 1
}

# 备份原始配置
print_message "备份原始配置..."
backup_files=(
    "/etc/sysctl.conf"
    "/etc/security/limits.conf"
    "/etc/selinux/config"
    "/etc/ssh/sshd_config"
    "/etc/resolv.conf"
)
for file in "${backup_files[@]}"; do
    [ -f "$file" ] && cp -v "$file" "${BACKUP_DIR}/"
done

cp /etc/security/limits.conf ${BACKUP_DIR}/ 2>/dev/null || true
cp /etc/selinux/config ${BACKUP_DIR}/ 2>/dev/null || true
cp /etc/ssh/sshd_config ${BACKUP_DIR}/ 2>/dev/null || true
cp /etc/resolv.conf ${BACKUP_DIR}/ 2>/dev/null || true

# 设置时区
print_message "设置系统时区..."
timedatectl set-timezone Asia/Shanghai

# 优化 DNS 配置
print_message "优化 DNS 配置..."
cat > /etc/resolv.conf << EOF
nameserver 114.114.114.114
nameserver 8.8.8.8
options timeout:2 attempts:3 rotate single-request-reopen
EOF

# 优化历史命令记录
print_message "优化历史命令记录..."
cat >> /etc/profile << EOF
# 历史命令优化
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTTIMEFORMAT="%F %T "
EOF

# SSH 服务优化
print_message "优化 SSH 服务..."
cp /etc/ssh/sshd_config ${BACKUP_DIR}/sshd_config.bak
cat >> /etc/ssh/sshd_config << EOF
# SSH 优化
ClientAliveInterval 60
ClientAliveCountMax 3
UseDNS no
EOF

# 建议修改
if sshd -t; then
    systemctl restart sshd
else
    print_error "SSH 配置测试失败，保持原配置"
    cp ${BACKUP_DIR}/sshd_config.bak /etc/ssh/sshd_config
fi

# 系统参数优化（在原有基础上添加）
print_message "优化系统参数..."
cat >> /etc/sysctl.conf << EOF
# 网络优化补充
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1

# 内核崩溃转储设置
kernel.core_pattern = /var/crash/core-%e-%s-%u-%g-%p-%t
kernel.core_uses_pid = 1

# SWAP 优化
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10
EOF

# 进程资源限制优化（在原有基础上添加）
cat >> /etc/security/limits.conf << EOF
# 进程资源限制补充
* soft memlock unlimited
* hard memlock unlimited
* soft core unlimited
* hard core unlimited
EOF

# 系统日志优化
print_message "优化系统日志..."
cat > /etc/logrotate.d/syslog << EOF
/var/log/cron
/var/log/maillog
/var/log/messages
/var/log/secure
/var/log/spooler
{
    daily
    rotate 30
    missingok
    sharedscripts
    compress
    postrotate
        /bin/kill -HUP \`cat /var/run/syslogd.pid 2> /dev/null\` 2> /dev/null || true
    endscript
}
EOF

# 禁用透明大页
print_message "禁用透明大页..."
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# 设置开机自动禁用透明大页
cat > /etc/rc.local << EOF
#!/bin/bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF
chmod +x /etc/rc.local

# 检查是否启用 NUMA
if command -v numactl >/dev/null 2>&1; then
    print_message "检查 NUMA 配置..."
    numactl --hardware
    print_warning "如果有多个 CPU，建议在 grub 配置中添加 numa=off 参数"
fi

# 优化磁盘调度算法
print_message "优化磁盘调度算法..."
for disk in $(lsblk -d -o name -n | grep -Ev '(sr0|loop)'); do
    if [ -f "/sys/block/$disk/queue/scheduler" ]; then
        echo deadline > "/sys/block/$disk/queue/scheduler"
        print_message "设置 $disk 的调度算法为 deadline"
    fi
done

# 显示优化结果
print_message "系统优化完成，配置备份位置：${BACKUP_DIR}"
print_message "已优化项目："
echo "1. 系统时区和时间同步"
echo "2. DNS 配置优化"
echo "3. 历史命令记录优化"
echo "4. SSH 服务安全加固"
echo "5. 系统参数优化"
echo "6. 进程资源限制优化"
echo "7. 系统日志优化"
echo "8. 透明大页禁用"
echo "9. NUMA 检查"
echo "10. 磁盘调度算法优化"

# 检查关键服务状态
print_message "关键服务状态："
systemctl status chronyd | grep Active
systemctl status sshd | grep Active
sysctl -p | grep "error" || true

print_message "建议重启系统以使所有更改生效"
print_warning "请检查 ${BACKUP_DIR} 中的配置备份"