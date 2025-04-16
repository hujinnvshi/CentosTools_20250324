#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 设置环境变量
HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
LOG_DIR="${HADOOP_HOME}/logs"
DATE=$(date +%Y%m%d_%H%M%S)

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查进程是否运行
check_process() {
    ps -ef | grep "$1" | grep -v grep > /dev/null
    return $?
}

# 关闭服务
stop_hadoop() {
    # 关闭YARN
    print_message "正在关闭YARN服务..."
    ${HADOOP_HOME}/sbin/stop-yarn.sh > ${LOG_DIR}/yarn_shutdown_${DATE}.log 2>&1
    
    # 等待YARN关闭
    sleep 8
    if check_process "ResourceManager"; then
        print_error "ResourceManager YARN服务未能正常关闭"
    fi

    if check_process "NodeManager"; then
        print_error "NodeManager YARN服务未能正常关闭"
    fi

    # 关闭HDFS
    print_message "正在关闭HDFS服务..."
    ${HADOOP_HOME}/sbin/stop-dfs.sh > ${LOG_DIR}/hdfs_shutdown_${DATE}.log 2>&1
    
    # 等待HDFS关闭
    sleep 8
    if check_process "SecondaryNameNode"; then
        print_error "SecondaryNameNode HDFS服务未能正常关闭"
    fi
    if check_process "NameNode"; then
        print_error "NameNode HDFS服务未能正常关闭"
    fi
    if check_process "DataNode"; then
        print_error "DataNode HDFS服务未能正常关闭"
    fi 
}

# 清理进程
cleanup() {
    print_message "清理残留进程..."
    for PROC in "NameNode" "DataNode" "ResourceManager" "NodeManager"
    do
        if check_process "$PROC"; then
            pkill -f "$PROC"
            sleep 2
        fi
    done
}

# 主流程
main() {
    stop_hadoop
    cleanup
    
    print_message "Hadoop服务已关闭！"
    print_message "HDFS关闭日志：${LOG_DIR}/hdfs_shutdown_${DATE}.log"
    print_message "YARN关闭日志：${LOG_DIR}/yarn_shutdown_${DATE}.log"
}

main