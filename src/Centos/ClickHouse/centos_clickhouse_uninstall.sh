#!/bin/bash

# ClickHouse 完全清理脚本
# 适用于 CentOS 7.9 系统
# 作者: 应用开发工程师
# 版本: 1.0
# 日期: $(date +%Y-%m-%d)

set -e  # 遇到错误退出脚本

# 颜色输出函数
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否以root用户运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以root权限运行"
        exit 1
    fi
}

# 确认操作
confirm_action() {
    echo "=============================================="
    print_warning "此操作将完全删除 ClickHouse 及其所有数据!"
    print_warning "所有数据库和表数据将被永久删除!"
    echo "=============================================="
    
    read -p "是否继续? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "操作已取消"
        exit 0
    fi
}

# 停止ClickHouse服务
stop_clickhouse() {
    print_step "停止ClickHouse服务..."
    
    if systemctl is-active --quiet clickhouse-server; then
        systemctl stop clickhouse-server
        systemctl disable clickhouse-server
        print_info "ClickHouse服务已停止并禁用"
    else
        print_info "ClickHouse服务未运行"
    fi
}

# 卸载ClickHouse包
uninstall_clickhouse() {
    print_step "卸载ClickHouse包..."
    
    # 检查是否安装了ClickHouse
    if rpm -q clickhouse-server >/dev/null 2>&1; then
        # 卸载所有ClickHouse相关包
        yum remove -y clickhouse-server clickhouse-client clickhouse-common-static
        
        # 清理YUM缓存
        yum clean all
        
        print_info "ClickHouse包已卸载"
    else
        print_info "未安装ClickHouse包"
    fi
}

# 删除数据和配置文件
remove_data_and_config() {
    print_step "删除数据和配置文件..."
    
    # 删除数据目录
    if [ -d "/var/lib/clickhouse" ]; then
        rm -rf /var/lib/clickhouse
        print_info "数据目录已删除: /var/lib/clickhouse"
    fi
    
    # 删除日志目录
    if [ -d "/var/log/clickhouse-server" ]; then
        rm -rf /var/log/clickhouse-server
        print_info "日志目录已删除: /var/log/clickhouse-server"
    fi
    
    # 删除配置文件
    if [ -d "/etc/clickhouse-server" ]; then
        # 备份配置文件
        local backup_dir="/tmp/clickhouse-backup-$(date +%Y%m%d%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r /etc/clickhouse-server/ "$backup_dir/"
        print_info "配置文件已备份到: $backup_dir"
        
        # 删除配置文件
        rm -rf /etc/clickhouse-server
        print_info "配置文件已删除: /etc/clickhouse-server"
    fi
    
    # 删除临时文件
    rm -rf /tmp/clickhouse*
}

# 清理防火墙规则
cleanup_firewall() {
    print_step "清理防火墙规则..."
    
    # 检查防火墙状态
    if systemctl is-active firewalld >/dev/null 2>&1; then
        # 移除ClickHouse端口规则
        firewall-cmd --permanent --remove-port=9000/tcp 2>/dev/null || true
        firewall-cmd --permanent --remove-port=8123/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
        print_info "防火墙规则已清理"
    else
        print_info "防火墙未运行，跳过规则清理"
    fi
}

# 删除用户和组
remove_user_and_group() {
    print_step "删除用户和组..."
    
    # 删除clickhouse用户
    if id "clickhouse" &>/dev/null; then
        userdel clickhouse
        print_info "用户已删除: clickhouse"
    else
        print_info "用户不存在: clickhouse"
    fi
    
    # 删除clickhouse组
    if getent group "clickhouse" &>/dev/null; then
        groupdel clickhouse
        print_info "组已删除: clickhouse"
    else
        print_info "组不存在: clickhouse"
    fi
}

# 显示清理结果
show_cleanup_result() {
    echo ""
    print_info "ClickHouse 清理完成!"
    echo "=============================================="
    print_info "已执行的操作:"
    print_info "1. 停止并禁用ClickHouse服务"
    print_info "2. 卸载ClickHouse软件包"
    print_info "3. 删除数据目录: /var/lib/clickhouse"
    print_info "4. 删除日志目录: /var/log/clickhouse-server"
    print_info "5. 删除配置文件: /etc/clickhouse-server"
    print_info "6. 清理防火墙规则"
    print_info "7. 删除clickhouse用户和组"
    echo ""
    print_warning "注意: 所有ClickHouse数据已被永久删除!"
    print_info "如需重新安装，请运行安装脚本"
    echo "=============================================="
}

# 主函数
main() {
    print_info "开始清理 ClickHouse"
    echo ""
    
    # 记录开始时间
    local start_time=$(date +%s)
    
    # 执行清理步骤
    check_root
    confirm_action
    stop_clickhouse
    uninstall_clickhouse
    remove_data_and_config
    cleanup_firewall
    remove_user_and_group
    show_cleanup_result
    
    # 计算清理时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    print_info "清理完成，总耗时: ${duration} 秒"
}

# 异常处理
trap 'print_error "脚本执行被中断"; exit 1' INT TERM

# 执行主函数
main "$@"