#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用root用户执行此脚本"
fi

# 设置变量
export PERCONA_VERSION="8.4.0-1"
export PERCONA_HOME="/data/percona_8.4.0"
export PERCONA_USER="percona"
export PERCONA_GROUP="perconagrp"
export PERCONA_PORT="3308"
export PERCONA_PASSWORD="Secsmart#612"

# 添加清理函数
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        print_message "安装失败，开始清理..."  # 改用print_message，因为print_error会导致递归退出
        systemctl stop percona 2>/dev/null || true  # 添加错误处理
        rm -rf ${PERCONA_HOME} 2>/dev/null || true
        rm -f /usr/lib/systemd/system/percona.service 2>/dev/null || true
        rm -f /etc/profile.d/percona.sh 2>/dev/null || true
    fi
    exit $exit_code
}
# trap cleanup ERR

# 检查安装包
if [ ! -f "/tmp/Percona-Server-${PERCONA_VERSION}-Linux.x86_64.glibc2.17.tar.gz" ]; then
    print_error "安装包不存在：/tmp/Percona-Server-${PERCONA_VERSION}-Linux.x86_64.glibc2.17.tar.gz"
fi

# 检查并安装依赖包
print_message "检查并安装依赖包..."
DEPS="libaio numactl net-tools"
for pkg in $DEPS; do
    if ! rpm -q $pkg &>/dev/null; then
        print_message "正在安装 ${pkg}..."
        yum install -y $pkg || print_error "安装 ${pkg} 失败"
    else
        print_message "${pkg} 已安装"
    fi
done

# 检查端口占用
if netstat -tuln | grep ":${PERCONA_PORT}" >/dev/null; then
    print_error "端口 ${PERCONA_PORT} 已被占用"
fi

# 添加备份功能
if [ -d "${PERCONA_HOME}" ]; then
    BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
    print_message "备份已存在的Percona目录..."
    # tar czf ${PERCONA_HOME}_backup_${BACKUP_TIME}.tar.gz ${PERCONA_HOME} || print_error "备份失败"
fi

# 创建目录结构
print_message "创建目录结构..."
mkdir -p ${PERCONA_HOME}/{base,data,log/binlog,tmp}
touch ${PERCONA_HOME}/log/error.log
touch ${PERCONA_HOME}/log/slow.log

# 创建用户和组
print_message "创建percona用户和组..."
groupadd ${PERCONA_GROUP} 2>/dev/null || true
useradd -r -m -s /bin/bash -g ${PERCONA_GROUP} ${PERCONA_USER} 2>/dev/null || true

# 解压安装包
print_message "解压安装包..."
cd /tmp || print_error "无法进入/tmp目录"

# 定义临时目录
TEMP_DIR="/tmp/percona_${PERCONA_VERSION}_$(date +%s)"
mkdir -p "${TEMP_DIR}" || print_error "创建临时目录失败"

# 解压文件
tar zxf Percona-Server-${PERCONA_VERSION}-Linux.x86_64.glibc2.17.tar.gz -C "${TEMP_DIR}" || print_error "解压安装包失败"

# 查找实际的Percona目录并复制文件
PERCONA_EXTRACT_DIR=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "Percona-Server-*" | head -n 1)
echo "Percona提取目录: ${PERCONA_EXTRACT_DIR}"
if [ -n "${PERCONA_EXTRACT_DIR}" ] && [ -d "${PERCONA_EXTRACT_DIR}" ]; then
    cp -r "${PERCONA_EXTRACT_DIR}/"* ${PERCONA_HOME}/base/ || print_error "复制文件失败"
else
    print_error "无法找到解压后的Percona目录"
fi

# 清理临时文件
rm -rf "${TEMP_DIR}"

# 配置my.cnf
print_message "配置my.cnf..."
# 计算InnoDB缓冲池大小（系统内存的20%）
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ -z "$TOTAL_MEM" ] || [ "$TOTAL_MEM" -eq 0 ]; then
    print_error "无法获取系统内存大小"
fi
BUFFER_POOL_SIZE=$(($TOTAL_MEM * 20 / 100))
if [ "$BUFFER_POOL_SIZE" -eq 0 ]; then
    BUFFER_POOL_SIZE=1  # 至少设置1G
fi

cat > ${PERCONA_HOME}/my.cnf << EOF
# my.cnf中的用户配置应该与实际用户一致
[mysqld]
user = ${PERCONA_USER}  # 改为变量，而不是固定的mysql
port = ${PERCONA_PORT}
basedir = ${PERCONA_HOME}/base
datadir = ${PERCONA_HOME}/data
socket = ${PERCONA_HOME}/tmp/mysql.sock
pid-file = ${PERCONA_HOME}/tmp/mysql.pid
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
explicit_defaults_for_timestamp = 1
default-time-zone = '+8:00'
mysqlx_socket = ${PERCONA_HOME}/tmp/mysqlx.sock
secure-log-path = ${PERCONA_HOME}/log

# 性能配置
innodb_buffer_pool_size = ${BUFFER_POOL_SIZE}G
innodb_redo_log_capacity = 1G
innodb_log_buffer_size = 16M
max_connections = 214
thread_cache_size = 214
tmp_table_size = 16M
sort_buffer_size = 2M

# 日志配置
log-error = ${PERCONA_HOME}/log/error.log
slow_query_log = 1
slow_query_log_file = ${PERCONA_HOME}/log/slow.log
long_query_time = 2
log_queries_not_using_indexes = 1
log-bin = ${PERCONA_HOME}/log/binlog/Percona-bin
binlog_expire_logs_seconds = 604800
binlog_cache_size = 1M
sync_binlog = 1

# 安全配置
local_infile = 0
max_allowed_packet = 16M
require_secure_transport = OFF
bind-address = 0.0.0.0

# 其他优化
thread_handling = one-thread-per-connection
lower_case_table_names = 1
skip-name-resolve
event_scheduler = ON

# 监控配置
performance_schema = ON

[client]
port = ${PERCONA_PORT}
socket = ${PERCONA_HOME}/tmp/mysql.sock
default-character-set = utf8mb4

[mysql]
default-character-set = utf8mb4
EOF

# 设置权限
print_message "设置权限..."
rm -rf ${PERCONA_HOME}/data
mkdir -p ${PERCONA_HOME}/data
chmod 750 ${PERCONA_HOME}
chmod 700 ${PERCONA_HOME}/data
chmod 700 ${PERCONA_HOME}/log
chmod 700 ${PERCONA_HOME}/tmp
chmod 755 ${PERCONA_HOME}/base
chmod 644 ${PERCONA_HOME}/my.cnf
chown -R ${PERCONA_USER}:${PERCONA_GROUP} ${PERCONA_HOME}

# 检查端口占用并清理
print_message "检查端口占用..."
if netstat -tuln | grep ":${PERCONA_PORT}" >/dev/null; then
    print_message "端口 ${PERCONA_PORT} 被占用，尝试清理..."
    pid=$(lsof -t -i:${PERCONA_PORT})
    if [ -n "$pid" ]; then
        kill -9 $pid
        sleep 2
    fi
fi

# 初始化数据库
print_message "初始化数据库..."
rm -rf ${PERCONA_HOME}/data/*
mkdir -p ${PERCONA_HOME}/data
chown ${PERCONA_USER}:${PERCONA_GROUP} ${PERCONA_HOME}/data

# 使用su命令执行初始化
su - ${PERCONA_USER} -c "
    ${PERCONA_HOME}/base/bin/mysqld \
    --defaults-file=${PERCONA_HOME}/my.cnf \
    --initialize \
    --user=${PERCONA_USER} \
    --datadir=${PERCONA_HOME}/data
"

# 显示错误日志中的ERROR信息
print_message "显示错误日志中的ERROR信息..."
grep -i "error" ${PERCONA_HOME}/log/error.log || true

# 获取临时密码
TEMP_PASSWORD=$(grep 'temporary password' ${PERCONA_HOME}/log/error.log | awk '{print $NF}')
if [ -z "${TEMP_PASSWORD}" ]; then
    print_error "无法获取临时密码，初始化可能失败"
fi
echo "临时密码: ${TEMP_PASSWORD}"

# 创建服务文件
print_message "创建系统服务..."
cat > /usr/lib/systemd/system/percona.service << EOF
[Unit]
Description=Percona Server
After=network.target

[Service]
Type=forking
User=${PERCONA_USER}
Group=${PERCONA_GROUP}
ExecStart=${PERCONA_HOME}/base/bin/mysqld_safe --defaults-file=${PERCONA_HOME}/my.cnf
ExecStop=/bin/kill \$MAINPID
PIDFile=${PERCONA_HOME}/tmp/mysql.pid
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 配置环境变量
print_message "配置环境变量..."
cat > /etc/profile.d/percona.sh << EOF
export PERCONA_HOME=${PERCONA_HOME}
export PATH=\$PERCONA_HOME/base/bin:\$PATH
EOF
source /etc/profile.d/percona.sh || print_error "加载环境变量失败"

# 启动服务
print_message "启动Percona服务..."
systemctl daemon-reload
systemctl start percona

# 增加启动检查重试
RETRY_COUNT=0
MAX_RETRIES=3
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if systemctl is-active percona >/dev/null 2>&1; then
        break
    fi
    print_message "等待服务启动... (${RETRY_COUNT}/${MAX_RETRIES})"
    sleep 5
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if ! systemctl is-active percona >/dev/null 2>&1; then
    print_error "Percona服务启动失败，请检查日志：${PERCONA_HOME}/log/error.log"
fi

systemctl enable percona

# 等待服务启动
sleep 10

# 设置root密码
print_message "设置root密码..."
${PERCONA_HOME}/base/bin/mysql --connect-expired-password -uroot -p"${TEMP_PASSWORD}" << EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${PERCONA_PASSWORD}';
FLUSH PRIVILEGES;
EOF

# 4. 执行安全配置
${PERCONA_HOME}/base/bin/mysql_secure_installation << EOF
y
${PERCONA_PASSWORD}
${PERCONA_PASSWORD}
y
y
y
y
EOF

# 创建测试数据
print_message "创建测试数据..."
cat > /tmp/init.sql << EOF
CREATE DATABASE test_db;
CREATE USER 'test_user'@'localhost' IDENTIFIED WITH mysql_native_password BY 'Test@123';
GRANT ALL PRIVILEGES ON test_db.* TO 'test_user'@'localhost';
FLUSH PRIVILEGES;

CREATE DATABASE admin;
CREATE USER 'admin'@'%' IDENTIFIED WITH mysql_native_password BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%';
FLUSH PRIVILEGES;

USE test_db;
CREATE TABLE employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    age INT,
    department VARCHAR(50),
    salary DECIMAL(10,2),
    hire_date DATE
);

INSERT INTO employees (name, age, department, salary, hire_date)
VALUES ('张三', 30, '技术部', 15000.00, '2023-01-01');
EOF

if ! ${PERCONA_HOME}/base/bin/mysql -uroot -p${PERCONA_PASSWORD} < /tmp/init.sql; then
    print_error "创建测试数据失败"
fi
rm -f /tmp/init.sql

print_message "Percona安装完成！"
print_message "数据库启动命令: systemctl start percona"
print_message "数据库停止命令: systemctl stop percona"
print_message "数据库重启命令: systemctl restart percona"
print_message "数据库状态查看: systemctl status percona"
print_message "数据库连接命令: mysql -uroot -p${PERCONA_PASSWORD}"
print_message "测试用户连接命令: mysql -utest_user -pTest@123 test_db"