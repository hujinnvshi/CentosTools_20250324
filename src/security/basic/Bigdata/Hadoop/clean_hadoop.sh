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

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 设置变量
HADOOP_VERSION="2.7.7"
HADOOP_HOME="/data/hadoop-${HADOOP_VERSION}/base"
HADOOP_DATA="/data/hadoop-${HADOOP_VERSION}/data"
HADOOP_LOGS="/data/hadoop-${HADOOP_VERSION}/logs"

# 停止服务
print_message "停止 Hadoop 服务..."
systemctl stop hadoop 2>/dev/null || true
su - hdfs -c "${HADOOP_HOME}/sbin/stop-all.sh" 2>/dev/null || true
sleep 5

# 检查并杀死残留进程
print_message "检查残留进程..."
for proc in NameNode DataNode ResourceManager NodeManager; do
    pid=$(ps -ef | grep $proc | grep -v grep | awk '{print $2}')
    if [ ! -z "$pid" ]; then
        print_warning "强制终止 $proc 进程 (PID: $pid)"
        kill -9 $pid 2>/dev/null || true
    fi
done

# 禁用服务
print_message "禁用 Hadoop 服务..."
systemctl disable hadoop 2>/dev/null || true

# 备份配置文件（可选）
backup_dir="/data/backup/hadoop-$(date +%Y%m%d_%H%M%S)"
print_message "创建配置备份到 ${backup_dir}..."
if [ -d "${HADOOP_HOME}/etc/hadoop" ]; then
    mkdir -p "${backup_dir}/conf"
    cp -r "${HADOOP_HOME}/etc/hadoop" "${backup_dir}/conf/" 2>/dev/null || true
fi

# 清理文件
print_message "清理 Hadoop 文件..."
rm -rf ${HADOOP_HOME} 2>/dev/null || print_warning "清理 ${HADOOP_HOME} 失败"
rm -rf ${HADOOP_DATA} 2>/dev/null || print_warning "清理 ${HADOOP_DATA} 失败"
rm -rf ${HADOOP_LOGS} 2>/dev/null || print_warning "清理 ${HADOOP_LOGS} 失败"

# 清理环境变量
print_message "清理环境变量配置..."
rm -f /etc/profile.d/hadoop.sh 2>/dev/null || print_warning "清理环境变量配置失败"

# 清理服务文件
print_message "清理服务文件..."
rm -f /usr/lib/systemd/system/hadoop.service 2>/dev/null || print_warning "清理服务文件失败"
systemctl daemon-reload

# 清理日志轮转配置
print_message "清理日志轮转配置..."
rm -f /etc/logrotate.d/hadoop 2>/dev/null || print_warning "清理日志轮转配置失败"

print_message "Hadoop 清理完成！"
print_message "备份文件位置: ${backup_dir}"
print_message "如需完全清理，请手动执行："
print_message "1. userdel -r hdfs    # 删除 hdfs 用户及其主目录"
print_message "2. groupdel hadoop    # 删除 hadoop 用户组"