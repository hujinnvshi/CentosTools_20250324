#!/bin/bash
set -euo pipefail

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "❌ 此脚本必须使用 root 权限运行" >&2
    exit 1
fi

# 配置参数（与安装脚本一致）
N9E_VERSION="8.1.0"
BASE_DIR="/opt/n9e"
RUN_USER="n9e"
SERVICE_NAME="supervisord"

# 确认卸载
function confirm_uninstall() {
    echo "⚠️ 警告：这将完全卸载 Nightingale 监控系统"
    echo "---------------------------------------------"
    echo "将删除以下内容："
    echo "1. 安装目录: ${BASE_DIR}"
    echo "2. 系统服务: ${SERVICE_NAME}"
    echo "3. 运行用户: ${RUN_USER}"
    echo "4. 所有配置和数据"
    echo "---------------------------------------------"
    
    read -p "确定要卸载 Nightingale v${N9E_VERSION} 吗？(y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo "卸载已取消"
        exit 0
    fi
}

# 停止并禁用服务
function stop_services() {
    echo "🛑 停止服务..."
    
    # 停止 supervisord 服务
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        systemctl stop ${SERVICE_NAME}
    fi
    
    # 禁用服务
    if systemctl is-enabled --quiet ${SERVICE_NAME}; then
        systemctl disable ${SERVICE_NAME}
    fi
    
    # 移除服务文件
    if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
        rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        systemctl daemon-reload
    fi
    
    # 移除 supervisor 配置
    if [[ -d "/etc/supervisor.d" ]]; then
        rm -f /etc/supervisor.d/n9e-*.conf
    fi
}

# 删除安装文件
function remove_files() {
    echo "🗑️ 删除安装文件..."
    
    # 删除安装目录
    if [[ -d "${BASE_DIR}" ]]; then
        rm -rf "${BASE_DIR}"
        echo "已删除安装目录: ${BASE_DIR}"
    fi
    
    # 删除日志文件
    if [[ -d "/var/log/supervisor" ]]; then
        rm -f /var/log/supervisor/n9e-*.log
    fi
    
    # 删除证书文件
    if [[ -f "/etc/supervisord.conf" ]]; then
        rm -f /etc/supervisord.conf
    fi
}

# 删除运行用户
function remove_user() {
    echo "👤 删除运行用户..."
    
    if id -u "${RUN_USER}" >/dev/null 2>&1; then
        # 检查用户是否只用于 Nightingale
        local user_home=$(eval echo ~${RUN_USER})
        if [[ "${user_home}" == "${BASE_DIR}" ]]; then
            userdel -r ${RUN_USER} 2>/dev/null || true
            echo "已删除用户: ${RUN_USER}"
        else
            echo "⚠️ 用户 ${RUN_USER} 的主目录不是 ${BASE_DIR}，未删除"
            echo "请手动检查: userdel -r ${RUN_USER}"
        fi
    else
        echo "用户 ${RUN_USER} 不存在，跳过删除"
    fi
}

# 清理数据库（可选）
function cleanup_database() {
    echo "🧹 数据库清理选项..."
    
    read -p "是否删除 SQLite 数据库文件？(y/N): " del_sqlite
    if [[ $del_sqlite =~ ^[Yy]$ ]]; then
        if [[ -f "${BASE_DIR}/data/sqlite/n9e.db" ]]; then
            rm -f "${BASE_DIR}/data/sqlite/n9e.db"
            echo "已删除 SQLite 数据库"
        fi
    fi
    
    read -p "是否删除 MySQL 数据库？(需要手动操作)(y/N): " del_mysql
    if [[ $del_mysql =~ ^[Yy]$ ]]; then
        echo "请手动执行以下命令删除 MySQL 数据库:"
        echo "mysql -u[用户名] -p[密码] -e 'DROP DATABASE [数据库名];'"
    fi
}

# 卸载完成
function uninstall_complete() {
    echo -e "\n✅ Nightingale v${N9E_VERSION} 已成功卸载"
    echo "---------------------------------------------"
    echo "以下内容未被删除:"
    echo "1. Redis 数据（如果使用了外部 Redis）"
    echo "2. MySQL 数据库（需要手动删除）"
    echo "3. 防火墙规则（需要手动清理）"
    echo "---------------------------------------------"
}

# 主函数
function main() {
    confirm_uninstall
    stop_services
    remove_files
    remove_user
    cleanup_database
    uninstall_complete
}

main