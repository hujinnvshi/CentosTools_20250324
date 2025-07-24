#!/bin/bash

# MySQL性能测试脚本
# 使用sysbench测试MySQL 5.7性能

# 配置信息
DB_HOST="172.16.47.185"
DB_PORT="6006"
DB_USER="admin"
DB_PASSWORD="Secsmart#612"
TEST_DB="sysbench_test"
TEST_TABLES=16
TEST_THREADS=(1 4 8 16 32 64)  # 测试线程数
TEST_TIME=300                  # 每个测试持续时间(秒)
TEST_ROWS=1000000              # 每个表的测试数据行数
TEST_DIR=$(dirname "$(realpath "$0")")
REPORT_DIR="${TEST_DIR}/reports/$(date +%Y%m%d_%H%M%S)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 未找到，请先安装"
        exit 1
    fi
}

# 检查MySQL连接
check_mysql_connection() {
    log_info "检查MySQL连接..."
    if ! mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT 1;" &> /dev/null; then
        log_error "无法连接到MySQL服务器，请检查配置"
        exit 1
    fi
    log_info "MySQL连接成功"
}

# 创建测试数据库
create_test_db() {
    log_info "创建测试数据库..."
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "DROP DATABASE IF EXISTS $TEST_DB;"
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "CREATE DATABASE $TEST_DB;"
    if [ $? -ne 0 ]; then
        log_error "创建数据库失败"
        exit 1
    fi
    log_info "测试数据库 $TEST_DB 创建成功"
}

# 准备测试数据
prepare_test_data() {
    log_info "准备测试数据..."
    
    # 创建报告目录
    mkdir -p "$REPORT_DIR"
    
    # 准备OLTP测试数据
    sysbench oltp_read_write \
        --db-driver=mysql \
        --mysql-host="$DB_HOST" \
        --mysql-port="$DB_PORT" \
        --mysql-user="$DB_USER" \
        --mysql-password="$DB_PASSWORD" \
        --mysql-db="$TEST_DB" \
        --tables="$TEST_TABLES" \
        --table-size="$TEST_ROWS" \
        prepare
    
    if [ $? -ne 0 ]; then
        log_error "准备测试数据失败"
        exit 1
    fi
    
    log_info "测试数据准备完成"
}

# 执行性能测试
run_performance_test() {
    log_info "开始执行性能测试..."
    
    for threads in "${TEST_THREADS[@]}"; do
        log_info "执行 $threads 线程测试..."
        
        # 执行OLTP读写测试
        sysbench oltp_read_write \
            --db-driver=mysql \
            --mysql-host="$DB_HOST" \
            --mysql-port="$DB_PORT" \
            --mysql-user="$DB_USER" \
            --mysql-password="$DB_PASSWORD" \
            --mysql-db="$TEST_DB" \
            --tables="$TEST_TABLES" \
            --table-size="$TEST_ROWS" \
            --threads="$threads" \
            --time="$TEST_TIME" \
            --report-interval=10 \
            run > "${REPORT_DIR}/oltp_read_write_${threads}t.txt"
        
        # 执行只读测试
        sysbench oltp_read_only \
            --db-driver=mysql \
            --mysql-host="$DB_HOST" \
            --mysql-port="$DB_PORT" \
            --mysql-user="$DB_USER" \
            --mysql-password="$DB_PASSWORD" \
            --mysql-db="$TEST_DB" \
            --tables="$TEST_TABLES" \
            --table-size="$TEST_ROWS" \
            --threads="$threads" \
            --time="$TEST_TIME" \
            --report-interval=10 \
            run > "${REPORT_DIR}/oltp_read_only_${threads}t.txt"
        
        # 执行只写测试
        sysbench oltp_write_only \
            --db-driver=mysql \
            --mysql-host="$DB_HOST" \
            --mysql-port="$DB_PORT" \
            --mysql-user="$DB_USER" \
            --mysql-password="$DB_PASSWORD" \
            --mysql-db="$TEST_DB" \
            --tables="$TEST_TABLES" \
            --table-size="$TEST_ROWS" \
            --threads="$threads" \
            --time="$TEST_TIME" \
            --report-interval=10 \
            run > "${REPORT_DIR}/oltp_write_only_${threads}t.txt"
    done
    
    log_info "性能测试执行完成，报告保存在: $REPORT_DIR"
}

# 生成汇总报告
generate_summary_report() {
    log_info "生成测试汇总报告..."
    
    SUMMARY_FILE="${REPORT_DIR}/summary_report.txt"
    echo "MySQL性能测试汇总报告" > "$SUMMARY_FILE"
    echo "测试时间: $(date)" >> "$SUMMARY_FILE"
    echo "数据库版本: $(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "SELECT VERSION();" | grep -v VERSION)" >> "$SUMMARY_FILE"
    echo "----------------------------------------" >> "$SUMMARY_FILE"
    
    # 汇总各测试结果
    for test_type in "oltp_read_write" "oltp_read_only" "oltp_write_only"; do
        echo -e "\n$test_type 测试结果:" >> "$SUMMARY_FILE"
        echo "线程数\tTPS\t\tQPS\t\t平均延迟(ms)" >> "$SUMMARY_FILE"
        
        for threads in "${TEST_THREADS[@]}"; do
            report_file="${REPORT_DIR}/${test_type}_${threads}t.txt"
            if [ -f "$report_file" ]; then
                tps=$(grep "transactions:" "$report_file" | awk '{print $3}' | sed 's/,//')
                qps=$(grep "queries:" "$report_file" | awk '{print $3}' | sed 's/,//')
                latency=$(grep "avg:" "$report_file" | tail -1 | awk '{print $2}')
                echo "$threads\t$tps\t$qps\t$latency" >> "$SUMMARY_FILE"
            fi
        done
    done
    
    log_info "汇总报告生成完成: $SUMMARY_FILE"
}

# 清理测试数据
cleanup_test_data() {
    log_info "清理测试数据..."
    
    # 清理sysbench数据
    sysbench oltp_read_write \
        --db-driver=mysql \
        --mysql-host="$DB_HOST" \
        --mysql-port="$DB_PORT" \
        --mysql-user="$DB_USER" \
        --mysql-password="$DB_PASSWORD" \
        --mysql-db="$TEST_DB" \
        --tables="$TEST_TABLES" \
        cleanup
    
    # 删除测试数据库
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" -e "DROP DATABASE IF EXISTS $TEST_DB;"
    
    log_info "测试数据清理完成"
}

# 主函数
main() {
    log_info "开始MySQL性能测试..."
    
    # 检查依赖
    check_command sysbench
    check_command mysql
    
    # 检查MySQL连接
    check_mysql_connection
    
    # 创建测试数据库
    create_test_db
    
    # 准备测试数据
    prepare_test_data
    
    # 执行性能测试
    run_performance_test
    
    # 生成汇总报告
    generate_summary_report
    
    # 清理测试数据
    cleanup_test_data
    
    log_info "MySQL性能测试全部完成!"
}

# 执行主函数
main