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
ZK_VERSION="3.8.1"
ZK_HOME="/data/zookeeper"
ZK_DATA="${ZK_HOME}/data"
ZK_LOGS="${ZK_HOME}/logs"
ZK_CONF="${ZK_HOME}/conf"
ZK_PACKAGE="apache-zookeeper-${ZK_VERSION}-bin.tar.gz"
ZK_DOWNLOAD_URL="https://archive.apache.org/dist/zookeeper/zookeeper-${ZK_VERSION}/${ZK_PACKAGE}"

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
    
    # 计算 ZooKeeper 建议内存
    ZK_HEAP_SIZE=$(($TOTAL_MEM / 4))
    [ $ZK_HEAP_SIZE -gt 8 ] && ZK_HEAP_SIZE=8
    [ $ZK_HEAP_SIZE -lt 1 ] && ZK_HEAP_SIZE=1
}

# 下载安装包部分
download_package() {
    print_message "检查安装包..."
    if [ ! -f "/tmp/${ZK_PACKAGE}" ]; then
        print_message "下载 ZooKeeper 安装包..."
        wget -P /tmp ${ZK_DOWNLOAD_URL} || {
            print_error "下载失败，请检查网络连接或手动下载安装包到 /tmp 目录"
            exit 1
        }
    else
        print_message "安装包已存在，验证文件完整性..."
        if ! tar -tzf "/tmp/${ZK_PACKAGE}" >/dev/null 2>&1; then
            print_error "安装包可能损坏，请删除后重新下载"
            exit 1
        fi
    fi
}

# 安装 ZooKeeper 部分
install_zookeeper() {
    print_message "安装 ZooKeeper..."
    
    # 检查并清理旧安装
    if [ -d "${ZK_HOME}" ]; then
        print_warning "发现旧安装，正在备份..."
        mv ${ZK_HOME} ${ZK_HOME}_backup_$(date +%Y%m%d_%H%M%S)
    fi
    
    # 创建目录
    mkdir -p ${ZK_HOME}/{data,logs,conf}
    
    # 解压安装包
    tar -xzf /tmp/${ZK_PACKAGE} -C ${ZK_HOME} --strip-components=1 || {
        print_error "解压失败"
        exit 1
    }
    
    # 创建配置文件
    cat > ${ZK_CONF}/zoo.cfg << EOF
tickTime=2000
initLimit=10
syncLimit=5
dataDir=${ZK_DATA}
dataLogDir=${ZK_LOGS}
clientPort=2181
maxClientCnxns=60
admin.serverPort=8080
EOF

    # 配置环境变量
    cat > /etc/profile.d/zookeeper.sh << EOF
# ZooKeeper Environment Variables
export ZOOKEEPER_HOME=${ZK_HOME}
export PATH=\$PATH:\$ZOOKEEPER_HOME/bin
export ZOO_LOG_DIR=${ZK_LOGS}
export ZOOPIDFILE=${ZK_HOME}/zookeeper_server.pid
export SERVER_JVMFLAGS="-Xms${ZK_HEAP_SIZE}g -Xmx${ZK_HEAP_SIZE}g -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
EOF

    # 设置权限
    chown -R hive:hadoop ${ZK_HOME}
    chmod -R 755 ${ZK_HOME}
    
    # 创建所需目录
    mkdir -p ${ZK_DATA} ${ZK_LOGS}
    chown -R hive:hadoop ${ZK_DATA} ${ZK_LOGS}
    
    # 创建 myid 文件
    echo "1" > ${ZK_DATA}/myid
}

# 创建服务管理脚本
create_service_script() {
    print_message "创建服务管理脚本..."
    
    # 创建系统服务文件
    cat > /etc/systemd/system/zookeeper.service << EOF
[Unit]
Description=Apache ZooKeeper
After=network.target

[Service]
Type=forking
User=hive
Group=hadoop
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="ZOOKEEPER_HOME=${ZK_HOME}"
Environment="ZOO_LOG_DIR=${ZK_LOGS}"
Environment="ZOOPIDFILE=${ZK_HOME}/zookeeper_server.pid"
Environment="SERVER_JVMFLAGS=-Xms${ZK_HEAP_SIZE}g -Xmx${ZK_HEAP_SIZE}g -XX:+UseG1GC"
ExecStart=${ZK_HOME}/bin/zkServer.sh start
ExecStop=${ZK_HOME}/bin/zkServer.sh stop
ExecReload=${ZK_HOME}/bin/zkServer.sh restart
TimeoutSec=30
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载系统服务
    systemctl daemon-reload
    
    # 创建控制脚本
    cat > ${ZK_HOME}/bin/zk_control.sh << EOF
#!/bin/bash
case "\$1" in
    start)
        systemctl start zookeeper
        ;;
    stop)
        systemctl stop zookeeper
        ;;
    status)
        systemctl status zookeeper
        ;;
    restart)
        systemctl restart zookeeper
        ;;
    *)
        echo "Usage: \$0 {start|stop|status|restart}"
        exit 1
esac
EOF

    chmod +x ${ZK_HOME}/bin/zk_control.sh
}

# 主函数部分
main() {
    print_message "开始安装 ZooKeeper..."
    
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
    install_zookeeper
    create_service_script
    
    # 加载环境变量
    source /etc/profile.d/zookeeper.sh
    
    print_message "ZooKeeper 安装完成！"
    print_message "安装目录: ${ZK_HOME}"
    print_message "数据目录: ${ZK_DATA}"
    print_message "日志目录: ${ZK_LOGS}"
    print_message "配置文件: ${ZK_CONF}/zoo.cfg"
    print_message ""
    print_message "使用以下命令管理服务："
    print_message "启动: ${ZK_HOME}/bin/zk_control.sh start"
    print_message "停止: ${ZK_HOME}/bin/zk_control.sh stop"
    print_message "状态: ${ZK_HOME}/bin/zk_control.sh status"
    print_message "重启: ${ZK_HOME}/bin/zk_control.sh restart"
}

# 执行主函数
main