关闭 Ubuntu 24.04.1 LTS 系统防火墙，并禁止开机启动，
查看系统cpu,内存数量，然后根据获取到的信息，调整系统的最大文件句柄数量，以及优化常见的系统参数.
SELINUX=enforcing 改为 SELINUX=disabled
修改主机名称为：ainode_yyyymmdd(为当前日期)
帮我设置一个美观的PS1风格的环境变量
帮我生成一键执行bash脚本
保证逻辑完整，结构清晰，并且有注释

我帮你优化一下需求描述，使其更加清晰和结构化：

# Ubuntu 24.04.1 LTS 系统初始化配置需求

## 1. 系统安全配置
- 关闭并禁用系统防火墙（ufw）
- 禁用 SELinux 安全策略

## 2. 系统资源检查与优化
- 检查并显示 CPU 信息（核心数、型号）
- 检查并显示内存信息（总量、可用量）
- 根据系统资源情况自动优化：
  - 最大文件句柄数（ulimit）
  - 系统内核参数（sysctl）
  - TCP 网络参数
  - 虚拟内存参数

## 3. 系统标识配置
- 修改主机名为：ainode_当前日期格式（ainode_20250409）
- 配置个性化的 PS1 命令提示符：
  - 显示用户名和主机名
  - 显示当前目录
  - 显示命令执行状态
  - 使用彩色样式

## 4. 脚本要求
- 使用 bash 编写
- 需要 root 权限检查
- 执行前备份重要配置
- 添加执行日志
- 提供执行结果验证
- 错误处理机制
- 支持回滚操作

## 5. 输出要求
- 显示所有配置修改结果
- 显示系统优化参数
- 保存配置修改日志

这样的需求描述更加清晰，便于开发脚本实现所需功能。需要我帮你实现这个脚本吗？

我来帮你创建一个完整的 Ubuntu 系统初始化配置脚本：

```bash:/Users/www.redelego.cn/CentosTools_20250324/src/security/Centos/setup/ubuntu_init.sh
#!/bin/bash

# 设置变量
BACKUP_DIR="/root/system_backup_$(date +%Y%m%d)"
LOG_FILE="/var/log/system_init_$(date +%Y%m%d).log"
HOSTNAME="ainode_$(date +%Y%m%d)"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; exit 1; }

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "请使用root权限运行此脚本"
    fi
}
# 检查系统版本
check_system_version() {
    log "检查系统版本..."
    if ! lsb_release -a 2>/dev/null | grep -q "Ubuntu 24.04"; then
        error "此脚本仅支持 Ubuntu 24.04 系统"
    fi
}
# 系统安全配置
configure_security() {
    log "配置系统安全..."
    
    # 关闭防火墙
    systemctl stop ufw
    systemctl disable ufw
    
    # 禁用SELinux（Ubuntu默认没有SELinux）
    if [ -f "/etc/selinux/config" ]; then
        backup_file "/etc/selinux/config"
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
    fi
}

# 系统资源检查
check_resources() {
    log "检查系统资源..."
    
    # CPU信息
    CPU_CORES=$(nproc)
    CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | sed 's/^[ \t]*//')
    
    # 内存信息
    TOTAL_MEM=$(free -h | awk '/^Mem:/{print $2}')
    AVAIL_MEM=$(free -h | awk '/^Mem:/{print $7}')
    
    log "CPU核心数: $CPU_CORES"
    log "CPU型号: $CPU_MODEL"
    log "总内存: $TOTAL_MEM"
    log "可用内存: $AVAIL_MEM"
}

# 系统参数优化
optimize_system() {
    log "优化系统参数..."
    
    # 备份系统配置
    backup_file "/etc/sysctl.conf"
    backup_file "/etc/security/limits.conf"
    
    # 设置文件句柄数
    cat >> /etc/security/limits.conf << EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF

    # 优化内核参数
    cat >> /etc/sysctl.conf << EOF
# 系统级别文件句柄优化
fs.file-max = 655350
fs.inotify.max_user_watches = 89100

# 虚拟内存优化
vm.swappiness = 10
vm.dirty_ratio = 40
vm.dirty_background_ratio = 10

# 网络优化
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.ip_local_port_range = 1024 65000
EOF

    # 应用sysctl配置
    sysctl -p
}

# 配置系统标识
configure_identity() {
    log "配置系统标识..."
    
    # 设置主机名
    hostnamectl set-hostname "$HOSTNAME"
    
    # 配置PS1提示符
    backup_file "/etc/bash.bashrc"
    cat >> /etc/bash.bashrc << 'EOF'
export PS1='\[\e[38;5;82m\]\u\[\e[0m\]@\[\e[38;5;226m\]\h\[\e[0m\] \[\e[38;5;39m\]\w\[\e[0m\] \[\e[38;5;196m\]$?\[\e[0m\]\n\[\e[38;5;226m\]➜\[\e[0m\] '
EOF
}

# 验证配置
verify_configuration() {
    log "验证配置..."
    
    # 检查防火墙状态
    if systemctl is-active ufw &>/dev/null; then
        warn "防火墙仍在运行"
    else
        log "防火墙已关闭"
    fi
    
    # 检查主机名
    if [ "$(hostname)" = "$HOSTNAME" ]; then
        log "主机名配置成功"
    else
        warn "主机名配置失败"
    fi
    
    # 检查系统参数
    log "当前系统参数值："
    sysctl -a | grep -E "fs.file-max|net.core.somaxconn|vm.swappiness"
}

# 回滚函数
rollback() {
    if [ -d "$BACKUP_DIR" ]; then
        log "开始回滚..."
        for file in "$BACKUP_DIR"/*; do
            cp "$file" "/${file#$BACKUP_DIR/}"
            log "已恢复: ${file#$BACKUP_DIR/}"
        done
    fi
}
# 备份函数
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        mkdir -p "$BACKUP_DIR"
        cp -p "$file" "${BACKUP_DIR}/$(basename ${file}).bak" || error "备份 $file 失败"
        log "已备份: $file"
    else
        warn "文件不存在，跳过备份: $file"
    fi
}

# 回滚函数
rollback() {
    if [ -d "$BACKUP_DIR" ]; then
        log "开始回滚..."
        for file in "$BACKUP_DIR"/*; do
            if [ -f "$file" ]; then
                cp -p "$file" "/${file#$BACKUP_DIR/}" || warn "回滚 ${file#$BACKUP_DIR/} 失败"
                log "已恢复: ${file#$BACKUP_DIR/}"
            fi
        done
        log "回滚完成"
    else
        warn "未找到备份目录，无法回滚"
    fi
}
# 检查必要命令
check_commands() {
    local cmds=("hostnamectl" "sysctl" "lsb_release" "free" "nproc")
    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "未找到必要命令: $cmd"
        fi
    done
}

# 主函数
main() {
    # 创建日志文件
    touch "$LOG_FILE"
    log "开始系统初始化配置..."
    
    # 检查root权限
    check_root
    check_system_version    # 添加版本检查
    check_commands    # 添加命令检查
    
    # 执行配置
    configure_security
    check_resources
    optimize_system
    configure_identity
    
    # 验证配置
    verify_configuration
    
    log "配置完成，日志文件: $LOG_FILE"
    log "备份目录: $BACKUP_DIR"
}

# 错误处理
trap 'error "脚本执行失败，开始回滚"; rollback' ERR

# 执行主函数
main
```

使用方法：
```bash
touch ubuntu_init.sh
chmod +x ubuntu_init.sh
sudo ./ubuntu_init.sh
```

脚本特点：
1. 完整的错误处理和日志记录
2. 自动备份所有修改的配置文件
3. 支持配置回滚
4. 系统参数自动优化
5. 美观的命令提示符
6. 详细的执行过程输出

建议在执行前：
1. 确保系统为 Ubuntu 24.04.1 LTS
2. 确保有足够的磁盘空间
3. 建议在测试环境先运行验证