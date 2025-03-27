#!/bin/bash

# 设置颜色变量
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 输出函数
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 设置变量
HADOOP_VERSION="2.7.7"
HADOOP_HOME="/data/hadoop-${HADOOP_VERSION}/base"
HADOOP_DATA="/data/hadoop-${HADOOP_VERSION}/data"
HADOOP_LOGS="/data/hadoop-${HADOOP_VERSION}/logs"

# 检查系统环境
check_system() {
    print_message "检查系统环境..."
    
    # 检查 Java
    if ! command -v java &> /dev/null; then
        print_error "未检测到 Java 环境"
        return 1
    fi
    
    # 检查 JAVA_HOME
    if [ -z "${JAVA_HOME}" ]; then
        print_error "JAVA_HOME 未设置"
        return 1
    fi
    
    # 检查 Hadoop 安装
    if [ ! -d "${HADOOP_HOME}" ]; then
        print_error "Hadoop 未安装"
        return 1
    fi
    
    return 0
}

# 检查服务状态
check_services() {
    print_message "检查 Hadoop 服务状态..."
    local services=("NameNode" "DataNode" "ResourceManager" "NodeManager")
    
    for service in "${services[@]}"; do
        if ! jps | grep -q "$service"; then
            print_error "$service 未运行"
            return 1
        fi
        print_message "$service 运行正常"
    done
    
    return 0
}

# 检查端口
check_ports() {
    print_message "检查端口状态..."
    local ports=(8020 50070 8088)
    
    for port in "${ports[@]}"; do
        if ! netstat -tuln | grep -q ":$port "; then
            print_error "端口 $port 未监听"
            return 1
        fi
        print_message "端口 $port 监听正常"
    done
    
    return 0
}

# 测试 HDFS 基本功能
test_hdfs() {
    print_message "测试 HDFS 功能..."
    
    # 创建测试目录和文件
    su - hdfs -c "
        ${HADOOP_HOME}/bin/hadoop fs -mkdir -p /test
        echo 'test content' > /tmp/test_file
        ${HADOOP_HOME}/bin/hadoop fs -put /tmp/test_file /test/
        rm /tmp/test_file
        
        if ${HADOOP_HOME}/bin/hadoop fs -test -e /test/test_file; then
            echo '文件创建测试成功'
        else
            exit 1
        fi
        ${HADOOP_HOME}/bin/hadoop fs -rm -r /test
    "
    
    if [ $? -ne 0 ]; then
        print_error "HDFS 功能测试失败"
        return 1
    fi
    
    print_message "HDFS 功能测试成功"
    return 0
}

# 测试 MapReduce
test_mapreduce() {
    print_message "测试 MapReduce..."
    
    su - hdfs -c "
        ${HADOOP_HOME}/bin/hadoop jar \
        ${HADOOP_HOME}/share/hadoop/mapreduce/hadoop-mapreduce-examples-${HADOOP_VERSION}.jar \
        pi 2 2
    "
    
    if [ $? -ne 0 ]; then
        print_error "MapReduce 测试失败"
        return 1
    fi
    
    print_message "MapReduce 测试成功"
    return 0
}

# 检查目录权限
check_permissions() {
    print_message "检查目录权限..."
    local dirs=("${HADOOP_HOME}" "${HADOOP_DATA}" "${HADOOP_LOGS}")
    
    for dir in "${dirs[@]}"; do
        # 检查目录是否存在
        if [ ! -d "$dir" ]; then
            print_error "目录不存在: $dir"
            return 1
        fi
        
        # 检查所有者和组
        local owner=$(stat -c '%U' "$dir")
        local group=$(stat -c '%G' "$dir")
        
        if [ "$owner" != "hdfs" ]; then
            print_error "目录 $dir 的所有者不是 hdfs 用户（当前：$owner）"
            return 1
        fi
        
        if [ "$group" != "hadoop" ]; then
            print_error "目录 $dir 的组不是 hadoop 组（当前：$group）"
            return 1
        fi
        
        # 检查权限（755）
        local perms=$(stat -c '%a' "$dir")
        if [ "$perms" != "755" ]; then
            print_error "目录 $dir 的权限不是 755（当前：$perms）"
            return 1
        fi
        
        print_message "目录 $dir 权限检查通过"
    done
    
    print_message "所有目录权限正确"
    return 0
}

# 主函数
main() {
    local failed=0
    check_system || failed=1
    check_services || failed=1
    check_ports || failed=1
    check_permissions || failed=1
    test_hdfs || failed=1
    test_mapreduce || failed=1
    
    if [ $failed -eq 0 ]; then
        print_message "所有检查和测试通过！"
        return 0
    else
        print_error "部分检查或测试失败，请查看上述日志"
        return 1
    fi
}

# 执行主函数
main