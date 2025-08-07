#!/bin/bash
set -euo pipefail

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
    exit 1
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                MYSQL_VERSION="$2"
                shift 2
                ;;
            --instance)
                INSTANCE_ID="$2"
                shift 2
                ;;
            --port)
                MYSQL_PORT="$2"
                shift 2
                ;;
            --password)
                MYSQL_PASSWORD="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "未知参数: $1"
                ;;
        esac
    done
}

# 显示帮助信息
show_help() {
    cat << EOF
MySQL 多实例安装脚本
用法: $0 [选项]

选项:
  --version <版本>    指定 MySQL 版本 (默认: 8.0.25)
  --instance <标识>   实例标识符 (默认: v1)
  --port <端口>       数据库端口 (默认: 3312)
  --password <密码>   root 密码 (默认: Secsmart#612)
  --help              显示帮助信息

示例:
  $0 --version 8.0.25 --instance v1 --port 3312
  $0 --version 8.0.34 --instance v2 --port 3313
  $0 --version 8.0.44 --instance v3 --port 3400
EOF
}

# 设置默认变量
set_defaults() {
    MYSQL_VERSION="${MYSQL_VERSION:-8.0.25}"
    INSTANCE_ID="${INSTANCE_ID:-v1}"
    MYSQL_PORT="${MYSQL_PORT:-3312}"
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-Secsmart#612}"
    
    # 生成唯一标识符
    INSTANCE_NAME="mysql_${MYSQL_VERSION//./_}_${INSTANCE_ID}"
    
    # 安装路径
    MYSQL_HOME="/data/${INSTANCE_NAME}"    
    # 服务名称
    SERVICE_NAME="${INSTANCE_NAME}"
    
    # 用户和组
    MYSQL_USER="${INSTANCE_NAME}"
    MYSQL_GROUP="${INSTANCE_NAME}"
    
    # 安装包信息
    MYSQL_PACKAGE="mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.xz"
    MYSQL_DOWNLOAD_URL="https://cdn.mysql.com/archives/mysql-8.0/${MYSQL_PACKAGE}"
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用root用户执行此脚本"
    fi
}

# 添加清理函数
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        print_message "安装失败，开始清理..."
        systemctl stop ${SERVICE_NAME} 2>/dev/null || true
        rm -rf ${MYSQL_HOME} 2>/dev/null || true
        rm -f /usr/lib/systemd/system/${SERVICE_NAME}.service 2>/dev/null || true
        rm -f /etc/profile.d/${SERVICE_NAME}.sh 2>/dev/null || true
    fi
    exit $exit_code
}
trap cleanup ERR

# 检查并安装依赖包
install_dependencies() {
    print_message "检查并安装依赖包..."
    local DEPS="libaio numactl net-tools wget"
    for pkg in $DEPS; do
        if ! rpm -q $pkg &>/dev/null; then
            print_message "正在安装 ${pkg}..."
            yum install -y $pkg || print_error "安装 ${pkg} 失败"
        else
            print_message "${pkg} 已安装"
        fi
    done
}

# 检查端口占用
check_port_availability() {
    if netstat -tuln | grep ":${MYSQL_PORT}" >/dev/null; then
        print_error "端口 ${MYSQL_PORT} 已被占用"
    fi
    print_message "端口 ${MYSQL_PORT} 可用"
}

# 备份现有安装
backup_existing_installation() {
    if [ -d "${MYSQL_HOME}" ]; then
        BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
        print_message "备份已存在的MySQL目录..."
        backup_file="${MYSQL_HOME}_backup_${BACKUP_TIME}.tar.gz"
        tar czf "${backup_file}" -C $(dirname ${MYSQL_HOME}) $(basename ${MYSQL_HOME}) || 
            print_error "备份失败"
        print_message "已备份至: ${backup_file}"
    fi
}

# 创建目录结构
create_directory_structure() {
    print_message "创建目录结构..."
    mkdir -p ${MYSQL_HOME}/{base,data,log/binlog,tmp}
    touch ${MYSQL_HOME}/log/error.log
    touch ${MYSQL_HOME}/log/slow.log
    touch ${MYSQL_HOME}/log/general.log
}

# 创建用户和组
create_user_and_group() {
    print_message "创建MySQL用户和组..."
    if ! getent group ${MYSQL_GROUP} >/dev/null; then
        groupadd ${MYSQL_GROUP} || print_error "创建组 ${MYSQL_GROUP} 失败"
    fi
    
    if ! id -u ${MYSQL_USER} >/dev/null; then
        useradd -r -m -s /bin/bash -g ${MYSQL_GROUP} ${MYSQL_USER} -d ${MYSQL_HOME} || print_error "创建用户 ${MYSQL_USER} 失败"
    fi
}

# 下载安装包
download_package() {
    print_message "检查安装包..."
    if [ ! -f "/tmp/${MYSQL_PACKAGE}" ]; then
        print_message "下载 MySQL ${MYSQL_VERSION} 安装包..."
        wget -t 3 -T 30 -P /tmp ${MYSQL_DOWNLOAD_URL} || {
            print_warning "主镜像下载失败，尝试备份镜像..."
            wget -t 2 -T 20 "https://downloads.mysql.com/archives/get/p/23/file/${MYSQL_PACKAGE}" -O "/tmp/${MYSQL_PACKAGE}" || 
            print_error "下载失败，请检查网络连接或手动下载安装包到 /tmp 目录"
        }
    else
        print_message "安装包已存在，验证文件完整性..."
        if ! tar -tJf "/tmp/${MYSQL_PACKAGE}" >/dev/null 2>&1; then
            print_warning "安装包可能损坏，重新下载..."
            rm -f "/tmp/${MYSQL_PACKAGE}"
            download_package
        fi
    fi
}

# 解压安装包
extract_package() {
    print_message "解压 MySQL..."
    if [ ! -d "/tmp/mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64" ]; then
        tar xJf /tmp/${MYSQL_PACKAGE} -C /tmp || print_error "解压失败"
    fi
    cp -avf /tmp/mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64/* ${MYSQL_HOME}/base/
}

# 配置my.cnf
configure_mycnf() {
    print_message "配置my.cnf..."
    
    # 计算InnoDB缓冲池大小（系统内存的20%）
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [ -z "$TOTAL_MEM" ] || [ "$TOTAL_MEM" -eq 0 ]; then
        TOTAL_MEM=1
        print_warning "无法获取准确的内存信息，使用默认值 1GB"
    fi
    BUFFER_POOL_SIZE=$(($TOTAL_MEM * 20 / 100))
    [ $BUFFER_POOL_SIZE -eq 0 ] && BUFFER_POOL_SIZE=1
    
    cat > ${MYSQL_HOME}/my.cnf << EOF
[mysqld]
user = ${MYSQL_USER}
port = ${MYSQL_PORT}
basedir = ${MYSQL_HOME}/base
datadir = ${MYSQL_HOME}/data
socket = ${MYSQL_HOME}/tmp/mysql.sock
pid-file = ${MYSQL_HOME}/tmp/mysql.pid
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
explicit_defaults_for_timestamp = 1
default-time-zone = '+8:00'
server-id = ${MYSQL_PORT}
gtid_mode = ON
enforce_gtid_consistency = ON
# skip-grant-tables

# TLS 配置
tls_version = TLSv1.2,TLSv1.3
admin_tls_version = TLSv1.2,TLSv1.3

# x plugin 配置
mysqlx=0
mysqlx_socket=${MYSQL_HOME}/tmp/mysqlx.sock

# 性能配置
innodb_buffer_pool_size = ${BUFFER_POOL_SIZE}G
innodb_log_file_size = 1G
innodb_log_buffer_size = 16M
max_connections = 1000
thread_cache_size = 100
tmp_table_size = 16M
sort_buffer_size = 2M

# 日志配置
log-error = ${MYSQL_HOME}/log/error.log
general_log = 1
general_log_file = ${MYSQL_HOME}/log/general.log
slow_query_log = 3
slow_query_log_file = ${MYSQL_HOME}/log/slow.log
long_query_time = 5
log_queries_not_using_indexes = 1

log-bin = ${MYSQL_HOME}/log/binlog/mysql-bin
binlog_expire_logs_seconds = 604800
binlog_cache_size = 4M
sync_binlog = 1

# 安全配置
local_infile = 0
max_allowed_packet = 16M
require_secure_transport = OFF
bind-address = 0.0.0.0

# 其他优化
lower_case_table_names = 1
skip-name-resolve
event_scheduler = ON

# 监控配置
performance_schema = ON

[client]
port = ${MYSQL_PORT}
socket = ${MYSQL_HOME}/tmp/mysql.sock
default-character-set = utf8mb4

[mysql]
default-character-set = utf8mb4
EOF
}

# 设置权限
set_permissions() {
    print_message "设置权限..."
    chown -R ${MYSQL_USER}:${MYSQL_GROUP} ${MYSQL_HOME}
    chmod 755 ${MYSQL_HOME}
    chmod 750 ${MYSQL_HOME}/data
    chmod 770 ${MYSQL_HOME}/log
    chmod 770 ${MYSQL_HOME}/tmp
    chmod 750 ${MYSQL_HOME}/base
    chmod 640 ${MYSQL_HOME}/my.cnf
}

# 初始化数据库
initialize_database() {
    print_message "初始化数据库..."
    rm -rf ${MYSQL_HOME}/data/*
    echo "" > ${MYSQL_HOME}/log/error.log
    mkdir -p ${MYSQL_HOME}/data
    
    # 使用sudo执行初始化
    sudo -u ${MYSQL_USER} ${MYSQL_HOME}/base/bin/mysqld \
        --defaults-file=${MYSQL_HOME}/my.cnf \
        --initialize \
        --user=${MYSQL_USER} \
        --datadir=${MYSQL_HOME}/data || print_error "数据库初始化失败"
    
    # 获取临时密码
    TEMP_PASSWORD=$(grep 'temporary password' ${MYSQL_HOME}/log/error.log | awk '{print $NF}')
    if [ -z "${TEMP_PASSWORD}" ]; then
        print_error "无法获取临时密码，初始化可能失败"
    fi
    print_message "临时密码: ${TEMP_PASSWORD}"
}

# 创建系统服务
create_systemd_service() {
    print_message "创建系统服务: ${SERVICE_NAME}..."    
    cat > /usr/lib/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=MySQL Server (${INSTANCE_NAME})
After=network.target
After=syslog.target

[Service]
Type=notify
User=${MYSQL_USER}
Group=${MYSQL_GROUP}
Environment="LD_LIBRARY_PATH=${MYSQL_HOME}/base/lib"
ExecStart=${MYSQL_HOME}/base/bin/mysqld_safe --defaults-file=${MYSQL_HOME}/my.cnf
ExecStop=${MYSQL_HOME}/base/bin/mysqladmin --defaults-file=${MYSQL_HOME}/my.cnf -uroot -p${MYSQL_PASSWORD} shutdown
PIDFile=${MYSQL_HOME}/tmp/mysql.pid

# 更安全的终止模式
KillMode=process
TimeoutStartSec=300
TimeoutStopSec=300
Restart=no
RestartSec=50s
LimitNOFILE=10000
PrivateTmp=false
RemainAfterExit=no
# 确保工作目录存在
WorkingDirectory=${MYSQL_HOME}
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
}

# 配置环境变量
configure_environment() {
    print_message "配置环境变量..."
    cat > /etc/profile.d/${SERVICE_NAME}.sh << EOF
# MySQL Environment Variables (${INSTANCE_NAME})
export MYSQL_HOME=${MYSQL_HOME}
export PATH=\$PATH:\${MYSQL_HOME}/base/bin
EOF
    source /etc/profile.d/${SERVICE_NAME}.sh || print_warning "加载环境变量失败"
}

# 启动服务
start_service() {
    print_message "启动MySQL服务: ${SERVICE_NAME}..."
    systemctl start ${SERVICE_NAME}
    
    # 检查服务状态
    local MAX_RETRIES=5
    local RETRY_COUNT=0
    local SERVICE_ACTIVE=false
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # 使用 systemctl 检查服务状态
        if systemctl is-active --quiet ${SERVICE_NAME}; then
            print_message "MySQL服务已成功启动"
            SERVICE_ACTIVE=true
            break
        fi        
        print_message "等待服务启动... (${RETRY_COUNT}/${MAX_RETRIES})"
        sleep 5
        RETRY_COUNT=$((RETRY_COUNT + 1))
    done
    
    if ! $SERVICE_ACTIVE; then
        print_error "MySQL服务启动超时，请检查日志：${MYSQL_HOME}/log/error.log"
    fi
    
    # 启用服务自启
    systemctl disable ${SERVICE_NAME}
}

# 设置root密码
set_root_password() {
    print_message "设置root密码..."
    ${MYSQL_HOME}/base/bin/mysql -P ${MYSQL_PORT} -S ${MYSQL_HOME}/tmp/mysql.sock \
        --connect-expired-password -uroot -p"${TEMP_PASSWORD}" << EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_PASSWORD}';
FLUSH PRIVILEGES;
EOF
}

# 执行安全配置
secure_installation() {
    print_message "执行安全配置..."
    ${MYSQL_HOME}/base/bin/mysql_secure_installation -P ${MYSQL_PORT} -S ${MYSQL_HOME}/tmp/mysql.sock \
        -uroot -p"${MYSQL_PASSWORD}" << EOF
n
y
2
n
n
n
n
y
EOF
}

# 创建测试数据
create_test_data() {
    print_message "创建测试数据..."
    cat > /tmp/init.sql << EOF
CREATE DATABASE test_db;
CREATE USER 'test_user'@'localhost' IDENTIFIED BY 'Test@123';
GRANT ALL PRIVILEGES ON test_db.* TO 'test_user'@'localhost';
FLUSH PRIVILEGES;

CREATE DATABASE admin;
CREATE USER 'admin'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
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
INSERT INTO employees (name, age, department, salary, hire_date) VALUES 
('张三', 30, '技术部', 15000.00, '2023-01-01'),
('李四', 28, '市场部', 12000.00, '2023-02-15'),
('王五', 35, '财务部', 18000.00, '2022-11-01');
EOF

    ${MYSQL_HOME}/base/bin/mysql -P ${MYSQL_PORT} -S ${MYSQL_HOME}/tmp/mysql.sock \
        -uroot -p"${MYSQL_PASSWORD}" < /tmp/init.sql || print_error "创建测试数据失败"
}


# 显示安装摘要
show_summary() {
    local LOCAL_IP=$(hostname -I | awk '{print $1}')
    [ -z "${LOCAL_IP}" ] && LOCAL_IP="127.0.0.1"
    
    cat << EOF

${GREEN}==================== MySQL 安装完成 ====================${NC}

实例名称:     ${INSTANCE_NAME}
MySQL版本:    ${MYSQL_VERSION}
安装路径:     ${MYSQL_HOME}
数据目录:     ${MYSQL_HOME}/data
日志目录:     ${MYSQL_HOME}/log
配置文件:     ${MYSQL_HOME}/my.cnf
服务用户:     ${MYSQL_USER}:${MYSQL_GROUP}
客户端端口:   ${MYSQL_PORT}
root密码:     ${MYSQL_PASSWORD}

${YELLOW}管理命令:${NC}
启动服务:     systemctl start ${SERVICE_NAME}
停止服务:     systemctl stop ${SERVICE_NAME}
查看状态:     systemctl status ${SERVICE_NAME}
查看日志:     journalctl -u ${SERVICE_NAME} -f
连接命令:     mysql -P ${MYSQL_PORT} -S ${MYSQL_HOME}/tmp/mysql.sock -uroot -p${MYSQL_PASSWORD}
测试用户:     mysql -h ${LOCAL_IP} -P ${MYSQL_PORT} -utest_user -pTest@123 test_db
管理员用户:   mysql -h ${LOCAL_IP} -P ${MYSQL_PORT} -uadmin -p${MYSQL_PASSWORD}

${GREEN}全局管理脚本:${NC}
启动所有实例: start_all_mysql.sh
停止所有实例: stop_all_mysql.sh
重启所有实例: restart_all_mysql.sh
手动启动：/data/${INSTANCE_NAME}/base/bin/mysqld --defaults-file=/data/${INSTANCE_NAME}/my.cnf
${GREEN}服务已配置为禁止开机自启${NC}
${YELLOW}=================================================${NC}
EOF
}

# 主函数
main() {
    parse_arguments "$@"
    set_defaults
    check_root
    install_dependencies
    check_port_availability
    backup_existing_installation
    create_directory_structure
    create_user_and_group
    download_package
    extract_package
    configure_mycnf
    set_permissions
    initialize_database
    create_systemd_service
    configure_environment
    # start_service
    set_root_password
    secure_installation
    create_test_data
    show_summary
    print_message "MySQL ${MYSQL_VERSION} (实例: ${INSTANCE_ID}) 安装完成！"
}

# 执行主函数
main "$@"