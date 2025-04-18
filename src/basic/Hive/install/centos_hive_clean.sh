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
HIVE_HOME="/data/hive"
HIVE_LOG_DIR="/data/hive/logs"
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
MYSQL_DB="hive20250324"
MYSQL_USER="hive20250324"
MYSQL_PASSWORD="Secsmart#612"

# 停止服务
print_message "停止 Hive 服务..."
systemctl stop hive 2>/dev/null || true
systemctl stop hive-metastore 2>/dev/null || true
sleep 5

# 检查并杀死残留进程
print_message "检查残留进程..."
for proc in HiveServer2 HiveMetaStore; do
    pid=$(ps -ef | grep $proc | grep -v grep | awk '{print $2}')
    if [ ! -z "$pid" ]; then
        print_warning "强制终止 $proc 进程 (PID: $pid)"
        kill -9 $pid 2>/dev/null || true
    fi
done

# 禁用服务
print_message "禁用 Hive 服务..."
systemctl disable hive 2>/dev/null || true
systemctl disable hive-metastore 2>/dev/null || true

# 备份配置文件（可选）
backup_dir="/data/backup/hive-$(date +%Y%m%d_%H%M%S)"
print_message "创建配置备份到 ${backup_dir}..."
if [ -d "${HIVE_HOME}/conf" ]; then
    mkdir -p "${backup_dir}/conf"
    cp -r "${HIVE_HOME}/conf" "${backup_dir}/" 2>/dev/null || true
fi

# 清理元数据库
print_message "清理 Hive 元数据库..."
mysql -h${MYSQL_HOST} -P${MYSQL_PORT} -u${MYSQL_USER} -p${MYSQL_PASSWORD} -e "DROP DATABASE IF EXISTS ${MYSQL_DB};" 2>/dev/null || print_warning "清理元数据库失败"

# 清理文件
print_message "清理 Hive 文件..."
rm -rf ${HIVE_HOME} 2>/dev/null || print_warning "清理 ${HIVE_HOME} 失败"
rm -rf ${HIVE_LOG_DIR} 2>/dev/null || print_warning "清理 ${HIVE_LOG_DIR} 失败"

# 清理环境变量
print_message "清理环境变量配置..."
rm -f /etc/profile.d/hive.sh 2>/dev/null || print_warning "清理环境变量配置失败"

# 清理服务文件
print_message "清理服务文件..."
rm -f /usr/lib/systemd/system/hive.service 2>/dev/null || print_warning "清理 hive 服务文件失败"
rm -f /usr/lib/systemd/system/hive-metastore.service 2>/dev/null || print_warning "清理 metastore 服务文件失败"
systemctl daemon-reload

# 清理日志轮转配置
print_message "清理日志轮转配置..."
rm -f /etc/logrotate.d/hive 2>/dev/null || print_warning "清理日志轮转配置失败"

# 清理 HDFS 上的 Hive 目录
print_message "清理 HDFS 上的 Hive 目录..."
su - hdfs -c "hdfs dfs -rm -r -f /user/hive/warehouse" 2>/dev/null || print_warning "清理 HDFS warehouse 目录失败"
su - hdfs -c "hdfs dfs -rm -r -f /tmp/hive" 2>/dev/null || print_warning "清理 HDFS tmp 目录失败"

print_message "Hive 清理完成！"
print_message "备份文件位置: ${backup_dir}"
print_message "如需完全清理，请手动执行："
print_message "1. userdel -r hive     # 删除 hive 用户及其主目录"
print_message "2. rm -rf /home/hive   # 如果用户目录仍然存在"

# 提示重新安装
print_message "现在可以重新运行 install_hive.sh 进行安装"