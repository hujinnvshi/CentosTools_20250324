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

# 默认配置
DEFAULT_BROKERS="localhost:9092,localhost:9094,localhost:9096"
DEFAULT_TOPIC="test-topic"
DEFAULT_PARTITIONS=3
DEFAULT_REPLICATION=3
DEFAULT_TEST_MESSAGES=1000

# 帮助信息
show_usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -b, --brokers <brokers>       Kafka brokers 列表 (默认: ${DEFAULT_BROKERS})
    -t, --topic <topic>           测试主题名称 (默认: ${DEFAULT_TOPIC})
    -p, --partitions <num>        分区数量 (默认: ${DEFAULT_PARTITIONS})
    -r, --replication <num>       副本因子 (默认: ${DEFAULT_REPLICATION})
    -m, --messages <num>          测试消息数量 (默认: ${DEFAULT_TEST_MESSAGES})
    -h, --help                    显示此帮助信息

示例:
    $0
    $0 -b "localhost:9092,localhost:9094" -t "my-topic" -p 5 -r 2 -m 2000
EOF
}

# 解析参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--brokers)
                BROKERS="$2"
                shift 2
                ;;
            -t|--topic)
                TOPIC="$2"
                shift 2
                ;;
            -p|--partitions)
                PARTITIONS="$2"
                shift 2
                ;;
            -r|--replication)
                REPLICATION="$2"
                shift 2
                ;;
            -m|--messages)
                TEST_MESSAGES="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "未知参数: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # 设置默认值
    BROKERS=${BROKERS:-$DEFAULT_BROKERS}
    TOPIC=${TOPIC:-$DEFAULT_TOPIC}
    PARTITIONS=${PARTITIONS:-$DEFAULT_PARTITIONS}
    REPLICATION=${REPLICATION:-$DEFAULT_REPLICATION}
    TEST_MESSAGES=${TEST_MESSAGES:-$DEFAULT_TEST_MESSAGES}
}

# 检查集群状态
check_cluster_status() {
    print_message "检查集群状态..."
    
    if ! kafka-broker-api-versions.sh --bootstrap-server "$BROKERS" &>/dev/null; then
        print_error "无法连接到 Kafka 集群"
        exit 1
    fi
    
    # 获取集群信息
    print_message "集群信息:"
    kafka-broker-api-versions.sh --bootstrap-server "$BROKERS" | grep "id"
    
    # 检查 Controller 状态
    print_message "Controller 信息:"
    kafka-metadata-quorum.sh --bootstrap-server "$BROKERS" describe --status
}

# 创建测试主题
create_test_topic() {
    print_message "创建测试主题: $TOPIC"
    
    # 检查主题是否已存在
    if kafka-topics.sh --bootstrap-server "$BROKERS" --describe --topic "$TOPIC" &>/dev/null; then
        print_warning "主题 $TOPIC 已存在，将被删除重建"
        kafka-topics.sh --bootstrap-server "$BROKERS" --delete --topic "$TOPIC"
        sleep 5
    fi
    
    # 创建主题
    kafka-topics.sh --bootstrap-server "$BROKERS" --create \
        --topic "$TOPIC" \
        --partitions "$PARTITIONS" \
        --replication-factor "$REPLICATION" || {
        print_error "创建主题失败"
        exit 1
    }
    
    # 显示主题信息
    print_message "主题信息:"
    kafka-topics.sh --bootstrap-server "$BROKERS" --describe --topic "$TOPIC"
}

# 生产测试消息
produce_test_messages() {
    print_message "生产 $TEST_MESSAGES 条测试消息..."
    
    for i in $(seq 1 "$TEST_MESSAGES"); do
        echo "测试消息 $i: $(date '+%Y-%m-%d %H:%M:%S')"
    done | timeout 30s kafka-console-producer.sh \
        --bootstrap-server "$BROKERS" \
        --topic "$TOPIC" || {
        print_error "生产消息失败"
        exit 1
    }
}

# 消费测试消息
consume_test_messages() {
    print_message "消费测试消息..."
    
    # 使用临时消费者组
    local GROUP_ID="test-group-$(date +%s)"
    
    # 设置超时时间为30秒
    timeout 30s kafka-console-consumer.sh \
        --bootstrap-server "$BROKERS" \
        --topic "$TOPIC" \
        --group "$GROUP_ID" \
        --from-beginning \
        --max-messages "$TEST_MESSAGES" || {
        print_error "消费消息失败"
        exit 1
    }
}

# 检查消费者组状态
check_consumer_group() {
    print_message "消费者组信息:"
    kafka-consumer-groups.sh --bootstrap-server "$BROKERS" --describe --all-groups
}

# 主函数
main() {
    print_message "开始 Kafka 集群测试..."
    
    # 检查必要命令
    if ! command -v kafka-topics.sh &>/dev/null; then
        print_error "未找到 Kafka 命令行工具，请确保 Kafka bin 目录在 PATH 中"
        exit 1
    fi
    
    # 执行测试步骤
    check_cluster_status
    create_test_topic
    produce_test_messages
    consume_test_messages
    check_consumer_group
    
    print_message "测试完成！"
}

# 解析命令行参数并执行主函数
parse_args "$@"
main
# 自定义参数测试
# ./kafka_cluster_test.sh -b "localhost:9092,localhost:9094" -t "my-topic" -p 5 -r 2 -m 2000