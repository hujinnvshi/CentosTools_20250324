#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 设置路径变量
MYSQL_BASE="/data2/MySQL5739_6003/base"
MYSQL_CNF="${MYSQL_BASE}/my.cnf"
MYSQL_CNF_BAK="${MYSQL_BASE}/my.cnf.$(date +%Y%m%d_%H%M%S).bak"
MYSQL_CNF_NEW="${MYSQL_BASE}/my.cnf.optimized"

# 获取系统信息
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
CPU_CORES=$(nproc)
DISK_SPEED=$(dd if=/dev/zero of=/tmp/test_io bs=64k count=16k conv=fdatasync 2>&1 | tail -n 1 | awk '{print $(NF-1)}')

# 备份原配置
cp ${MYSQL_CNF} ${MYSQL_CNF_BAK}

# 生成优化后的配置
cat > ${MYSQL_CNF_NEW} << EOF
[mysqld]
# 基础配置
user = MySQL5739_6003
port = 6003
basedir = ${MYSQL_BASE}
datadir = /data2/MySQL5739_6003/data
socket = /data2/MySQL5739_6003/data/mysql.sock
pid-file = /data2/MySQL5739_6003/data/mysql.pid
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci

# 内存配置
innodb_buffer_pool_size = $(( TOTAL_MEM * 70 / 100 ))G
innodb_buffer_pool_instances = ${CPU_CORES}
innodb_log_buffer_size = 64M
key_buffer_size = 256M
tmp_table_size = 64M
max_heap_table_size = 64M
sort_buffer_size = 4M
join_buffer_size = 4M
read_buffer_size = 2M
read_rnd_buffer_size = 4M

# 并发配置
max_connections = $((TOTAL_MEM * 100))
innodb_thread_concurrency = $((CPU_CORES * 2))
thread_cache_size = 32
innodb_read_io_threads = ${CPU_CORES}
innodb_write_io_threads = ${CPU_CORES}

# InnoDB 配置
innodb_file_per_table = 1
innodb_flush_log_at_trx_commit = 1
innodb_log_file_size = 1G
innodb_log_files_in_group = 2
innodb_flush_method = O_DIRECT
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000

# 日志配置
slow_query_log = 1
slow_query_log_file = /data2/MySQL5739_6003/logs/slow.log
long_query_time = 2
log_error = /data2/MySQL5739_6003/logs/error.log

# 其他优化
skip_name_resolve = ON
max_allowed_packet = 16M
EOF

echo -e "${GREEN}配置文件优化完成！${NC}"
echo "原配置已备份至：${MYSQL_CNF_BAK}"
echo "新配置文件位置：${MYSQL_CNF_NEW}"