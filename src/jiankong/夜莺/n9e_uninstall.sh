#!/bin/bash
set -euo pipefail

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "❌ 此脚本必须使用 root 权限运行" >&2
    exit 1
fi

# 配置参数（与安装脚本一致）
BASE_DIR="/data/n9e"
RUN_USER="n9e"

# 停止并禁用服务
function stop_services() {
    echo "🛑 停止所有相关服务..."
    
    # 停止 Nightingale 组件
    if command -v supervisorctl &> /dev/null; then
        supervisorctl stop n9e-* || true
    fi
    
    # 停止 Supervisor 服务
    if systemctl is-active --quiet supervisord; then
        systemctl stop supervisord
    fi
    
    # 禁用 Supervisor 服务
    if systemctl is-enabled --quiet supervisord; then
        systemctl disable supervisord
    fi
}

# 移除 Supervisor 配置
function remove_supervisor_configs() {
    echo "🗑️ 移除 Supervisor 配置..."
    
    # 删除 Nightingale 配置文件
    rm -f /etc/supervisor.d/n9e-*.conf
    
    # 删除 Supervisor 主配置（恢复默认）
    if [[ -f /etc/supervisord.conf.bak ]]; then
        mv /etc/supervisord.conf.bak /etc/supervisord.conf
    fi
    
    # 删除自定义配置目录
    rm -rf /etc/supervisor.d
}

# 卸载软件包
function uninstall_packages() {
    echo "🧹 卸载相关软件包..."
    
    # 卸载 Supervisor
    if yum list installed supervisor &> /dev/null; then
        yum remove -y supervisor
    fi
    
    # 卸载依赖包（可选）
    # yum remove -y jq sqlite unzip openssl-devel python2-pip
}

# 删除用户和组
function remove_user() {
    echo "👤 删除专用用户..."
    
    if id -u "${RUN_USER}" &> /dev/null; then
        userdel -r "${RUN_USER}" 2>/dev/null || true
    fi
}

# 清理安装目录
function clean_installation() {
    echo "🧽 清理安装目录..."
    
    if [[ -d "${BASE_DIR}" ]]; then
        # 删除管理脚本
        rm -f "${BASE_DIR}"/*.sh
        
        # 删除安装目录
        rm -rf "${BASE_DIR}"
    fi
}

# 恢复防火墙设置
function restore_firewall() {
    echo "🔥 恢复防火墙设置..."
    
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --remove-port=17000/tcp
        firewall-cmd --reload
    fi
}

# 主卸载流程
function main() {
    echo "🔴 开始卸载 Nightingale..."
    
    stop_services
    remove_supervisor_configs
    uninstall_packages
    clean_installation
    remove_user
    restore_firewall
    
    echo -e "\n✅ Nightingale 已完全卸载"
    echo "已清理以下内容："
    echo "  - 所有服务已停止"
    echo "  - Supervisor 配置已移除"
    echo "  - 安装目录 ${BASE_DIR} 已删除"
    echo "  - 专用用户 ${RUN_USER} 已删除"
    echo "  - 防火墙规则已恢复"
}

main