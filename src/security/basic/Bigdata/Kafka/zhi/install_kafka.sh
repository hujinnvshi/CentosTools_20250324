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
KAFKA_HOME="/data/kafka"
KAFKA_DATA="${KAFKA_HOME}/data"
KAFKA_LOGS="${KAFKA_HOME}/logs"
KAFKA_CONF="${KAFKA_HOME}/config"
KAFKA_PACKAGE="kafka_2.13-${KAFKA_VERSION}.tgz"
KAFKA_DOWNLOAD_URL="https://downloads.apache.org/kafka/${KAFKA_VERSION}/${KAFKA_PACKAGE}"

# 检查系统资源
check_system() {
    print_message "检查系统资源..."
    
    # 检查是否安装必要工具
    command -v nproc >/dev/null 2>&1 || yum install -y coreutils
    command -v wget >/dev/null 2>&1 || yum install -y wget
    
    # CPU 信息
    CPU_CORES=$(nproc)
    print_message "CPU 核心数: ${CPU_CORES}"
    
    # 内存信息
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    if [ -z "$TOTAL_MEM" ] || [ "$TOTAL_MEM" -eq 0 ]; then
        TOTAL_MEM=1
        print_warning "无法获取准确的内存信息，使用默认值 1GB"
    fi
    print_message "系统总内存: ${TOTAL_MEM}GB"
    
    # 计算 Kafka 建议内存
    KAFKA_HEAP_SIZE=$(($TOTAL_MEM / 2))
    [ $KAFKA_HEAP_SIZE -gt 8 ] && KAFKA_HEAP_SIZE=8
    [ $KAFKA_HEAP_SIZE -lt 1 ] && KAFKA_HEAP_SIZE=1
}

# 创建用户和组
create_user() {
    print_message "创建用户和组..."
    groupadd kafka 2>/dev/null || print_warning "组 kafka 已存在"
    useradd -g kafka -m -d /home/kafka kafka 2>/dev/null || print_warning "用户 kafka 已存在"
}

# 下载安装包
download_package() {
    print_message "检查安装包..."
    if [ ! -f "/tmp/${KAFKA_PACKAGE}" ]; then
        print_message "下载 Kafka 安装包..."
        wget -P /tmp ${KAFKA_DOWNLOAD_URL} || {
            print_error "下载失败，请检查网络连接或手动下载安装包到 /tmp 目录"
            exit 1
        }
    else
        print_message "安装包已存在，验证文件完整性..."
        if ! tar -tzf "/tmp/${KAFKA_PACKAGE}" >/dev/null 2>&1; then
            print_error "安装包可能损坏，请删除后重新下载"
            exit 1
        fi
    fi
}

# 安装 Kafka
install_kafka() {
    print_message "安装 Kafka..."
    
    # 检查并清理旧安装
    if [ -d "${KAFKA_HOME}" ]; then
        print_warning "发现旧安装，正在备份..."
        mv ${KAFKA_HOME} ${KAFKA_HOME}_backup_$(date +%Y%m%d_%H%M%S)
    fi
    
    # 创建目录
    mkdir -p ${KAFKA_HOME}/{data,logs,config}
    
    # 解压安装包
    tar -xzf /tmp/${KAFKA_PACKAGE} -C ${KAFKA_HOME} --strip-components=1 || {
        print_error "解压失败"
        exit 1
    }
    
    # 生成集群ID
    CLUSTER_ID=$(${KAFKA_HOME}/bin/kafka-storage.sh random-uuid)
    
    # 创建配置文件
    cat > ${KAFKA_CONF}/kraft/server.properties << EOF
# Kafka Broker 配置
node.id=1
process.roles=broker,controller
listeners=PLAINTEXT://localhost:9092,CONTROLLER://localhost:9093
advertised.listeners=PLAINTEXT://localhost:9092
controller.listener.names=CONTROLLER
controller.quorum.voters=1@localhost:9093

# 基础配置
num.network.threads=${CPU_CORES}
num.io.threads=${CPU_CORES}
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
num.partitions=3
default.replication.factor=1

# 日志配置
log.dirs=${KAFKA_DATA}
num.recovery.threads.per.data.dir=1
log.retention.hours=168
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000

# 内存配置
heap.opts=-Xmx${KAFKA_HEAP_SIZE}g -Xms${KAFKA_HEAP_SIZE}g
EOF

    # 配置环境变量
    cat > /etc/profile.d/kafka.sh << EOF
# Kafka Environment Variables
export KAFKA_HOME=${KAFKA_HOME}
export PATH=\$PATH:\$KAFKA_HOME/bin
export KAFKA_HEAP_OPTS="-Xmx${KAFKA_HEAP_SIZE}g -Xms${KAFKA_HEAP_SIZE}g -XX:+UseG1GC"
export KAFKA_JVM_PERFORMANCE_OPTS="-server -XX:+UseG1GC -XX:MaxGCPauseMillis=20 -XX:InitiatingHeapOccupancyPercent=35 -XX:+ExplicitGCInvokesConcurrent -Djava.awt.headless=true"
export KAFKA_LOG_DIRS=${KAFKA_LOGS}
EOF

    # 设置权限
    chown -R kafka:kafka ${KAFKA_HOME}
    chmod -R 755 ${KAFKA_HOME}
    
    # 格式化存储目录
    su - kafka -c "${KAFKA_HOME}/bin/kafka-storage.sh format -t ${CLUSTER_ID} -c ${KAFKA_CONF}/kraft/server.properties"
}

# 创建服务管理脚本
create_service_script() {
    print_message "创建服务管理脚本..."
    
    # 创建系统服务文件
    cat > /etc/systemd/system/kafka.service << EOF
[Unit]
Description=Apache Kafka
After=network.target

[Service]
Type=simple
User=kafka
Group=kafka
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="KAFKA_HEAP_OPTS=-Xmx${KAFKA_HEAP_SIZE}g -Xms${KAFKA_HEAP_SIZE}g"
ExecStart=${KAFKA_HOME}/bin/kafka-server-start.sh ${KAFKA_CONF}/kraft/server.properties
ExecStop=${KAFKA_HOME}/bin/kafka-server-stop.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载系统服务
    systemctl daemon-reload
    
    # 创建控制脚本
    cat > ${KAFKA_HOME}/bin/kafka_control.sh << EOF
#!/bin/bash
case "\$1" in
    start)
        systemctl start kafka
        ;;
    stop)
        systemctl stop kafka
        ;;
    status)
        systemctl status kafka
        ;;
    restart)
        systemctl restart kafka
        ;;
    *)
        echo "Usage: \$0 {start|stop|status|restart}"
        exit 1
esac
EOF

    chmod +x ${KAFKA_HOME}/bin/kafka_control.sh
}

# 主函数
main() {
    print_message "开始安装 Kafka..."
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户执行此脚本"
        exit 1
    fi
    
    # 检查 JAVA_HOME
    if [ -z "$JAVA_HOME" ]; then
        print_error "未设置 JAVA_HOME 环境变量"
        exit 1
    fi
    
    # 执行安装步骤
    check_system
    create_user
    download_package
    install_kafka
    create_service_script
    
    # 加载环境变量
    source /etc/profile.d/kafka.sh
    
    print_message "Kafka 安装完成！"
    print_message "安装目录: ${KAFKA_HOME}"
    print_message "数据目录: ${KAFKA_DATA}"
    print_message "日志目录: ${KAFKA_LOGS}"
    print_message "配置文件: ${KAFKA_CONF}/kraft/server.properties"
    print_message ""
    print_message "使用以下命令管理服务："
    print_message "启动: ${KAFKA_HOME}/bin/kafka_control.sh start"
    print_message "停止: ${KAFKA_HOME}/bin/kafka_control.sh stop"
    print_message "状态: ${KAFKA_HOME}/bin/kafka_control.sh status"
    print_message "重启: ${KAFKA_HOME}/bin/kafka_control.sh restart"
}

# 执行主函数
main