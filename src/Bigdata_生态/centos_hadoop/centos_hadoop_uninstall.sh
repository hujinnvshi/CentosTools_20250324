#!/bin/bash
# Hadoop 清理脚本
# 用于完全移除 Hadoop 安装和相关资源

set -euo pipefail

# 配置参数（与安装脚本一致）
HADOOP_VERSION="2.7.7"
Service_ID="hadoop_${HADOOP_VERSION}_v1"
HADOOP_BASE_DIR="/data/${Service_ID}"
HADOOP_USER=${Service_ID}
HADOOP_GROUP=${Service_ID}

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root用户运行此脚本"
    exit 1
fi

# 停止Hadoop服务
stop_hadoop_services() {
    echo "停止Hadoop服务..."
    
    # 检查服务是否运行
    if [ -f "$HADOOP_BASE_DIR/stop-hadoop.sh" ]; then
        echo "执行停止脚本..."
        sudo -u "$HADOOP_USER" "$HADOOP_BASE_DIR/stop-hadoop.sh" || true
    else
        echo "停止脚本不存在，尝试直接停止..."
        # 尝试停止相关进程
        pkill -u "$HADOOP_USER" -f "hadoop" || true
        sleep 3
    fi
    
    echo "Hadoop服务已停止"
}

# 删除安装目录
remove_installation() {
    echo "删除安装目录: $HADOOP_BASE_DIR..."
    if [ -d "$HADOOP_BASE_DIR" ]; then
        rm -rf "$HADOOP_BASE_DIR"
        echo "安装目录已删除"
    else
        echo "安装目录不存在，跳过"
    fi
}

# 删除环境变量配置
remove_environment() {
    echo "删除环境变量配置..."
    local env_file="/etc/profile.d/hadoop.sh"
    
    if [ -f "$env_file" ]; then
        rm -f "$env_file"
        echo "环境变量文件已删除"
    else
        echo "环境变量文件不存在，跳过"
    fi
}

# 删除用户和组
remove_user_group() {
    echo "删除Hadoop用户和组..."
    
    # 检查用户是否存在
    if id "$HADOOP_USER" &>/dev/null; then
        # 检查是否有其他进程使用该用户
        if pgrep -u "$HADOOP_USER" >/dev/null; then
            echo "警告：用户 $HADOOP_USER 仍有进程运行，跳过删除"
        else
            userdel -r "$HADOOP_USER" || true
            echo "用户 $HADOOP_USER 已删除"
        fi
    else
        echo "用户 $HADOOP_USER 不存在，跳过"
    fi
    
    # 检查组是否存在
    if getent group "$HADOOP_GROUP" >/dev/null; then
        groupdel "$HADOOP_GROUP" || true
        echo "组 $HADOOP_GROUP 已删除"
    else
        echo "组 $HADOOP_GROUP 不存在，跳过"
    fi
}

# 清理临时文件
clean_temporary_files() {
    echo "清理临时文件..."
    
    # 清理测试文件
    rm -f /tmp/hadoop_test_*.txt
    
    # 清理下载缓存
    #find /tmp -name "hadoop-*.tar.gz" -delete
}

# 清理端口占用
release_ports() {
    echo "检查并释放端口..."
    local ports=("9000" "50070" "8088" "19888")
    
    for port in "${ports[@]}"; do
        if netstat -tuln | grep ":$port" >/dev/null; then
            echo "端口 $port 仍被占用，尝试释放..."
            fuser -k "$port/tcp" || true
        fi
    done
}

# 主清理流程
main() {
    echo "开始清理 Hadoop 安装..."
    
    # 1. 停止服务
    stop_hadoop_services
    
    # 2. 释放端口
    release_ports
    
    # 3. 删除安装目录
    remove_installation
    
    # 4. 删除环境变量
    remove_environment
    
    # 5. 清理临时文件
    clean_temporary_files
    
    # 6. 删除用户和组（可选）
    read -p "是否删除用户和组? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        remove_user_group
    else
        echo "保留用户和组"
    fi
    
    echo -e "\n✅ Hadoop 清理完成"
}

# 执行主函数
main