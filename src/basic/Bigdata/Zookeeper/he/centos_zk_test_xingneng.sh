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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ZooKeeper 命令行客户端
ZK_CLI="/data/zookeeper/zk_3.5.8_v2/bin/zkCli.sh"

# 测试连接
test_connection() {
    print_message "测试 ZooKeeper 连接..."
    ${ZK_CLI} -server localhost:2181 ls / > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        print_error "连接 ZooKeeper 失败"
        exit 1
    fi
    print_message "连接成功"
}

# 测试数据操作
test_operations() {
    print_message "开始测试数据操作..."
    
    # 创建测试数据
    ${ZK_CLI} -server localhost:2181 << EOF
# 创建持久节点
create /test_root "root_data"
create /test_root/node1 "node1_data"
create /test_root/node2 "node2_data"

# 创建临时节点
create -e /test_root/temp "temp_data"

# 创建序列节点
create -s /test_root/seq "seq_data"

# 获取数据
get /test_root
get /test_root/node1
get /test_root/node2

# 修改数据
set /test_root/node1 "updated_data"

# 列出子节点
ls /test_root

# 删除节点
delete /test_root/node2
rmr /test_root

# 退出
quit
EOF
}

# 测试监听器
test_watcher() {
    print_message "测试监听器功能..."
    
    # 在后台启动监听
    ${ZK_CLI} -server localhost:2181 << EOF &
create /watch_test "initial_data"
get -w /watch_test
EOF
    
    # 等待监听器启动
    sleep 2
    
    # 修改数据触发监听
    ${ZK_CLI} -server localhost:2181 << EOF
set /watch_test "updated_data"
quit
EOF
}

# 测试性能
test_performance() {
    print_message "测试性能..."
    
    # 创建100个节点并计时
    start_time=$(date +%s%N)
    
    for i in {1..100}; do
        ${ZK_CLI} -server localhost:2181 create /perf_test_$i "data_$i" > /dev/null 2>&1
    done
    
    end_time=$(date +%s%N)
    duration=$(( ($end_time - $start_time) / 1000000 ))
    
    print_message "创建100个节点耗时: ${duration}ms"
    
    # 清理测试数据
    for i in {1..100}; do
        ${ZK_CLI} -server localhost:2181 delete /perf_test_$i > /dev/null 2>&1
    done
}

# 主函数
main() {
    print_message "开始 ZooKeeper 功能测试..."
    
    # 执行测试
    test_connection
    test_operations
    test_watcher
    test_performance
    print_message "测试完成"
}

# 执行主函数
main