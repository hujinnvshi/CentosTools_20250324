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

# 设置变量
ZK_VERSION="${ZK_VERSION:-3.8.1}"               # 允许通过环境变量覆盖版本(3.5.8,3.6.3,3.8.1)
ZK_INSTANCE="${ZK_INSTANCE:-v1}"                # 实例标识符
ZK_INSTANCE_ID="zk_${ZK_VERSION}_${ZK_INSTANCE}" # 实例ID
ZK_BASE_DIR="/data/zookeeper"                   # 基础安装目录
ZK_HOME="${ZK_BASE_DIR}/${ZK_INSTANCE_ID}"      # 实例安装目录
ZK_USER="${ZK_INSTANCE_ID}"                     # 专用用户
ZK_GROUP="${ZK_INSTANCE_ID}"                    # 专用组
FORCE=false                                     # 初始化强制标志

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            ZK_VERSION="$2"
            shift 2
            ;;
        --instance)
            ZK_INSTANCE="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            print_error "未知参数: $1"
            ;;
    esac
done

# 验证实例ID
if [ -z "${ZK_INSTANCE_ID}" ]; then
    print_error "未指定有效的实例ID"
fi

# 确认操作
confirm_cleanup() {
    echo -e "${YELLOW}=================================================${NC}"
    echo -e "${YELLOW}即将清理以下 ZooKeeper 实例:${NC}"
    echo -e "${YELLOW}实例ID:      ${ZK_INSTANCE_ID}${NC}"
    echo -e "${YELLOW}安装目录:    ${ZK_HOME}${NC}"
    echo -e "${YELLOW}服务用户:    ${ZK_USER}${NC}"
    echo -e "${YELLOW}服务组:      ${ZK_GROUP}${NC}"
    echo -e "${YELLOW}=================================================${NC}"
    
    if [ "${FORCE}" != true ]; then
        read -p "确定要清理吗? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_message "操作已取消"
            exit 0
        fi
    fi
}

# 主清理函数
cleanup_zookeeper() {
    print_message "开始清理 ZooKeeper 实例: ${ZK_INSTANCE_ID}"
    
    # 1. 停止并禁用服务
    if systemctl list-unit-files | grep -q "^${ZK_INSTANCE_ID}.service"; then
        if systemctl is-active --quiet ${ZK_INSTANCE_ID}; then
            print_message "停止服务: ${ZK_INSTANCE_ID}"
            systemctl stop ${ZK_INSTANCE_ID}
        fi
        
        if systemctl is-enabled --quiet ${ZK_INSTANCE_ID}; then
            print_message "禁用服务: ${ZK_INSTANCE_ID}"
            systemctl disable ${ZK_INSTANCE_ID}
        fi
    fi
    
    # 2. 删除服务文件
    local service_file="/etc/systemd/system/${ZK_INSTANCE_ID}.service"
    if [ -f "${service_file}" ]; then
        print_message "删除服务文件: ${service_file}"
        rm -f "${service_file}"
        systemctl daemon-reload
    fi
    
    # 3. 删除环境变量文件
    local env_file="/etc/profile.d/zookeeper_${ZK_INSTANCE_ID}.sh"
    if [ -f "${env_file}" ]; then
        print_message "删除环境变量文件: ${env_file}"
        rm -f "${env_file}"
    fi
    
    # 4. 删除安装目录
    if [ -d "${ZK_HOME}" ]; then
        print_message "删除安装目录: ${ZK_HOME}"
        rm -rf "${ZK_HOME}"
    fi
    
    # 5. 删除日志目录
    local log_dir="/var/log/zookeeper/${ZK_INSTANCE_ID}"
    if [ -d "${log_dir}" ]; then
        print_message "删除日志目录: ${log_dir}"
        rm -rf "${log_dir}"
    fi
    
    # 6. 删除用户和组
    if id -u ${ZK_USER} &>/dev/null; then
        # 检查是否有其他进程使用该用户
        if pgrep -u ${ZK_USER} &>/dev/null; then
            if [ "${FORCE}" = true ]; then
                print_warning "强制终止使用用户 ${ZK_USER} 的进程"
                pkill -9 -u ${ZK_USER}
                sleep 2
            else
                print_error "用户 ${ZK_USER} 仍有进程运行，使用 --force 强制终止"
            fi
        fi
        
        print_message "删除用户: ${ZK_USER}"
        userdel -r ${ZK_USER} 2>/dev/null || true
    fi
    
    if getent group ${ZK_GROUP} &>/dev/null; then
        print_message "删除组: ${ZK_GROUP}"
        groupdel ${ZK_GROUP} 2>/dev/null || true
    fi
    
    print_message "清理完成: ZooKeeper 实例 ${ZK_INSTANCE_ID} 已完全移除"
}

# 主函数
main() {
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户执行此脚本"
    fi
    
    confirm_cleanup
    cleanup_zookeeper
}

# 执行主函数
main