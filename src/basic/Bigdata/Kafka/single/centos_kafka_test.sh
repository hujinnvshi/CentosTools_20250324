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

# 获取本机IP地址
get_local_ip() {
    # 优先获取非回环IP地址
    LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n 1)
    if [ -z "$LOCAL_IP" ]; then
        print_error "无法获取本机IP地址"
        exit 1
    fi
    print_message "本机IP地址: ${LOCAL_IP}"
}

# Kafka 相关变量(注意修改为你的实际配置)
KAFKA_HOME="/data/kafka_cluster/broker1"
KAFKA_BIN="${KAFKA_HOME}/bin"

# 测试主题名称
TEST_TOPIC="test-topic"
MULTI_PARTITION_TOPIC="multi-partition-topic"

# 测试连接
test_connection() {
    print_message "测试 Kafka 连接... ${BOOTSTRAP_SERVER}"
    ${KAFKA_BIN}/kafka-topics.sh --bootstrap-server ${BOOTSTRAP_SERVER} --list >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        print_error "连接 Kafka 失败"
        exit 1
    fi
    print_message "连接成功"
}


# 创建测试主题
create_test_topics() {
    print_message "创建测试主题..."
    
    # 创建单分区主题
    ${KAFKA_BIN}/kafka-topics.sh --bootstrap-server ${BOOTSTRAP_SERVER} \
        --create --topic ${TEST_TOPIC} --partitions 1 --replication-factor 1
    
    # 创建多分区主题
    ${KAFKA_BIN}/kafka-topics.sh --bootstrap-server ${BOOTSTRAP_SERVER} \
        --create --topic ${MULTI_PARTITION_TOPIC} --partitions 3 --replication-factor 1
    
    # 查看主题列表
    print_message "已创建的主题列表："
    ${KAFKA_BIN}/kafka-topics.sh --bootstrap-server ${BOOTSTRAP_SERVER} --list
}

# 测试消息生产和消费
test_produce_consume() {
    print_message "测试消息生产和消费..."
    
    # 生产测试消息
    print_message "生产消息到 ${TEST_TOPIC}..."
    echo "Hello, Kafka!" | ${KAFKA_BIN}/kafka-console-producer.sh \
        --bootstrap-server ${BOOTSTRAP_SERVER} --topic ${TEST_TOPIC}
    
    # 消费测试消息
    print_message "从 ${TEST_TOPIC} 消费消息..."
    ${KAFKA_BIN}/kafka-console-consumer.sh \
        --bootstrap-server ${BOOTSTRAP_SERVER} \
        --topic ${TEST_TOPIC} \
        --from-beginning \
        --max-messages 1
}

# 测试多分区生产和消费
test_multi_partition() {
    print_message "测试多分区消息生产和消费..."
    
    # 生产多条消息到不同分区
    for i in {1..6}; do
        echo "Message $i" | ${KAFKA_BIN}/kafka-console-producer.sh \
            --bootstrap-server ${BOOTSTRAP_SERVER} \
            --topic ${MULTI_PARTITION_TOPIC} \
            --property "partition=$((i % 3))"
    done
    
    # 查看分区信息
    print_message "查看分区信息："
    ${KAFKA_BIN}/kafka-topics.sh --bootstrap-server ${BOOTSTRAP_SERVER} \
        --describe --topic ${MULTI_PARTITION_TOPIC}
    
    # 消费所有分区的消息
    print_message "消费所有分区的消息..."
    ${KAFKA_BIN}/kafka-console-consumer.sh \
        --bootstrap-server ${BOOTSTRAP_SERVER} \
        --topic ${MULTI_PARTITION_TOPIC} \
        --from-beginning \
        --max-messages 6
}

# 测试性能
test_performance() {
    print_message "测试生产者性能..."
    ${KAFKA_BIN}/kafka-producer-perf-test.sh \
        --topic ${TEST_TOPIC} \
        --num-records 100000 \
        --record-size 1000 \
        --throughput -1 \
        --producer-props bootstrap.servers=${BOOTSTRAP_SERVER}
    
    print_message "测试消费者性能..."
    ${KAFKA_BIN}/kafka-consumer-perf-test.sh \
        --bootstrap-server ${BOOTSTRAP_SERVER} \
        --topic ${TEST_TOPIC} \
        --messages 100000
}

# 清理测试数据
cleanup() {
    print_message "清理测试数据..."
    
    # 删除测试主题
    ${KAFKA_BIN}/kafka-topics.sh --bootstrap-server ${BOOTSTRAP_SERVER} \
        --delete --topic ${TEST_TOPIC}
    ${KAFKA_BIN}/kafka-topics.sh --bootstrap-server ${BOOTSTRAP_SERVER} \
        --delete --topic ${MULTI_PARTITION_TOPIC}
}

# 主函数
main() {
    print_message "开始 Kafka 功能测试..."
    # 获取本机IP
    get_local_ip
    # 定义 BOOTSTRAP_SERVER
    BOOTSTRAP_SERVER="$LOCAL_IP:9092"
    # 执行测试
    test_connection
    create_test_topics
    test_produce_consume
    test_multi_partition
    test_performance
    cleanup    
    print_message "测试完成"
}

# 执行主函数
main