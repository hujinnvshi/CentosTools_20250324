#!/bin/bash

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
}

# 设置变量
KAFKA_HOME="/data/kafka"
BACKUP_DIR="/data/kafka_backups"

# 停止 Kafka 服务
stop_kafka() {
    print_message "停止 Kafka 服务..."
    
    if systemctl is-active --quiet kafka; then
        systemctl stop kafka
        sleep 5
    fi
    
    if pgrep -f "kafka\.Kafka" >/dev/null; then
        print_warning "强制停止 Kafka 进程..."
        pkill -9 -f "kafka\.Kafka"
    fi
}

# 备份数据
backup_data() {
    print_message "备份 Kafka 数据..."
    
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_NAME="kafka_backup_${TIMESTAMP}.tar.gz"
    
    mkdir -p ${BACKUP_DIR}
    tar -czf ${BACKUP_DIR}/${BACKUP_NAME} \
        ${KAFKA_HOME}/config \
        ${KAFKA_HOME}/data \
        ${KAFKA_HOME}/logs
    
    print_message "备份已保存到: ${BACKUP_DIR}/${BACKUP_NAME}"
}

# 清理 Kafka 安装
clean_kafka() {
    print_message "清理 Kafka 安装..."
    
    # 删除安装目录
    if [ -d "${KAFKA_HOME}" ]; then
        rm -rf ${KAFKA_HOME}
        print_message "已删除 Kafka 安装目录"
    fi
    
    # 删除系统服务
    if [ -f "/etc/systemd/system/kafka.service" ]; then
        systemctl disable kafka --now
        rm -f /etc/systemd/system/kafka.service
        systemctl daemon-reload
        print_message "已删除 Kafka 系统服务"
    fi
    
    # 删除环境变量
    if [ -f "/etc/profile.d/kafka.sh" ]; then
        rm -f /etc/profile.d/kafka.sh
        print_message "已删除 Kafka 环境变量配置"
    fi
    
    # 删除用户和组（可选）
    read -p "是否删除 Kafka 用户和组？(y/n): " DELETE_USER
    if [ "$DELETE_USER" = "y" ]; then
        if id "kafka" &>/dev/null; then
            userdel -r kafka
            groupdel kafka
            print_message "已删除 Kafka 用户和组"
        else
            print_warning "Kafka 用户不存在"
        fi
    fi
    
    # 清理临时文件
    # rm -f /tmp/kafka_*.tgz
}

# 清理旧备份
clean_old_backups() {
    print_message "清理旧备份..."
    
    # 保留最近 5 个备份
    cd ${BACKUP_DIR}
    BACKUP_COUNT=$(ls -1 | wc -l)
    
    if [ $BACKUP_COUNT -gt 5 ]; then
        OLD_BACKUPS=$(ls -t | tail -n +6)
        for backup in $OLD_BACKUPS; do
            rm -f ${BACKUP_DIR}/${backup}
            print_message "已删除旧备份: ${backup}"
        done
    else
        print_message "无需清理，备份数量: ${BACKUP_COUNT}"
    fi
}

# 主函数
main() {
    print_message "开始清理 Kafka 环境..."
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户执行此脚本"
        exit 1
    fi
    
    # 执行清理步骤
    stop_kafka
    backup_data
    clean_kafka
    clean_old_backups    
    print_message "Kafka 环境清理完成！"
    print_message "备份保存在: ${BACKUP_DIR}"
}

# 执行主函数
main