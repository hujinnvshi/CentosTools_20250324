#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置信息
ROOT_PASS="Secsmart#612"
ADMIN_PASS="Secsmart#612"
MARIADB_BASE="/data/mariadb"
# 删除版本号变量，使用系统源默认版本

# 日志文件
LOG_FILE="${MARIADB_BASE}/log/mariadb_install_$(date +%Y%m%d_%H%M%S).log"

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a ${LOG_FILE}
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a ${LOG_FILE}
    exit 1
}

# 检查环境
check_environment() {
    print_message "检查系统环境..."
    
    # 检查系统版本（麒麟系统可能有多种版本号格式）
    if ! grep -qi "kylin" /etc/*-release; then
        print_error "此脚本仅支持麒麟系统"
    fi
    
    # 检查CPU架构（增加错误提示）
    if ! uname -m | grep -qi "aarch64"; then
        print_error "此脚本仅支持飞腾处理器（aarch64架构）"
    fi
    
    # 获取系统资源信息
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    CPU_CORES=$(nproc)
    
    # 检查内存大小（增加最小内存要求）
    if [ -z "${TOTAL_MEM}" ] || [ "${TOTAL_MEM}" -lt 4 ]; then
        print_error "系统内存不足，建议至少4GB内存"
    fi
}

# 创建目录结构
create_directories() {
    print_message "创建目录结构..."
    
    # 检查目录是否已存在
    if [ -d "${MARIADB_BASE}" ]; then
        print_message "目录已存在，备份旧目录..."
        mv ${MARIADB_BASE} ${MARIADB_BASE}_backup_$(date +%Y%m%d_%H%M%S)
    fi
    
    # 创建所需的目录结构
    mkdir -p ${MARIADB_BASE}/{base,data,tmp,conf} || print_error "创建目录失败"
    mkdir -p ${MARIADB_BASE}/log/{binlog,slow} || print_error "创建日志目录失败"
    
    # 创建二进制日志索引文件
    touch ${MARIADB_BASE}/log/binlog/mariadb-bin.index
    
    # 检查mysql用户是否存在
    id mysql >/dev/null 2>&1 || useradd mysql
    
    # 设置目录权限
    chown -R mysql:mysql ${MARIADB_BASE}
    chmod -R 755 ${MARIADB_BASE}
    chmod 700 ${MARIADB_BASE}/log/binlog
}

# 卸载已有的 MariaDB
uninstall_old_mariadb() {
    print_message "检查并卸载已安装的 MariaDB..."
    
    # 停止服务
    systemctl stop mariadb 2>/dev/null
    
    # 卸载所有相关包
    rpm -qa | grep -i "mariadb" | xargs rpm -e --nodeps 2>/dev/null
    
    # 清理残留文件
    rm -rf /var/lib/mysql
    rm -rf /var/log/mariadb
    rm -rf /etc/my.cnf
    rm -rf /etc/my.cnf.d
    rm -f /etc/yum.repos.d/MariaDB.repo    
    print_message "旧版本清理完成"
}

# 安装MariaDB
install_mariadb() {
    print_message "安装MariaDB..."
    # 先卸载旧版本
    uninstall_old_mariadb
    # 清理并更新源
    yum clean all
    yum makecache
    # 安装 MariaDB（不指定版本）
    yum install -y mariadb-server mariadb
    if [ $? -ne 0 ]; then
        print_error "MariaDB 安装失败"
    fi
    print_message "MariaDB 安装成功"
}

# 配置MariaDB
configure_mariadb() {
    print_message "配置MariaDB..."
    
    # 备份原有配置
    if [ -f "/etc/my.cnf" ]; then
        mv /etc/my.cnf /etc/my.cnf.backup_$(date +%Y%m%d_%H%M%S)
    fi
    
    # 计算配置参数 - 确保最小值为5MB
    BUFFER_POOL_SIZE="$((TOTAL_MEM * 1024))"  # Convert GB to MB
    if [ ${BUFFER_POOL_SIZE} -lt 5 ]; then
        BUFFER_POOL_SIZE=5
    fi
    
    # 创建配置文件
    cat > ${MARIADB_BASE}/conf/my.cnf << EOF
[mysqld]
# 基础配置
port = 3306
datadir = ${MARIADB_BASE}/data
socket = /${MARIADB_BASE}/mysql.sock
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
explicit_defaults_for_timestamp = 1

# 目录配置
tmpdir = ${MARIADB_BASE}/tmp
log_error = ${MARIADB_BASE}/log/error.log
slow_query_log_file = ${MARIADB_BASE}/log/slow.log
log_bin = ${MARIADB_BASE}/log/binlog/mariadb-bin

# 性能配置
innodb_buffer_pool_size = ${BUFFER_POOL_SIZE}M
innodb_log_file_size = 1G
innodb_log_buffer_size = 16M
query_cache_size = 0
max_connections = 10000
thread_cache_size = 10000
tmp_table_size = 16M
sort_buffer_size = 2M

# 日志配置
slow_query_log = 1
long_query_time = 2
log_queries_not_using_indexes = 1
expire_logs_days = 7
binlog_cache_size = 1M
sync_binlog = 1

# 安全配置
local_infile = 0
max_allowed_packet = 16M
ssl = OFF
skip_name_resolve = ON

# 高级特性
thread_handling = pool-of-threads
lower_case_table_names = 1
event_scheduler = ON
performance_schema = ON

# 时区设置
default_time_zone = '+8:00'

[client]
default-character-set = utf8mb4

EOF
    # 链接配置文件
    ln -sf ${MARIADB_BASE}/conf/my.cnf /etc/my.cnf
    ln -sf ${MARIADB_BASE}/mysql.sock /var/lib/mysql/mysql.sock
}

# 配置MariaDB启动和关闭脚本
configure_scripts() {
    print_message "配置启动和关闭脚本..."
    
    # 创建启动脚本
    cat > ${MARIADB_BASE}/base/start_mysql.sh << EOF
#!/bin/bash
echo "正在启动 MariaDB 服务..."
/usr/bin/mysqld_safe \
--defaults-file=${MARIADB_BASE}/conf/my.cnf \
--datadir=${MARIADB_BASE}/data &

# 等待服务启动
timeout=30
while ! mysqladmin ping --socket=/${MARIADB_BASE}/mysql.sock >/dev/null 2>&1; do
    timeout=\$((timeout-1))
    if [ \$timeout -le 0 ]; then
        echo "MariaDB服务启动超时"
        exit 1
    fi
    sleep 1
done
echo "MariaDB服务已启动"
EOF

    # 创建关闭脚本
    cat > ${MARIADB_BASE}/base/stop_mysql.sh << EOF
#!/bin/bash
echo "正在关闭 MariaDB 服务..."
if [ -f ${MARIADB_BASE}/data/\`hostname\`.pid ]; then
    # 使用 mysqladmin 安全关闭数据库
    mysqladmin -u root -p${ROOT_PASS} shutdown

    # 等待服务停止
    timeout=30
    while [ -f ${MARIADB_BASE}/data/\`hostname\`.pid ]; do
        timeout=\$((timeout-1))
        if [ \$timeout -le 0 ]; then
            echo "MariaDB服务停止超时，尝试强制关闭..."
            kill \`cat ${MARIADB_BASE}/data/\`hostname\`.pid\`
            sleep 3
            break
        fi
        sleep 1
    done
    
    if [ ! -f ${MARIADB_BASE}/data/\`hostname\`.pid ]; then
        echo "MariaDB服务已安全停止"
    else
        echo "MariaDB服务可能未完全停止，请检查进程"
    fi
else
    echo "MariaDB服务未运行"
fi
EOF

    # 创建重启脚本
    cat > ${MARIADB_BASE}/base/restart_mysql.sh << EOF
#!/bin/bash
${MARIADB_BASE}/base/stop_mysql.sh
sleep 2
${MARIADB_BASE}/base/start_mysql.sh
EOF

    # 设置脚本权限
    chmod +x ${MARIADB_BASE}/base/start_mysql.sh
    chmod +x ${MARIADB_BASE}/base/stop_mysql.sh
    chmod +x ${MARIADB_BASE}/base/restart_mysql.sh
    chown mysql:mysql ${MARIADB_BASE}/base/*.sh
}

# 修改初始化数据库函数
initialize_db() {
    print_message "初始化数据库..."
    
    # 先初始化数据库
    mysql_install_db --user=mysql \
                     --datadir=${MARIADB_BASE}/data \
                     --defaults-file=${MARIADB_BASE}/conf/my.cnf
    
    if [ $? -ne 0 ]; then
        print_error "数据库初始化失败"
    fi
    # 启动 MariaDB
    ${MARIADB_BASE}/base/start_mysql.sh
    # 使用 mysqladmin 直接设置 root 密码
    mysqladmin -u root password "${ROOT_PASS}"
    # 使用 mysql 命令执行安全配置
    mysql -uroot -p"${ROOT_PASS}" << EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
}

# 修改环境变量配置
configure_environment() {
    print_message "配置环境变量..."
    if [ ! -d "/etc/profile.d" ]; then
        print_error "环境变量目录不存在"
    fi
    cat > /etc/profile.d/mariadb.sh << EOF
export PATH=\$PATH:${MARIADB_BASE}/base
alias start_db='${MARIADB_BASE}/base/start_mysql.sh'
alias stop_db='${MARIADB_BASE}/base/stop_mysql.sh'
alias restart_db='${MARIADB_BASE}/base/restart_mysql.sh'
EOF
    source /etc/profile.d/mariadb.sh
}

# 修改验证安装函数
verify_installation() {
    print_message "验证安装..."
    
    # 检查服务状态
    if [ -f ${MARIADB_BASE}/data/`hostname`.pid ]; then
        print_message "MariaDB 服务正在运行"
    else
        print_error "MariaDB 服务未运行"
    fi
    
    # 添加版本信息输出
    mysql -uadmin -p${ADMIN_PASS} -e "SELECT VERSION() as '当前安装版本';"
    mysql -uadmin -p${ADMIN_PASS} -e "SELECT * FROM testdb.testtable;"
}

# 修改主函数，添加脚本配置
main() {
    print_message "开始安装MariaDB..."
    check_environment
    create_directories
    install_mariadb
    configure_mariadb
    configure_scripts    # 新增此行
    initialize_db
    create_test_env
    configure_environment
    verify_installation
    cleanup

    print_message "MariaDB安装完成！"
    print_message "配置文件：${MARIADB_BASE}/conf/my.cnf"
    print_message "数据目录：${MARIADB_BASE}/data"
    print_message "日志目录：${MARIADB_BASE}/log"
    print_message "Root密码：${ROOT_PASS}"
    print_message "Admin密码：${ADMIN_PASS}"
    
    cat << EOF

数据库操作命令：
- 启动：${MARIADB_BASE}/base/start_mysql.sh
- 停止：${MARIADB_BASE}/base/stop_mysql.sh
- 重启：${MARIADB_BASE}/base/restart_mysql.sh
- 连接：mysql -uadmin -p${ADMIN_PASS}
- 查看日志：tail -f ${MARIADB_BASE}/log/error.log
EOF
}

# 创建测试环境
create_test_env() {
    print_message "创建测试环境..."
    # 测试数据库连接
    if ! mysql -uroot -p${ROOT_PASS} -e "SELECT 1" >/dev/null 2>&1; then
        print_error "无法连接到数据库"
    fi

    mysql -uroot -p${ROOT_PASS} << EOF
-- 创建管理员用户
CREATE USER 'admin'@'%' IDENTIFIED BY '${ADMIN_PASS}';
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;

-- 创建测试数据库和表
CREATE DATABASE testdb CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE testdb;
CREATE TABLE testtable (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50),
    description TEXT,
    create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    update_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 插入测试数据
INSERT INTO testtable (name, description) VALUES ('test_data', '测试数据');

-- 刷新权限
FLUSH PRIVILEGES;
EOF
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    print_error "请使用root权限运行此脚本"
fi

# 执行主函数
main