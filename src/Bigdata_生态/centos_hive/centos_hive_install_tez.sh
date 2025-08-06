#!/bin/bash
set -euo pipefail

# ========================
# 用户可配置参数 (可按需调整)
# ========================
TEZ_VERSION="${TEZ_VERSION:-0.9.2}"             # 默认使用较新版本
HIVE_VERSION="${HIVE_VERSION:-2.3.9}"
INSTANCE_ID="${INSTANCE_ID:-v1}"
HADOOP_VERSION="${HADOOP_VERSION:-2.7.7}"        # 添加Hadoop版本变量
HADOOP_INSTANCE="${HADOOP_INSTANCE:-v1}"         # Hadoop实例标识

# ========================
# 系统路径定义 (默认值)
# ========================
HIVE_BASE_DIR="/data/hive_${HIVE_VERSION}_${INSTANCE_ID}"
TEZ_BASE_DIR="/data/tez_${TEZ_VERSION}_hive${HIVE_VERSION}_${INSTANCE_ID}"
HADOOP_HOME="/data/hadoop_${HADOOP_VERSION}_${HADOOP_INSTANCE}/current"
JAVA_HOME="/data/java/jdk1.8.0_251"

# ========================
# 服务用户定义
# ========================
HADOOP_USER="hadoop_${HADOOP_VERSION}_${HADOOP_INSTANCE}"
HIVE_USER="hive_${HIVE_VERSION}_${INSTANCE_ID}"

# ========================
# 颜色定义
# ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ========================
# 状态函数
# ========================
error() { echo -e "${RED}[ERROR] $* ${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN] $* ${NC}" >&2; }
info() { echo -e "${GREEN}[INFO] $* ${NC}"; }

# ========================
# 参数验证函数
# ========================
validate_parameters() {
    [[ "$INSTANCE_ID" =~ ^v[0-9]+$ ]] || error "无效实例ID: $INSTANCE_ID, 格式应为v[数字]"
    [[ "$HADOOP_INSTANCE" =~ ^v[0-9]+$ ]] || error "无效Hadoop实例ID: $HADOOP_INSTANCE"
    
    # Tez版本兼容性检查
    case "$TEZ_VERSION" in
        0.9.*|0.10.*)
            info "Tez版本$TEZ_VERSION兼容性验证通过" ;;
        *)
            warn "未充分测试的Tez版本: $TEZ_VERSION, 可能存在兼容性问题" ;;
    esac
}

# ========================
# 检查Hive是否已安装
# ========================
check_hive_installed() {
    [ -d "$HIVE_BASE_DIR" ] || error "Hive未安装在 $HIVE_BASE_DIR"
    [ -f "$HIVE_BASE_DIR/conf/hive-site.xml" ] || error "Hive配置文件不存在"
    info "Hive环境验证通过"
}

# ========================
# 检查系统依赖
# ========================
check_dependencies() {
    # Java环境验证
    [ -d "$JAVA_HOME" ] || error "JAVA_HOME路径不存在: $JAVA_HOME"
    "$JAVA_HOME/bin/java" -version >/dev/null 2>&1 || error "Java安装损坏"
    
    # Hadoop环境验证
    [ -d "$HADOOP_HOME" ] || error "Hadoop路径不存在: $HADOOP_HOME"
    [ -f "$HADOOP_HOME/bin/hdfs" ] || error "Hadoop二进制文件缺失"
    
    # 检查必要命令
    for cmd in wget tar hdfs xmlstarlet nc; do
        command -v $cmd &>/dev/null || error "缺少必要命令: $cmd"
    done
    
    # 检查用户账户
    id "$HIVE_USER" >/dev/null 2>&1 || error "Hive用户 $HIVE_USER 不存在"
    id "$HADOOP_USER" >/dev/null 2>&1 || error "Hadoop用户 $HADOOP_USER 不存在"
    
    info "所有依赖检查通过"
}

# ========================
# 下载Tez安装包
# ========================
download_tez() {
    local tez_tar="apache-tez-${TEZ_VERSION}-bin.tar.gz"
    local tez_url="https://archive.apache.org/dist/tez/${TEZ_VERSION}/${tez_tar}"
    
    info "开始下载Tez $TEZ_VERSION"
    
    # 使用本地缓存或下载
    if [ -f "/tmp/$tez_tar" ]; then
        info "使用本地缓存的Tez安装包"
        cp "/tmp/$tez_tar" .
    else
        if ! wget -t 3 -T 30 "$tez_url" -O "$tez_tar"; then
            # 尝试备份镜像源
            backup_url="https://dlcdn.apache.org/tez/${TEZ_VERSION}/${tez_tar}"
            warn "主镜像下载失败，尝试备份源"
            wget -t 2 -T 20 "$backup_url" -O "$tez_tar" || error "Tez下载失败"
        fi
        cp "$tez_tar" /tmp/
    fi
    
    # 检查文件完整性
    local min_size=1000000  # 1MB
    [ $(stat -c %s "$tez_tar") -gt $min_size ] || error "下载的Tez包不完整"
    
    info "Tez下载成功"
}

# ========================
# 安装Tez
# ========================
install_tez() {
    info "安装Tez到: $TEZ_BASE_DIR"
    
    # 清理旧目录
    [ -d "$TEZ_BASE_DIR" ] && { 
        warn "发现已存在的Tez安装，备份后将删除"
        backup_dir="${TEZ_BASE_DIR}.bak_$(date +%Y%m%d%H%M)"
        mv "$TEZ_BASE_DIR" "$backup_dir"
    }
    
    # 创建安装目录
    mkdir -p "$TEZ_BASE_DIR"
    
    # 解压Tez
    local tez_tar="apache-tez-${TEZ_VERSION}-bin.tar.gz"
    tar -zxf "$tez_tar" -C "$TEZ_BASE_DIR" --strip-components=1
    
    # 清理安装包
    rm -f "$tez_tar"
    
    # 在HDFS创建Tez目录并设置安全权限
    su - "$HADOOP_USER" <<EOF
        hdfs dfs -mkdir -p /user/tez
        hdfs dfs -mkdir -p /tmp/tez
        hdfs dfs -chown $HIVE_USER:$HADOOP_USER /user/tez
        hdfs dfs -chmod 755 /user/tez
        hdfs dfs -chown $HIVE_USER:$HADOOP_USER /tmp/tez
        hdfs dfs -chmod 750 /tmp/tez
EOF

    info "Tez安装完成"
}

# ========================
# 配置Tez环境
# ========================
configure_tez() {
    info "配置Tez环境"
    
    # 创建配置目录
    mkdir -p "$TEZ_BASE_DIR/conf"
    
    # 创建安全的tez-site.xml配置
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

    # 添加Hadoop代理用户配置（使用临时文件确保安全）
    HADOOP_CORE_SITE="$HADOOP_HOME/etc/hadoop/core-site.xml"
    local tmp_core=$(mktemp)
    
    # 检查并添加配置
    if ! xmlstarlet sel -t -v "//configuration/property[name='hadoop.proxyuser.hive.hosts']" "$HADOOP_CORE_SITE" >/dev/null; then
        xmlstarlet ed \
            -s "//configuration" -t elem -n "property" \
            -s "//configuration/property[last()]" -t elem -n "name" -v "hadoop.proxyuser.hive.hosts" \
            -s "//configuration/property[last()]" -t elem -n "value" -v "*" \
            "$HADOOP_CORE_SITE" > "$tmp_core" && mv "$tmp_core" "$HADOOP_CORE_SITE"
    fi

    if ! xmlstarlet sel -t -v "//configuration/property[name='hadoop.proxyuser.hive.groups']" "$HADOOP_CORE_SITE" >/dev/null; then
        xmlstarlet ed \
            -s "//configuration" -t elem -n "property" \
            -s "//configuration/property[last()]" -t elem -n "name" -v "hadoop.proxyuser.hive.groups" \
            -s "//configuration/property[last()]" -t elem -n "value" -v "*" \
            "$HADOOP_CORE_SITE" > "$tmp_core" && mv "$tmp_core" "$HADOOP_CORE_SITE"
    fi
    
    # 分发Tez库到HDFS
    su - "$HADOOP_USER" <<EOF
        hdfs dfs -mkdir -p /user/tez/tez-${TEZ_VERSION}-libs
        hdfs dfs -put "$TEZ_BASE_DIR/"* /user/tez/tez-${TEZ_VERSION}-libs/
        hdfs dfs -chown -R "$HIVE_USER:$HADOOP_USER" /user/tez/tez-${TEZ_VERSION}-libs
        hdfs dfs -chmod -R 755 /user/tez/tez-${TEZ_VERSION}-libs
EOF

    info "Tez配置完成"
}

# ========================
# 配置Hive使用Tez
# ========================
configure_hive_tez() {
    info "配置Hive使用Tez执行引擎"    
    local hive_site="$HIVE_BASE_DIR/conf/hive-site.xml"
    local tmp_file=$(mktemp)
    
    # 备份原有配置
    local timestamp=$(date +%Y%m%d%H%M%S)
    cp "$hive_site" "${hive_site}.bak_$timestamp"
    
    # 设置执行引擎为Tez
    if xmlstarlet sel -t -v "//configuration/property[name='hive.execution.engine']/value" "$hive_site" >/dev/null; then
        xmlstarlet ed -u "//configuration/property[name='hive.execution.engine']/value" -v "tez" "$hive_site" > "$tmp_file"
    else
        xmlstarlet ed -s "//configuration" -t elem -n "property" \
            -s "//configuration/property[last()]" -t elem -n "name" -v "hive.execution.engine" \
            -s "//configuration/property[last()]" -t elem -n "value" -v "tez" \
            "$hive_site" > "$tmp_file"
    fi
    mv "$tmp_file" "$hive_site"
    
    # 禁用Tez会话池
    if ! xmlstarlet sel -t -v "//configuration/property[name='hive.tez.session.pool.enabled']/value" "$hive_site" >/dev/null; then
        xmlstarlet ed -s "//configuration" -t elem -n "property" \
            -s "//configuration/property[last()]" -t elem -n "name" -v "hive.tez.session.pool.enabled" \
            -s "//configuration/property[last()]" -t elem -n "value" -v "false" \
            "$hive_site" > "$tmp_file" && mv "$tmp_file" "$hive_site"
    fi
    
    # 添加环境变量
    local hive_env="$HIVE_BASE_DIR/conf/hive-env.sh"
    grep -q "TEZ_HOME" "$hive_env" || {
        echo "export TEZ_HOME=\"$TEZ_BASE_DIR\"" >> "$hive_env"
        echo 'export HIVE_AUX_JARS_PATH=$TEZ_HOME/*:$TEZ_HOME/lib/*:$HIVE_AUX_JARS_PATH' >> "$hive_env"
    }
    
    # 创建系统级环境脚本
    local env_file="/etc/profile.d/tez-${TEZ_VERSION}-hive${HIVE_VERSION}-${INSTANCE_ID}.sh"
    cat > "$env_file" <<EOF
# Tez环境配置 (自动生成)
export TEZ_HOME="$TEZ_BASE_DIR"
export PATH="\$PATH:\$TEZ_HOME/bin"
export HADOOP_CLASSPATH=\$HADOOP_CLASSPATH:\$TEZ_HOME/*:\$TEZ_HOME/lib/*
EOF
    
    # 应用环境变量
    source "$env_file"
    
    info "Hive-Tez集成配置完成"
}

# ========================
# 端口检测函数
# ========================
wait_for_port() {
    local port=$1 service=$2 timeout=60
    info "等待 $service 服务在端口 $port 启动..."
    
    until nc -z localhost "$port"; do
        sleep 1
        timeout=$((timeout-1))
        [ $timeout -le 0 ] && error "$service 服务启动超时"
    done
    info "$service 服务启动成功"
}

# ========================
# 启动Hive服务
# ========================
start_hive_services() {
    info "启动Hive服务..."
    
    local pid_dir="$HIVE_BASE_DIR/pids"
    local log_dir="$HIVE_BASE_DIR/logs"
    local log_date=$(date +%Y%m%d_%H%M%S)
    
    mkdir -p "$pid_dir" "$log_dir"
    
    # 获取端口配置
    local metastore_port=$(xmlstarlet sel -t -v "//configuration/property[name='hive.metastore.uris']/value" "$HIVE_BASE_DIR/conf/hive-site.xml" | cut -d: -f3)
    local hiveserver_port=$(xmlstarlet sel -t -v "//configuration/property[name='hive.server2.thrift.port']/value" "$HIVE_BASE_DIR/conf/hive-site.xml")
    [ -z "$metastore_port" ] && metastore_port=9083
    [ -z "$hiveserver_port" ] && hiveserver_port=10000
    
    # 停止旧服务
    for service in metastore hiveserver2; do
        local pid_file="$pid_dir/$service.pid"
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if ps -p "$pid" >/dev/null; then
                info "停止正在运行的Hive $service服务 (PID: $pid)"
                kill "$pid"
                sleep 3
            fi
            rm -f "$pid_file"
        fi
    done
    
    # 启动元数据服务
    info "启动MetaStore服务 (端口: $metastore_port)"
    nohup "$HIVE_BASE_DIR/bin/hive" --service metastore > "${log_dir}/metastore_${log_date}.log" 2>&1 &
    echo $! > "$pid_dir/metastore.pid"
    wait_for_port "$metastore_port" "HiveMetaStore"
    
    # 启动HiveServer2
    info "启动HiveServer2服务 (端口: $hiveserver_port)"
    nohup "$HIVE_BASE_DIR/bin/hive" --service hiveserver2 > "${log_dir}/hiveserver2_${log_date}.log" 2>&1 &
    echo $! > "$pid_dir/hiveserver2.pid"
    wait_for_port "$hiveserver_port" "HiveServer2"
    
    info "所有Hive服务启动完成"
}

# ========================
# 测试Tez功能
# ========================
test_tez() {
    info "开始Tez功能测试..."
    
    local test_db="tez_test_db_${HIVE_VERSION}_${INSTANCE_ID}_$(date +%s)"
    local test_table="test_tez_table"
    
    # 获取连接信息
    local hiveserver_port=$(xmlstarlet sel -t -v "//configuration/property[name='hive.server2.thrift.port']/value" "$HIVE_BASE_DIR/conf/hive-site.xml")
    local hostname=$(hostname -f)
    
    # 执行测试SQL
    info "执行测试SQL: 创建数据库 $test_db"
    "$HIVE_BASE_DIR/bin/beeline" -u "jdbc:hive2://$hostname:$hiveserver_port/default" -n "$HIVE_USER" -e "
        DROP DATABASE IF EXISTS $test_db CASCADE;
        CREATE DATABASE $test_db;
        USE $test_db;
        CREATE TABLE $test_table (id INT, name STRING);
        INSERT INTO $test_table VALUES (1, 'tez_test'), (2, 'hive_test');
        SELECT COUNT(*) FROM $test_table;
        DROP DATABASE $test_db CASCADE;
    " > "${HIVE_BASE_DIR}/logs/tez_test_${test_db}.log" 2>&1
    
    # 验证结果
    if [ $? -eq 0 ]; then
        info "Tez执行引擎测试成功"
        # 额外验证任务执行方式
        local execution_engine=$("$HIVE_BASE_DIR/bin/beeline" -u "jdbc:hive2://$hostname:$hiveserver_port/default" -n "$HIVE_USER" -e "set hive.execution.engine" | grep "tez")
        [ -n "$execution_engine" ] && info "执行引擎验证: Tez激活成功" || warn "执行引擎未设置为Tez"
    else
        warn "Tez测试失败，请检查日志: ${HIVE_BASE_DIR}/logs/tez_test_${test_db}.log"
    fi
}

# ========================
# 主流程控制
# ========================
main() {
    info "开始为Hive $HIVE_VERSION (实例: $INSTANCE_ID) 安装Tez $TEZ_VERSION"
    echo "===================================================="
    echo "Hadoop版本:    $HADOOP_VERSION (实例: $HADOOP_INSTANCE)"
    echo "Hadoop路径:    $HADOOP_HOME"
    echo "Hive路径:      $HIVE_BASE_DIR"
    echo "Tez路径:       $TEZ_BASE_DIR"
    echo "Java路径:      $JAVA_HOME"
    echo "运行用户:      $HIVE_USER"
    echo "===================================================="
    
    # 执行步骤
    validate_parameters
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

==================== 安装完成 ====================
Tez版本:     $TEZ_VERSION
安装路径:    $TEZ_BASE_DIR
集成Hive版本: $HIVE_VERSION (实例: $INSTANCE_ID)

验证命令:
  1. 加载环境变量: 
     source /etc/profile.d/tez-${TEZ_VERSION}-hive${HIVE_VERSION}-${INSTANCE_ID}.sh
  2. 检查配置:
     $HIVE_BASE_DIR/bin/hive -e "set hive.execution.engine;"
  3. 查看服务状态:
     jps | grep -E 'RunJar|HiveServer2'
  4. 监控任务执行:
     yarn application -list | grep HIVE

注意: Tez Web UI默认不启用，需要时配置tez.site.uri
=================================================
EOF
}

# 执行入口点
main