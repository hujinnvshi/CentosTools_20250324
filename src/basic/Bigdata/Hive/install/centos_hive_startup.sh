#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 设置环境变量
HIVE_HOME="/data2/Hive210/base/apache-hive-2.1.0-bin"
LOG_DIR="${HIVE_HOME}/logs"
DATE=$(date +%Y%m%d_%H%M%S)

# Hadoop环境变量
export HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
export HADOOP_CLASSPATH=${HADOOP_HOME}/share/hadoop/common/lib/*:${HADOOP_HOME}/share/hadoop/common/*:${HADOOP_HOME}/share/hadoop/hdfs/*:${HADOOP_HOME}/share/hadoop/hdfs/lib/*

# Tez环境变量
export TEZ_HOME="/data2/Hive210/base/apache-tez-0.9.1-bin"
export TEZ_CONF_DIR=${TEZ_HOME}/conf
export TEZ_JARS=${TEZ_HOME}
export HADOOP_CLASSPATH=${HADOOP_CLASSPATH}:${TEZ_JARS}/*:${TEZ_JARS}/lib/*

# 设置最终CLASSPATH
export CLASSPATH=$CLASSPATH:${HADOOP_CLASSPATH}

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

# 检查端口是否被占用
check_port() {
    local port=$1
    if netstat -tln | grep ":${port}" > /dev/null; then
        # 查找占用端口的进程
        local pid=$(lsof -i:${port} -t)
        if [ -n "$pid" ]; then
            print_message "端口 ${port} 被进程 PID:${pid} 占用"
            print_message "正在尝试关闭占用进程..."
            kill -9 $pid
            sleep 2
        fi
        return 0
    fi
    return 1
}

# 清理历史进程和临时文件
cleanup() {
    print_message "清理历史进程和临时文件..."
    
    # 清理历史进程
    pkill -f HiveServer2
    pkill -f HiveMetaStore
    
    # 清理临时文件
    rm -rf /tmp/hive
    rm -rf /tmp/hadoop-Hive210
    
    sleep 2
}

# 在启动服务前执行清理
cleanup

# 启动MetaStore服务
print_message "正在启动Hive MetaStore服务..."
nohup ${HIVE_HOME}/bin/hive --service metastore > ${LOG_DIR}/metastore_${DATE}.log 2>&1 &

# 等待MetaStore启动
sleep 5
if ! check_process "HiveMetaStore"; then
    print_error "MetaStore服务启动失败，请检查日志：${LOG_DIR}/metastore_${DATE}.log"
fi

# 启动HiveServer2服务
print_message "正在启动HiveServer2服务..."
nohup ${HIVE_HOME}/bin/hiveserver2 > ${LOG_DIR}/hiveserver2_${DATE}.log 2>&1 &

# 等待HiveServer2启动
sleep 10
if ! check_process "HiveServer2"; then
    print_error "HiveServer2服务启动失败，请检查日志：${LOG_DIR}/hiveserver2_${DATE}.log"
fi

# 创建日志软链接
ln -sf ${LOG_DIR}/metastore_${DATE}.log ${LOG_DIR}/metastore.log
ln -sf ${LOG_DIR}/hiveserver2_${DATE}.log ${LOG_DIR}/hiveserver2.log

print_message "Hive服务启动成功！"
print_message "MetaStore日志：${LOG_DIR}/metastore.log"
print_message "HiveServer2日志：${LOG_DIR}/hiveserver2.log"