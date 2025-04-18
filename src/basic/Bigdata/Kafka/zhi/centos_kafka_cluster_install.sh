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
KAFKA_VERSION="3.9.0"
KAFKA_BASE="/data/kafka_cluster"
KAFKA_PACKAGE="kafka_2.13-${KAFKA_VERSION}.tgz"
KAFKA_DOWNLOAD_URL="https://downloads.apache.org/kafka/${KAFKA_VERSION}/${KAFKA_PACKAGE}"

# Broker 配置
declare -A BROKER_PORTS=(
    ["broker1"]="9092,9093"
    ["broker2"]="9094,9095"
    ["broker3"]="9096,9097"
)

# ... (保留 check_system 和 create_user 函数) ...

# 安装 Kafka
install_kafka() {
    print_message "安装 Kafka 集群..."
    
    # 创建基础目录
    mkdir -p ${KAFKA_BASE}
    
    # 下载并解压安装包
    if [ ! -f "/tmp/${KAFKA_PACKAGE}" ]; then
        wget -P /tmp ${KAFKA_DOWNLOAD_URL}
    fi
    
    # 生成集群ID
    CLUSTER_ID=$(${KAFKA_BASE}/broker1/bin/kafka-storage.sh random-uuid)
    
    # 为每个 broker 创建独立目录和配置
    for broker in "${!BROKER_PORTS[@]}"; do
        BROKER_HOME="${KAFKA_BASE}/${broker}"
        BROKER_DATA="${BROKER_HOME}/data"
        BROKER_LOGS="${BROKER_HOME}/logs"
        BROKER_CONF="${BROKER_HOME}/config"
        
        # 创建目录结构
        mkdir -p ${BROKER_DATA} ${BROKER_LOGS} ${BROKER_CONF}/kafka
        
        # 解压安装包
        tar -xzf /tmp/${KAFKA_PACKAGE} -C ${BROKER_HOME} --strip-components=1
        
        # 获取端口
        IFS=',' read -r CLIENT_PORT CONTROLLER_PORT <<< "${BROKER_PORTS[$broker]}"
        
        # 创建配置文件
        cat > ${BROKER_CONF}/kafka/server.properties << EOF
# Broker 配置
node.id=${broker#broker}
process.roles=broker,controller
listeners=PLAINTEXT://localhost:${CLIENT_PORT},CONTROLLER://localhost:${CONTROLLER_PORT}
advertised.listeners=PLAINTEXT://localhost:${CLIENT_PORT}
controller.listener.names=CONTROLLER
controller.quorum.voters=1@localhost:9093,2@localhost:9095,3@localhost:9097

# 基础配置
num.network.threads=${CPU_CORES}
num.io.threads=${CPU_CORES}
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
num.partitions=3
default.replication.factor=3

# 日志配置
log.dirs=${BROKER_DATA}
num.recovery.threads.per.data.dir=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

# 内存配置
heap.opts=-Xmx${KAFKA_HEAP_SIZE}g -Xms${KAFKA_HEAP_SIZE}g
EOF

        # 创建服务文件
        cat > /etc/systemd/system/kafka-${broker}.service << EOF
[Unit]
Description=Apache Kafka ${broker}
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="KAFKA_HEAP_OPTS=-Xmx${KAFKA_HEAP_SIZE}g -Xms${KAFKA_HEAP_SIZE}g"
ExecStart=${BROKER_HOME}/bin/kafka-server-start.sh ${BROKER_CONF}/kafka/server.properties
ExecStop=${BROKER_HOME}/bin/kafka-server-stop.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

        # 设置权限
        chown -R kafka:kafka ${BROKER_HOME}
        chmod -R 755 ${BROKER_HOME}
        
        # 格式化存储目录
        su kafka -c "cd ~ && ${BROKER_HOME}/bin/kafka-storage.sh format -t ${CLUSTER_ID} -c ${BROKER_CONF}/kafka/server.properties"
    done
    
    # 创建集群控制脚本
    cat > ${KAFKA_BASE}/kafka_cluster_control.sh << EOF
#!/bin/bash
case "\$1" in
    start)
        for broker in broker{1..3}; do
            systemctl start kafka-\${broker}
            sleep 5
        done
        ;;
    stop)
        for broker in broker{3..1}; do
            systemctl stop kafka-\${broker}
        done
        ;;
    status)
        for broker in broker{1..3}; do
            echo "Status of \${broker}:"
            systemctl status kafka-\${broker}
        done
        ;;
    restart)
        \$0 stop
        sleep 10
        \$0 start
        ;;
    *)
        echo "Usage: \$0 {start|stop|status|restart}"
        exit 1
esac
EOF

    chmod +x ${KAFKA_BASE}/kafka_cluster_control.sh
    chown kafka:kafka ${KAFKA_BASE}/kafka_cluster_control.sh
}

# ... (保留其他辅助函数) ...

main() {
    print_message "开始安装 Kafka 集群..."
    
    # 检查权限和依赖
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户执行此脚本"
        exit 1
    fi
    
    if [ -z "$JAVA_HOME" ]; then
        print_error "未设置 JAVA_HOME 环境变量"
        exit 1
    fi
    
    # 执行安装
    check_system
    create_user
    install_kafka
    
    systemctl daemon-reload
    
    print_message "Kafka 集群安装完成！"
    print_message "集群目录: ${KAFKA_BASE}"
    print_message "Broker1 端口: 9092(Client), 9093(Controller)"
    print_message "Broker2 端口: 9094(Client), 9095(Controller)"
    print_message "Broker3 端口: 9096(Client), 9097(Controller)"
    print_message ""
    print_message "使用以下命令管理集群："
    print_message "启动: ${KAFKA_BASE}/kafka_cluster_control.sh start"
    print_message "停止: ${KAFKA_BASE}/kafka_cluster_control.sh stop"
    print_message "状态: ${KAFKA_BASE}/kafka_cluster_control.sh status"
    print_message "重启: ${KAFKA_BASE}/kafka_cluster_control.sh restart"
}

main