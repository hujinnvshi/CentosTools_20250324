#!/bin/bash
# Sybase ASE 15.7 CentOS 清理卸载脚本
# 版本: 1.1
# 作者: Rancher
# 最后更新: 2025-08-20

# 设置环境变量（与安装脚本保持一致）
export SYBASE_USER="sb157v1"  # 与安装脚本保持一致
export SYBASE_GROUP="sb157v1" # 与安装脚本保持一致
export SYBASE_HOME="/data/sb157v1"  # 与安装脚本保持一致
export ASE_VERSION="15.7"
export ASE_INSTALL_DIR="$SYBASE_HOME/ASE-$ASE_VERSION"
export ASE_DATA_DIR="$SYBASE_HOME/data"
export ASE_BACKUP_DIR="$SYBASE_HOME/backups"
export ASE_INSTALL_FILE="ase157_linuxx86-64.tgz"
export ASE_INSTALL_PATH="/tmp/$ASE_INSTALL_FILE"

export SA_PASSWORD=${SA_PASSWORD:-"Secsmart#612"} # 可从环境变量获取密码

# 设置严格模式
set -euo pipefail

# 检查是否以root用户运行
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "错误: 此脚本必须以root权限运行"
        exit 1
    fi
}

# 停止Sybase服务
stop_service() {
    echo "停止Sybase服务..."
    if systemctl is-active --quiet sybase157v1.service; then
        # 尝试优雅停止服务，最多重试3次
        for i in {1..3};
        do
            systemctl stop sybase157v1.service
            if ! systemctl is-active --quiet sybase157v1.service; then
                echo "Sybase服务已成功停止"
                return 0
            else
                echo "停止失败，重试 ($i/3)..."
                sleep 5
            fi
        done
        echo "警告: 无法正常停止Sybase服务，将强制终止进程"
    else
        echo "Sybase服务未运行"
    fi
}

# 禁用Sybase服务
disable_service() {
    echo "禁用Sybase服务..."
    if systemctl is-enabled --quiet sybase157v1.service; then
        systemctl disable sybase157v1.service
        echo "Sybase服务已禁用"
    else
        echo "Sybase服务未启用"
    fi
}

# 删除服务文件
remove_service_file() {
    echo "删除Sybase服务文件..."
    if [ -f "/etc/systemd/system/sybase157v1.service" ]; then
        rm -f /etc/systemd/system/sybase157v1.service
        systemctl daemon-reload
        echo "Sybase服务文件已删除"
    else
        echo "Sybase服务文件不存在"
    fi
}

# 删除环境变量配置
remove_environment_config() {
    echo "删除环境变量配置..."
    if [ -f "/etc/profile.d/sybase.sh" ]; then
        rm -f /etc/profile.d/sybase.sh
        echo "环境变量配置已删除"
    else
        echo "环境变量配置文件不存在"
    fi
}

# 终止所有Sybase相关进程
kill_sybase_processes() {
    echo "终止Sybase相关进程..."
    pids=$(ps -ef | grep "$SYBASE_HOME" | grep -v grep | awk '{print $2}')
    if [ -n "$pids" ]; then
        echo "尝试正常终止进程..."
        kill $pids
        sleep 5
        # 检查是否还有进程存活
        remaining_pids=$(ps -ef | grep "$SYBASE_HOME" | grep -v grep | awk '{print $2}')
        if [ -n "$remaining_pids" ]; then
            echo "正常终止失败，尝试强制终止..."
            kill -9 $remaining_pids
        fi
        echo "已终止Sybase相关进程"
    else
        echo "未发现运行中的Sybase进程"
    fi
}

# 删除Sybase用户和组
remove_user_group() {
    echo "删除Sybase用户和组..."
    if id -u $SYBASE_USER >/dev/null 2>&1; then
        userdel -r $SYBASE_USER
        echo "Sybase用户已删除"
    else
        echo "Sybase用户不存在"
    fi
    
    if getent group $SYBASE_GROUP >/dev/null 2>&1; then
        groupdel $SYBASE_GROUP
        echo "Sybase组已删除"
    else
        echo "Sybase组不存在"
    fi
}

# 删除Sybase安装目录
remove_installation() {
    echo "删除Sybase安装目录..."
    if [ -d "$SYBASE_HOME" ]; then
        rm -rf $SYBASE_HOME
        echo "Sybase安装目录已删除"
    else
        echo "Sybase安装目录不存在"
    fi
}

# 清理响应文件和interfaces文件
cleanup_config_files() {
    echo "清理配置文件..."
    # 清理响应文件
    if [ -f "$SYBASE_HOME/ase_install.rs" ]; then
        rm -f $SYBASE_HOME/ase_install.rs
        echo "响应文件已删除"
    else
        echo "响应文件不存在"
    fi
    
    # 清理interfaces文件
    if [ -f "$SYBASE_HOME/interfaces" ]; then
        rm -f $SYBASE_HOME/interfaces
        echo "interfaces文件已删除"
    else
        echo "interfaces文件不存在"
    fi
}

# 恢复系统配置
restore_system_config() {
    echo "恢复系统配置..."
    
    # 恢复sysctl.conf配置
    if grep -q "# Sybase ASE 优化参数" /etc/sysctl.conf; then
        sed -i '/# Sybase ASE 优化参数/,+6d' /etc/sysctl.conf
        sysctl -p
        echo "已恢复sysctl配置"
    else
        echo "未找到Sybase相关的sysctl配置"
    fi
    
    # 恢复limits.conf配置
    if grep -q "# Sybase ASE 资源限制" /etc/security/limits.conf; then
        sed -i "/# Sybase ASE 资源限制/,+4d" /etc/security/limits.conf
        echo "已恢复limits配置"
    else
        echo "未找到Sybase相关的limits配置"
    fi
    
    # 恢复备份的配置文件（如果存在）
    if [ -f "/etc/sysctl.conf.bak" ]; then
        cp /etc/sysctl.conf.bak /etc/sysctl.conf
        sysctl -p
        echo "已恢复sysctl.conf备份"
    fi
    
    if [ -f "/etc/security/limits.conf.bak" ]; then
        cp /etc/security/limits.conf.bak /etc/security/limits.conf
        echo "已恢复limits.conf备份"
    fi
}

# 主函数
main() {
    echo "===== 开始清理 Sybase ASE 15.7 ====="
    check_root
    
    # 确认操作
    echo "警告: 此操作将删除所有Sybase ASE 15.7相关文件和配置(保留安装包)"
    echo "是否继续? (y/N)"
    read -r reply
    if [[ ! \$reply =~ ^[Yy]$ ]]; then
        echo "操作已取消"
        exit 0
    fi
    
    stop_service
    disable_service
    remove_service_file
    remove_environment_config
    kill_sybase_processes
    cleanup_config_files
    remove_installation
    remove_user_group
    
    echo "===== Sybase ASE 15.7 清理完成！====="
    echo "注意: 安装包 \$ASE_INSTALL_PATH 未被删除，可根据需要手动清理"
}

# 执行主函数
main "\$@"