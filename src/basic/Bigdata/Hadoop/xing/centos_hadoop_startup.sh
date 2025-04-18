#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 设置环境变量
HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
LOG_DIR="${HADOOP_HOME}/logs"
DATE=$(date +%Y%m%d_%H%M%S)

# 创建日志目录
mkdir -p ${LOG_DIR}

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

# 清理历史进程和临时文件
cleanup() {
    print_message "清理临时文件..."
    rm -rf /tmp/hadoop-Hive210
    sleep 2
}

# 启动服务
start_hadoop() {
    # 启动HDFS
    print_message "正在启动HDFS服务..."
    ${HADOOP_HOME}/sbin/start-dfs.sh > ${LOG_DIR}/hdfs_startup_${DATE}.log 2>&1

    # 等待NameNode启动
    sleep 5
    if ! check_process "NameNode"; then
        print_error "NameNode启动失败，请检查日志"
    fi

    # 启动YARN
    print_message "正在启动YARN服务..."
    ${HADOOP_HOME}/sbin/start-yarn.sh > ${LOG_DIR}/yarn_startup_${DATE}.log 2>&1

    # 等待ResourceManager启动
    sleep 5
    if ! check_process "ResourceManager"; then
        print_error "ResourceManager启动失败，请检查日志"
    fi
}

# 验证服务状态
check_services() {
    print_message "验证服务状态..."
    
    # 检查HDFS状态
    if ! ${HADOOP_HOME}/bin/hdfs dfsadmin -report > /dev/null 2>&1; then
        print_error "HDFS服务异常"
    fi
    
    # 检查YARN状态
    if ! ${HADOOP_HOME}/bin/yarn node -list > /dev/null 2>&1; then
        print_error "YARN服务异常"
    fi
}

# 主流程
main() {
    cleanup
    start_hadoop
    check_services
    
    print_message "Hadoop服务启动成功！"
    print_message "HDFS启动日志：${LOG_DIR}/hdfs_startup_${DATE}.log"
    print_message "YARN启动日志：${LOG_DIR}/yarn_startup_${DATE}.log"
}

main