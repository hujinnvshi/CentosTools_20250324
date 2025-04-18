#!/bin/bash

# 环境变量定义
HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
HIVE_HOME="/data2/Hive210/base/apache-hive-2.1.0-bin"

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

# 停止HiveServer2
stop_hiveserver2() {
    log "正在停止 HiveServer2..."
    PID=$(ps -ef | grep -v grep | grep "hiveserver2" | awk '{print $2}')
    if [ ! -z "$PID" ]; then
        kill $PID
        sleep 3
        if ps -p $PID > /dev/null 2>&1; then
            kill -9 $PID
        fi
        log "HiveServer2 已停止"
    else
        log "HiveServer2 未运行"
    fi
}

# 停止Hive MetaStore
stop_metastore() {
    log "正在停止 Hive MetaStore..."
    PID=$(ps -ef | grep -v grep | grep "hive.metastore" | awk '{print $2}')
    if [ ! -z "$PID" ]; then
        kill $PID
        sleep 3
        if ps -p $PID > /dev/null 2>&1; then
            kill -9 $PID
        fi
        log "Hive MetaStore 已停止"
    else
        log "Hive MetaStore 未运行"
    fi
}

# 停止Hadoop YARN
stop_yarn() {
    log "正在停止 YARN..."
    ${HADOOP_HOME}/sbin/stop-yarn.sh
    if [ $? -eq 0 ]; then
        log "YARN 已停止"
    else
        error "YARN 停止失败"
    fi
}

# 停止Hadoop HDFS
stop_hdfs() {
    log "正在停止 HDFS..."
    ${HADOOP_HOME}/sbin/stop-dfs.sh
    if [ $? -eq 0 ]; then
        log "HDFS 已停止"
    else
        error "HDFS 停止失败"
    fi
}

# 检查服务状态
check_status() {
    log "检查剩余进程..."
    jps
    netstat -nltp | grep -E "9083|10000" || true
}

# 主函数
main() {
    log "开始停止 Hadoop/Hive 服务..."
    # 按照依赖关系反序停止服务
    stop_hiveserver2
    stop_metastore
    stop_yarn
    stop_hdfs
    check_status
    log "所有服务已停止"
}

# 执行主函数
main