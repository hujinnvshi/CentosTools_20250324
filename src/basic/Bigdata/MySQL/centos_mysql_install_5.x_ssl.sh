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
MYSQL_VERSION="5.7.44"
MYSQL_ROOT_PASSWORD="Secsmart#612"
MYSQL_BASE="/data/mysql_ssl_${MYSQL_VERSION}_v2"
MYSQL_Service="mysql_ssl_${MYSQL_VERSION}_v2"

# 修正内存计算逻辑（避免0G情况）
SYSTEM_MEMORY=$(free -g | awk '/^Mem:/{print $2}')
if [ "$SYSTEM_MEMORY" -eq 0 ]; then
    # 内存小于1G时默认256M
    INNODB_BUFFER_POOL_SIZE="256M"
else
    INNODB_BUFFER_POOL_SIZE=$(($SYSTEM_MEMORY * 70 / 100))G
fi

MySQL_Port=6004
MySQL_ServerID=10088

# 清理旧环境（避免残留文件冲突）
print_message "清理旧环境..."
rm -fr "${MYSQL_BASE}"
rm -f "/tmp/mysql.sock"

# 创建目录结构
print_message "创建目录结构..."
print_message "创建目录结构..."
dirs=(base data log/binlog tmp ssl)
for dir in "${dirs[@]}"; do
    mkdir -p "${MYSQL_BASE}/${dir}" || {
        print_error "创建目录 ${dir} 失败"
        exit 1
    }
done

chmod 700 "${MYSQL_BASE}/ssl" || {
    print_error "设置SSL目录权限失败"
    exit 1
}

# 安装依赖（添加错误检查）
print_message "安装依赖包..."
if command -v dnf &> /dev/null; then
    PM="dnf"
else
    PM="yum"
fi
sudo $PM install -y wget libaio numactl-libs perl net-tools jemalloc || {
    print_error "安装依赖包失败"
    exit 1
}

# 生成SSL证书（去重冗余输出，添加错误检查）
print_message "生成SSL证书..."
openssl req -newkey rsa:2048 -days 365 -nodes -x509 \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Secsmart/CN=MySQL CA" \
    -keyout "${MYSQL_BASE}/ssl/ca-key.pem" \
    -out "${MYSQL_BASE}/ssl/ca.pem" || {
    print_error "生成CA证书失败"
    exit 1
}

openssl req -newkey rsa:2048 -nodes \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=Secsmart/CN=mysql-server" \
    -keyout "${MYSQL_BASE}/ssl/server-key.pem" \
    -out "${MYSQL_BASE}/ssl/server-req.pem" || {
    print_error "生成服务器证书请求失败"
    exit 1
}

openssl x509 -req -in "${MYSQL_BASE}/ssl/server-req.pem" \
    -CA "${MYSQL_BASE}/ssl/ca.pem" \
    -CAkey "${MYSQL_BASE}/ssl/ca-key.pem" \
    -CAcreateserial \
    -out "${MYSQL_BASE}/ssl/server-cert.pem" || {
    print_error "签署服务器证书失败"
    exit 1
}

# 创建mysql用户和组（避免重复创建报错）
print_message "创建mysql用户和组..."
groupadd -f mysql || {
    print_error "创建mysql组失败"
    exit 1
}
useradd -r -g mysql -s /bin/false mysql || {
    print_error "创建mysql用户失败"
    exit 1
}

# 设置目录权限（确保所有目录归属正确）
print_message "设置目录权限..."
chown -R mysql:mysql "${MYSQL_BASE}" || {
    print_error "修改目录权限失败"
    exit 1
}
chmod 600 "${MYSQL_BASE}/ssl/"* || {
    print_error "设置SSL证书权限失败"
    exit 1
}

# 下载并安装MySQL（添加错误检查）
print_message "准备MySQL安装包..."
cd /tmp || {
    print_error "进入/tmp目录失败"
    exit 1
}
MYSQL_FILE="mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.gz"

if [ ! -f "${MYSQL_FILE}" ]; then
    print_message "下载MySQL安装包..."
    wget https://dev.mysql.com/get/Downloads/MySQL-5.7/${MYSQL_FILE} --no-check-certificate || {
        print_error "下载MySQL安装包失败"
        exit 1
    }
fi

# 解压安装包
print_message "解压MySQL安装包..."
tar xzf "${MYSQL_FILE}" || {
    print_error "解压MySQL安装包失败"
    exit 1
}
mv "mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64/"* "${MYSQL_BASE}/base/" || {
    print_error "移动MySQL文件失败"
    exit 1
}

# 创建配置文件
print_message "创建MySQL配置文件..."
cat > "${MYSQL_BASE}/my.cnf" << EOF
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
require_secure_transport = OFF

# 其他优化
lower_case_table_names = 1
skip-name-resolve
event_scheduler = ON
default-time-zone = '+8:00'

# 监控配置
performance_schema = ON
performance_schema_show_processlist = ON

[mysqld_safe]
log-error = ${MYSQL_BASE}/log/error.log
pid-file = ${MYSQL_BASE}/mysql.pid
malloc-lib = /usr/lib64/libjemalloc.so.1
EOF

# 初始化MySQL（关键步骤，必须检查成功与否）
print_message "初始化MySQL数据库..."
${MYSQL_BASE}/base/bin/mysqld --initialize \
    --explicit_defaults_for_timestamp=1 \
    --user=mysql \
    --basedir="${MYSQL_BASE}/base" \
    --datadir="${MYSQL_BASE}/data" \
    --log-error="${MYSQL_BASE}/log/error.log" \
    --ssl || {
    print_error "MySQL初始化失败，请查看日志：${MYSQL_BASE}/log/error.log"
    exit 1
}

# 创建系统服务（确保服务文件正确）
print_message "创建MySQL系统服务..."
cat > "/usr/lib/systemd/system/${MYSQL_Service}.service" << EOF
[Unit]
Description=MySQL Server ${MYSQL_VERSION}
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

# 设置服务文件权限
chmod 644 "/usr/lib/systemd/system/${MYSQL_Service}.service" || {
    print_error "设置服务文件权限失败"
    exit 1
}

# 启动MySQL服务并检查状态
print_message "启动MySQL服务..."
systemctl daemon-reload || {
    print_error "重载systemd配置失败"
    exit 1
}
systemctl enable "${MYSQL_Service}" || {
    print_error "设置MySQL开机启动失败"
    exit 1
}
systemctl start "${MYSQL_Service}" || {
    print_error "启动MySQL服务失败"
    exit 1
}

# 等待MySQL启动（通过socket文件检查，更可靠）
print_message "等待MySQL启动..."
for i in {1..20}; do
    if [ -S "${MYSQL_BASE}/mysql.sock" ]; then
        print_message "MySQL已成功启动"
        break
    fi
    if [ $i -eq 20 ]; then
        print_error "MySQL启动超时，请查看日志：${MYSQL_BASE}/log/error.log"
        exit 1
    fi
    sleep 3
done

# 提取临时密码（增强健壮性）
print_message "提取临时密码..."
temp_password=$(grep 'temporary password' "${MYSQL_BASE}/log/error.log" | tail -1 | awk -F'root@localhost: ' '{print $2}')
if [ -z "$temp_password" ]; then
    print_error "无法从日志中获取临时密码，请手动查看：${MYSQL_BASE}/log/error.log"
    exit 1
fi

# 设置root密码及安全配置（检查SQL执行结果）
print_message "配置MySQL安全设置..."
${MYSQL_BASE}/base/bin/mysql -u root --socket="${MYSQL_BASE}/mysql.sock" \
    --password="${temp_password}" --connect-expired-password -e "exit" || {
    print_error "连接MySQL失败，临时密码可能错误：${temp_password}"
    exit 1
}

# 执行安全配置SQL
${MYSQL_BASE}/base/bin/mysql -u root --socket="${MYSQL_BASE}/mysql.sock" \
    --password="${temp_password}" --connect-expired-password << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;

-- 创建测试数据库和用户
CREATE DATABASE IF NOT EXISTS admin CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'admin'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

CREATE DATABASE IF NOT EXISTS testdb CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS 'testuser'@'localhost' IDENTIFIED BY 'Secsmart#612';
GRANT ALL PRIVILEGES ON testdb.* TO 'testuser'@'localhost';
FLUSH PRIVILEGES;

-- 创建测试表和数据
USE testdb;
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('active', 'inactive') DEFAULT 'active'
);
INSERT IGNORE INTO users (username, email) VALUES ('test_user', 'test@secsmart.net');
FLUSH PRIVILEGES;
EOF

# 验证SQL执行结果
if [ $? -ne 0 ]; then
    print_error "MySQL安全配置失败，请检查密码是否符合复杂度要求"
    exit 1
fi

# 验证安装结果
print_message "验证MySQL安装..."
${MYSQL_BASE}/base/bin/mysql -u admin -p"${MYSQL_ROOT_PASSWORD}" \
    --socket="${MYSQL_BASE}/mysql.sock" -e "SELECT VERSION();" || {
    print_error "验证管理员连接失败"
    exit 1
}

${MYSQL_BASE}/base/bin/mysql -u testuser -p"Secsmart#612" testdb \
    --socket="${MYSQL_BASE}/mysql.sock" -e "SELECT * FROM users;" || {
    print_error "验证测试用户连接失败"
    exit 1
}

# 配置环境变量
print_message "配置环境变量..."
cat > "/etc/profile.d/mysql.sh" << EOF
# MySQL环境变量
export MYSQL_HOME=${MYSQL_BASE}/base
export PATH=\$MYSQL_HOME/bin:\$PATH
EOF
chmod 644 "/etc/profile.d/mysql.sh" || {
    print_error "设置环境变量文件权限失败"
    exit 1
}
chown root:root "/etc/profile.d/mysql.sh" || {
    print_error "设置环境变量文件归属失败"
    exit 1
}

# 创建socket软链接（处理已存在的情况）
print_message "创建socket软链接..."
rm -f /tmp/mysql.sock || true
ln -s "${MYSQL_BASE}/mysql.sock" /tmp/mysql.sock || {
    print_error "创建socket软链接失败"
    exit 1
}

# 生效环境变量（提示用户）
source "/etc/profile.d/mysql.sh"

# 输出安装结果
print_message "============================================="

print_message "MySQL ${MYSQL_VERSION} 安装完成！"
print_message "服务名称：${MYSQL_Service}"
print_message "安装路径：${MYSQL_BASE}"
print_message "端口：${MySQL_Port}"
print_message "Root密码：${MYSQL_ROOT_PASSWORD}"
print_message "测试用户：testuser (密码：Secsmart#612)"
print_message "测试数据库：testdb"
print_message "服务管理：systemctl [start|stop|restart|status] ${MYSQL_Service}"
print_message "环境变量已配置，新会话生效；当前会话可执行：source /etc/profile"

print_message "============================================="