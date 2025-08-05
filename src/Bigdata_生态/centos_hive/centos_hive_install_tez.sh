#!/bin/bash
set -euo pipefail

# 配置参数 - 可根据需要调整版本
TEZ_VERSION="${TEZ_VERSION:-0.9.2}"
HIVE_VERSION="${HIVE_VERSION:-2.3.9}"
INSTANCE_ID="${INSTANCE_ID:-v2}"
HIVE_BASE_DIR="/data/hive_${HIVE_VERSION}_${INSTANCE_ID}"
TEZ_BASE_DIR="/data/tez_${TEZ_VERSION}_hive${HIVE_VERSION}_${INSTANCE_ID}"

# 依赖路径 (与Hive安装脚本保持一致)
HADOOP_HOME="/data/hadoop_2.7.7_v1/current"
JAVA_HOME="/data/java/jdk1.8.0_251"
HADOOP_USER="hadoop_2.7.7_v1"
HIVE_USER="hive_${HIVE_VERSION}_${INSTANCE_ID}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 状态函数
error() { echo -e "${RED}[ERROR] $* ${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN] $* ${NC}" >&2; }
info() { echo -e "${GREEN}[INFO] $* ${NC}"; }

# 检查Hive是否已安装
check_hive_installed() {
    [ -d "$HIVE_BASE_DIR" ] || error "Hive未安装在 $HIVE_BASE_DIR，请先安装Hive"
    [ -f "$HIVE_BASE_DIR/conf/hive-site.xml" ] || error "Hive配置文件不存在"
    info "Hive环境验证通过"
}

# 检查依赖
check_dependencies() {
    [ -d "$JAVA_HOME" ] || error "JAVA_HOME路径不存在: $JAVA_HOME"
    [ -d "$HADOOP_HOME" ] || error "Hadoop路径不存在: $HADOOP_HOME"
    
    # 检查必要命令
    for cmd in wget tar; do
        command -v $cmd &>/dev/null || error "缺少必要命令: $cmd，请先安装"
    done
    
    info "所有依赖检查通过"
}

# 下载Tez
download_tez() {
    local tez_tar="apache-tez-${TEZ_VERSION}-bin.tar.gz"
    local tez_url="https://archive.apache.org/dist/tez/${TEZ_VERSION}/${tez_tar}"
    
    info "开始下载Tez $TEZ_VERSION"
    
    # 使用本地缓存或下载
    if [ -f "/tmp/$tez_tar" ]; then
        info "使用本地缓存的Tez安装包"
        cp "/tmp/$tez_tar" .
    else
        wget "$tez_url" -O "$tez_tar" || error "下载Tez失败"
        cp "$tez_tar" /tmp/
    fi
    info "下载完成"
    # 检查文件完整性
    [ $(stat -c %s "$tez_tar") -gt 1000000 ] || error "下载的Tez包不完整"
    
    info "Tez下载成功"
}

# 安装Tez
install_tez() {
    info "安装Tez到: $TEZ_BASE_DIR"
    
    # 清理并创建目录
    [ -d "$TEZ_BASE_DIR" ] && rm -rf "$TEZ_BASE_DIR"
    mkdir -p "$TEZ_BASE_DIR"
    
    # 解压Tez
    local tez_tar="apache-tez-${TEZ_VERSION}-bin.tar.gz"
    tar -zxf "$tez_tar" -C "$TEZ_BASE_DIR" --strip-components=1
    cp "$tez_tar" /tmp
    rm -f "$tez_tar"
    
    # 创建Tez临时目录并设置权限
    su - $HADOOP_USER <<EOF
        hdfs dfs -mkdir -p /user/tez
        hdfs dfs -chmod -R 777 /user/tez
        hdfs dfs -mkdir -p /tmp/tez
        hdfs dfs -chmod -R 777 /tmp/tez
EOF

    info "Tez安装完成"
}

# 配置Tez
configure_tez() {
    info "配置Tez环境"
    
    # 创建tez-site.xml配置
    cat > "$TEZ_BASE_DIR/conf/tez-site.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property>
    <name>tez.lib.uris</name>
    <value>hdfs:///user/tez/tez-${TEZ_VERSION}-libs</value>
  </property>
  <property>
    <name>tez.use.cluster.hadoop-libs</name>
    <value>true</value>
  </property>
  <property>
    <name>tez.history.logging.service.class</name>
    <value>org.apache.tez.dag.history.logging.ats.ATSHistoryLoggingService</value>
  </property>
  <property>
    <name>tez.am.resource.memory.mb</name>
    <value>1024</value>
  </property>
  <property>
    <name>tez.container.max.java.heap.fraction</name>
    <value>0.7</value>
  </property>
  <property>
    <name>tez.task.resource.memory.mb</name>
    <value>1024</value>
  </property>
</configuration>
EOF

    # 配置Hadoop的tez环境
    # 使用xmlstarlet向core-site.xml添加代理用户配置
    HADOOP_CORE_SITE="$HADOOP_HOME/etc/hadoop/core-site.xml"

    # 添加hadoop.proxyuser.hive.hosts
    if ! xmlstarlet sel -t -v "//configuration/property[name='hadoop.proxyuser.hive.hosts']" "$HADOOP_CORE_SITE" >/dev/null; then
        xmlstarlet ed -L \
            -s "//configuration" -t elem -n "property" \
            -s "//configuration/property[last()]" -t elem -n "name" -v "hadoop.proxyuser.hive.hosts" \
            -s "//configuration/property[last()]" -t elem -n "value" -v "*" \
            "$HADOOP_CORE_SITE"
    fi

    # 添加hadoop.proxyuser.hive.groups
    if ! xmlstarlet sel -t -v "//configuration/property[name='hadoop.proxyuser.hive.groups']" "$HADOOP_CORE_SITE" >/dev/null; then
        xmlstarlet ed -L \
            -s "//configuration" -t elem -n "property" \
            -s "//configuration/property[last()]" -t elem -n "name" -v "hadoop.proxyuser.hive.groups" \
            -s "//configuration/property[last()]" -t elem -n "value" -v "*" \
            "$HADOOP_CORE_SITE"
    fi

    # 分发Tez库到HDFS
    su - $HADOOP_USER <<EOF
        hdfs dfs -mkdir -p /user/tez/tez-${TEZ_VERSION}-libs
        hdfs dfs -put $TEZ_BASE_DIR/* /user/tez/tez-${TEZ_VERSION}-libs/
EOF
    info "Tez配置完成"
}

# 配置Hive使用Tez
configure_hive_tez() {
    info "配置Hive使用Tez执行引擎"    
    local hive_site="$HIVE_BASE_DIR/conf/hive-site.xml"
    
    # 备份原有配置
    [ -f "$hive_site.bak" ] || cp "$hive_site" "$hive_site.bak"
    
    # 添加Tez相关配置到Hive
    # 使用xmlstarlet工具修改XML配置（如果没有会自动安装）
    if ! command -v xmlstarlet &>/dev/null; then
        info "安装xmlstarlet工具"
        if command -v yum &>/dev/null; then
            yum install -y xmlstarlet
        elif command -v apt-get &>/dev/null; then
            apt-get install -y xmlstarlet
        else
            error "无法安装xmlstarlet，请手动安装后重试"
        fi
    fi
    
    # 设置执行引擎为Tez
    if xmlstarlet sel -t -v "//configuration/property[name='hive.execution.engine']/value" "$hive_site" >/dev/null; then
        xmlstarlet ed -L -u "//configuration/property[name='hive.execution.engine']/value" -v "tez" "$hive_site"
    else
        xmlstarlet ed -L -s "//configuration" -t elem -n "property" \
            -s "//configuration/property[last()]" -t elem -n "name" -v "hive.execution.engine" \
            -s "//configuration/property[last()]" -t elem -n "value" -v "tez" \
            "$hive_site"
    fi
    
    # 禁用Tez会话池（避免冲突）
    if ! xmlstarlet sel -t -v "//configuration/property[name='hive.tez.session.pool.enabled']/value" "$hive_site" >/dev/null; then
        xmlstarlet ed -L -s "//configuration" -t elem -n "property" \
            -s "//configuration/property[last()]" -t elem -n "name" -v "hive.tez.session.pool.enabled" \
            -s "//configuration/property[last()]" -t elem -n "value" -v "false" \
            "$hive_site"
    fi
    
    # 添加Tez到Hive环境变量
    local hive_env="$HIVE_BASE_DIR/conf/hive-env.sh"
    if ! grep -q "TEZ_HOME" "$hive_env"; then
        cat >> "$hive_env" <<EOF
export TEZ_HOME="$TEZ_BASE_DIR"
export HIVE_AUX_JARS_PATH=\$TEZ_HOME/*:\$TEZ_HOME/lib/*:\$HIVE_AUX_JARS_PATH
EOF
    fi
    
    # 创建环境变量脚本
    local env_file="/etc/profile.d/tez-${TEZ_VERSION}-hive${HIVE_VERSION}-${INSTANCE_ID}.sh"
    cat > "$env_file" <<EOF
export TEZ_HOME="$TEZ_BASE_DIR"
export PATH="\$PATH:\$TEZ_HOME/bin"
export HADOOP_CLASSPATH=\$HADOOP_CLASSPATH:\$TEZ_HOME/*:\$TEZ_HOME/lib/*
EOF
    
    source "$env_file"
    info "Hive-Tez集成配置完成"
}

# 启动Hive服务
start_hive_services() {
    info "启动Hive服务..."
    
    local pid_dir="$HIVE_BASE_DIR/pids"
    local log_dir="$HIVE_BASE_DIR/logs"
    
    mkdir -p "$pid_dir" "$log_dir"
    
    # 停止可能运行的服务
    if [ -f "$pid_dir/metastore.pid" ]; then
        kill $(cat "$pid_dir/metastore.pid") 2>/dev/null || true
        rm -f "$pid_dir/metastore.pid"
    fi
    
    if [ -f "$pid_dir/hiveserver2.pid" ]; then
        kill $(cat "$pid_dir/hiveserver2.pid") 2>/dev/null || true
        rm -f "$pid_dir/hiveserver2.pid"
    fi
    
    # 启动元数据服务
    nohup "$HIVE_BASE_DIR/bin/hive" --service metastore > "$log_dir/metastore-tez.log" 2>&1 &
    echo $! > "$pid_dir/metastore.pid"
    
    # 启动HiveServer2
    nohup "$HIVE_BASE_DIR/bin/hive" --service hiveserver2 > "$log_dir/hiveserver2-tez.log" 2>&1 &
    echo $! > "$pid_dir/hiveserver2.pid"
    
    # 等待服务启动
    sleep 15
    info "Hive服务启动完成"
}

# 测试Tez配置
test_tez() {
    info "开始测试Tez执行引擎..."
    
    local test_db="tez_test_db_${HIVE_VERSION}_${INSTANCE_ID}"
    local test_table="test_tez_table"
    
    # 使用beeline连接Hive
    local hiveserver_port=$(xmlstarlet sel -t -v "//configuration/property[name='hive.server2.thrift.port']/value" "$HIVE_BASE_DIR/conf/hive-site.xml")
    local hostname=$(hostname -f)
    
    # 执行测试SQL
    "$HIVE_BASE_DIR/bin/beeline" -u "jdbc:hive2://$hostname:$hiveserver_port/default" -n "$HIVE_USER" -e "
        DROP DATABASE IF EXISTS $test_db CASCADE;
        CREATE DATABASE $test_db;
        USE $test_db;
        CREATE TABLE $test_table (id INT, name STRING);
        INSERT INTO $test_table VALUES (1, 'tez_test'), (2, 'hive_test');
        SELECT COUNT(*) FROM $test_table;
        DROP DATABASE $test_db CASCADE;
    " || error "Tez测试执行失败"
    info "Tez执行引擎测试成功"
}

# 主流程
main() {
    info "开始为Hive $HIVE_VERSION (实例: $INSTANCE_ID)安装Tez $TEZ_VERSION"
    
    check_hive_installed
    check_dependencies
    download_tez
    install_tez
    configure_tez
    configure_hive_tez
    start_hive_services
    test_tez
    
    info "Tez安装并配置成功!"
    cat <<EOF
=============================================================
Tez版本:    $TEZ_VERSION
安装路径:   $TEZ_BASE_DIR
Hive版本:   $HIVE_VERSION
Hive路径:   $HIVE_BASE_DIR

验证Tez是否生效的命令:
source /etc/profile.d/tez-${TEZ_VERSION}-hive${HIVE_VERSION}-${INSTANCE_ID}.sh
$HIVE_BASE_DIR/bin/hive -e "set hive.execution.engine;"

应输出: hive.execution.engine=tez
=============================================================
EOF
}

# 执行入口
main