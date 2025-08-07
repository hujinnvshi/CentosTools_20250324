#!/bin/bash
set -euo pipefail

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
    exit 1
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                MYSQL_VERSION="$2"
                shift 2
                ;;
            --instance)
                INSTANCE_ID="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "未知参数: $1"
                ;;
        esac
    done
}

# 显示帮助信息
show_help() {
    cat << EOF
MySQL 多实例清理脚本
用法: $0 [选项]

选项:
  --version <版本>    指定 MySQL 版本 (默认: 8.0.25)
  --instance <标识>   实例标识符 (默认: v1)
  --force             强制清理，不进行确认
  --help              显示帮助信息

示例:
  $0 --version 8.0.25 --instance v1
  $0 --version 8.0.34 --instance v1
EOF
}

# 设置默认变量
set_defaults() {
    MYSQL_VERSION="${MYSQL_VERSION:-8.0.25}"
    INSTANCE_ID="${INSTANCE_ID:-v1}"
    FORCE="${FORCE:-false}"
    
    # 生成唯一标识符
    INSTANCE_NAME="mysql_${MYSQL_VERSION//./_}_${INSTANCE_ID}"
    
    # 安装路径
    MYSQL_HOME="/data/${INSTANCE_NAME}"
    
    # 服务名称
    SERVICE_NAME="${INSTANCE_NAME}"
    
    # 用户和组
    MYSQL_USER="${INSTANCE_NAME}"
    MYSQL_GROUP="${INSTANCE_NAME}"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用root用户执行此脚本"
    fi
}

# 确认清理操作
confirm_cleanup() {
    if [ "$FORCE" = true ]; then
        return
    fi
    
    echo -e "${YELLOW}警告：此操作将永久删除以下内容：${NC}"
    echo "  - MySQL 实例: ${INSTANCE_NAME}"
    echo "  - 安装目录: ${MYSQL_HOME}"
    echo "  - 服务文件: /usr/lib/systemd/system/${SERVICE_NAME}.service"
    echo "  - 环境变量文件: /etc/profile.d/${SERVICE_NAME}.sh"
    echo "  - 用户和组: ${MYSQL_USER}:${MYSQL_GROUP}"
    echo ""
    
    read -p "确定要清理此MySQL实例吗? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_message "操作已取消"
        exit 0
    fi
}

# 停止并禁用服务
stop_and_disable_service() {
    print_message "停止并禁用服务: ${SERVICE_NAME}..."
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        systemctl stop ${SERVICE_NAME}
    fi
    
    if systemctl is-enabled --quiet ${SERVICE_NAME}; then
        systemctl disable ${SERVICE_NAME}
    fi
    
    # 确保服务已停止
    sleep 2
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        print_warning "服务仍在运行，强制终止..."
        pkill -f "mysqld.*${MYSQL_HOME}" || true
    fi
}

# 删除服务文件
remove_service_file() {
    print_message "删除服务文件..."
    local service_file="/usr/lib/systemd/system/${SERVICE_NAME}.service"
    
    if [ -f "$service_file" ]; then
        rm -f "$service_file"
        systemctl daemon-reload
        systemctl reset-failed
    else
        print_warning "服务文件不存在: $service_file"
    fi
}

# 删除环境变量文件
remove_env_file() {
    print_message "删除环境变量文件..."
    local env_file="/etc/profile.d/${SERVICE_NAME}.sh"
    
    if [ -f "$env_file" ]; then
        rm -f "$env_file"
    else
        print_warning "环境变量文件不存在: $env_file"
    fi
}

# 删除安装目录
remove_installation_directory() {
    print_message "删除安装目录: ${MYSQL_HOME}..."
    
    if [ -d "$MYSQL_HOME" ]; then
        rm -rf "$MYSQL_HOME"
    else
        print_warning "安装目录不存在: $MYSQL_HOME"
    fi
}

# 删除用户和组
remove_user_and_group() {
    print_message "删除用户和组..."
    
    # 检查用户是否存在
    if id -u ${MYSQL_USER} >/dev/null 2>&1; then
        # 检查用户是否正在运行进程
        if pgrep -u ${MYSQL_USER} >/dev/null; then
            print_warning "用户 ${MYSQL_USER} 有正在运行的进程，强制终止..."
            pkill -9 -u ${MYSQL_USER} || true
        fi
        
        # 删除用户
        userdel -r ${MYSQL_USER} || print_warning "删除用户 ${MYSQL_USER} 失败"
    else
        print_warning "用户不存在: ${MYSQL_USER}"
    fi
    
    # 检查组是否存在
    if getent group ${MYSQL_GROUP} >/dev/null 2>&1; then
        # 删除组
        groupdel ${MYSQL_GROUP} || print_warning "删除组 ${MYSQL_GROUP} 失败"
    else
        print_warning "组不存在: ${MYSQL_GROUP}"
    fi
}

# 清理临时文件
cleanup_temporary_files() {
    print_message "清理临时文件..."
    
    # 清理测试数据文件
    local test_data_file="/tmp/init_${INSTANCE_NAME}.sql"
    if [ -f "$test_data_file" ]; then
        rm -f "$test_data_file"
    fi
    
    # 清理备份文件
    find /data -name "${INSTANCE_NAME}_backup_*.tar.gz" -delete
}

# 显示清理摘要
show_summary() {
    cat << EOF

${GREEN}==================== MySQL 清理完成 ====================${NC}
已清理实例:   ${INSTANCE_NAME}
MySQL版本:    ${MYSQL_VERSION}
清理内容:
  - 服务已停止并禁用
  - 服务文件已删除
  - 环境变量文件已删除
  - 安装目录已删除
  - 用户和组已删除
  - 临时文件已清理

${YELLOW}注意:${NC}
- 安装包 /tmp/mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.xz 已被保留
- 备份文件已被删除

${GREEN}如需重新安装，请运行安装脚本${NC}
${YELLOW}=================================================${NC}
EOF
}

# 主函数
main() {
    parse_arguments "$@"
    set_defaults
    check_root
    confirm_cleanup
    
    # 执行清理步骤
    stop_and_disable_service
    remove_service_file
    remove_env_file
    remove_installation_directory
    remove_user_and_group
    cleanup_temporary_files    
    show_summary
    print_message "MySQL ${MYSQL_VERSION} (实例: ${INSTANCE_ID}) 清理完成！"
}

# 执行主函数
main "$@"