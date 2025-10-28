#!/bin/bash

set -eo pipefail

# 常量定义
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'
readonly BACKUP_DIR="/data/backup/system_$(date +%Y%m%d_%H%M%S)"

# 全局变量声明
CPU_CORES=""
TOTAL_MEM_KB=""
TOTAL_MEM_MB=""

# 日志函数
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1" && exit 1; }

# 系统检查
check_system() {
    print_message "检查系统环境..."
    [[ $EUID -ne 0 ]] && print_error "请使用root用户执行此脚本"
    
    # 检查系统版本
    if ! grep -q "CentOS Linux release 7" /etc/redhat-release; then
        print_warning "当前系统不是CentOS 7，可能存在兼容性问题"
        read -p "是否继续？(y/n) " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
    fi
    
    # 检查必要工具
    local tools=("curl" "wget" "net-tools")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            print_warning "安装必要工具: $tool"
            yum install -y "$tool" || print_error "安装 $tool 失败"
        fi
    done
}

# 获取系统信息
get_system_info() {
    print_message "获取系统信息..."
    CPU_CORES=$(nproc)
    TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    TOTAL_MEM_MB=$((TOTAL_MEM_KB / 1024))
    
    echo "CPU核心数：${CPU_CORES}"
    echo "内存大小：${TOTAL_MEM_MB}MB"
}

# 备份系统配置
backup_configs() {
    print_message "备份系统配置..."
    mkdir -p "${BACKUP_DIR}" || print_error "创建备份目录失败"
    
    local backup_files=(
        "/etc/sysctl.conf"
        "/etc/security/limits.conf"
        "/etc/selinux/config"
        "/etc/resolv.conf"
        "/etc/profile"
    )
    
    for file in "${backup_files[@]}"; do
        if [[ -f "$file" ]]; then
            cp -v "$file" "${BACKUP_DIR}/" || print_warning "备份 $file 失败"
        fi
    done
    
    # 创建备份信息文件
    {
        echo "备份时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "系统版本: $(cat /etc/redhat-release)"
        echo "内核版本: $(uname -r)"
    } > "${BACKUP_DIR}/backup_info.txt"
}

# 防火墙配置
configure_firewall() {
    print_message "配置防火墙..."    
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-service=ssh
        firewall-cmd --reload
        systemctl stop firewalld
        systemctl disable firewalld
        print_message "防火墙已禁用"
    else
        print_message "防火墙未开启，跳过配置"
    fi
}

# 系统参数优化
optimize_sysctl() {
    print_message "优化系统参数..."
    
    # 检查内存变量是否有效
    if [[ -z "$TOTAL_MEM_KB" || "$TOTAL_MEM_KB" -le 0 ]]; then
        print_error "无法获取有效的内存总量"
    fi
    
    # 计算文件句柄限制（基于内存大小）
    local FILE_MAX=$((TOTAL_MEM_KB * 1024))
    local MAX_FILE_LIMIT=1048576  # 最大文件句柄限制
    
    [[ "$FILE_MAX" -gt "$MAX_FILE_LIMIT" ]] && FILE_MAX="$MAX_FILE_LIMIT"
    
    print_message "文件句柄限制：${FILE_MAX}"
    
    # 备份原有配置
    if [[ -f /etc/sysctl.conf ]]; then
        cp /etc/sysctl.conf "${BACKUP_DIR}/sysctl.conf.backup"
    fi
    
    # 生成优化配置
    cat > /etc/sysctl.conf << EOF
# 文件句柄和进程数限制
fs.file-max = ${FILE_MAX}
fs.nr_open = ${FILE_MAX}

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
    
    # 应用配置
    if ! sysctl -p; then
        print_error "应用 sysctl 配置失败，已恢复备份"
        cp "${BACKUP_DIR}/sysctl.conf.backup" /etc/sysctl.conf
        sysctl -p
        return 1
    fi
    
    print_message "系统参数优化完成"
}

# 资源限制优化
configure_limits() {
    print_message "配置资源限制...  ${CPU_CORES}核，${TOTAL_MEM_MB}MB"
    
    # 动态计算资源限制
    local NOFILE_LIMIT=$((TOTAL_MEM_MB * 1024))  # 文件描述符限制
    local NPROC_LIMIT=$((CPU_CORES * 2048))      # 进程数限制
    local STACK_LIMIT=65536                      # 栈内存限制（KB）
    local MEMLOCK_LIMIT=1048576                  # 内存锁定限制（KB）
    
    # 设置合理上限
    NOFILE_LIMIT=$((NOFILE_LIMIT > 1048576 ? 1048576 : NOFILE_LIMIT))
    NPROC_LIMIT=$((NPROC_LIMIT > 65535 ? 65535 : NPROC_LIMIT))
    
    print_message "文件描述符限制：${NOFILE_LIMIT}"
    print_message "进程数限制：${NPROC_LIMIT}"
    
    # 备份原有配置
    if [[ -f /etc/security/limits.conf ]]; then
        cp /etc/security/limits.conf "${BACKUP_DIR}/limits.conf.backup"
    fi
    
    # 生成优化配置
    cat > /etc/security/limits.conf << EOF
* soft nofile  ${NOFILE_LIMIT}
* hard nofile  ${NOFILE_LIMIT}
* soft nproc   ${NPROC_LIMIT}
* hard nproc   ${NPROC_LIMIT}
* soft stack   ${STACK_LIMIT}
* hard stack   ${STACK_LIMIT}
* soft memlock ${MEMLOCK_LIMIT}
* hard memlock ${MEMLOCK_LIMIT}
* soft core    unlimited
* hard core    unlimited
EOF
    
    print_message "资源限制配置完成"
}

# SELinux配置
configure_selinux() {
    print_message "配置SELinux..."
    setenforce 0
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    print_message "SELinux 已禁用"
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
    
    print_message "基础优化完成"
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
    
    print_message "性能优化完成"
}

# PS1提示符配置
configure_ps1() {
    print_message "配置PS1环境变量..."
    
    # 检查写入权限
    if [[ ! -w /etc/profile.d/ ]]; then
        print_error "无法写入 /etc/profile.d/ 目录，请以 root 用户运行此脚本"
    fi
    
    # 自定义PS1配置
    cat > /etc/profile.d/custom_ps1.sh << 'EOF'
# 自定义PS1配置
export PS1="\[\e[1;32m\][\t]\[\e[m\] \[\e[1;34m\]\u\[\e[m\]@\[\e[1;31m\]\h\[\e[m\] \[\e[1;33m\]\w\[\e[m\]\n\[\e[1;31m\]➜\[\e[m\] "
EOF
    
    # 设置文件权限
    chmod +x /etc/profile.d/custom_ps1.sh
    
    print_message "PS1 配置已写入 /etc/profile.d/custom_ps1.sh"
    print_message "请执行以下命令使配置生效："
    print_message "  source /etc/profile"
    print_message "或重新登录系统"
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
    configure_ps1
    
    print_message "系统优化完成！配置备份位置：${BACKUP_DIR}"
    print_warning "建议重启系统以使所有更改生效"
}

# 执行主函数
main "$@"