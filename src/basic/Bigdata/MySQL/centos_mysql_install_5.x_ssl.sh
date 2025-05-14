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
MYSQL_BASE="/data/mysql_ssl_${MYSQL_VERSION}_v1"
MYSQL_Service="mysql_ssl_${MYSQL_VERSION}_v1"
SYSTEM_MEMORY=$(free -g | awk '/^Mem:/{print $2}')
INNODB_BUFFER_POOL_SIZE=$(($SYSTEM_MEMORY * 70 / 100))G
MySQL_Port=3013
MySQL_ServerID=10087

# 创建目录结构
print_message "创建目录结构..."
mkdir -p ${MYSQL_BASE}/{base,data,log/binlog,tmp}
print_message "创建SSL证书目录..."
mkdir -p ${MYSQL_BASE}/ssl
chmod 700 ${MYSQL_BASE}/ssl

# 安装依赖
print_message "安装依赖包..."
yum install -y wget libaio numactl-libs perl net-tools

# 在安装依赖后添加SSL证书生成（约第65行后）
print_message "生成SSL证书..."
# 修改SSL证书生成部分（约第65行）
print_message "生成SSL证书..."

openssl req -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Secsmart/CN=MySQL CA" \
    -keyout ${MYSQL_BASE}/ssl/ca-key.pem \
    -out ${MYSQL_BASE}/ssl/ca.pem

openssl req -newkey rsa:2048 -nodes \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Secsmart/CN=mysql-server" \
    -keyout ${MYSQL_BASE}/ssl/server-key.pem \
    -out ${MYSQL_BASE}/ssl/server-req.pem

openssl x509 -req -in ${MYSQL_BASE}/ssl/server-req.pem \
    -CA ${MYSQL_BASE}/ssl/ca.pem \
    -CAkey ${MYSQL_BASE}/ssl/ca-key.pem \
    -CAcreateserial \
    -out ${MYSQL_BASE}/ssl/server-cert.pem

chown mysql:mysql ${MYSQL_BASE}/ssl/*
chmod 600 ${MYSQL_BASE}/ssl/*

# 下载并安装 MySQL
print_message "准备 MySQL 安装包..."
cd /tmp
MYSQL_FILE="mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.gz"

if [ -f "${MYSQL_FILE}" ]; then
    print_message "MySQL 安装包已存在，跳过下载"
else
    print_message "下载 MySQL 安装包..."
    wget https://dev.mysql.com/get/Downloads/MySQL-5.7/${MYSQL_FILE}
fi

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
rm -fr ${MYSQL_BASE}/data

# 创建配置文件
print_message "创建 MySQL 配置文件..."
cat > ${MYSQL_BASE}/my.cnf << EOF
[mysqld]
# 基础配置
user = mysql
port = ${MySQL_Port}
basedir = ${MYSQL_BASE}/base
datadir = ${MYSQL_BASE}/data
socket = ${MYSQL_BASE}/mysql.sock
pid-file = ${MYSQL_BASE}/mysql.pid
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
explicit_defaults_for_timestamp = 1
server-id = ${MySQL_ServerID}
gtid_mode=ON
enforce_gtid_consistency=ON

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
ssl-ca = ${MYSQL_BASE}/ssl/ca.pem
ssl-cert = ${MYSQL_BASE}/ssl/server-cert.pem
ssl-key = ${MYSQL_BASE}/ssl/server-key.pem
tls_version = TLSv1.2,TLSv1.3
ssl_cipher = HIGH:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK

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
${MYSQL_BASE}/base/bin/mysqld --initialize \
    --explicit_defaults_for_timestamp=1 \
    --user=mysql \
    --basedir=${MYSQL_BASE}/base \
    --datadir=${MYSQL_BASE}/data \
    --log-error=${MYSQL_BASE}/log/error.log \
    --ssl

# 创建服务文件
print_message "创建 MySQL 服务..."
cat > /usr/lib/systemd/system/${MYSQL_Service}.service << EOF
[Unit]
Description=MySQL Server
After=network.target

[Service]
User=mysql
Group=mysql
ExecStart=${MYSQL_BASE}/base/bin/mysqld_safe --defaults-file=${MYSQL_BASE}/my.cnf
LimitNOFILE=65535
Restart=on-failure
RestartSec=5
TimeoutSec=600

[Install]
WantedBy=multi-user.target
EOF

# 创建 mysqld_safe 配置
print_message "创建 mysqld_safe 配置..."
cat >> ${MYSQL_BASE}/my.cnf << EOF

[mysqld_safe]
log-error = ${MYSQL_BASE}/log/error.log
pid-file = ${MYSQL_BASE}/mysql.pid
malloc-lib = /usr/lib64/libjemalloc.so.1
EOF

# 安装 jemalloc 以提升性能(需要先配置好yum 源)
print_message "安装 jemalloc..."
yum install -y jemalloc

# 启动 MySQL
print_message "启动 MySQL 服务..."
systemctl daemon-reload
systemctl start ${MYSQL_Service}
systemctl enable ${MYSQL_Service}

# 等待 MySQL 启动
sleep 10

# 等待 MySQL 启动并检查状态
print_message "等待 MySQL 启动..."
for i in {1..5}; do
    if [ -S "${MYSQL_BASE}/mysql.sock" ]; then
        print_message "MySQL 已成功启动"
        break
    fi
    print_message "等待 MySQL 启动中... $i/5"
    sleep 2
done

if [ ! -S "${MYSQL_BASE}/mysql.sock" ]; then
    print_error "MySQL 启动失败，请检查错误日志：${MYSQL_BASE}/log/error.log"
    exit 1
fi

# 设置 root 密码和安全配置
print_message "配置 MySQL root 密码..."
${MYSQL_BASE}/base/bin/mysql -u root --socket=${MYSQL_BASE}/mysql.sock << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;

-- 创建测试数据库和用户
CREATE DATABASE admin CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'admin'@'%' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%';

CREATE DATABASE testdb CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER 'testuser'@'localhost' IDENTIFIED BY 'Secsmart#612';
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
INSERT INTO users (username, email) VALUES ('test_user', 'test@secsmart.net');
FLUSH PRIVILEGES;
EOF

# 验证安装
print_message "验证 MySQL 安装..."
${MYSQL_BASE}/base/bin/mysql -u root -p${MYSQL_ROOT_PASSWORD} --socket=${MYSQL_BASE}/mysql.sock  -e "SELECT VERSION();"
${MYSQL_BASE}/base/bin/mysql -u testuser -p${MYSQL_ROOT_PASSWORD} testdb --socket=${MYSQL_BASE}/mysql.sock  -e "SELECT * FROM users;"

print_message "MySQL 安装完成！"
print_message "MySQL 版本：$(${MYSQL_BASE}/base/bin/mysql -V)"
print_message "Root 密码：${MYSQL_ROOT_PASSWORD}"
print_message "测试用户：testuser"
print_message "测试密码：Secsmart#612"
print_message "测试数据库：testdb"

# 配置环境变量
print_message "配置环境变量..."
cat > /etc/profile.d/mysql.sh << EOF
# MySQL 环境变量
export MYSQL_HOME=${MYSQL_BASE}/base
export PATH=\$MYSQL_HOME/bin:\$PATH
EOF

# 设置正确的权限
chmod 644 /etc/profile.d/mysql.sh
chown root:root /etc/profile.d/mysql.sh

# 立即生效环境变量
source /etc/profile.d/mysql.sh

ln -s ${MYSQL_BASE}/mysql.sock /tmp/mysql.sock

print_message "环境变量已配置，已自动生效"
print_message "如果环境变量未生效，请执行：source /etc/profile"

# ⭐️ 172.16.48.171 时间戳：2025-04-11 17:05:27