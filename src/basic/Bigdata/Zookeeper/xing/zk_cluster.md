
我来帮你创建一个部署单机三节点 ZooKeeper 集群的安装脚本：

```bash:/Users/www.redelego.cn/CentosTools_20250324/src/security/basic/Bigdata/Zookeeper/install_zk_cluster.sh
#!/bin/bash

# 设置变量
ZK_VERSION="3.7.1"
ZK_BASE="/data/zookeeper"
ZK_PACKAGE="apache-zookeeper-${ZK_VERSION}-bin.tar.gz"
ZK_DOWNLOAD_URL="https://archive.apache.org/dist/zookeeper/zookeeper-${ZK_VERSION}/${ZK_PACKAGE}"
NODES=(1 2 3)
CLIENT_PORTS=(2181 2182 2183)
PEER_PORTS=(2888 2889 2890)
ELECTION_PORTS=(3888 3889 3890)
ADMIN_PORTS=(8086 8087 8088)

# 颜色输出
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 系统检查和优化
check_system() {
    log "检查系统环境..."
    command -v wget >/dev/null 2>&1 || yum install -y wget
    
    # 获取系统资源信息
    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    
    # 计算每个节点的ZK内存（系统内存的1/6，最大4G）
    ZK_HEAP_SIZE=$(($TOTAL_MEM / 6))
    [ $ZK_HEAP_SIZE -gt 4 ] && ZK_HEAP_SIZE=4
    [ $ZK_HEAP_SIZE -lt 1 ] && ZK_HEAP_SIZE=1
    
    log "CPU核心数: ${CPU_CORES}"
    log "系统内存: ${TOTAL_MEM}GB"
    log "每节点ZK堆内存: ${ZK_HEAP_SIZE}GB"
}

# 下载安装包
download_package() {
    if [ ! -f "/tmp/${ZK_PACKAGE}" ]; then
        log "下载ZooKeeper..."
        wget -P /tmp ${ZK_DOWNLOAD_URL} || error "下载失败"
    else
        log "安装包已存在，跳过下载"
    fi
}

# 安装单个ZooKeeper节点
install_node() {
    local NODE_ID=$1
    local CLIENT_PORT=${CLIENT_PORTS[$((NODE_ID-1))]}
    local ADMIN_PORT=${ADMIN_PORTS[$((NODE_ID-1))]}
    
    local ZK_HOME="${ZK_BASE}/zk${NODE_ID}"
    local ZK_DATA="${ZK_HOME}/data"
    local ZK_LOGS="${ZK_HOME}/logs"
    local ZK_CONF="${ZK_HOME}/conf"
    
    log "安装ZooKeeper节点${NODE_ID}..."
    
    # 创建目录
    mkdir -p ${ZK_HOME}/{data,logs,conf}
    
    # 解压
    tar -xzf /tmp/${ZK_PACKAGE} -C ${ZK_HOME} --strip-components=1
    
    # 创建配置文件
    cat > ${ZK_CONF}/zoo.cfg << EOF
tickTime=2000
initLimit=10
syncLimit=5
dataDir=${ZK_DATA}
dataLogDir=${ZK_LOGS}
clientPort=${CLIENT_PORT}
admin.serverPort=${ADMIN_PORT}
maxClientCnxns=60
autopurge.snapRetainCount=3
autopurge.purgeInterval=1

# 集群配置
EOF
    
    # 添加集群节点配置
    for i in "${NODES[@]}"; do
        echo "server.${i}=localhost:${PEER_PORTS[$((i-1))]}:${ELECTION_PORTS[$((i-1))]}" >> ${ZK_CONF}/zoo.cfg
    done
    
    # 创建myid文件
    echo "${NODE_ID}" > ${ZK_DATA}/myid
    
    # 设置权限
    chown -R root:root ${ZK_HOME}
    chmod -R 755 ${ZK_HOME}
}

# 创建服务
create_service() {
    local NODE_ID=$1
    local ZK_HOME="${ZK_BASE}/zk${NODE_ID}"
    
    cat > /etc/systemd/system/zookeeper${NODE_ID}.service << EOF
[Unit]
Description=Apache ZooKeeper Node ${NODE_ID}
After=network.target

[Service]
Type=forking
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="ZOO_LOG_DIR=${ZK_HOME}/logs"
Environment="JVMFLAGS=-Xms${ZK_HEAP_SIZE}g -Xmx${ZK_HEAP_SIZE}g -XX:+UseG1GC"
ExecStart=${ZK_HOME}/bin/zkServer.sh start
ExecStop=${ZK_HOME}/bin/zkServer.sh stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zookeeper${NODE_ID}
}

# 配置环境变量
setup_environment() {
    cat > /etc/profile.d/zookeeper.sh << EOF
# ZooKeeper Environment Variables
export ZK_HOME=${ZK_BASE}
export PATH=\$PATH:${ZK_BASE}/zk1/bin
EOF
    source /etc/profile.d/zookeeper.sh
}

# 主函数
main() {
    [ "$EUID" -ne 0 ] && error "请使用root用户运行"
    [ -z "$JAVA_HOME" ] && error "请设置JAVA_HOME环境变量"
    
    check_system
    download_package
    
    # 安装所有节点
    for node in "${NODES[@]}"; do
        install_node $node
        create_service $node
    done
    
    setup_environment
    
    # 启动所有节点
    for node in "${NODES[@]}"; do
        systemctl start zookeeper${node}
        sleep 3
    done
    
    # 验证集群状态
    sleep 5
    for node in "${NODES[@]}"; do
        local CLIENT_PORT=${CLIENT_PORTS[$((node-1))]}
        if echo stat | nc localhost ${CLIENT_PORT} >/dev/null 2>&1; then
            log "节点${node}启动成功"
        else
            error "节点${node}启动失败"
        fi
    done
    
    log "ZooKeeper集群安装完成"
    log "节点1: localhost:${CLIENT_PORTS[0]}"
    log "节点2: localhost:${CLIENT_PORTS[1]}"
    log "节点3: localhost:${CLIENT_PORTS[2]}"
}

main
```

使用说明：

1. 脚本会在 `/data/zookeeper` 下创建三个节点：
   - zk1: 端口 2181, 2888, 3888, 8086
   - zk2: 端口 2182, 2889, 3889, 8087
   - zk3: 端口 2183, 2890, 3890, 8088

2. 运行方式：
```bash
chmod +x install_zk_cluster.sh
./install_zk_cluster.sh
```

3. 验证集群：
```bash
# 检查节点状态
for port in 2181 2182 2183; do
    echo "srvr" | nc localhost $port
done
```

4. 服务管理：
```bash
# 启动/停止/重启指定节点
systemctl start|stop|restart zookeeper1
systemctl start|stop|restart zookeeper2
systemctl start|stop|restart zookeeper3
```

脚本特点：
- 自动检测系统资源并优化配置
- 智能分配内存给每个节点
- 自动配置集群通信端口
- 创建独立的systemd服务
- 包含基本的健康检查