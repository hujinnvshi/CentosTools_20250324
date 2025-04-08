#!/bin/bash

# 环境变量定义
HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
HIVE_HOME="/data2/Hive210/base/apache-hive-2.1.0-bin"
TEST_DIR="/data2/Hive210/test"
LOG_DIR="/data2/Hive210/test/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${LOG_DIR}/test_report_${TIMESTAMP}.txt"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a ${REPORT_FILE}
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a ${REPORT_FILE}
    exit 1
}

# 初始化测试环境
init_test_env() {
    log "初始化测试环境..."
    mkdir -p ${TEST_DIR} ${LOG_DIR}
    echo "测试报告 - $(date '+%Y-%m-%d %H:%M:%S')" > ${REPORT_FILE}
}

# 测试HDFS基本功能
test_hdfs() {
    log "开始HDFS功能测试..."
    
    # 创建测试目录
    ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /test/input
    
    # 生成测试数据
    dd if=/dev/urandom of=${TEST_DIR}/test_file_100mb bs=1M count=100
    
    # 上传测试
    local start_time=$(date +%s)
    ${HADOOP_HOME}/bin/hdfs dfs -put ${TEST_DIR}/test_file_100mb /test/input/
    local end_time=$(date +%s)
    local upload_time=$((end_time - start_time))
    log "HDFS上传100MB文件耗时: ${upload_time}秒"
    
    # 下载测试
    start_time=$(date +%s)
    ${HADOOP_HOME}/bin/hdfs dfs -get /test/input/test_file_100mb ${TEST_DIR}/test_file_download
    end_time=$(date +%s)
    local download_time=$((end_time - start_time))
    log "HDFS下载100MB文件耗时: ${download_time}秒"
    
    # 验证数据一致性
    if md5sum ${TEST_DIR}/test_file_100mb ${TEST_DIR}/test_file_download | awk '{print $1}' | uniq -c | grep -q "2"; then
        log "HDFS数据一致性测试通过"
    else
        error "HDFS数据一致性测试失败"
    fi
}

# 测试Hive SQL功能
test_hive() {
    log "开始Hive功能测试..."
    
    # 创建测试数据库
    ${HIVE_HOME}/bin/hive -e "CREATE DATABASE IF NOT EXISTS test_db;"
    
    # 创建测试表
    ${HIVE_HOME}/bin/hive -e "
    USE test_db;
    CREATE TABLE IF NOT EXISTS test_table (
        id INT,
        name STRING,
        value DOUBLE
    ) ROW FORMAT DELIMITED FIELDS TERMINATED BY ',';"
    
    # 生成测试数据
    local test_data=${TEST_DIR}/test_data.csv
    for i in {1..10000}; do
        echo "$i,test_name_$i,$RANDOM.${RANDOM}" >> ${test_data}
    done
    
    # 导入数据
    local start_time=$(date +%s)
    ${HIVE_HOME}/bin/hive -e "
    USE test_db;
    LOAD DATA LOCAL INPATH '${test_data}' INTO TABLE test_table;"
    local end_time=$(date +%s)
    local load_time=$((end_time - start_time))
    log "Hive导入1万条数据耗时: ${load_time}秒"
    
    # 查询测试
    start_time=$(date +%s)
    ${HIVE_HOME}/bin/hive -e "
    USE test_db;
    SELECT COUNT(*), AVG(value), MAX(value), MIN(value) FROM test_table;" > ${TEST_DIR}/query_result.txt
    end_time=$(date +%s)
    local query_time=$((end_time - start_time))
    log "Hive聚合查询耗时: ${query_time}秒"
}

# 清理测试数据
cleanup() {
    log "清理测试数据..."
    
    # 清理HDFS测试数据
    ${HADOOP_HOME}/bin/hdfs dfs -rm -r -f /test
    
    # 清理Hive测试数据
    ${HIVE_HOME}/bin/hive -e "
    DROP DATABASE IF EXISTS test_db CASCADE;
    "
    
    # 清理本地测试文件
    rm -f ${TEST_DIR}/test_file_*
    rm -f ${TEST_DIR}/test_data.csv
    rm -f ${TEST_DIR}/query_result.txt
    
    log "测试数据清理完成"
}

# 生成测试报告
generate_report() {
    log "测试报告已生成: ${REPORT_FILE}"
    log "系统信息:"
    log "CPU: $(cat /proc/cpuinfo | grep 'model name' | head -1)"
    log "内存: $(free -h | grep Mem | awk '{print $2}')"
    log "磁盘: $(df -h ${TEST_DIR} | tail -1 | awk '{print $2}')"
}

# 主函数
main() {
    init_test_env
    
    # 检查服务状态
    jps | grep -E "NameNode|DataNode|ResourceManager|NodeManager|RunJar" > /dev/null || error "Hadoop服务未启动"
    
    test_hdfs
    test_hive
    generate_report
    cleanup
    
    log "测试完成"
}

# 执行主函数
main