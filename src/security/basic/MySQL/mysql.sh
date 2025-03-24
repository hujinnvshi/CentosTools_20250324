#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 输出带颜色的信息函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    print_error "请使用 root 用户执行此脚本"
    exit 1
fi

# 设置变量
MYSQL_VERSION="5.7.39"
MYSQL_ROOT_PASSWORD="Secsmart#612"
MYSQL_BASE="/data/mysql"
SYSTEM_MEMORY=$(free -g | awk '/^Mem:/{print $2}')
INNODB_BUFFER_POOL_SIZE=$(($SYSTEM_MEMORY * 70 / 100))G

# 创建目录结构
print_message "创建目录结构..."
mkdir -p ${MYSQL_BASE}/{base,data,log/binlog,tmp}

# 安装依赖
print_message "安装依赖包..."
yum install -y wget libaio numactl-libs perl net-tools

# 下载并安装 MySQL
print_message "下载 MySQL..."
cd /tmp
wget https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.gz

print_message "解压 MySQL..."
tar xzf mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.gz
mv mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64/* ${MYSQL_BASE}/base/

# 创建 mysql 用户和组
print_message "创建 mysql 用户..."
groupadd mysql
useradd -r -g mysql -s /bin/false mysql

# 设置目录权限
print_message "设置目录权限..."
chown -R mysql:mysql ${MYSQL_BASE}
chmod -R 755 ${MYSQL_BASE}

# 创建配置文件
print_message "创建 MySQL 配置文件..."
cat > ${MYSQL_BASE}/my.cnf << EOF
[mysqld]
# 基础配置
user = mysql
port = 3306
basedir = ${MYSQL_BASE}/base
datadir = ${MYSQL_BASE}/data
socket = ${MYSQL_BASE}/mysql.sock
pid-file = ${MYSQL_BASE}/mysql.pid
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
explicit_defaults_for_timestamp = 1

# 性能配置
innodb_buffer_pool_size = ${INNODB_BUFFER_POOL_SIZE}
innodb_log_file_size = 1G
innodb_log_buffer_size = 16M
query_cache_size = 0
query_cache_type = 0
max_connections = 10000
max_user_connections = 10000
tmp_table_size = 16M
sort_buffer_size = 2M

# 日志配置
log-error = ${MYSQL_BASE}/log/error.log
slow_query_log = 1
slow_query_log_file = ${MYSQL_BASE}/log/slow.log
long_query_time = 2
log_queries_not_using_indexes = 1
log-bin = ${MYSQL_BASE}/log/binlog/mysql-bin
binlog_format = ROW
expire_logs_days = 7
binlog_cache_size = 1M
sync_binlog = 1

# 安全配置
local-infile = 0
max_allowed_packet = 16M
ssl = 1
validate_password_policy = STRONG
secure-file-priv = NULL

# 其他优化
lower_case_table_names = 1
skip-name-resolve
event_scheduler = ON
default-time-zone = '+8:00'

# 监控配置
performance_schema = ON
EOF

# 初始化 MySQL
print_message "初始化 MySQL..."
${MYSQL_BASE}/base/bin/mysqld --initialize-insecure --user=mysql --basedir=${MYSQL_BASE}/base --datadir=${MYSQL_BASE}/data

# 创建服务文件
print_message "创建 MySQL 服务..."
cat > /usr/lib/systemd/system/mysqld.service << EOF
[Unit]
Description=MySQL Server
After=network.target

[Service]
User=mysql
Group=mysql
ExecStart=${MYSQL_BASE}/base/bin/mysqld --defaults-file=${MYSQL_BASE}/my.cnf
LimitNOFILE=65535
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 启动 MySQL
print_message "启动 MySQL 服务..."
systemctl daemon-reload
systemctl start mysqld
systemctl enable mysqld

# 等待 MySQL 启动
sleep 10

# 设置 root 密码和安全配置
print_message "配置 MySQL root 密码..."
${MYSQL_BASE}/base/bin/mysql -u root << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;

-- 创建测试数据库和用户
CREATE DATABASE testdb CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'testuser'@'localhost' IDENTIFIED BY 'Test#123456';
GRANT ALL PRIVILEGES ON testdb.* TO 'testuser'@'localhost';

-- 创建测试表和数据
USE testdb;
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('active', 'inactive') DEFAULT 'active'
);

INSERT INTO users (username, email) VALUES ('test_user', 'test@example.com');
FLUSH PRIVILEGES;
EOF

# 验证安装
print_message "验证 MySQL 安装..."
${MYSQL_BASE}/base/bin/mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "SELECT VERSION();"
${MYSQL_BASE}/base/bin/mysql -u testuser -pTest#123456 testdb -e "SELECT * FROM users;"

print_message "MySQL 安装完成！"
print_message "MySQL 版本：$(${MYSQL_BASE}/base/bin/mysql -V)"
print_message "Root 密码：${MYSQL_ROOT_PASSWORD}"
print_message "测试用户：testuser"
print_message "测试密码：Test#123456"
print_message "测试数据库：testdb"