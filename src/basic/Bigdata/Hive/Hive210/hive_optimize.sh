#!/bin/bash

# 配置信息
HIVE_HOME="/data2/Hive210/base/apache-hive-2.1.0-bin"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${HIVE_HOME}/conf_backup_${TIMESTAMP}"

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

# 清理函数
cleanup() {
    if [ $? -ne 0 ]; then
        log "发生错误，正在恢复原配置..."
        if [ -d "${BACKUP_DIR}" ]; then
            cp "${BACKUP_DIR}"/*.xml "${HIVE_HOME}/conf/"
            log "配置已恢复"
        fi
    fi
}

# 设置退出陷阱
trap cleanup EXIT

# 获取系统信息
get_system_info() {
    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    AVAILABLE_MEM=$(free -g | awk '/^Mem:/{print $7}')
    
    log "系统信息:"
    log "CPU核心数: $CPU_CORES"
    log "总内存: ${TOTAL_MEM}GB"
    log "可用内存: ${AVAILABLE_MEM}GB"
}

# 备份配置文件
backup_configs() {
    mkdir -p ${BACKUP_DIR}
    if [ -f "${HIVE_HOME}/conf/hive-site.xml" ]; then
        cp "${HIVE_HOME}/conf/hive-site.xml" "${BACKUP_DIR}/"
        log "配置文件已备份到: ${BACKUP_DIR}"
    else
        error "hive-site.xml 不存在"
    fi
}

# 优化hive-site.xml
optimize_hive_site() {
    # 计算优化参数
    local parallel_threads=$((CPU_CORES * 2))
    # 在 optimize_hive_site 函数开始添加
    if [ $parallel_threads -lt 1 ]; then
        error "并行线程数计算错误"
    fi

    local heap_size=$((AVAILABLE_MEM * 1024 * 6 / 10))
    
    cat > ${HIVE_HOME}/conf/hive-site.xml << EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
    <!-- 保留原有数据库配置 -->
    <property>
        <name>javax.jdo.option.ConnectionURL</name>
        <value>jdbc:mysql://172.16.48.28:6003/HIVE2_1_0?createDatabaseIfNotExist=true&amp;useSSL=false&amp;serverTimezone=UTC</value>
        <description>JDBC connect string for a JDBC metastore</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionDriverName</name>
        <value>com.mysql.jdbc.Driver</value>
        <description>Driver class name for a JDBC metastore</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionUserName</name>
        <value>HIVE2_1_0</value>
        <description>username to use against metastore database</description>
    </property>
    <property>
        <name>javax.jdo.option.ConnectionPassword</name>
        <value>Secsmart#612</value>
        <description>password to use against metastore database</description>
    </property>

    <!-- 性能优化配置 -->
    <property>
        <name>hive.exec.parallel</name>
        <value>true</value>
        <description>是否并行执行任务</description>
    </property>
    <property>
        <name>hive.exec.parallel.thread.number</name>
        <value>${parallel_threads}</value>
        <description>并行执行任务的线程数</description>
    </property>
    <property>
        <name>hive.exec.reducers.bytes.per.reducer</name>
        <value>268435456</value>
        <description>每个reducer处理的数据量</description>
    </property>
    <property>
        <name>hive.execution.engine</name>
        <value>mr</value>
        <description>mr</description>
    </property>
    <property>
        <name>hive.auto.convert.join</name>
        <value>true</value>
        <description>自动转换MapJoin</description>
    </property>
    <property>
        <name>hive.mapjoin.smalltable.filesize</name>
        <value>25000000</value>
        <description>小表阈值</description>
    </property>
    <property>
        <name>hive.optimize.reducededuplication</name>
        <value>true</value>
        <description>优化reduce阶段去重</description>
    </property>
    <property>
        <name>hive.optimize.skewjoin</name>
        <value>true</value>
        <description>优化数据倾斜</description>
    </property>
    <property>
        <name>hive.server2.thrift.port</name>
        <value>10000</value>
        <description>HiveServer2端口</description>
    </property>
    <property>
        <name>hive.server2.thrift.min.worker.threads</name>
        <value>${CPU_CORES}</value>
        <description>最小工作线程数</description>
    </property>
    <property>
        <name>hive.server2.thrift.max.worker.threads</name>
        <value>${parallel_threads}</value>
        <description>最大工作线程数</description>
    </property>
</configuration>
EOF
}

# 主函数
main() {
    # 在 main 函数开始添加
    # 检查必要命令
    command -v nproc >/dev/null 2>&1 || error "未找到 nproc 命令"
    command -v free >/dev/null 2>&1 || error "未找到 free 命令"

    # 检查 MySQL 连接
    if ! nc -z 172.16.48.28 6003; then
        error "无法连接到 MySQL 服务器"
    fi

    log "开始优化Hive配置..."
    
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        error "请使用root用户执行此脚本"
    fi

    # 检查配置目录写入权限
    if [ ! -w "${HIVE_HOME}/conf" ]; then
        error "没有配置目录的写入权限: ${HIVE_HOME}/conf"
    fi
    
    # 检查Hive目录
    [ -d "$HIVE_HOME" ] || error "Hive目录不存在: $HIVE_HOME"
    
    # 获取系统信息
    get_system_info
    
    # 备份配置
    backup_configs
    
    # 优化配置文件
    optimize_hive_site
    
    log "配置优化完成"
    log "原配置文件备份在: ${BACKUP_DIR}"
    log "请检查配置并重启Hive服务"
}

# 执行主函数
main