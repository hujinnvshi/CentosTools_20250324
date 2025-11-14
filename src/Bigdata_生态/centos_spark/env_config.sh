#!/bin/bash
# 环境参数配置文件 - 请根据实际环境修改这些参数

# ========================
# 必需的环境路径配置
# ========================

# Hadoop 安装路径
export HADOOP_HOME="/opt/hadoop-3.1.2"

# Hive 安装路径  
export HIVE_HOME="/opt/hive-2.3.9"

# Spark 安装路径（如果已存在）
export SPARK_HOME="/opt/spark-3.4.1"

# Java 安装路径
export JAVA_HOME="/usr/lib/jvm/java-11-openjdk"

# ========================
# 服务端口配置
# ========================

# HDFS 端口（根据实际配置修改）
export HDFS_PORT="8020"

# Hive Metastore 端口
export HIVE_METASTORE_PORT="9083"

# ========================
# 数据库配置（如果使用 MySQL）
# ========================

# MySQL 连接信息（用于 Hive Metastore）
export MYSQL_HOST="localhost"
export MYSQL_PORT="3306"
export MYSQL_HIVE_USER="hive"
export MYSQL_HIVE_PASSWORD="hive123"

# ========================
# 资源配置
# ========================

# Spark 内存配置
export SPARK_DRIVER_MEMORY="2g"
export SPARK_EXECUTOR_MEMORY="2g"
export SPARK_WORKER_CORES="4"

# ========================
# 网络配置
# ========================

# 主机名或IP地址
export CLUSTER_HOSTNAME="localhost"

# 验证配置
validate_config() {
    echo "=== 环境配置验证 ==="
    echo "HADOOP_HOME: $HADOOP_HOME"
    echo "HIVE_HOME: $HIVE_HOME" 
    echo "SPARK_HOME: $SPARK_HOME"
    echo "JAVA_HOME: $JAVA_HOME"
    echo "HDFS_PORT: $HDFS_PORT"
    echo "HIVE_METASTORE_PORT: $HIVE_METASTORE_PORT"
    echo ""
    
    # 检查目录是否存在
    for dir in $HADOOP_HOME $HIVE_HOME $JAVA_HOME; do
        if [ -d "$dir" ]; then
            echo "✅ $dir 存在"
        else
            echo "❌ $dir 不存在"
        fi
    done
}

# 如果直接执行此脚本，则验证配置
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    validate_config
fi