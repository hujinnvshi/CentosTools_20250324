#!/bin/bash

set -eo pipefail

# 常量定义
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'
readonly BACKUP_DIR="/data/backup/system_$(date +%Y%m%d_%H%M%S)"

# 日志函数
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" && exit 1; }

# 系统检查
check_system() {
    [[ $EUID -ne 0 ]] && print_error "请使用root用户执行此脚本"
    grep -q "CentOS Linux release 7" /etc/redhat-release || print_warning "当前系统不是CentOS 7，可能存在兼容性问题"
}

# 系统信息获取
get_system_info() {
    readonly CPU_CORES=$(nproc)
    readonly TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    readonly TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
    
    print_message "系统信息："
    echo "CPU核心数：$CPU_CORES"
    echo "内存大小：${TOTAL_MEM_MB}MB"
}

# 防火墙配置
configure_firewall() {
    print_message "配置防火墙..."
    systemctl stop firewalld
    systemctl disable firewalld
}

# 系统参数优化
optimize_sysctl() {
    print_message "优化系统参数..."
    cat > /etc/sysctl.conf << EOF
# 文件句柄和进程数限制
fs.file-max = $((TOTAL_MEM_KB * 1024))
fs.nr_open = $((TOTAL_MEM_KB * 1024))

# 网络参数优化
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1

# 内存参数优化
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# 内核转储设置
kernel.core_pattern = /var/crash/core-%e-%s-%u-%g-%p-%t
kernel.core_uses_pid = 1
EOF
    sysctl -p
}

# 资源限制优化
configure_limits() {
    print_message "配置资源限制..."
    cat > /etc/security/limits.conf << EOF
* soft nofile $((TOTAL_MEM_MB * 5242))
* hard nofile $((TOTAL_MEM_MB * 5242))
* soft nproc  $((CPU_CORES * 204800))
* hard nproc  $((CPU_CORES * 204800))
* soft stack  163840
* hard stack  163840
* soft memlock unlimited
* hard memlock unlimited
* soft core unlimited
* hard core unlimited
EOF
}

# SELinux配置
configure_selinux() {
    print_message "配置SELinux..."
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
}

# 系统配置备份
backup_configs() {
    print_message "备份系统配置..."
    mkdir -p "${BACKUP_DIR}"
    local backup_files=(
        "/etc/sysctl.conf"
        "/etc/security/limits.conf"
        "/etc/selinux/config"
        "/etc/resolv.conf"
    )
    for file in "${backup_files[@]}"; do
        [[ -f "$file" ]] && cp -v "$file" "${BACKUP_DIR}/"
    done
}

# 基础系统优化
optimize_basic() {
    print_message "执行基础优化..."
    # 时区设置
    timedatectl set-timezone Asia/Shanghai
    
    # DNS优化
    cat > /etc/resolv.conf << EOF
nameserver 114.114.114.114
nameserver 8.8.8.8
options timeout:2 attempts:3 rotate single-request-reopen
EOF
    
    # 历史命令优化
    cat >> /etc/profile << EOF
export HISTSIZE=10000
export HISTFILESIZE=20000
export HISTTIMEFORMAT="%F %T "
EOF
}

# 性能优化
optimize_performance() {
    print_message "执行性能优化..."
    # 禁用透明大页
    echo never > /sys/kernel/mm/transparent_hugepage/enabled
    echo never > /sys/kernel/mm/transparent_hugepage/defrag
    
    # 配置开机自动禁用透明大页
    cat > /etc/rc.local << EOF
#!/bin/bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
EOF
    chmod +x /etc/rc.local
    
    # 磁盘调度优化
    for disk in $(lsblk -d -o name -n | grep -Ev '(sr0|loop)'); do
        [[ -f "/sys/block/$disk/queue/scheduler" ]] && \
        echo deadline > "/sys/block/$disk/queue/scheduler"
    done
}

# 主函数
main() {
    check_system
    get_system_info
    backup_configs
    configure_firewall
    optimize_sysctl
    configure_limits
    configure_selinux
    optimize_basic
    optimize_performance
    
    print_message "系统优化完成！配置备份位置：${BACKUP_DIR}"
    print_warning "建议重启系统以使所有更改生效"
}

# 执行主函数
main "$@"
# 业已核验之次数： ⭐️ 