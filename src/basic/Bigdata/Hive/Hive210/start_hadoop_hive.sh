#!/bin/bash

# 环境变量定义
HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
HIVE_HOME="/data2/Hive210/base/apache-hive-2.1.0-bin"
LOG_DIR="/data2/Hive210/logs"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# 创建日志目录
mkdir -p ${LOG_DIR}

# 启动Hadoop HDFS
start_hdfs() {
    log "正在启动 HDFS..."
    ${HADOOP_HOME}/sbin/start-dfs.sh
    if [ $? -eq 0 ]; then
        log "HDFS 启动成功"
    else
        error "HDFS 启动失败"
    fi
    sleep 5
}

# 启动Hadoop YARN
start_yarn() {
    log "正在启动 YARN..."
    ${HADOOP_HOME}/sbin/start-yarn.sh
    if [ $? -eq 0 ]; then
        log "YARN 启动成功"
    else
        error "YARN 启动失败"
    fi
    sleep 5
}

# 启动Hive MetaStore
start_metastore() {
    log "正在启动 Hive MetaStore..."
    nohup ${HIVE_HOME}/bin/hive --service metastore > ${LOG_DIR}/metastore.log 2>&1 &
    sleep 5
    if ps -ef | grep -v grep | grep "hive.metastore" > /dev/null; then
        log "Hive MetaStore 启动成功"
    else
        error "Hive MetaStore 启动失败"
    fi
}

# 启动HiveServer2
start_hiveserver2() {
    log "正在启动 HiveServer2..."
    nohup ${HIVE_HOME}/bin/hiveserver2 > ${LOG_DIR}/hiveserver2.log 2>&1 &
    sleep 5
    if ps -ef | grep -v grep | grep "hiveserver2" > /dev/null; then
        log "HiveServer2 启动成功"
    else
        error "HiveServer2 启动失败"
    fi
}

# 检查服务状态
check_status() {
    log "检查服务状态..."
    jps
    netstat -nltp | grep -E "9083|10000"
}

# 主函数
main() {
    log "开始启动 Hadoop/Hive 服务..."
    
    start_hdfs
    start_yarn
    start_metastore
    start_hiveserver2
    
    check_status
    log "所有服务启动完成"
}

# 执行主函数
main