#!/bin/bash

# 配置信息
HADOOP_HOME="/data2/Hive210/base/hadoop-2.10.2"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${HADOOP_HOME}/conf_backup_${TIMESTAMP}"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 日志函数
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# 错误处理
error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# 获取系统信息
get_system_info() {
    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    AVAILABLE_MEM=$(free -g | awk '/^Mem:/{print $7}')
    
    log "系统信息:"
    log "CPU核心数: $CPU_CORES"
    log "总内存: ${TOTAL_MEM}GB"
    log "可用内存: ${AVAILABLE_MEM}GB"
}

# 备份配置文件
backup_configs() {
    mkdir -p ${BACKUP_DIR}
    cp ${HADOOP_HOME}/etc/hadoop/*.xml ${BACKUP_DIR}/
    log "配置文件已备份到: ${BACKUP_DIR}"
}

# 优化core-site.xml
optimize_core_site() {
    cat > ${HADOOP_HOME}/etc/hadoop/core-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>io.file.buffer.size</name>
        <value>131072</value>
    </property>
    <property>
        <name>fs.trash.interval</name>
        <value>1440</value>
    </property>
</configuration>
EOF
}

# 优化hdfs-site.xml
optimize_hdfs_site() {
    local dfs_replication=3
    
    cat > ${HADOOP_HOME}/etc/hadoop/hdfs-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>dfs.namenode.handler.count</name>
        <value>$(( CPU_CORES * 20 ))</value>
    </property>
    <property>
        <name>dfs.datanode.handler.count</name>
        <value>${CPU_CORES}</value>
    </property>
    <property>
        <name>dfs.replication</name>
        <value>${dfs_replication}</value>
    </property>
</configuration>
EOF
}

# 优化mapred-site.xml
optimize_mapred_site() {
    local map_memory=$((AVAILABLE_MEM / 2))GB
    
    cat > ${HADOOP_HOME}/etc/hadoop/mapred-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>mapreduce.map.memory.mb</name>
        <value>${map_memory}</value>
    </property>
    <property>
        <name>mapreduce.reduce.memory.mb</name>
        <value>${map_memory}</value>
    </property>
</configuration>
EOF
}

# 优化yarn-site.xml
optimize_yarn_site() {
    local nm_memory=$((AVAILABLE_MEM * 8 / 10))GB
    
    cat > ${HADOOP_HOME}/etc/hadoop/yarn-site.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <property>
        <name>yarn.nodemanager.resource.memory-mb</name>
        <value>${nm_memory}</value>
    </property>
    <property>
        <name>yarn.scheduler.maximum-allocation-mb</name>
        <value>${nm_memory}</value>
    </property>
</configuration>
EOF
}

# 主函数
main() {
    log "开始优化Hadoop配置..."
    
    # 检查Hadoop目录
    [ -d "$HADOOP_HOME" ] || error "Hadoop目录不存在: $HADOOP_HOME"
    
    # 获取系统信息
    get_system_info
    
    # 备份配置
    backup_configs
    
    # 优化配置文件
    optimize_core_site
    optimize_hdfs_site
    optimize_mapred_site
    optimize_yarn_site
    
    log "配置优化完成"
    log "原配置文件备份在: ${BACKUP_DIR}"
    log "请检查配置并重启Hadoop服务"
}

# 执行主函数
main