#!/bin/bash
set -euo pipefail

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
    exit 1
}

# 端口生成函数
generate_ports() {
    # 基础端口
    local base_client_port=2181
    local base_admin_port=8080
    
    # 从实例ID中提取数字部分
    local instance_num=$(echo "$ZK_INSTANCE" | sed 's/[^0-9]*//g')
    [ -z "$instance_num" ] && instance_num=1
    
    # 计算端口
    ZK_PORT=$((base_client_port + instance_num - 1))
    ZK_ADMIN_PORT=$((base_admin_port + instance_num - 1))
    
    print_message "实例 ${ZK_INSTANCE} 使用端口: 客户端 ${ZK_PORT}, 管理 ${ZK_ADMIN_PORT}"
}

# 检查端口可用性
check_port_availability() {
    local port=$1
    local service=$2
    
    if netstat -tuln | grep -q ":$port "; then
        print_error "端口 ${port} 已被占用，无法用于 ${service}"
    fi
    print_message "端口 ${port} 可用，将用于 ${service}"
}

# 设置变量
ZK_HOST="${ZK_HOST:-$(hostname -I | awk '{print $1}')}" # 自动获取主机IP
ZK_VERSION="${ZK_VERSION:-3.8.1}"                       # 默认版本
ZK_INSTANCE="${ZK_INSTANCE:-v1}"                        # 默认实例标识符
ZK_BASE_DIR="/data/zookeeper"                            # 基础安装目录
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java}"              # 默认Java路径

# 基于实例和版本生成ID
ZK_INSTANCE_ID="zk_${ZK_VERSION}_${ZK_INSTANCE}"
ZK_HOME="${ZK_BASE_DIR}/${ZK_INSTANCE_ID}"      # 实例安装目录
ZK_DATA="${ZK_HOME}/data"
ZK_LOGS="${ZK_HOME}/logs"
ZK_CONF="${ZK_HOME}/conf"

# 自动生成端口
generate_ports

ZK_PACKAGE="apache-zookeeper-${ZK_VERSION}-bin.tar.gz"
ZK_DOWNLOAD_URL="https://archive.apache.org/dist/zookeeper/zookeeper-${ZK_VERSION}/${ZK_PACKAGE}"
ZK_USER="${ZK_INSTANCE_ID}"                     # 专用用户
ZK_GROUP="${ZK_INSTANCE_ID}"                    # 专用组

# 验证用户/组名长度
validate_username() {
    local max_length=32
    if [ ${#ZK_USER} -gt $max_length ]; then
        print_error "用户名过长 (${#ZK_USER} > $max_length): ${ZK_USER}"
    fi
    if [ ${#ZK_GROUP} -gt $max_length ]; then
        print_error "组名过长 (${#ZK_GROUP} > $max_length): ${ZK_GROUP}"
    fi
}

# 检查系统资源
check_system() {
    print_message "检查系统资源..."    
    
    # 检查是否安装必要工具
    for cmd in wget tar netstat; do
        if ! command -v $cmd &>/dev/null; then
            print_warning "缺少命令: $cmd，尝试安装..."
            if command -v yum &>/dev/null; then
                yum install -y $cmd
            elif command -v apt-get &>/dev/null; then
                apt-get update && apt-get install -y $cmd
            else
                print_warning "无法自动安装 $cmd，请确保该命令可用"
            fi
        fi
    done
    
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
    
    # 计算 ZooKeeper 建议内存
    ZK_HEAP_SIZE=$(($TOTAL_MEM / 4))
    [ $ZK_HEAP_SIZE -gt 8 ] && ZK_HEAP_SIZE=8
    [ $ZK_HEAP_SIZE -lt 1 ] && ZK_HEAP_SIZE=1
    print_message "设置 ZooKeeper 堆内存: ${ZK_HEAP_SIZE}GB"
}

# 创建专用用户
create_user() {
    print_message "创建 ZooKeeper 专用用户: ${ZK_USER}..."
    
    if ! id -u $ZK_USER &>/dev/null; then
        useradd -r -s /sbin/nologin $ZK_USER
        print_message "用户 $ZK_USER 创建成功"
    else
        print_message "用户 $ZK_USER 已存在"
    fi
    
    if ! getent group $ZK_GROUP &>/dev/null; then
        groupadd -r $ZK_GROUP
        print_message "组 $ZK_GROUP 创建成功"
    else
        print_message "组 $ZK_GROUP 已存在"
    fi
    
    # 将用户加入组
    usermod -a -G $ZK_GROUP $ZK_USER
}

# 下载安装包部分
download_package() {
    print_message "检查安装包..."
    if [ ! -f "/tmp/${ZK_PACKAGE}" ]; then
        print_message "下载 ZooKeeper ${ZK_VERSION} 安装包..."
        wget -t 3 -T 30 -P /tmp ${ZK_DOWNLOAD_URL} || {
            # 尝试备份镜像源
            print_warning "主镜像下载失败，尝试 CDN 镜像..."
            wget -t 2 -T 20 "https://dlcdn.apache.org/zookeeper/zookeeper-${ZK_VERSION}/${ZK_PACKAGE}" -O "/tmp/${ZK_PACKAGE}" || 
            print_error "下载失败，请检查网络连接或手动下载安装包到 /tmp 目录"
        }
    else
        print_message "安装包已存在，验证文件完整性..."
        if ! tar -tzf "/tmp/${ZK_PACKAGE}" >/dev/null 2>&1; then
            print_warning "安装包可能损坏，重新下载..."
            rm -f "/tmp/${ZK_PACKAGE}"
            download_package
        fi
    fi
}

# 安装 ZooKeeper 部分
install_zookeeper() {
    print_message "安装 ZooKeeper ${ZK_VERSION} (实例: ${ZK_INSTANCE})..."
    
    # 检查并备份旧安装
    if [ -d "${ZK_HOME}" ]; then
        print_warning "发现旧安装，正在备份..."
        backup_dir="${ZK_HOME}_backup_$(date +%Y%m%d_%H%M%S)"
        mv ${ZK_HOME} ${backup_dir}
        print_message "旧安装已备份至: ${backup_dir}"
    fi
    
    # 创建目录结构
    mkdir -p ${ZK_HOME} ${ZK_DATA} ${ZK_LOGS} ${ZK_CONF}
    
    # 解压安装包
    tar -xzf "/tmp/${ZK_PACKAGE}" -C ${ZK_HOME} --strip-components=1 || {
        print_error "解压失败，请检查磁盘空间和权限"
    }
    
    # 创建配置文件
    cat > ${ZK_CONF}/zoo.cfg << EOF
# ZooKeeper 配置文件 (实例: ${ZK_INSTANCE})
# 生成时间: $(date)
tickTime=2000
initLimit=10
syncLimit=5
dataDir=${ZK_DATA}
dataLogDir=${ZK_LOGS}
clientPort=${ZK_PORT}
maxClientCnxns=60
admin.serverPort=${ZK_ADMIN_PORT}
autopurge.snapRetainCount=3
autopurge.purgeInterval=24
4lw.commands.whitelist=*
EOF

    # 配置环境变量
    local env_file="/etc/profile.d/zookeeper_${ZK_INSTANCE_ID}.sh"
    cat > ${env_file} << EOF
# ZooKeeper Environment Variables (实例: ${ZK_INSTANCE_ID})
export ZOOKEEPER_HOME=${ZK_HOME}
export PATH=\$PATH:\${ZOOKEEPER_HOME}/bin
export ZOO_LOG_DIR=${ZK_LOGS}
export ZOOPIDFILE=${ZK_HOME}/zookeeper_server.pid
export SERVER_JVMFLAGS="-Xms${ZK_HEAP_SIZE}g -Xmx${ZK_HEAP_SIZE}g -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+HeapDumpOnOutOfMemoryError"
EOF

    # 设置权限
    chown -R ${ZK_USER}:${ZK_GROUP} ${ZK_HOME}
    chmod -R 750 ${ZK_HOME}
    
    # 创建所需目录
    mkdir -p ${ZK_DATA} ${ZK_LOGS}
    chown -R ${ZK_USER}:${ZK_GROUP} ${ZK_DATA} ${ZK_LOGS}
    
    # 创建 myid 文件
    echo "1" > ${ZK_DATA}/myid
    chown ${ZK_USER}:${ZK_GROUP} ${ZK_DATA}/myid
    chmod 640 ${ZK_DATA}/myid
    
    # 创建日志目录
    mkdir -p /var/log/zookeeper/${ZK_INSTANCE_ID}
    chown -R ${ZK_USER}:${ZK_GROUP} /var/log/zookeeper/${ZK_INSTANCE_ID}
}

# 创建服务管理脚本
create_service_script() {
    print_message "配置 ZooKeeper 系统服务 (实例: ${ZK_INSTANCE_ID})..."
    
    # 服务文件名
    local service_file="/etc/systemd/system/${ZK_INSTANCE_ID}.service"
    
    # 创建系统服务文件
    cat > ${service_file} << EOF
[Unit]
Description=Apache ZooKeeper (实例: ${ZK_INSTANCE_ID})
After=network.target
Requires=network.target

[Service]
Type=forking
User=${ZK_USER}
Group=${ZK_GROUP}
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="ZOOKEEPER_HOME=${ZK_HOME}"
Environment="ZOO_LOG_DIR=/var/log/zookeeper/${ZK_INSTANCE_ID}"
Environment="ZOOPIDFILE=${ZK_HOME}/zookeeper_server.pid"
Environment="SERVER_JVMFLAGS=-Xms${ZK_HEAP_SIZE}g -Xmx${ZK_HEAP_SIZE}g -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError"
ExecStart=${ZK_HOME}/bin/zkServer.sh start
ExecStop=${ZK_HOME}/bin/zkServer.sh stop
ExecReload=${ZK_HOME}/bin/zkServer.sh restart
TimeoutStartSec=60
TimeoutStopSec=30
Restart=on-failure
RestartSec=10
SuccessExitStatus=143

# 安全设置
PrivateTmp=true
ProtectSystem=full
NoNewPrivileges=true
LimitNOFILE=65536
LimitNPROC=65536

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载系统服务
    systemctl daemon-reload
    
    # 创建控制脚本
    cat > ${ZK_HOME}/bin/zk_control.sh << EOF
#!/bin/bash
# ZooKeeper 服务控制脚本 (实例: ${ZK_INSTANCE_ID})
# 版本: ${ZK_VERSION}
# 路径: ${ZK_HOME}

case "\$1" in
    start)
        systemctl start ${ZK_INSTANCE_ID}
        ;;
    stop)
        systemctl stop ${ZK_INSTANCE_ID}
        ;;
    status)
        systemctl status ${ZK_INSTANCE_ID}
        ;;
    restart)
        systemctl restart ${ZK_INSTANCE_ID}
        ;;
    logs)
        journalctl -u ${ZK_INSTANCE_ID} -f
        ;;
    *)
        echo "Usage: \$0 {start|stop|status|restart|logs}"
        exit 1
esac
EOF

    chmod +x ${ZK_HOME}/bin/zk_control.sh
}

# 配置日志管理
configure_logging() {
    print_message "配置日志管理 (实例: ${ZK_INSTANCE_ID})..."
    
    # 创建日志配置文件
    cat > ${ZK_CONF}/log4j.properties << EOF
# ZooKeeper 日志配置 (实例: ${ZK_INSTANCE_ID})
log4j.rootLogger=INFO, ROLLINGFILE

# 控制台日志
log4j.appender.CONSOLE=org.apache.log4j.ConsoleAppender
log4j.appender.CONSOLE.Threshold=INFO
log4j.appender.CONSOLE.layout=org.apache.log4j.PatternLayout
log4j.appender.CONSOLE.layout.ConversionPattern=%d{ISO8601} [myid:%X{myid}] - %-5p [%t:%C{1}@%L] - %m%n

# 滚动文件日志
log4j.appender.ROLLINGFILE=org.apache.log4j.RollingFileAppender
log4j.appender.ROLLINGFILE.Threshold=INFO
log4j.appender.ROLLINGFILE.File=/var/log/zookeeper/${ZK_INSTANCE_ID}/zookeeper.log
log4j.appender.ROLLINGFILE.MaxFileSize=256MB
log4j.appender.ROLLINGFILE.MaxBackupIndex=10
log4j.appender.ROLLINGFILE.layout=org.apache.log4j.PatternLayout
log4j.appender.ROLLINGFILE.layout.ConversionPattern=%d{ISO8601} [myid:%X{myid}] - %-5p [%t:%C{1}@%L] - %m%n

# 审计日志
log4j.logger.org.apache.zookeeper.audit=WARN, AUDIT
log4j.appender.AUDIT=org.apache.log4j.RollingFileAppender
log4j.appender.AUDIT.File=/var/log/zookeeper/${ZK_INSTANCE_ID}/zookeeper-audit.log
log4j.appender.AUDIT.MaxFileSize=128MB
log4j.appender.AUDIT.MaxBackupIndex=5
log4j.appender.AUDIT.layout=org.apache.log4j.PatternLayout
log4j.appender.AUDIT.layout.ConversionPattern=%d{ISO8601} [%t] - %m%n
EOF

    # 设置日志目录权限
    chown -R ${ZK_USER}:${ZK_GROUP} /var/log/zookeeper/${ZK_INSTANCE_ID}
}

# 验证安装
verify_installation() {
    print_message "验证安装 (实例: ${ZK_INSTANCE_ID})..."
    
    # 检查关键文件
    [ -f "${ZK_HOME}/bin/zkServer.sh" ] || print_error "缺少关键文件: zkServer.sh"
    [ -f "${ZK_CONF}/zoo.cfg" ] || print_error "缺少配置文件: zoo.cfg"
    [ -f "${ZK_DATA}/myid" ] || print_error "缺少 myid 文件"
    
    # 检查用户权限
    su - ${ZK_USER} -s /bin/bash -c "test -r ${ZK_HOME}/bin/zkServer.sh" || 
        print_error "用户 ${ZK_USER} 没有读取权限"
    
    # 检查端口配置
    grep -q "clientPort=${ZK_PORT}" ${ZK_CONF}/zoo.cfg || 
        print_error "客户端端口配置错误"
    grep -q "admin.serverPort=${ZK_ADMIN_PORT}" ${ZK_CONF}/zoo.cfg || 
        print_error "管理端口配置错误"
    
    # 检查Java版本
    JAVA_VERSION=$(${JAVA_HOME}/bin/java -version 2>&1 | head -1 | cut -d'"' -f2)
    if [[ $JAVA_VERSION != 1.8.* ]]; then
        print_warning "Java 版本不兼容 (${JAVA_VERSION})，推荐使用 Java 8"
    fi
    
    print_message "安装验证通过"
}

# 启动服务
start_service() {
    print_message "启动 ZooKeeper 服务 (实例: ${ZK_INSTANCE_ID})..."
    systemctl enable ${ZK_INSTANCE_ID}
    systemctl start ${ZK_INSTANCE_ID}
    
    # 检查服务状态
    sleep 3
    if systemctl is-active --quiet ${ZK_INSTANCE_ID}; then
        print_message "服务启动成功"
    else
        print_error "服务启动失败，请检查日志: journalctl -u ${ZK_INSTANCE_ID}"
    fi
}

# 显示安装摘要
show_summary() {
    cat << EOF

${GREEN}==================== ZooKeeper 安装完成 ====================${NC}
实例标识:     ${ZK_INSTANCE}
版本:         ${ZK_VERSION}
安装路径:     ${ZK_HOME}
数据目录:     ${ZK_DATA}
日志目录:     ${ZK_LOGS}
配置文件:     ${ZK_CONF}/zoo.cfg
服务用户:     ${ZK_USER}:${ZK_GROUP}
客户端端口:   ${ZK_PORT}
管理端口:     ${ZK_ADMIN_PORT}
堆内存:       ${ZK_HEAP_SIZE}GB

${YELLOW}管理命令:${NC}
启动服务:     systemctl start ${ZK_INSTANCE_ID}
停止服务:     systemctl stop ${ZK_INSTANCE_ID}
查看状态:     systemctl status ${ZK_INSTANCE_ID}
查看日志:     journalctl -u ${ZK_INSTANCE_ID} -f
控制脚本:     ${ZK_HOME}/bin/zk_control.sh

${GREEN}服务已配置为开机自启${NC}
${YELLOW}=================================================${NC}
EOF
}

# 主函数部分
main() {
    print_message "开始安装 ZooKeeper (实例: ${ZK_INSTANCE})..."
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用 root 用户执行此脚本"
    fi
    
    # 检查 JAVA_HOME
    if [ -z "${JAVA_HOME}" ]; then
        print_error "未设置 JAVA_HOME 环境变量"
    fi
    if [ ! -d "${JAVA_HOME}" ]; then
        print_error "JAVA_HOME 路径不存在: ${JAVA_HOME}"
    fi
    
    # 验证用户名长度
    validate_username
    
    # 检查端口可用性
    check_port_availability $ZK_PORT "客户端"
    check_port_availability $ZK_ADMIN_PORT "管理"
    
    # 执行安装步骤
    check_system
    create_user
    download_package
    install_zookeeper
    create_service_script
    configure_logging
    verify_installation
    start_service
    
    # 加载环境变量
    if [ -f "/etc/profile.d/zookeeper_${ZK_INSTANCE_ID}.sh" ]; then
        source "/etc/profile.d/zookeeper_${ZK_INSTANCE_ID}.sh"
    fi
    
    show_summary
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            ZK_VERSION="$2"
            shift 2
            ;;
        --instance)
            ZK_INSTANCE="$2"
            shift 2
            ;;
        --client-port)
            ZK_PORT="$2"
            shift 2
            ;;
        --admin-port)
            ZK_ADMIN_PORT="$2"
            shift 2
            ;;
        --java-home)
            JAVA_HOME="$2"
            shift 2
            ;;
        *)
            print_error "未知参数: $1"
            ;;
    esac
done

# 执行主函数
main