是的，ZooKeeper 可以部署为单节点环境，适用于开发测试场景。不过需要注意，单节点模式不具备高可用性，不建议在生产环境使用。

让我修改一下安装脚本，创建一个单节点版本：

```bash:/Users/www.redelego.cn/CentosTools_20250324/src/security/basic/Bigdata/Zookeeper/xing/install_zk_standalone.sh
#!/bin/bash
# 设置变量
ZK_VERSION="3.8.1"
ZK_HOME="/data/zookeeper"
ZK_DATA="${ZK_HOME}/data"
ZK_LOGS="${ZK_HOME}/logs"
ZK_CONF="${ZK_HOME}/conf"
ZK_PACKAGE="apache-zookeeper-${ZK_VERSION}-bin.tar.gz"
ZK_DOWNLOAD_URL="https://archive.apache.org/dist/zookeeper/zookeeper-${ZK_VERSION}/${ZK_PACKAGE}"

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
    
    # 计算ZK内存（系统内存的1/4，最大4G）
    ZK_HEAP_SIZE=$(($TOTAL_MEM / 4))
    [ $ZK_HEAP_SIZE -gt 4 ] && ZK_HEAP_SIZE=4
    [ $ZK_HEAP_SIZE -lt 1 ] && ZK_HEAP_SIZE=1
    
    log "CPU核心数: ${CPU_CORES}"
    log "系统内存: ${TOTAL_MEM}GB"
    log "ZK堆内存: ${ZK_HEAP_SIZE}GB"
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

# 安装ZooKeeper
install_zookeeper() {
    log "安装ZooKeeper..."
    
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
clientPort=2181
maxClientCnxns=60
admin.serverPort=8086
autopurge.snapRetainCount=3
autopurge.purgeInterval=1
4lw.commands.whitelist=*
EOF
    
    # 配置环境变量
    cat > /etc/profile.d/zookeeper.sh << EOF
export ZOOKEEPER_HOME=${ZK_HOME}
export PATH=\$PATH:\$ZOOKEEPER_HOME/bin
export ZOO_LOG_DIR=${ZK_LOGS}
export JVMFLAGS="-Xms${ZK_HEAP_SIZE}g -Xmx${ZK_HEAP_SIZE}g -XX:+UseG1GC"
EOF

    # 设置权限
    chown -R root:root ${ZK_HOME}
    chmod -R 755 ${ZK_HOME}
}

# 创建服务
create_service() {
    cat > /etc/systemd/system/zookeeper.service << EOF
[Unit]
Description=Apache ZooKeeper
After=network.target

[Service]
Type=forking
Environment="JAVA_HOME=${JAVA_HOME}"
Environment="ZOO_LOG_DIR=${ZK_HOME}/logs"
ExecStart=${ZK_HOME}/bin/zkServer.sh start
ExecStop=${ZK_HOME}/bin/zkServer.sh stop
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zookeeper
}

# 主函数
main() {
    [ "$EUID" -ne 0 ] && error "请使用root用户运行"
    [ -z "$JAVA_HOME" ] && error "请设置JAVA_HOME环境变量"
    
    check_system
    download_package
    install_zookeeper
    create_service
    
    source /etc/profile.d/zookeeper.sh
    
    systemctl start zookeeper
    sleep 3
    
    if echo stat | nc localhost 2181 >/dev/null 2>&1; then
        log "ZooKeeper安装完成并成功启动"
        log "访问端口: 2181"
        log "管理端口: 8086"
    else
        error "ZooKeeper启动失败"
    fi
}

main
```

使用方法：
```bash
chmod +x install_zk_standalone.sh
./install_zk_standalone.sh
```

验证服务：
```bash
# 检查服务状态
systemctl status zookeeper

# 检查ZK状态
echo stat | nc localhost 2181
```

这个单节点版本的特点：
1. 配置更简单，移除了集群相关配置
2. 资源占用更少，适合开发测试
3. 保留了基本的性能优化
4. 包含必要的监控端口

但要注意，单节点模式：
1. 不具备高可用性
2. 不支持故障转移
3. 不适合生产环境使用