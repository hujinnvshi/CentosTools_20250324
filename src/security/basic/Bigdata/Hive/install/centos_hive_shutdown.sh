#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 设置环境变量
HIVE_HOME="/data2/Hive210/base/apache-hive-2.1.0-bin"
LOG_DIR="${HIVE_HOME}/logs"
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

# 关闭进程函数
kill_process() {
    local process_name=$1
    local pid=$(ps -ef | grep "$process_name" | grep -v grep | awk '{print $2}')
    if [ -n "$pid" ]; then
        print_message "正在关闭 $process_name 进程 (PID: $pid)..."
        kill $pid
        sleep 3
        if check_process "$process_name"; then
            print_message "进程未响应，强制终止..."
            kill -9 $pid
        fi
    else
        print_message "$process_name 进程未运行"
    fi
}

# 记录关闭操作日志
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始关闭Hive服务" >> ${LOG_DIR}/shutdown_${DATE}.log

# 关闭HiveServer2
print_message "正在关闭HiveServer2服务..."
kill_process "HiveServer2"

# 关闭MetaStore
print_message "正在关闭Hive MetaStore服务..."
kill_process "HiveMetaStore"

# 验证服务是否已关闭
if check_process "HiveServer2" || check_process "metastore"; then
    print_error "部分Hive服务未能正常关闭，请检查进程状态"
fi

# 记录关闭结果
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hive服务已关闭" >> ${LOG_DIR}/shutdown_${DATE}.log

print_message "Hive服务已成功关闭！"
print_message "关闭操作日志：${LOG_DIR}/shutdown_${DATE}.log"