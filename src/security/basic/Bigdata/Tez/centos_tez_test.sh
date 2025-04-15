#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 函数定义
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 环境变量设置
export TEZ_HOME=/data/apache-tez-0.9.2-bin
export HADOOP_CLASSPATH=${TEZ_HOME}/*:${TEZ_HOME}/lib/*

# 检查必要条件
if [ -z "$HADOOP_HOME" ]; then
    print_error "HADOOP_HOME 环境变量未设置"
fi

if [ ! -d "$TEZ_HOME" ]; then
    print_error "Tez 目录不存在: $TEZ_HOME"
fi

# 准备测试数据
print_message "准备测试数据..."
hdfs dfs -mkdir -p /datas || print_error "创建 HDFS 目录失败"

# 创建测试数据文件
cat > /tmp/wordcount.data << 'EOF' || print_error "创建测试数据文件失败"
Hello World
Hello Hadoop
Hello Tez
World of Big Data
Hadoop and Tez
Big Data Processing
EOF

# 上传并设置权限
print_message "上传数据到 HDFS..."
hdfs dfs -rm -r /datas/wordcount.data 2>/dev/null
hdfs dfs -put /tmp/wordcount.data /datas/ || print_error "上传文件失败"
hdfs dfs -chmod 644 /datas/wordcount.data || print_error "设置权限失败"

# 清理本地临时文件
rm -f /tmp/wordcount.data

# 清理已存在的输出目录
print_message "清理输出目录..."
hdfs dfs -rm -r /output 2>/dev/null

# 运行测试程序
print_message "运行 WordCount 示例..."
${HADOOP_HOME}/bin/yarn jar ${TEZ_HOME}/tez-examples-0.9.2.jar \
    orderedwordcount /datas/wordcount.data /output/ || print_error "WordCount 执行失败"

# 显示结果
print_message "测试结果："
hdfs dfs -cat /output/* || print_error "读取结果失败"

print_message "测试完成"